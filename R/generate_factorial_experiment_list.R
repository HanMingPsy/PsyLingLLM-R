#' @importFrom dplyr mutate select row_number all_of
#' @importFrom magrittr %>%
#' @importFrom readxl read_excel
#' @importFrom readr read_csv write_excel_csv locale
#' @importFrom stringi stri_enc_toutf8 stri_enc_isutf8 stri_replace_all_fixed
NULL

#' Generate LLM Experiment List for Factorial Design (UTF-8 safe)
#'
#' This function reads carrier sentences from a CSV/XLSX file or a data.frame,
#' optionally expands a CW (critical word) wide table into long format, applies factors,
#' repeats, randomizes order, and ensures UTF-8 safe text.
#'
#' @param data Path to CSV/XLSX file or a data.frame with columns `Item` and `Material`.
#' @param factors List of factors, e.g. `list(Congruity = c("Congruent","Incongruent"))`.
#' @param CW data.frame with `Item` and columns corresponding to factor-level combinations (wide format).
#' @param trial_prompt Character string applied globally if not overridden per trial.
#' @param repeats Integer, number of times to repeat the dataset.
#' @param random Logical, whether to randomize trial order.
#' @param force_base_cols Logical, whether to force `Run`/`Item` to appear first.
#' @param save_path Optional character, path to save the processed CSV/XLSX.
#'
#' @return A long-format data.frame with `Run`, `Item`, `Material`, `Word`, factor columns, `TrialPrompt`.
#' @export
generate_llm_factorial_experiment_list <- function(data,
                                                   factors,
                                                   CW = NULL,
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
      # Detect potential non-UTF8 characters in char columns
      char_cols <- names(df)[sapply(df, is.character)]
      any_nonutf8 <- any(sapply(df[char_cols], function(col) !stringi::stri_enc_isutf8(col)))
      if (any_nonutf8) {
        warning(
          "[PsyLingLLM] Warning: The input CSV file contains non-UTF-8 characters (e.g., smart quotes). ",
          "This may cause issues with LLM processing. Automatic conversion to UTF-8 was attempted. ",
          "To avoid potential problems, consider saving as XLSX."
        )
        df[, char_cols] <- lapply(df[, char_cols], stringi::stri_enc_toutf8)
      }
    } else if (ext %in% c("xls", "xlsx")) {
      df <- readxl::read_excel(data)
    } else {
      stop("Unsupported file type. Please use CSV or Excel (.xls/.xlsx).")
    }
  } else if (is.data.frame(data)) {
    df <- data
  } else {
    stop("'data' must be a data.frame or a valid CSV/XLSX path.")
  }

  factor_names <- names(factors)

  # --------------------------
  # 2. Convert CW wide table -> long table
  # --------------------------
  if (!is.null(CW)) {
    long_data <- data.frame()
    for (col in setdiff(colnames(CW), "Item")) {
      levels <- strsplit(col, "_")[[1]]
      if (length(levels) != length(factor_names)) stop("CW column name does not match number of factors.")
      temp <- data.frame(
        Item = CW$Item,
        Material = df$Material[CW$Item],
        Word = CW[[col]],
        stringsAsFactors = FALSE
      )
      for (i in seq_along(factor_names)) temp[[factor_names[i]]] <- levels[i]
      long_data <- rbind(long_data, temp)
    }
    df <- long_data
  } else {
    if (is.null(colnames(df)) || any(grepl("^X\\d+$", colnames(df))) || any(colnames(df) == "")) {
      warning("[PsyLingLLM] Input appears to have no proper headers. Using first column as 'Material', ignoring other unnamed columns.")
      colnames(df)[1] <- "Material"
      unnamed_cols <- which(grepl("^X\\d+$", colnames(df)) | colnames(df) == "")
      if (length(unnamed_cols) > 1) df <- df[, c(1, setdiff(seq_along(df), unnamed_cols[-1])), drop = FALSE]
    }
    if (!"Item" %in% colnames(df)) df$Item <- seq_len(nrow(df))

    # xpand factors
    if (!is.null(factors) && length(factors) > 0) {
      design <- expand.grid(factors, stringsAsFactors = FALSE)
      df <- merge(df, design, by = NULL)
    }
  }

  # --------------------------
  # 3. Replication & randomization
  # --------------------------
  df <- df[rep(seq_len(nrow(df)), repeats), , drop = FALSE]
  if (isTRUE(random)) df <- df[sample(nrow(df)), ]

  # --------------------------
  # 4. Generate Run column
  # --------------------------
  df$Run <- seq_len(nrow(df))

  # --------------------------
  # 5. Apply TrialPrompt
  # --------------------------
  if ("TrialPrompt" %in% colnames(df)) df$TrialPrompt[is.na(df$TrialPrompt)] <- trial_prompt
  else df$TrialPrompt <- trial_prompt

  # --------------------------
  # 6. Reorder columns
  # --------------------------
  cols_order <- c("Run", "Item", factor_names, "Material", "Word", "TrialPrompt")
  cols_order <- cols_order[cols_order %in% colnames(df)]
  if (force_base_cols) df <- df[, cols_order, drop = FALSE]

  # --------------------------
  # 7. Optional auto-save
  # --------------------------
  if (!is.null(save_path)) {
    ext <- tolower(tools::file_ext(save_path))
    if (ext %in% c("csv")) readr::write_excel_csv(df, save_path)
    else if (ext %in% c("xls","xlsx")) openxlsx::write.xlsx(df, save_path)
    else {
      warning("Unsupported save format; defaulting to CSV.")
      readr::write_excel_csv(df, paste0(save_path, ".csv"))
    }
  }

  return(df)
}
