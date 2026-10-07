#' Save Experiment Results to File
#'
#' Saves experiment results to a CSV or Excel file, conforming to
#' PsyLingLLM_Schema. If `output_path` is NULL, a default filename is
#' generated as \code{{model}_{YYYYMMDD_HHMMSS}.csv} in
#' the `results` subdirectory of the package user-data directory returned by
#' \code{tools::R_user_dir("PsyLingLLM", "data")}.
#'
#' Columns that are entirely NA (e.g., FirstTokenLatency when streaming = FALSE)
#' will be removed automatically.
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

  # Clean data
  if ("ErrorMessage" %in% colnames(data)) data$ErrorMessage <- NULL
  drop_cols <- vapply(data, function(col) all(is.na(col) | col == ""), logical(1))
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
    writexl::write_xlsx(data, path = temporary)
  }
  replace_file_safely(temporary, output_path, overwrite = overwrite)
  if (!file.exists(output_path)) {
    stop("Result file was not created: ", output_path, call. = FALSE)
  }

  saved <- normalizePath(output_path, mustWork = TRUE)
  message("\n", sprintf("[PsyLingLLM] Results saved: %s", saved))
  invisible(saved)
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
