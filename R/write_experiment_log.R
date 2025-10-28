#' Write experiment log entry
#'
#' Append a formatted log entry to the experiment log file.
#'
#' @param logfile Character. Path to log file.
#' @param stage Character. One of "start", "error", "warning", "end".
#' @param run_id Integer or NA. Run index (if applicable).
#' @param msg Character. Message text.
#' @param model Character. Model name (for start/end).
#' @param streaming Logical. Streaming flag (for start).
#' @param total_runs Integer. Total number of runs (for start/end).
#' @param success Integer. Successful runs (for end).
#' @param failed Integer. Failed runs (for end).
#' @param elapsed Numeric. Total elapsed seconds (for end).
#' @param output_path Character. Results file path (for start/end).
#'
#' @return Invisible TRUE
#' @noRd
write_experiment_log <- function(logfile,
                                 stage = c("start","error","warning","end"),
                                 run_id = NA,
                                 msg = NULL,
                                 model = NULL,
                                 streaming = NULL,
                                 total_runs = NULL,
                                 success = NULL,
                                 failed = NULL,
                                 elapsed = NULL,
                                 output_path = NULL) {
  stage <- match.arg(stage)
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

  entry <- switch(stage,
                  start = {
                    c(
                      "[PsyLingLLM] ===========================================",
                      "[PsyLingLLM] Experiment started",
                      sprintf("[PsyLingLLM] Date: %s", timestamp),
                      sprintf("[PsyLingLLM] Model: %s", model %||% "unknown"),
                      sprintf("[PsyLingLLM] Streaming: %s", ifelse(isTRUE(streaming), "TRUE", "FALSE")),
                      sprintf("[PsyLingLLM] Trials: %s", total_runs %||% "NA"),
                      sprintf("[PsyLingLLM] Output path: %s", output_path %||% "NA"),
                      "[PsyLingLLM] ==========================================="
                    )
                  },
                  error = {
                    sprintf("[PsyLingLLM] %s Run %s ERROR - %s",
                            timestamp,
                            ifelse(is.na(run_id), "NA", run_id),
                            msg %||% "Unknown error")
                  },
                  warning = {
                    sprintf("[PsyLingLLM] %s Run %s WARNING - %s",
                            timestamp,
                            ifelse(is.na(run_id), "NA", run_id),
                            msg %||% "Warning")
                  },
                  end = {
                    c(
                      if (!is.null(success) && !is.null(failed) && failed == 0) {
                        sprintf("[PsyLingLLM]\n[PsyLingLLM] No warnings or errors occurred during execution.\n[PsyLingLLM]")
                      }else NULL,
                      "[PsyLingLLM] ===========================================",
                      "[PsyLingLLM] Experiment completed",
                      sprintf("[PsyLingLLM] Date: %s", timestamp),
                      sprintf("[PsyLingLLM] Total runs: %s", total_runs %||% "NA"),
                      sprintf("[PsyLingLLM] Successful: %s", success %||% "NA"),
                      sprintf("[PsyLingLLM] Failed: %s", failed %||% "NA"),
                      sprintf("[PsyLingLLM] Total elapsed time: %.1f sec", elapsed %||% NA_real_),
                      "[PsyLingLLM] ==========================================="
                    )
                  }
  )

  write(entry, file = logfile, append = TRUE)
  invisible(TRUE)
}

