#' Save Experiment Results to File
#'
#' Saves experiment results to a CSV or Excel file, conforming to
#' PsyLingLLM_Schema. If `output_path` is NULL, a default filename is
#' generated as \code{{model}_{YYYYMMDD_HHMMSS}.csv} in
#' the `results` subdirectory of the package user-data directory returned by
#' \code{tools::R_user_dir("PsyLingLLM", "data")}.
#'
#' Package-defined result columns are retained even when every value is
#' missing, so the saved result schema remains stable across streaming and
#' non-streaming runs. Other entirely empty columns are removed.
#'
#' If \code{data} contains a \code{raw} list-column, ordinary CSV and Excel
#' result tables exclude that nested column. When \code{raw_output_path} is
#' supplied, the complete result is saved losslessly as a redacted RDS archive.
#' Excel output then adds a compact \code{RawIndex} sheet that maps each result
#' row to its corresponding \code{raw[[i]]} record, plus a two-column
#' \code{RawMetadata} sheet that describes the RDS archive once. Complete
#' provider payloads are never expanded into Excel worksheets.
#'
#' The RDS archive supports nested serializable R values without flattening
#' them to spreadsheet cells. Its standard type contract covers \code{NULL},
#' atomic vectors, raw bytes, lists, data frames, factors, dates, and
#' date-times. Use
#' \code{get_trial_raw()}, \code{extract_process_metrics()}, or
#' \code{extract_token_probabilities()} after \code{readRDS()}.
#' Parent directories are created when needed. Data are written to a temporary
#' file before the destination is replaced, and write failures raise an error
#' rather than returning a path to a missing file.
#'
#' @param data data.frame Result dataset (following PsyLingLLM_Schema).
#' @param output_path character File path (CSV or Excel). If NULL, auto-generate
#'   model name + timestamp in default folder.
#' @param model character Model name (used for auto-naming).
#' @param overwrite logical Whether to overwrite existing file. Default TRUE.
#' @param auto_naming logical If TRUE (default), and no explicit filename is
#'   provided, auto-generate filename as \code{model_timestamp.csv}.
#' @param raw_output_path Character scalar ending in \code{.rds}, or
#'   \code{NULL}. When supplied, \code{data} must contain a one-record-per-row
#'   \code{raw} list-column. The complete result is written atomically as a
#'   redacted RDS archive. For Excel output, compact \code{RawIndex} and
#'   \code{RawMetadata} sheets are added; CSV output remains unchanged.
#'
#' @return Invisible normalized file path
#' @export
save_experiment_results <- function(data,
                                    output_path = NULL,
                                    model = NULL,
                                    overwrite = TRUE,
                                    auto_naming = TRUE,
                                    raw_output_path = NULL) {
  # If output_path is NULL → auto filename
  if (is.null(output_path)) {
    base_dir <- default_results_directory()
    if (!dir.exists(base_dir)) {
      ensure_psylingllm_directory(base_dir, "result directory")
      message("\n", "[PsyLingLLM] Created directory: ", base_dir)
    }
    ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
    model_name <- gsub("[^A-Za-z0-9_-]", "", model %||% "model")
    output_path <- file.path(base_dir, sprintf("%s_%s.csv", model_name, ts))
  }

  # If user provides a directory
  if (dir.exists(output_path) || tools::file_ext(output_path) == "") {
    ensure_psylingllm_directory(output_path, "result directory")
    if (auto_naming) {
      ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
      model_name <- gsub("[^A-Za-z0-9_-]", "", model %||% "model")
      output_path <- file.path(output_path, sprintf("%s_%s.csv", model_name, ts))
    } else {
      output_path <- file.path(output_path, "results.csv")
    }
  }

  ensure_psylingllm_directory(dirname(output_path), "result directory")

  has_raw <- "raw" %in% names(data)
  normalized_raw_path <- validate_raw_output_request(
    raw_output_path = raw_output_path,
    return_raw = has_raw,
    overwrite = overwrite
  )
  archive_data <- if (!is.null(normalized_raw_path)) {
    prepare_raw_archive_data(data)
  } else {
    NULL
  }
  raw_index <- if (!is.null(archive_data)) {
    build_raw_index(archive_data)
  } else {
    NULL
  }
  raw_metadata <- if (!is.null(archive_data)) {
    build_raw_metadata(normalized_raw_path)
  } else {
    NULL
  }
  if (has_raw) data$raw <- NULL

  # Clean the flat Results table while retaining its documented schema.
  if ("ErrorMessage" %in% colnames(data)) data$ErrorMessage <- NULL
  keep_empty <- c(
    "Response", "Think", "ModelName", "TotalResponseTime",
    "FirstTokenLatency", "PromptTokens", "CompletionTokens",
    "TrialStatus", "ResponseStatus", "Streaming", "Timestamp", "RequestID"
  )
  drop_cols <- vapply(data, is_empty_result_column, logical(1)) &
    !(names(data) %in% keep_empty)
  data <- data[, !drop_cols, drop = FALSE]

  # Save to a temporary file beside the target, then replace safely.
  ext <- tolower(tools::file_ext(output_path))
  if (!(ext %in% c("csv", "xlsx", "xls"))) {
    stop("Unsupported extension: ", ext, call. = FALSE)
  }
  if (file.exists(output_path) && !isTRUE(overwrite)) {
    stop("[PsyLingLLM] File already exists: ", output_path, call. = FALSE)
  }
  temporary <- tempfile(
    pattern = ".results-",
    tmpdir = dirname(output_path),
    fileext = paste0(".", ext)
  )
  on.exit(if (file.exists(temporary)) unlink(temporary, force = TRUE),
          add = TRUE)
  raw_temporary <- NULL
  if (!is.null(archive_data)) {
    raw_temporary <- tempfile(
      pattern = ".raw-results-",
      tmpdir = dirname(normalized_raw_path),
      fileext = ".rds"
    )
    on.exit(if (file.exists(raw_temporary)) unlink(raw_temporary, force = TRUE),
            add = TRUE)
    saveRDS(archive_data, raw_temporary, compress = TRUE)
  }
  if (ext == "csv") {
    readr::write_excel_csv(data, temporary)
  } else {
    if (!requireNamespace("writexl", quietly = TRUE)) {
      stop("Package 'writexl' is required but not installed.")
    }
    workbook <- list(Results = data)
    if (!is.null(raw_index)) {
      workbook$RawIndex <- raw_index
      workbook$RawMetadata <- raw_metadata
    }
    writexl::write_xlsx(workbook, path = temporary)
  }
  if (!is.null(raw_temporary)) {
    replace_file_safely(
      raw_temporary,
      normalized_raw_path,
      overwrite = overwrite
    )
  }
  replace_file_safely(temporary, output_path, overwrite = overwrite)
  if (!file.exists(output_path)) {
    stop("Result file was not created: ", output_path, call. = FALSE)
  }

  saved <- normalizePath(output_path, mustWork = TRUE)
  message("\n", sprintf("[PsyLingLLM] Results saved: %s", saved))
  if (!is.null(normalized_raw_path)) {
    message(sprintf("[PsyLingLLM] RAW archive saved: %s", normalized_raw_path))
  }
  invisible(saved)
}

is_empty_result_column <- function(column) {
  if (!length(column)) {
    return(TRUE)
  }
  missing <- is.na(column)
  if (is.character(column) || is.factor(column)) {
    missing <- missing | trimws(as.character(column)) == ""
  }
  all(missing)
}

validate_raw_output_request <- function(raw_output_path,
                                        return_raw,
                                        overwrite = TRUE) {
  if (is.null(raw_output_path)) {
    return(NULL)
  }
  if (!is.character(raw_output_path) || length(raw_output_path) != 1L ||
      is.na(raw_output_path) || !nzchar(raw_output_path)) {
    stop("`raw_output_path` must be NULL or one non-empty path.",
         call. = FALSE)
  }
  if (!isTRUE(return_raw)) {
    stop("`raw_output_path` requires `return_raw = TRUE`.", call. = FALSE)
  }
  if (!identical(tolower(tools::file_ext(raw_output_path)), "rds")) {
    stop("`raw_output_path` must use the `.rds` extension.", call. = FALSE)
  }
  ensure_psylingllm_directory(dirname(raw_output_path), "RAW archive directory")
  normalized <- normalizePath(raw_output_path, mustWork = FALSE)
  if (file.exists(normalized) && !isTRUE(overwrite)) {
    stop("[PsyLingLLM] File already exists: ", normalized, call. = FALSE)
  }
  normalized
}

prepare_raw_archive_data <- function(data) {
  if (!("raw" %in% names(data)) || !is.list(data$raw)) {
    stop("A RAW archive requires a `raw` list-column.", call. = FALSE)
  }
  if (length(data$raw) != nrow(data)) {
    stop("RAW records must correspond one-to-one with result rows.",
         call. = FALSE)
  }
  archive <- data
  archive$raw <- lapply(archive$raw, redact_llm_diagnostics)
  metadata <- raw_archive_metadata()
  attr(archive, "psylingllm_raw_schema_version") <-
    metadata$raw_schema_version
  attr(archive, "psylingllm_archive_format") <- metadata$archive_format
  attr(archive, "psylingllm_archive_object") <- metadata$archive_object
  attr(archive, "psylingllm_supported_value_types") <-
    metadata$supported_value_types
  archive
}

build_raw_index <- function(data) {
  if (!("raw" %in% names(data)) || length(data$raw) != nrow(data)) {
    stop("RAW records must correspond one-to-one with result rows.",
         call. = FALSE)
  }
  n <- nrow(data)
  data.frame(
    ResultRow = seq_len(n),
    RawRecordIndex = seq_len(n),
    RawAvailable = !vapply(data$raw, is.null, logical(1)),
    RawPath = sprintf("raw[[%d]]", seq_len(n)),
    stringsAsFactors = FALSE
  )
}

build_raw_metadata <- function(raw_output_path) {
  metadata <- raw_archive_metadata()
  data.frame(
    Field = c(
      "RawArtifact",
      "ArchiveFormat",
      "RawSchemaVersion",
      "ArchiveObject",
      "SupportedValueTypes",
      "AnalysisFunctions"
    ),
    Value = c(
      basename(raw_output_path),
      metadata$archive_format,
      metadata$raw_schema_version,
      metadata$archive_object,
      paste(metadata$supported_value_types, collapse = "|"),
      paste(
        c(
          "get_trial_raw()",
          "extract_process_metrics()",
          "extract_token_probabilities()"
        ),
        collapse = "; "
      )
    ),
    stringsAsFactors = FALSE
  )
}

raw_archive_metadata <- function() {
  list(
    archive_format = "RDS",
    raw_schema_version = "psylingllm.raw.v1",
    archive_object = "data.frame with raw list-column",
    supported_value_types = c(
      "NULL", "logical", "integer", "double", "complex", "character",
      "raw", "list", "data.frame", "factor", "Date", "POSIXct"
    )
  )
}

save_raw_result_archive <- function(data, raw_output_path, overwrite = TRUE) {
  normalized <- validate_raw_output_request(
    raw_output_path = raw_output_path,
    return_raw = "raw" %in% names(data),
    overwrite = overwrite
  )
  archive <- prepare_raw_archive_data(data)
  temporary <- tempfile(
    pattern = ".raw-results-",
    tmpdir = dirname(normalized),
    fileext = ".rds"
  )
  on.exit(if (file.exists(temporary)) unlink(temporary, force = TRUE),
          add = TRUE)
  saveRDS(archive, temporary, compress = TRUE)
  replace_file_safely(temporary, normalized, overwrite = overwrite)
  if (!file.exists(normalized)) {
    stop("RAW archive was not created: ", normalized, call. = FALSE)
  }
  message(sprintf("[PsyLingLLM] RAW archive saved: %s", normalized))
  invisible(normalized)
}

#' Resolve output and log file paths
#'
#' @param output_path character or NULL. User-specified output path or filename.
#' @param model character. Model name for auto-naming.
#' @return List with `result_file` and `log_file`.
#' @noRd
resolve_output_and_log <- function(output_path, model) {
  base_dir <- default_results_directory()

  # --- Sanitize model name for safe filenames ---
  sanitize_filename <- function(x) {
    gsub("[^A-Za-z0-9_-]", "_", x)
  }
  model_safe <- sanitize_filename(model)

  # --- Case 1: output_path missing/null ---
  if (is.null(output_path)) {
    ensure_psylingllm_directory(base_dir, "result directory")
    ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
    result_file <- file.path(base_dir, sprintf("%s_%s.csv", model_safe, ts))
    log_file <- sub("\\.csv$", ".log", result_file)
    return(list(result_file = result_file, log_file = log_file))
  }

  # --- Case 2: output_path is a pure filename (no "/" or "\" separators) ---
  if (!grepl("[/\\\\]", output_path)) {
    ensure_psylingllm_directory(base_dir, "result directory")
    result_file <- file.path(base_dir, output_path)
    log_file <- sub("\\.[^.]+$", ".log", result_file)
    return(list(result_file = result_file, log_file = log_file))
  }

  # --- Case 3: output_path is a directory ---
  if (dir.exists(output_path) || tools::file_ext(output_path) == "") {
    ensure_psylingllm_directory(output_path, "result directory")
    ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
    result_file <- file.path(output_path, sprintf("%s_%s.csv", model_safe, ts))
    log_file <- sub("\\.csv$", ".log", result_file)
    return(list(result_file = result_file, log_file = log_file))
  }

  # --- Case 4: output_path is a full file path ---
  dir <- dirname(output_path)
  ensure_psylingllm_directory(dir, "result directory")
  result_file <- normalizePath(output_path, mustWork = FALSE)
  log_file <- sub("\\.[^.]+$", ".log", result_file)
  list(result_file = result_file, log_file = log_file)
}

default_results_directory <- function() {
  file.path(tools::R_user_dir("PsyLingLLM", "data"), "results")
}
