# Runtime result normalization ---------------------------------------------

normalize_llm_result <- function(config,
                                 compatibility_entry,
                                 request,
                                 transport_response,
                                 parsed_response,
                                 return_raw = FALSE) {
  validate_llm_request(request)
  validate_llm_transport_response(transport_response)
  validate_llm_parsed_response(
    parsed_response,
    config$interface$response$parser
  )

  usage <- c(
    parsed_response$usage,
    list(id = parsed_response$request_id)
  )
  public_status <- if (is.null(parsed_response$error)) {
    parsed_response$status
  } else {
    599L
  }
  response_status <- classify_normalized_response(parsed_response)
  raw_request <- if (isTRUE(return_raw)) {
    redact_llm_diagnostics(list(
      url = request$url,
      headers = request$headers,
      body = jsonlite::fromJSON(
        transport_response$request_payload,
        simplifyVector = FALSE
      )
    ))
  } else {
    NULL
  }

  if (request$stream) {
    legacy_response <- as_legacy_stream_response(transport_response)
    return(list(
      status = public_status,
      interface = compatibility_entry$interface,
      model_key = compatibility_entry$model_key,
      streaming = TRUE,
      usage = usage,
      answer = parsed_response$answer,
      thinking = parsed_response$reasoning,
      response_status = response_status,
      first_token_latency = transport_response$timing$first_token_latency,
      raw = if (isTRUE(return_raw)) {
        redact_llm_diagnostics(list(
          request = raw_request,
          response = list(stream = legacy_response)
        ))
      } else {
        NULL
      },
      error = redact_llm_diagnostics(parsed_response$error)
    ))
  }

  legacy_response <- as_legacy_nonstream_response(transport_response)
  list(
    status = public_status,
    interface = compatibility_entry$interface,
    model_key = compatibility_entry$model_key,
    streaming = FALSE,
    usage = usage,
    answer = parsed_response$answer,
    thinking = parsed_response$reasoning,
    response_status = response_status,
    raw = if (isTRUE(return_raw)) {
      redact_llm_diagnostics(list(
        request = raw_request,
        response = list(non_stream = list(
          status = legacy_response$status,
          text = legacy_response$text,
          parsed = legacy_response$parsed
        ))
      ))
    } else {
      NULL
    },
    error = redact_llm_diagnostics(parsed_response$error)
  )
}

classify_normalized_response <- function(parsed_response) {
  if (!is.null(parsed_response$error)) {
    error_code <- suppressWarnings(
      as.integer(parsed_response$error$code %||% NA_integer_)
    )
    if (length(error_code) && !is.na(error_code[[1L]]) &&
        error_code[[1L]] == 599L) {
      return("TIMEOUT")
    }
    return("ERROR")
  }

  answer <- parsed_response$answer
  has_answer <- is.character(answer) && length(answer) > 0L &&
    any(!is.na(answer) & nzchar(trimws(answer)))
  if (has_answer) "OK" else "EMPTY_RESPONSE"
}

llm_result_abort <- function(message, reason = "invalid_result") {
  condition <- structure(
    list(
      message = paste0("LLM result normalization failed: ", message),
      call = NULL,
      reason = reason
    ),
    class = c("llm_result_error", "error", "condition")
  )
  stop(condition)
}
