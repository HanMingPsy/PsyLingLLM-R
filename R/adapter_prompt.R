# --------------------------
# Prepare prompt adapter
# --------------------------
#' Prepare model-specific prompt
#'
#' @param model model name
#' @param trial_prompt prompt text
#' @param material extra context/material
#' @param enable_thinking logical, whether thinking mode enabled
#' @return character, final prompt
#' @export
prepare_prompt <- function(model, trial_prompt, material, enable_thinking = TRUE) {
  prefix <- ""
  model_lower <- tolower(model)

  # --- Qwen 系列: fast 模式用 /no_think ---
  if (grepl("qwen", model_lower)) {
    if (!enable_thinking) prefix <- "/no_think "
  }

  # --- Hunyuan 系列: fast 模式用 /no_think ---
  if (grepl("hunyuan", model_lower)) {
    if (!enable_thinking) prefix <- "/no_think "
  }

  # 其他模型默认不加前缀
  return(paste0(prefix, trial_prompt, "\n", material))
}
