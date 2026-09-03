# Runtime response parsing --------------------------------------------------

parse_llm_response <- function(response,
                               parser_id,
                               config = list(),
                               streaming = FALSE) {
  validate_llm_transport_response(response)
  validate_response_parser_id(parser_id)
  if (!is.list(config)) {
    llm_response_parser_abort(
      "Parser configuration must be a list.",
      parser_id = parser_id,
      reason = "invalid_config"
    )
  }
  if (!is.logical(streaming) || length(streaming) != 1L ||
      is.na(streaming)) {
    llm_response_parser_abort(
      "`streaming` must be a non-missing logical scalar.",
      parser_id = parser_id,
      reason = "invalid_config"
    )
  }

  parser <- llm_response_parsers()[[parser_id]]
  if (is.null(parser)) {
    llm_response_parser_abort(
      sprintf(
        "Response parser `%s` is recognized but not implemented. ",
        parser_id
      ),
      parser_id = parser_id,
      reason = "unavailable_parser"
    )
  }

  parsed <- parser(response, config, streaming)
  validate_llm_parsed_response(parsed, parser_id)
  parsed
}

llm_response_parsers <- function() {
  list(legacy_paths_v1 = parse_legacy_paths_response)
}

validate_response_parser_id <- function(parser_id) {
  valid <- is.character(parser_id) && length(parser_id) == 1L &&
    !is.na(parser_id) && nzchar(parser_id)
  if (!valid) {
    llm_response_parser_abort(
      "Parser ID must be a non-empty character scalar.",
      parser_id = parser_id,
      reason = "invalid_parser"
    )
  }
  if (!parser_id %in% registry_v2_component_ids()$response_parsers) {
    llm_response_parser_abort(
      sprintf("Unknown response parser `%s`.", parser_id),
      parser_id = parser_id,
      reason = "unknown_parser"
    )
  }
  invisible(TRUE)
}

legacy_response_parser_config <- function(entry) {
  list(
    selectors = list(
      answer = entry$output$respond_path %||% NULL,
      reasoning = entry$output$thinking_path %||% NULL,
      request_id = entry$output$id_path %||% NULL,
      usage_prompt = entry$output$token_usage_path$prompt %||% NULL,
      usage_completion = entry$output$token_usage_path$completion %||% NULL,
      answer_delta = entry$streaming$delta_path %||% NULL,
      reasoning_delta = entry$streaming$thinking_delta_path %||% NULL
    )
  )
}

parse_legacy_paths_response <- function(response, config, streaming) {
  selectors <- config$selectors
  if (!is.list(selectors)) {
    llm_response_parser_abort(
      "The legacy response parser requires a `selectors` list.",
      parser_id = "legacy_paths_v1",
      reason = "invalid_config"
    )
  }

  values <- if (streaming) {
    parse_legacy_stream_values(response$events, selectors)
  } else {
    parse_legacy_nonstream_values(response$parsed, selectors)
  }

  structure(
    list(
      status = response$status,
      streaming = streaming,
      answer = values$answer,
      reasoning = values$reasoning,
      usage = values$usage,
      request_id = values$request_id,
      finish_reason = NULL,
      error = legacy_response_error(response)
    ),
    class = c("psylingllm_parsed_response", "list")
  )
}

parse_legacy_nonstream_values <- function(parsed, selectors) {
  answer <- if (!is.null(selectors$answer)) {
    extract_text_by_spec(parsed, selectors$answer)
  } else {
    ""
  }
  reasoning <- if (!is.null(selectors$reasoning)) {
    value <- extract_text_by_spec(parsed, selectors$reasoning)
    if (nzchar(value)) value else NULL
  } else {
    NULL
  }

  list(
    answer = as.character(answer %||% ""),
    reasoning = reasoning,
    usage = list(
      prompt = parse_legacy_integer(parsed, selectors$usage_prompt),
      completion = parse_legacy_integer(
        parsed, selectors$usage_completion
      )
    ),
    request_id = if (!is.null(selectors$request_id)) {
      suppressWarnings(as.character(
        extract_text_by_spec(parsed, selectors$request_id)
      ))
    } else {
      NULL
    }
  )
}

parse_legacy_stream_values <- function(events, selectors) {
  answer <- stream_reconstruct_text(events, selectors$answer_delta)
  reasoning <- if (!is.null(selectors$reasoning_delta)) {
    stream_reconstruct_text(events, selectors$reasoning_delta)
  } else {
    NULL
  }

  list(
    answer = as.character(answer %||% ""),
    reasoning = if (is.null(reasoning)) NULL else as.character(reasoning),
    usage = list(
      prompt = parse_legacy_stream_integer(
        events, selectors$usage_prompt
      ),
      completion = parse_legacy_stream_integer(
        events, selectors$usage_completion
      )
    ),
    request_id = if (!is.null(selectors$request_id)) {
      suppressWarnings(stream_reconstruct_text(
        events, selectors$request_id
      ))
    } else {
      NULL
    }
  )
}

parse_legacy_integer <- function(parsed, selector) {
  if (is.null(selector)) {
    return(NULL)
  }
  suppressWarnings(as.integer(extract_text_by_spec(parsed, selector)))
}

parse_legacy_stream_integer <- function(events, selector) {
  if (is.null(selector)) {
    return(NULL)
  }
  suppressWarnings(as.integer(stream_reconstruct_text(events, selector)))
}

legacy_response_error <- function(response) {
  if (response$status < 400L) {
    return(NULL)
  }
  message <- response$legacy$error %||% "HTTP error"
  list(code = response$status, message = message)
}

validate_llm_parsed_response <- function(response, parser_id = NULL) {
  required <- c(
    "status", "streaming", "answer", "reasoning", "usage",
    "request_id", "finish_reason", "error"
  )
  valid_usage <- is.list(response$usage) &&
    identical(names(response$usage), c("prompt", "completion"))
  valid <- is.list(response) && identical(names(response), required) &&
    is.integer(response$status) && length(response$status) == 1L &&
    !is.na(response$status) && is.logical(response$streaming) &&
    length(response$streaming) == 1L && !is.na(response$streaming) &&
    is.character(response$answer) && length(response$answer) == 1L &&
    valid_usage && (is.null(response$error) || is.list(response$error))
  if (!valid) {
    llm_response_parser_abort(
      "Parser produced an invalid normalized response.",
      parser_id = parser_id,
      reason = "invalid_response"
    )
  }
  invisible(TRUE)
}

#' Extract text by registry path spec (flat-key with optional ".." wildcard)
#' @keywords internal
extract_text_by_spec <- function(obj, path_spec) {
  nr <- normalize_path_key_with_regex(path_spec)
  paths <- tryCatch(
    flatten_json_paths(obj, keep_numeric = TRUE),
    error = function(error) data.frame()
  )
  if (!nrow(paths)) {
    return("")
  }
  hit <- paths$value[paths$path == nr$key]
  if (length(hit)) {
    value <- suppressWarnings(as.character(hit[[1L]]))
    return(if (length(value)) value else "")
  }
  if (!is.na(nr$regex)) {
    hit <- paths$value[grepl(nr$regex, paths$path)]
    if (length(hit)) {
      value <- suppressWarnings(as.character(hit[[1L]]))
      return(if (length(value)) value else "")
    }
  }
  ""
}

llm_response_parser_abort <- function(message, parser_id = NULL,
                                      reason = NULL) {
  condition <- structure(
    list(
      message = paste0("LLM response parsing failed: ", message),
      call = NULL,
      parser_id = parser_id,
      reason = reason
    ),
    class = c("llm_response_parser_error", "error", "condition")
  )
  stop(condition)
}
