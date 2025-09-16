#' @importFrom dplyr mutate select row_number all_of
#' @importFrom readxl read_excel
#' @importFrom readr read_csv write_excel_csv
#' @importFrom stringi stri_enc_isutf8 stri_enc_toutf8
NULL

#' Generate LLM Experiment List (CSV→XLSX conversion, UTF-8 safe)
#'
#' Create an experiment trial table from a CSV/XLSX file or a data.frame.
#' CSV files are temporarily converted to XLSX to prevent encoding issues.
#' UTF-8 compatibility is ensured, and 'Item' and 'Run' are automatically generated if missing.
#'
#' @param data Path to CSV/XLSX file or a data.frame containing experiment materials.
#' @param trial_prompt Character string applied globally if not overridden per trial.
#' @param repeats Integer, number of times to repeat the dataset.
#' @param random Logical, whether to randomize trial order.
#' @param force_base_cols Logical, whether to force `Run` and `Item` to appear first.
#' @param save_path Optional path to save the processed CSV/XLSX file.
#'
#' @return A data.frame containing `Run`, `Item`, `Material`, optional metadata, and `TrialPrompt`.
#' @export
generate_llm_experiment_list <- function(data,
                                         trial_prompt = "",
                                         repeats = 1,
                                         random = FALSE,
                                         force_base_cols = TRUE,
                                         save_path = NULL) {

  # --------------------------
  # 1. Load data
  # --------------------------
  if (is.character(data) && length(data) == 1 && file.exists(data)) {
    ext <- tolower(tools::file_ext(data))
    if (ext == "csv") {
      df <- readr::read_csv(data, show_col_types = FALSE)
      # Detect non-UTF8 characters
      char_cols <- sapply(df, is.character)
      if (any(!sapply(df[, char_cols, drop = FALSE], stringi::stri_enc_isutf8))) {
        warning(
          "[PsyLingLLM] Warning: The input CSV file contains non-UTF-8 characters (e.g., smart quotes or special symbols). ",
          "This may cause display or processing issues in the LLM. Automatic conversion to UTF-8 was attempted. ",
          "To avoid potential problems, consider saving the file as XLSX."
        )
        df[, char_cols] <- lapply(df[, char_cols, drop = FALSE], stringi::stri_enc_toutf8)
      }
    } else if (ext %in% c("xls","xlsx")) {
      df <- readxl::read_excel(data)
    } else {
      stop("Unsupported file type. Please use CSV or Excel (.xls/.xlsx) files")
    }
  } else if (is.data.frame(data)) {
    df <- data
  } else {
    stop("'data' must be a data.frame or a valid file path (CSV/XLSX)")
  }

  # --------------------------
  # 2. Ensure 'Item' column
  # --------------------------
  if (!("Item" %in% colnames(df))) df$Item <- seq_len(nrow(df))

  # --------------------------
  # 3. Apply global TrialPrompt
  # --------------------------
  if (!("TrialPrompt" %in% colnames(df))) {
    df$TrialPrompt <- trial_prompt
  } else {
    df$TrialPrompt[is.na(df$TrialPrompt)] <- trial_prompt
  }

  # --------------------------
  # 4. Repeat & randomize
  # --------------------------
  repeats <- max(as.integer(repeats), 1)
  df <- df[rep(seq_len(nrow(df)), times = repeats), , drop = FALSE]
  if (isTRUE(random)) df <- df[sample(nrow(df)), , drop = FALSE]

  # --------------------------
  # 5. Generate Run column
  # --------------------------
  df$Run <- seq_len(nrow(df))

  # --------------------------
  # 6. Reorder columns
  # --------------------------
  if (force_base_cols) {
    base_cols <- c("Run","Item")
    base_cols <- base_cols[base_cols %in% colnames(df)]
    cond_cols <- grep("^(Condition|condition)", colnames(df), value = TRUE)
    fixed_cols <- c("TrialPrompt","Material")
    fixed_cols <- fixed_cols[fixed_cols %in% colnames(df)]
    other_cols <- setdiff(colnames(df), c(base_cols, cond_cols, fixed_cols))
    df <- df[, c(base_cols, cond_cols, fixed_cols, other_cols), drop = FALSE]
  }

  # --------------------------
  # 7. Auto-save CSV/XLSX
  # --------------------------
  if (!is.null(save_path)) {
    ext <- tolower(tools::file_ext(save_path))
    if (ext == "csv") {
      readr::write_excel_csv(df, save_path)
    } else if (ext %in% c("xls","xlsx")) {
      if (!requireNamespace("openxlsx", quietly = TRUE)) {
        stop("The 'openxlsx' package is required to save XLSX files.")
      }
      openxlsx::write.xlsx(df, save_path)
    } else {
      warning("Unsupported save format. Defaulting to CSV.")
      save_path <- paste0(save_path,".csv")
      readr::write_excel_csv(df, save_path)
    }
    message("Experiment file saved to: ", save_path)
  }

  return(df)
}
