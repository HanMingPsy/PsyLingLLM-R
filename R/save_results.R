#' Save Experiment Results to File
#'
#' Saves experiment results to a CSV or Excel file, conforming to
#' PsyLingLLM_Schema. If `output_path` is NULL, a default filename is
#' generated as \code{{model}_{YYYYMMDD_HHMMSS}.csv} in
#' \code{~/PsyLingLLM_Results}.
#'
#' Columns that are entirely NA (e.g., FirstTokenLatency when streaming = FALSE)
#' will be removed automatically.
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
  # Ensure base directory
  base_dir <- path.expand("~/.psylingllm/results")
  if (!dir.exists(base_dir)) {
    dir.create(base_dir, recursive = TRUE)
    message("\n", "[PsyLingLLM] Created directory: ", base_dir)
  }

  # If output_path is NULL → auto filename
  if (is.null(output_path)) {
    ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
    model_name <- gsub("[^A-Za-z0-9_-]", "", model %||% "model")
    output_path <- file.path(base_dir, sprintf("%s_%s.csv", model_name, ts))
  }

  # If user provides a directory
  if (dir.exists(output_path) || tools::file_ext(output_path) == "") {
    if (auto_naming) {
      ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
      model_name <- gsub("[^A-Za-z0-9_-]", "", model %||% "model")
      output_path <- file.path(output_path, sprintf("%s_%s.csv", model_name, ts))
    } else {
      output_path <- file.path(output_path, "results.csv")
    }
  }

  # Overwrite check
  if (!overwrite && file.exists(output_path)) {
    stop("[PsyLingLLM] File already exists: ", output_path)
  }

  # Clean data
  if ("ErrorMessage" %in% colnames(data)) data$ErrorMessage <- NULL
  drop_cols <- vapply(data, function(col) all(is.na(col) | col == ""), logical(1))
  data <- data[, !drop_cols, drop = FALSE]

  # Save file
  ext <- tolower(tools::file_ext(output_path))
  tryCatch({
    if (ext == "csv") {
      readr::write_excel_csv(data, output_path)
    } else if (ext %in% c("xlsx","xls")) {
      if (!requireNamespace("writexl", quietly = TRUE)) {
        stop("Package 'writexl' is required but not installed.")
      }
      writexl::write_xlsx(data, path = output_path)
    } else {
      stop("Unsupported extension: ", ext)
    }

    size_kb <- round(file.size(output_path) / 1024, 1)
    message("\n", sprintf(
      "[PsyLingLLM] Results saved: %s",
      normalizePath(output_path, mustWork = FALSE)))
  }, error = function(e) {
    warning("[PsyLingLLM] ERROR saving results: ", e$message)
  })


  invisible(normalizePath(output_path, mustWork = FALSE))
}

#' Resolve output and log file paths
#'
#' @param output_path character or NULL. User-specified output path or filename.
#' @param model character. Model name for auto-naming.
#' @return List with `result_file` and `log_file`.
#' @noRd
resolve_output_and_log <- function(output_path, model) {
  base_dir <- path.expand("~/.psylingllm/results")

  # --- Sanitize model name for safe filenames ---
  sanitize_filename <- function(x) {
    gsub("[^A-Za-z0-9_-]", "_", x)
  }
  model_safe <- sanitize_filename(model)

  # Ensure base_dir exists
  if (!dir.exists(base_dir)) dir.create(base_dir, recursive = TRUE)

  # --- Case 1: output_path missing/null ---
  if (is.null(output_path)) {
    ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
    result_file <- file.path(base_dir, sprintf("%s_%s.csv", model_safe, ts))
    log_file <- sub("\\.csv$", ".log", result_file)
    return(list(result_file = result_file, log_file = log_file))
  }

  # --- Case 2: output_path is a pure filename (no "/" or "\" separators) ---
  if (!grepl("[/\\\\]", output_path)) {
    result_file <- file.path(base_dir, output_path)
    log_file <- sub("\\.[^.]+$", ".log", result_file)
    return(list(result_file = result_file, log_file = log_file))
  }

  # --- Case 3: output_path is a directory ---
  if (dir.exists(output_path) || tools::file_ext(output_path) == "") {
    if (!dir.exists(output_path)) dir.create(output_path, recursive = TRUE)
    ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
    result_file <- file.path(output_path, sprintf("%s_%s.csv", model_safe, ts))
    log_file <- sub("\\.csv$", ".log", result_file)
    return(list(result_file = result_file, log_file = log_file))
  }

  # --- Case 4: output_path is a full file path ---
  dir <- dirname(output_path)
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  result_file <- normalizePath(output_path, mustWork = FALSE)
  log_file <- sub("\\.[^.]+$", ".log", result_file)
  list(result_file = result_file, log_file = log_file)
}
