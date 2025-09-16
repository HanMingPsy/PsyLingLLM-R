#' Run Multi-Model LLM Experiment
#'
#' Executes the same trial set across multiple models, calling a user-specified
#' experiment function (`experiment_fn`). Arguments not supported by the
#' experiment function are ignored with a warning.
#'
#' @param data data.frame Experiment material table (e.g., output of
#'   \code{generate_llm_experiment_list}).
#' @param model_file Path to CSV or Excel file containing model info.
#'   Must have columns: \code{ModelName}, \code{API_Key}, \code{API_URL},
#'   \code{Enable_Thinking}.
#' @param experiment_fn Function to run for each model
#'   (e.g., \code{trial_experiment}, \code{conversation_experiment}).
#' @param output_path Directory to save results. If missing, defaults to
#'   \code{~/PsyLingLLM_Results/MultiModel_Experiment_<timestamp>}.
#' @param max_tokens Integer. Maximum tokens per trial.
#' @param temperature Numeric. Sampling temperature.
#' @param random Logical. Whether to randomize trial order.
#' @param return_combined Logical. If TRUE, return combined results.
#' @param ... Additional arguments passed to \code{experiment_fn}.
#'   Unsupported arguments will trigger a warning and be ignored.
#'
#' @return If \code{return_combined = TRUE}, returns combined data.frame
#'   across models. Otherwise returns \code{NULL} invisibly.
#' @export
multi_model_experiment <- function(data,
                                   model_file,
                                   experiment_fn = trial_experiment,
                                   output_path,
                                   max_tokens = 1024,
                                   temperature = 0.7,
                                   random = FALSE,
                                   return_combined = FALSE,
                                   ...) {
  # --------------------------
  # Handle output paths with timestamp
  # --------------------------
  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")

  if (missing(output_path) || output_path %in% c(".", "")) {
    base_dir <- path.expand("~/PsyLingLLM_Results")
    if (!dir.exists(base_dir)) dir.create(base_dir, recursive = TRUE)
    output_path <- file.path(base_dir, paste0("MultiModel_", timestamp))
  }
  if (!dir.exists(output_path)) dir.create(output_path, recursive = TRUE)

  model_dir <- file.path(output_path, "Per_Model_Results")
  if (!dir.exists(model_dir)) dir.create(model_dir, recursive = TRUE)

  # --------------------------
  # Load model info
  # --------------------------
  ext <- tolower(tools::file_ext(model_file))
  if (ext == "csv") {
    model_df <- read.csv(model_file, stringsAsFactors = FALSE)
  } else if (ext %in% c("xls", "xlsx")) {
    if (!requireNamespace("readxl", quietly = TRUE)) stop("Package 'readxl' required")
    model_df <- readxl::read_excel(model_file)
    model_df <- as.data.frame(model_df, stringsAsFactors = FALSE)
  } else {
    stop("Unsupported model file type: must be .csv, .xls or .xlsx")
  }

  required_cols <- c("ModelName", "API_Key", "API_URL", "Enable_Thinking")
  missing_cols <- setdiff(required_cols, colnames(model_df))
  if (length(missing_cols) > 0) stop("Model file missing required columns: ", paste(missing_cols, collapse = ", "))

  # --------------------------
  # Prepare experiment function
  # --------------------------
  exp_fn <- match.fun(experiment_fn)
  exp_name <- if (is.character(experiment_fn)) experiment_fn else deparse(substitute(experiment_fn))
  fn_formals <- names(formals(exp_fn))
  has_dots <- "..." %in% fn_formals
  dots_list <- list(...)

  # Explicitly named user arguments (dots)
  # 1. 获取 experiment_fn 的参数
  fn_formals <- names(formals(exp_fn))
  has_dots <- "..." %in% fn_formals

  # 2. 检查 dots 中的用户传入参数
  dots_list <- list(...)
  dot_names <- names(dots_list)
  if (is.null(dot_names)) dot_names <- rep("", length(dots_list))
  explicit_named_dots <- unique(dot_names[dot_names != ""])

  # 3. 只检查 experiment_fn 不支持的参数
  if (!has_dots && length(explicit_named_dots) > 0) {
    unsupported <- setdiff(explicit_named_dots, fn_formals)
    if (length(unsupported) > 0) {
      warning(sprintf(
        "Experiment function '%s' does not accept these arguments: %s. Ignored.",
        exp_name, paste(unsupported, collapse = ", ")
      ))
    }
  }

  # --------------------------
  # Determine file encoding for CSV
  # --------------------------
  sys_name <- Sys.info()[["sysname"]]
  file_enc <- ifelse(sys_name == "Windows", "GB18030", "UTF-8")

  all_results <- list()

  # --------------------------
  # Loop over models
  # --------------------------
  for (m in seq_len(nrow(model_df))) {
    # --------------------------
    # Prepare model info and file paths
    # --------------------------
    model_info <- model_df[m, , drop = FALSE]

    # 原始模型名
    model_file_name_orig <- as.character(model_info$ModelName)

    # 标准化文件名/日志名
    model_file_name <- gsub("[^A-Za-z0-9_-]", "_", model_file_name_orig)

    # 判断是否启用思考模式，不启用则加 _FAST
    enable_thinking <- as.logical(model_info$Enable_Thinking)
    if (!enable_thinking) model_file_name <- paste0(model_file_name, "_FAST")

    # 输出文件路径
    model_path <- file.path(model_dir, paste0(model_file_name, ".csv"))

    # GitHub风格日志
    message("[PsyLingLLM] Running trials for model: ", model_file_name)

    # --------------------------
    # Prepare arguments for experiment function
    # --------------------------
    base_args <- list(
      data = data,
      api_key = model_info$API_Key,
      model = model_file_name_orig,
      api_url = model_info$API_URL,
      enable_thinking = enable_thinking,
      max_tokens = max_tokens,
      temperature = temperature,
      random = random,
      output_path = model_path
    )

    # Merge with dots
    args_candidates <- modifyList(base_args, dots_list)
    if (!has_dots) args_candidates <- args_candidates[names(args_candidates) %in% fn_formals]

    # Call experiment function safely
    res <- tryCatch({
      suppressMessages(
      do.call(exp_fn, args_candidates))
    }, error = function(e) {
      warning(sprintf("Model '%s' failed: %s", model_file_name, e$message))
      NULL
    })

    # Save per-model result
    if (!is.null(res) && is.data.frame(res)) {
      tryCatch({
        write.csv(res, file = model_path, row.names = FALSE, fileEncoding = file_enc, quote = TRUE)
        message("Saved per-model results: ", model_path)
      }, error = function(e) {
        warning(sprintf("Failed to save results for '%s': %s", model_file_name, e$message))
      })
    }

    all_results[[m]] <- res
  }

  # --------------------------
  # Merge non-null results
  # --------------------------
  non_null <- Filter(function(x) !is.null(x) && is.data.frame(x), all_results)
  combined <- if (length(non_null) > 0) do.call(rbind, non_null) else data.frame()

  combined_path <- file.path(output_path, paste0("MultiModel_Results", ".csv"))
  tryCatch({
    write.csv(combined, file = combined_path, row.names = FALSE, fileEncoding = file_enc, quote = TRUE)
    message("\n[PsyLingLLM] All model results successfully saved to: ", combined_path)
  }, error = function(e) warning("Failed to save combined CSV: ", e$message))

  if (isTRUE(return_combined)) return(combined) else invisible(NULL)
}
