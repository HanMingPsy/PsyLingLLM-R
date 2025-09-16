# --------------------------
# Model-specific request adapter
# --------------------------
#' Adapt request body for different LLM models
#'
#' @param model model name
#' @param body_list list, request body
#' @param enable_thinking logical, whether thinking mode enabled
#' @return list, adapted body
#' @export
adapt_model_request <- function(model, body_list, enable_thinking = TRUE) {
  model_lower <- tolower(model)

  # --- GPT 系列 ---
  if (grepl("gpt", model_lower)) {
    if (!enable_thinking) body_list$reasoning_effort <- "low"
  }

  # --- Hunyuan 系列 ---
  else if (grepl("hunyuan", model_lower)) {
    body_list$enable_thinking <- enable_thinking
  }

  # --- GLM 系列 ---
  else if (grepl("glm", model_lower)) {
    body_list$mode <- if (enable_thinking) "thinking" else "non-thinking"
  }

  # --- DeepCoder / DeepSeek 系列 ---
  else if (grepl("deepcoder|deepseek", model_lower)) {
    body_list$fast_mode <- !enable_thinking
  }

  return(body_list)
}
