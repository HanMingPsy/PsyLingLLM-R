#' Parse inline reasoning markers (e.g., Claude <thinking> and <answer>)
#'
#' @param text Character string with raw output.
#' @param markers A list with keys "think" and "answer".
#' @return List(answer, think)
#' @noRd
parse_inline_reasoning <- function(text, markers) {
  reasoning <- NA_character_
  answer <- text

  if (!is.null(markers$think)) {
    m <- regexec("<thinking>(.*?)</thinking>", text)
    g <- regmatches(text, m)
    if (length(g) > 0 && length(g[[1]]) > 1) {
      reasoning <- g[[1]][2]
    }
    if (is.null(markers$answer)) {
      answer <- sub(".*</thinking>", "", text)
    }
  }
  if (!is.null(markers$answer)) {
    m <- regexec("<answer>(.*?)</answer>", text)
    g <- regmatches(text, m)
    if (length(g) > 0 && length(g[[1]]) > 1) {
      answer <- g[[1]][2]
    }
  }

  list(
    answer = stringr::str_trim(answer),
    think = stringr::str_trim(reasoning)
  )
}

#' Parse response and reasoning (streaming or non-streaming) using new registry keys
#'
#' Supports:
#' - cfg$respond$respond_path (answer)
#' - cfg$respond$thinking_path (reasoning, non-stream)
#' - cfg$streaming$delta_path (answer deltas)
#' - cfg$streaming$thinking_delta_path (reasoning deltas)
#' Also keeps backward-compat with cfg$reasoning$* and inline markers.
#'
#' @noRd
parse_answer_and_think <- function(cfg,
                                   resp = NULL,
                                   response_buf = NULL,
                                   think_buf = NULL,
                                   fallback_text = NULL) {
  response <- fallback_text
  think <- NA_character_

  has_inline_field <- !is.null(cfg$reasoning$reasoning_field)
  has_think_path   <- !is.null(cfg$respond$thinking_path) || !is.null(cfg$reasoning$reasoning_path)
  has_think_delta  <- !is.null(cfg$streaming$thinking_delta_path) || !is.null(cfg$streaming$reasoning_delta_path)

  # ---------- streaming ----------
  if (!is.null(response_buf) || !is.null(think_buf)) {
    resp_text  <- if (length(response_buf)) paste(response_buf, collapse = "") else ""
    think_text <- if (length(think_buf)) paste(think_buf, collapse = "") else NA_character_

    if (has_think_delta) {
      response <- resp_text
      think <- think_text
      return(list(response = response, think = think))
    }
    if (has_inline_field) {
      parsed <- parse_inline_reasoning(resp_text, cfg$reasoning$reasoning_field)
      return(list(response = parsed$answer, think = parsed$think))
    }
    return(list(response = resp_text, think = NA_character_))
  }

  # ---------- non-streaming ----------
  if (!is.null(resp)) {
    # answer
    response <- extract_by_path(resp, cfg$respond$respond_path) %||% fallback_text

    # think (new key first, then legacy)
    if (!is.null(cfg$respond$thinking_path)) {
      think <- extract_by_path(resp, cfg$respond$thinking_path) %||% NA_character_
    } else if (!is.null(cfg$reasoning$reasoning_path)) {
      think <- extract_by_path(resp, cfg$reasoning$reasoning_path) %||% NA_character_
    }

    # inline markers (Claude/Qwen-style)
    if (!is.null(cfg$reasoning$reasoning_field)) {
      parsed <- parse_inline_reasoning(response, cfg$reasoning$reasoning_field)
      response <- parsed$answer
      think <- parsed$think
    }
  }

  list(response = response, think = think)
}

