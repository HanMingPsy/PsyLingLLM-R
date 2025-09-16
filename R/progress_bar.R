#' Update progress bar for experiment
#'
#' @param current 当前完成的试次数
#' @param total 总试次数
#' @param start_time 实验开始时间
#' @param bar_width 进度条宽度
#' @param model_name 模型名，用于显示
#' @return NULL (直接在控制台打印进度条)
#' @export
update_progress_bar <- function(current, total, start_time, bar_width = 40, model_name = "") {
  pct <- current / total
  n_filled <- round(pct * bar_width)
  n_empty <- bar_width - n_filled
  bar <- paste0(strrep("█", n_filled), strrep("░", n_empty))

  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  avg_time <- elapsed / max(current, 1)   # 避免除以0
  eta_sec <- round(avg_time * (total - current))

  # 转为整数
  eta_min <- as.integer(eta_sec %/% 60)
  eta_sec <- as.integer(eta_sec %% 60)

  eta_str <- sprintf("%02d:%02d", eta_min, eta_sec)

  line_width <- 120
  cat(sprintf("\r%-*s", line_width, ""))
  cat(sprintf("\r[%s] %3.0f%% Trial %d/%d - ETA: %s - %s",
              bar, pct * 100, current, total, eta_str, model_name))
  flush.console()
}
