#' Save Experiment Results to File
#'
#' Saves a data.frame of experiment results to a CSV or Excel file.
#' The default save location is the user's "Documents" directory if only a filename is provided.
#' If `enable_thinking = FALSE`, "_FAST" will be appended to the filename.
#'
#' @param data data.frame Result dataset.
#' @param output_path character File path (CSV or Excel). If only a filename is provided, it will be saved under the user's Documents folder.
#' @param enable_thinking logical Whether to enable "thinking mode" (affects filename suffix). Defaults to TRUE.
#'
#' @return NULL (the file is written to disk).
#' @export
save_experiment_results <- function(data, output_path, enable_thinking = TRUE, has_FAST = FALSE) {
  sys_name <- Sys.info()[["sysname"]]

  # If no directory is present in output_path, save to ~/Documents
  if (dirname(output_path) %in% c(".", "")) {
    doc_path <- path.expand("~/PsyLingLLM_Results")
    if (!dir.exists(doc_path)) dir.create(doc_path, recursive = TRUE)
    output_path <- file.path(doc_path, output_path)
  }


  ext <- tolower(tools::file_ext(output_path))
  base <- tools::file_path_sans_ext(output_path)
  output_path_mod <- if (!enable_thinking) {
    paste0(base, "_FAST.", ext)
  } else {
    output_path
  }

  if (ext == "csv") {
    file_enc <- ifelse(sys_name == "Windows", "GB18030", "UTF-8")
    tryCatch(
      {
        if(has_FAST){
        write.csv(
          data,
          file = output_path_mod,
          row.names = FALSE,
          fileEncoding = file_enc,
          quote = TRUE
        )
        message("Experiment results successfully saved as CSV: ", output_path_mod)}
        else{
          write.csv(
            data,
            file = output_path,
            row.names = FALSE,
            fileEncoding = file_enc,
            quote = TRUE
          )
          message("Experiment results successfully saved as CSV: ", output_path)
        }
      },
      error = function(e) warning("Failed to save CSV: ", e$message)
    )

  } else if (ext %in% c("xlsx", "xls")) {
    if (!requireNamespace("writexl", quietly = TRUE)) {
      stop("Package 'writexl' is required but not installed.")
    }
    tryCatch(
      {
        if(has_FAST){
          writexl::write_xlsx(data, path = output_path_mod)
          message("Experiment results successfully saved as Excel: ", output_path_mod)}
        else{
          writexl::write_xlsx(data, path = output_path)
          message("Experiment results successfully saved as Excel: ", output_path)}
      },
      error = function(e) warning("Failed to save Excel: ", e$message)
    )

  } else {
    warning("Unknown file extension. File not saved: ", output_path_mod)
  }
}
