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
  list(
    legacy_paths_v1 = parse_legacy_paths_response,
    openai_chat = parse_openai_chat_response,
    openai_responses = parse_openai_responses_response,
    anthropic_messages = parse_anthropic_messages_response
  )
}

runtime_response_parser_config <- function(config, compatibility_entry) {
  parser_id <- config$interface$response$parser
  if (identical(parser_id, "legacy_paths_v1")) {
    return(legacy_response_parser_config(compatibility_entry))
  }
  config$interface$response
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

parse_openai_chat_response <- function(response, config, streaming) {
  values <- if (streaming) {
    parse_openai_chat_events(response$events)
  } else {
    parse_openai_chat_body(response$parsed)
  }
  new_typed_parsed_response(response, streaming, values)
}

parse_openai_chat_body <- function(body) {
  body <- body %||% list()
  choice <- typed_first_list(body$choices)
  message <- choice$message %||% list()
  list(
    answer = typed_content_text(message$content),
    reasoning = typed_nullable_text(message$reasoning_content),
    usage = list(
      prompt = typed_integer(body$usage$prompt_tokens),
      completion = typed_integer(body$usage$completion_tokens)
    ),
    request_id = typed_character(body$id),
    finish_reason = typed_character(choice$finish_reason),
    error_message = typed_error_message(body$error),
    error_status = NULL
  )
}

parse_openai_chat_events <- function(events) {
  answers <- character()
  reasoning <- character()
  prompt_tokens <- NULL
  completion_tokens <- NULL
  request_id <- NULL
  finish_reason <- NULL
  error_message <- NULL

  for (event in events) {
    if (!is.list(event)) {
      next
    }
    choice <- typed_first_list(event$choices)
    delta <- choice$delta %||% list()
    answers <- c(answers, typed_content_text(delta$content))
    reasoning <- c(
      reasoning,
      typed_character(delta$reasoning_content) %||% character()
    )
    prompt_tokens <- typed_integer(event$usage$prompt_tokens) %||%
      prompt_tokens
    completion_tokens <- typed_integer(event$usage$completion_tokens) %||%
      completion_tokens
    request_id <- request_id %||% typed_character(event$id)
    finish_reason <- typed_character(choice$finish_reason) %||%
      finish_reason
    error_message <- error_message %||% typed_error_message(event$error)
  }

  list(
    answer = paste(answers, collapse = ""),
    reasoning = typed_collapsed_nullable(reasoning),
    usage = list(
      prompt = prompt_tokens,
      completion = completion_tokens
    ),
    request_id = request_id,
    finish_reason = finish_reason,
    error_message = error_message,
    error_status = NULL
  )
}

parse_openai_responses_response <- function(response, config, streaming) {
  values <- if (streaming) {
    parse_openai_responses_events(response$events)
  } else {
    parse_openai_responses_body(response$parsed)
  }
  new_typed_parsed_response(response, streaming, values)
}

parse_openai_responses_body <- function(body) {
  body <- body %||% list()
  channels <- parse_openai_response_items(body$output)
  list(
    answer = channels$answer,
    reasoning = channels$reasoning,
    usage = list(
      prompt = typed_integer(body$usage$input_tokens),
      completion = typed_integer(body$usage$output_tokens)
    ),
    request_id = typed_character(body$id),
    finish_reason = typed_character(body$incomplete_details$reason) %||%
      typed_character(body$status),
    error_message = typed_error_message(body$error),
    error_status = NULL
  )
}

parse_openai_response_items <- function(items) {
  answers <- character()
  reasoning_text <- character()
  reasoning_summary <- character()
  if (!is.list(items)) {
    return(list(answer = "", reasoning = NULL))
  }

  for (item in items) {
    if (!is.list(item)) {
      next
    }
    if (identical(item$type, "message") && is.list(item$content)) {
      for (block in item$content) {
        if (is.list(block) && identical(block$type, "output_text")) {
          answers <- c(answers, typed_character(block$text) %||% character())
        }
      }
    }
    if (identical(item$type, "reasoning")) {
      reasoning_text <- c(
        reasoning_text,
        typed_blocks_text(item$content, "reasoning_text", "text")
      )
      reasoning_summary <- c(
        reasoning_summary,
        typed_blocks_text(item$summary, "summary_text", "text")
      )
    }
  }

  reasoning <- if (length(reasoning_text)) {
    paste(reasoning_text, collapse = "")
  } else {
    typed_collapsed_nullable(reasoning_summary)
  }
  list(answer = paste(answers, collapse = ""), reasoning = reasoning)
}

parse_openai_responses_events <- function(events) {
  answers <- character()
  reasoning_text <- character()
  reasoning_summary <- character()
  completed_response <- NULL
  request_id <- NULL
  error_message <- NULL

  for (event in events) {
    if (!is.list(event)) {
      next
    }
    type <- typed_character(event$type)
    if (identical(type, "response.output_text.delta")) {
      answers <- c(answers, typed_character(event$delta) %||% character())
    } else if (identical(type, "response.reasoning_text.delta")) {
      reasoning_text <- c(
        reasoning_text,
        typed_character(event$delta) %||% character()
      )
    } else if (identical(type, "response.reasoning_summary_text.delta")) {
      reasoning_summary <- c(
        reasoning_summary,
        typed_character(event$delta) %||% character()
      )
    } else if (identical(type, "response.completed") ||
               identical(type, "response.incomplete") ||
               identical(type, "response.failed")) {
      completed_response <- event$response %||% completed_response
    } else if (identical(type, "error")) {
      error_message <- error_message %||% typed_error_message(event$error)
    }
    request_id <- request_id %||% typed_character(event$response$id)
  }

  completed <- parse_openai_responses_body(completed_response %||% list())
  answer <- if (length(answers)) {
    paste(answers, collapse = "")
  } else {
    completed$answer
  }
  reasoning <- if (length(reasoning_text)) {
    paste(reasoning_text, collapse = "")
  } else if (length(reasoning_summary)) {
    paste(reasoning_summary, collapse = "")
  } else {
    completed$reasoning
  }

  list(
    answer = answer,
    reasoning = reasoning,
    usage = completed$usage,
    request_id = request_id %||% completed$request_id,
    finish_reason = completed$finish_reason,
    error_message = error_message %||% completed$error_message,
    error_status = NULL
  )
}

parse_anthropic_messages_response <- function(response, config, streaming) {
  values <- if (streaming) {
    parse_anthropic_message_events(response$events)
  } else {
    parse_anthropic_message_body(response$parsed)
  }
  new_typed_parsed_response(response, streaming, values)
}

parse_anthropic_message_body <- function(body) {
  body <- body %||% list()
  list(
    answer = paste(
      typed_blocks_text(body$content, "text", "text"),
      collapse = ""
    ),
    reasoning = typed_collapsed_nullable(
      typed_blocks_text(body$content, "thinking", "thinking")
    ),
    usage = list(
      prompt = typed_integer(body$usage$input_tokens),
      completion = typed_integer(body$usage$output_tokens)
    ),
    request_id = typed_character(body$id),
    finish_reason = typed_character(body$stop_reason),
    error_message = typed_error_message(body$error),
    error_status = NULL
  )
}

parse_anthropic_message_events <- function(events) {
  answers <- character()
  reasoning <- character()
  prompt_tokens <- NULL
  completion_tokens <- NULL
  request_id <- NULL
  finish_reason <- NULL
  error_message <- NULL
  error_status <- NULL

  for (event in events) {
    if (!is.list(event)) {
      next
    }
    type <- typed_character(event$type)
    if (identical(type, "message_start")) {
      request_id <- request_id %||% typed_character(event$message$id)
      prompt_tokens <- typed_integer(event$message$usage$input_tokens) %||%
        prompt_tokens
      completion_tokens <- typed_integer(
        event$message$usage$output_tokens
      ) %||% completion_tokens
    } else if (identical(type, "content_block_delta")) {
      delta_type <- typed_character(event$delta$type)
      if (identical(delta_type, "text_delta")) {
        answers <- c(
          answers,
          typed_character(event$delta$text) %||% character()
        )
      } else if (identical(delta_type, "thinking_delta")) {
        reasoning <- c(
          reasoning,
          typed_character(event$delta$thinking) %||% character()
        )
      }
    } else if (identical(type, "message_delta")) {
      finish_reason <- typed_character(event$delta$stop_reason) %||%
        finish_reason
      completion_tokens <- typed_integer(event$usage$output_tokens) %||%
        completion_tokens
    } else if (identical(type, "error")) {
      error_message <- error_message %||% typed_error_message(event$error)
      error_status <- error_status %||% anthropic_error_status(
        typed_character(event$error$type)
      )
    }
  }

  list(
    answer = paste(answers, collapse = ""),
    reasoning = typed_collapsed_nullable(reasoning),
    usage = list(
      prompt = prompt_tokens,
      completion = completion_tokens
    ),
    request_id = request_id,
    finish_reason = finish_reason,
    error_message = error_message,
    error_status = error_status
  )
}

new_typed_parsed_response <- function(response, streaming, values) {
  error_message <- values$error_message
  if (is.null(error_message) && response$status >= 400L) {
    error_message <- response$legacy$error %||% "HTTP error"
  }
  status <- response$status
  if (!is.null(error_message) && status < 400L) {
    status <- values$error_status %||% 500L
  }
  error <- if (is.null(error_message)) {
    NULL
  } else {
    list(code = status, message = error_message)
  }

  structure(
    list(
      status = status,
      streaming = streaming,
      answer = values$answer %||% "",
      reasoning = values$reasoning %||% NULL,
      usage = values$usage %||% list(prompt = NULL, completion = NULL),
      request_id = values$request_id %||% NULL,
      finish_reason = values$finish_reason %||% NULL,
      error = error
    ),
    class = c("psylingllm_parsed_response", "list")
  )
}

typed_first_list <- function(value) {
  if (!is.list(value) || length(value) == 0L || !is.list(value[[1L]])) {
    return(list())
  }
  value[[1L]]
}

typed_character <- function(value) {
  if (!is.character(value) || length(value) == 0L || is.na(value[[1L]])) {
    return(NULL)
  }
  value[[1L]]
}

typed_integer <- function(value) {
  if (!is.numeric(value) || length(value) == 0L || is.na(value[[1L]]) ||
      !is.finite(value[[1L]])) {
    return(NULL)
  }
  suppressWarnings(as.integer(value[[1L]]))
}

typed_content_text <- function(content) {
  if (is.character(content)) {
    return(paste(content[!is.na(content)], collapse = ""))
  }
  paste(typed_blocks_text(content, "text", "text"), collapse = "")
}

typed_blocks_text <- function(blocks, type, field) {
  if (!is.list(blocks)) {
    return(character())
  }
  values <- lapply(blocks, function(block) {
    if (!is.list(block) || !identical(block$type, type)) {
      return(NULL)
    }
    typed_character(block[[field]])
  })
  unlist(Filter(Negate(is.null), values), use.names = FALSE)
}

typed_nullable_text <- function(value) {
  value <- typed_character(value)
  if (is.null(value) || !nzchar(value)) NULL else value
}

typed_collapsed_nullable <- function(values) {
  if (length(values) == 0L) {
    return(NULL)
  }
  value <- paste(values, collapse = "")
  if (nzchar(value)) value else NULL
}

typed_error_message <- function(error) {
  if (is.null(error)) {
    return(NULL)
  }
  if (is.character(error)) {
    return(typed_character(error))
  }
  if (is.list(error)) {
    return(typed_character(error$message))
  }
  NULL
}

anthropic_error_status <- function(type) {
  statuses <- c(
    invalid_request_error = 400L,
    authentication_error = 401L,
    permission_error = 403L,
    not_found_error = 404L,
    request_too_large = 413L,
    rate_limit_error = 429L,
    api_error = 500L,
    overloaded_error = 529L
  )
  if (is.null(type) || !type %in% names(statuses)) {
    return(500L)
  }
  unname(statuses[[type]])
}

validate_llm_parsed_response <- function(response, parser_id = NULL) {
  required <- c(
    "status", "streaming", "answer", "reasoning", "usage",
    "request_id", "finish_reason", "error"
  )
  if (!is.list(response) || !identical(names(response), required)) {
    llm_response_parser_abort(
      "Parser produced an invalid normalized response.",
      parser_id = parser_id,
      reason = "invalid_response"
    )
  }
  optional_character <- function(value) {
    is.null(value) || (
      is.character(value) && length(value) == 1L && !is.na(value)
    )
  }
  optional_integer <- function(value) {
    is.null(value) || (
      is.integer(value) && length(value) == 1L
    )
  }
  valid_usage <- is.list(response$usage) &&
    identical(names(response$usage), c("prompt", "completion")) &&
    optional_integer(response$usage$prompt) &&
    optional_integer(response$usage$completion)
  valid_error <- is.null(response$error) || (
    is.list(response$error) &&
      identical(names(response$error), c("code", "message")) &&
      is.integer(response$error$code) && length(response$error$code) == 1L &&
      !is.na(response$error$code) &&
      is.character(response$error$message) &&
      length(response$error$message) == 1L &&
      !is.na(response$error$message) && nzchar(response$error$message)
  )
  valid <-
    is.integer(response$status) && length(response$status) == 1L &&
    !is.na(response$status) && is.logical(response$streaming) &&
    length(response$streaming) == 1L && !is.na(response$streaming) &&
    is.character(response$answer) && length(response$answer) == 1L &&
    !is.na(response$answer) && optional_character(response$reasoning) &&
    valid_usage && optional_character(response$request_id) &&
    optional_character(response$finish_reason) && valid_error
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
