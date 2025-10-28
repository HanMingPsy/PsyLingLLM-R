#' Update progress bar for an experiment
#'
#' @param current Number of trials completed so far
#' @param total Total number of trials
#' @param start_time Experiment start time
#' @param bar_width Width of the progress bar (default 40)
#' @param model_name Name of the model, for display purposes
#'
#' @importFrom utils flush.console
#'
#' @return NULL (prints the progress bar directly to the console)
#' @export
update_progress_bar <- function(current, total, start_time, bar_width = 40, model_name = "") {
  pct <- current / total
  n_filled <- round(pct * bar_width)
  n_empty <- bar_width - n_filled
  # bar <- paste0(strrep("█", n_filled), strrep("░", n_empty))
  bar <- paste0(strrep("\u2588", n_filled), strrep("\u2591", n_empty))

  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  avg_time <- elapsed / max(current, 1)   # Avoid division by zero
  eta_sec <- round(avg_time * (total - current))

  # Convert to integers
  eta_min <- as.integer(eta_sec %/% 60)
  eta_sec <- as.integer(eta_sec %% 60)

  eta_str <- sprintf("%02d:%02d", eta_min, eta_sec)

  line_width <- 120
  cat(sprintf("\r%-*s", line_width, ""))
  cat(sprintf("\r[%s] %3.0f%% Trial %d/%d - ETA: %s - %s",
              bar, pct * 100, current, total, eta_str, model_name))
  flush.console()
}
