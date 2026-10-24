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
#' If \code{data} contains a \code{raw} list-column, CSV output excludes that
#' nested column. Excel output writes the ordinary table to \code{Results} and
#' a redacted, path-based tabular projection to \code{Raw}. Large projections
#' are continued in \code{Raw_2}, \code{Raw_3}, and so on. The in-memory RAW
#' objects are not modified; use \code{saveRDS()} for lossless persistence.
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
#'
#' @return Invisible normalized file path
#' @export
save_experiment_results <- function(data,
                                    output_path = NULL,
                                    model = NULL,
                                    overwrite = TRUE,
                                    auto_naming = TRUE) {
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

  raw_records <- NULL
  raw_links <- NULL
  if ("raw" %in% names(data)) {
    raw_records <- data$raw
    raw_links <- data.frame(
      ResultRow = seq_len(nrow(data)),
      RequestID = if ("RequestID" %in% names(data)) {
        as.character(data$RequestID)
      } else {
        rep(NA_character_, nrow(data))
      },
      stringsAsFactors = FALSE
    )
    data$raw <- NULL
  }

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
  temporary <- tempfile(
    pattern = ".results-",
    tmpdir = dirname(output_path),
    fileext = paste0(".", ext)
  )
  on.exit(if (file.exists(temporary)) unlink(temporary, force = TRUE),
          add = TRUE)
  if (ext == "csv") {
    readr::write_excel_csv(data, temporary)
  } else {
    if (!requireNamespace("writexl", quietly = TRUE)) {
      stop("Package 'writexl' is required but not installed.")
    }
    workbook <- list(Results = data)
    if (!is.null(raw_records)) {
      raw_table <- tabulate_raw_records(raw_records, raw_links)
      workbook <- c(workbook, split_raw_sheets(raw_table))
    }
    writexl::write_xlsx(workbook, path = temporary)
  }
  replace_file_safely(temporary, output_path, overwrite = overwrite)
  if (!file.exists(output_path)) {
    stop("Result file was not created: ", output_path, call. = FALSE)
  }

  saved <- normalizePath(output_path, mustWork = TRUE)
  message("\n", sprintf("[PsyLingLLM] Results saved: %s", saved))
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

tabulate_raw_records <- function(raw_records, links = NULL) {
  if (!is.list(raw_records)) {
    stop("`raw` must be a list-column.", call. = FALSE)
  }
  record_count <- length(raw_records)
  if (is.null(links)) {
    links <- data.frame(
      ResultRow = seq_len(record_count),
      RequestID = rep(NA_character_, record_count),
      stringsAsFactors = FALSE
    )
  }
  if (nrow(links) != record_count) {
    stop("RAW records must correspond one-to-one with result rows.", call. = FALSE)
  }
  if (!record_count) {
    return(data.frame(
      ResultRow = integer(),
      RequestID = character(),
      FieldPath = character(),
      ValueType = character(),
      ValueEncoding = character(),
      ValueChunk = integer(),
      ValueChunks = integer(),
      Value = character(),
      stringsAsFactors = FALSE
    ))
  }

  rows <- vector("list", record_count)
  for (index in seq_len(record_count)) {
    flattened <- flatten_raw_value(
      redact_llm_diagnostics(raw_records[[index]]),
      path = "$"
    )
    flattened$ResultRow <- links$ResultRow[[index]]
    flattened$RequestID <- links$RequestID[[index]]
    rows[[index]] <- flattened[, c(
      "ResultRow", "RequestID", "FieldPath", "ValueType",
      "ValueEncoding", "ValueChunk", "ValueChunks", "Value"
    )]
  }
  do.call(rbind, rows)
}

flatten_raw_value <- function(value, path) {
  if (is.null(value)) {
    return(new_raw_table_row(path, "null", "scalar", NA_character_))
  }
  if (is.raw(value)) {
    encoded <- paste(sprintf("%02x", as.integer(value)), collapse = "")
    return(new_raw_table_row(path, "raw", "hex", encoded))
  }
  if (inherits(value, "POSIXt")) {
    value <- format(value, "%Y-%m-%dT%H:%M:%OS%z")
  }
  if (is.data.frame(value)) {
    value <- as.list(value)
  }
  if (is.list(value)) {
    if (!length(value)) {
      return(new_raw_table_row(path, "list", "empty", NA_character_))
    }
    value_names <- names(value)
    children <- lapply(seq_along(value), function(index) {
      name <- if (!is.null(value_names) &&
                  !is.na(value_names[[index]]) &&
                  nzchar(value_names[[index]])) {
        separator <- if (identical(path, "$")) "" else "$"
        paste0(path, separator, value_names[[index]])
      } else {
        paste0(path, "[", index, "]")
      }
      flatten_raw_value(value[[index]], name)
    })
    return(do.call(rbind, children))
  }
  value_names <- names(value)
  has_names <- !is.null(value_names) &&
    any(!is.na(value_names) & nzchar(value_names))
  if (length(value) > 1L || has_names) {
    children <- lapply(seq_along(value), function(index) {
      child_path <- if (has_names &&
                        !is.na(value_names[[index]]) &&
                        nzchar(value_names[[index]])) {
        separator <- if (identical(path, "$")) "" else "$"
        paste0(path, separator, value_names[[index]])
      } else {
        paste0(path, "[", index, "]")
      }
      flatten_raw_value(value[[index]], child_path)
    })
    return(do.call(rbind, children))
  }

  value_type <- typeof(value)
  if (is.character(value)) {
    encoded <- as.character(jsonlite::toJSON(
      value,
      auto_unbox = TRUE,
      na = "null"
    ))
    encoding <- "json_string"
  } else if (is.na(value)) {
    encoded <- NA_character_
    encoding <- "scalar"
  } else {
    encoded <- as.character(value)
    encoding <- "scalar"
  }
  new_raw_table_row(path, value_type, encoding, encoded)
}

new_raw_table_row <- function(path, value_type, encoding, value,
                              chunk_size = 30000L) {
  if (is.na(value) || nchar(value, type = "chars") <= chunk_size) {
    return(data.frame(
      FieldPath = path,
      ValueType = value_type,
      ValueEncoding = encoding,
      ValueChunk = 1L,
      ValueChunks = 1L,
      Value = value,
      stringsAsFactors = FALSE
    ))
  }
  starts <- seq.int(1L, nchar(value), by = chunk_size)
  chunks <- substring(value, starts, pmin(starts + chunk_size - 1L, nchar(value)))
  data.frame(
    FieldPath = rep(path, length(chunks)),
    ValueType = rep(value_type, length(chunks)),
    ValueEncoding = rep(encoding, length(chunks)),
    ValueChunk = seq_along(chunks),
    ValueChunks = rep(length(chunks), length(chunks)),
    Value = chunks,
    stringsAsFactors = FALSE
  )
}

split_raw_sheets <- function(raw_table, max_excel_rows = 1048576L) {
  rows_per_sheet <- as.integer(max_excel_rows) - 1L
  if (rows_per_sheet < 1L) {
    stop("Excel row limit must allow at least one data row.", call. = FALSE)
  }
  if (!nrow(raw_table)) {
    return(list(Raw = raw_table))
  }
  sheet_index <- ceiling(seq_len(nrow(raw_table)) / rows_per_sheet)
  pieces <- split(raw_table, sheet_index)
  names(pieces) <- if (length(pieces) == 1L) {
    "Raw"
  } else {
    c("Raw", paste0("Raw_", seq.int(2L, length(pieces))))
  }
  pieces
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
