# --------------------------
# Parse output adapter
# --------------------------
#' Parse response from different LLM models
#'
#' 统一解析不同 LLM 模型的 API 输出，并将思考内容（reasoning/注释/解析）与最终回答拆分。
#'
#' @param model Character. 模型名称
#' @param resp_body List. LLM API 返回的原始 body
#'
#' @return A list with elements:
#'   \item{model}{模型名称}
#'   \item{think}{思考内容（reasoning/注释/解析）}
#'   \item{response}{最终回答（已清理）}
#'
#' @export
parse_output <- function(model, resp_body) {
  model_lower <- tolower(model)
  content <- NULL
  think <- NA_character_

  # --- GPT 系列 ---
  if (grepl("gpt", model_lower) && !is.null(resp_body$choices)) {
    content <- resp_body$choices[[1]]$message$content %||% ""
    if (!is.null(resp_body$choices[[1]]$message$reasoning_content)) {
      think <- stringr::str_trim(resp_body$choices[[1]]$message$reasoning_content)
    }

    # --- Qwen 系列 ---
  } else if (grepl("qwen", model_lower) && !is.null(resp_body$choices)) {
    content <- resp_body$choices[[1]]$message$content %||% ""
    think_text <- stringr::str_match(content, "(?s)<think>\\s*(.*?)\\s*</think>")[,2]
    if (!is.na(think_text) && nzchar(stringr::str_trim(think_text))) {
      think <- stringr::str_trim(think_text)
    }
    content <- gsub("(?s)<think>.*?</think>", "", content, perl = TRUE)
    content <- stringr::str_trim(content)

    # --- Hunyuan 系列 ---
  } else if (grepl("hunyuan", model_lower)) {
    content <- resp_body$content %||%
      (if (!is.null(resp_body$choices)) resp_body$choices[[1]]$message$content else "")
    if (!is.null(content) &&
        grepl("<think>", content, fixed=TRUE) &&
        grepl("<answer>", content, fixed=TRUE)) {
      think_text <- stringr::str_match(content, "(?s)<think>\\s*(.*?)\\s*</think>")[,2]
      answer_text <- stringr::str_match(content, "(?s)<answer>\\s*(.*?)\\s*</answer>")[,2]
      think <- if (!is.na(think_text)) stringr::str_trim(think_text) else NA_character_
      content <- if (!is.na(answer_text)) stringr::str_trim(answer_text) else content
    }

    # --- GLM 系列 ---
  } else if (grepl("glm", model_lower)) {
    content <- resp_body$output_text %||% resp_body$output %||% ""

    # --- DeepCoder / DeepSeek 系列 ---
  } else if (grepl("deepcoder|deepseek", model_lower)) {
    content <- resp_body$output_text %||% resp_body$output %||% ""
  }

  if (is.null(content)) content <- ""

  # --- 统一后处理 ---
  processed <- postprocess_response(content, think)

  return(list(
    model = model,
    think = processed$think,
    response = processed$content
  ))
}

# --------------------------
# Post-process response
# --------------------------
#' Post-process model output
#'
#' 将非标准输出中的 reasoning/注释/解析/分析等内容从回答中剥离，
#' 并统一存入 think。
#'
#' @param content Character. 模型原始回答
#' @param think Character. 已提取的思考内容（若有）
#'
#' @return A list with elements:
#'   \item{content}{清理后的最终回答}
#'   \item{think}{合并后的思考内容}
#'
#' @keywords internal
postprocess_response <- function(content, think) {
  if (is.null(content) || !nzchar(content)) {
    return(list(content = content, think = think))
  }

  extracted_thinks <- c()

  # 1. 匹配带关键词的 reasoning（中/英文）
  keyword_patterns <- c(
    "(?s)[（(\\[]?(注[:：]|解析[:：]|解释[:：]|理由[:：]|思考[:：]|分析[:：]).*?[)）\\]]",
    "(?s)[（(\\[]?注[:：]|解析[:：]|解释[:：]|理由[:：]|思考[:：]|分析[:：].*?[)）\\]]",
    "(?s)[\\[(]?(Note[:：]|Explanation[:：]|Reasoning[:：]|Analysis[:：]).*?[)\\]]"
  )

  for (pat in keyword_patterns) {
    matches <- stringr::str_match_all(content, pat)[[1]]
    if (nrow(matches) > 0) {
      for (m in matches[,1]) {
        if (!is.na(m) && nzchar(stringr::str_trim(m))) {
          extracted_thinks <- c(extracted_thinks, stringr::str_trim(m))
          content <- gsub(m, "", content, fixed = TRUE)
        }
      }
    }
  }

  # 2. 匹配句子后的“独立括号段落”
  generic_bracket_pattern <- "(?s)([。！？\\.!?]\\s*)\n\n[（(].*?[)）]$"
  matches <- stringr::str_match_all(content, generic_bracket_pattern)[[1]]
  if (nrow(matches) > 0) {
    for (m in matches[,1]) {
      if (!is.na(m) && nzchar(stringr::str_trim(m))) {
        # 去掉句子部分只保留括号
        bracket_only <- sub("^[。！？\\.!?]\\s*\n\n", "", m)
        extracted_thinks <- c(extracted_thinks, stringr::str_trim(bracket_only))
        content <- sub(m, "\\1", content, fixed = FALSE)
      }
    }
  }

  # 合并 think
  if (length(extracted_thinks) > 0) {
    if (is.na(think) || !nzchar(think)) {
      think <- paste(extracted_thinks, collapse = "\n")
    } else {
      think <- paste(think, paste(extracted_thinks, collapse = "\n"), sep = "\n")
    }
  }

  # 清理主回答
  content <- stringr::str_squish(content)

  return(list(content = content, think = think))
}



