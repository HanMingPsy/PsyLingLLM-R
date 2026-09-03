# Runtime transport ---------------------------------------------------------

send_llm_request <- function(request, debug = FALSE, transport = NULL) {
  validate_llm_request(request)
  payload <- encode_llm_request_body(request)

  if (is.null(transport)) {
    transports <- llm_transports()
    transport <- transports[[request$transport_id]]
    if (is.null(transport)) {
      llm_transport_abort(
        sprintf("Unknown transport `%s`.", request$transport_id),
        transport_id = request$transport_id,
        reason = "unknown_transport"
      )
    }
  }
  if (!is.function(transport)) {
    llm_transport_abort(
      "Injected transport must be a function.",
      transport_id = request$transport_id,
      reason = "invalid_transport"
    )
  }

  raw_response <- transport(request, payload, debug)
  response <- normalize_llm_transport_response(
    raw_response,
    request$transport_id,
    payload
  )
  validate_llm_transport_response(response)
  response
}

llm_transports <- function() {
  list(
    http_json = transport_http_json,
    sse_json = transport_sse_json
  )
}

encode_llm_request_body <- function(request) {
  if (!identical(request$encoding, "json")) {
    llm_transport_abort(
      sprintf("Unsupported request encoding `%s`.", request$encoding),
      transport_id = request$transport_id,
      reason = "unsupported_encoding"
    )
  }
  jsonlite::toJSON(
    request$body,
    auto_unbox = TRUE,
    null = "null",
    digits = NA
  )
}

transport_http_json <- function(request, payload, debug = FALSE) {
  do_nonstream_request(
    request$url,
    request$headers,
    payload,
    timeout = request$timeout,
    debug = debug
  )
}

transport_sse_json <- function(request, payload, debug = FALSE) {
  do_stream_request(
    request$url,
    request$headers,
    payload,
    timeout = request$timeout,
    debug = debug
  )
}

normalize_llm_transport_response <- function(response, transport_id,
                                             payload) {
  if (!is.list(response)) {
    llm_transport_abort(
      "Transport returned a non-list response.",
      transport_id = transport_id,
      reason = "invalid_response"
    )
  }
  status <- validate_transport_status(response$status, transport_id)
  error_message <- validate_transport_error(response$error, transport_id)
  error <- if (!is.null(response$error)) {
    list(
      type = if (identical(status, 599L)) {
        "connection"
      } else {
        "http"
      },
      message = error_message
    )
  } else if (status >= 400L) {
    list(type = "http", message = "HTTP error")
  } else {
    NULL
  }

  structure(
    list(
      transport_id = transport_id,
      status = as.integer(status),
      headers = response$headers %||% NULL,
      raw_body = response$raw_body %||% NULL,
      text = response$text %||% NULL,
      parsed = response$parsed %||% NULL,
      frames = response$raw_lines %||% NULL,
      events = response$raw_json %||% list(),
      timing = list(
        first_token_latency = response$first_token_latency %||% NA_real_
      ),
      error = error,
      request_payload = payload,
      legacy = response
    ),
    class = c("psylingllm_transport_response", "list")
  )
}

validate_transport_status <- function(status, transport_id) {
  status <- status %||% 599L
  valid <- is.numeric(status) && length(status) == 1L &&
    !is.na(status) && is.finite(status) && status >= 0 &&
    status == floor(status)
  if (!valid) {
    llm_transport_abort(
      "Transport returned an invalid HTTP status.",
      transport_id = transport_id,
      reason = "invalid_response"
    )
  }
  as.integer(status)
}

validate_transport_error <- function(error, transport_id) {
  if (is.null(error)) {
    return(NULL)
  }
  valid <- is.character(error) && length(error) == 1L &&
    !is.na(error) && nzchar(error)
  if (!valid) {
    llm_transport_abort(
      "Transport returned an invalid error message.",
      transport_id = transport_id,
      reason = "invalid_response"
    )
  }
  error
}

validate_llm_transport_response <- function(response) {
  required <- c(
    "transport_id", "status", "headers", "raw_body", "text", "parsed",
    "frames", "events", "timing", "error", "request_payload", "legacy"
  )
  valid <- is.list(response) && identical(names(response), required) &&
    is.character(response$transport_id) &&
    length(response$transport_id) == 1L &&
    is.integer(response$status) && length(response$status) == 1L &&
    !is.na(response$status) && is.list(response$events) &&
    is.list(response$timing) && is.list(response$legacy)
  if (!valid) {
    llm_transport_abort(
      "Transport produced an invalid normalized response.",
      transport_id = response$transport_id %||% NULL,
      reason = "invalid_response"
    )
  }
  invisible(TRUE)
}

as_legacy_nonstream_response <- function(response) {
  list(
    status = response$status,
    text = response$text,
    parsed = response$parsed,
    error = response$legacy$error %||% NULL
  )
}

as_legacy_stream_response <- function(response) {
  list(
    status = response$status,
    raw_json = response$events,
    raw_lines = response$legacy$raw_lines %||% NULL,
    first_token_latency = response$timing$first_token_latency,
    error = response$legacy$error %||% NULL
  )
}

new_sse_json_collector <- function(clock = Sys.time) {
  cache <- raw()
  raw_lines <- character()
  json_events <- list()
  first_token_latency <- NA_real_
  started_at <- clock()

  feed <- function(data) {
    if (!is.raw(data)) {
      llm_transport_abort(
        "SSE chunks must be raw vectors.",
        transport_id = "sse_json",
        reason = "invalid_chunk"
      )
    }
    cache <<- c(cache, data)
    newline_positions <- which(cache == as.raw(0x0a))
    if (length(newline_positions) == 0L) {
      return(TRUE)
    }

    starts <- c(1L, utils::head(newline_positions, -1L) + 1L)
    completed <- Map(function(start, end) {
      if (end < start) raw() else cache[start:end]
    }, starts, newline_positions - 1L)
    final_newline <- utils::tail(newline_positions, 1L)
    if (final_newline < length(cache)) {
      cache <<- cache[(final_newline + 1L):length(cache)]
    } else {
      cache <<- raw()
    }
    lines <- vapply(completed, function(line) {
      text <- iconv(
        rawToChar(line, multiple = FALSE),
        from = "UTF-8",
        to = "UTF-8",
        sub = ""
      )
      sub("\\r$", "", text)
    }, character(1))

    raw_lines <<- c(raw_lines, lines)
    data_lines <- grep("^data:", lines, value = TRUE)
    if (length(data_lines) == 0L) {
      return(TRUE)
    }
    if (is.na(first_token_latency)) {
      first_token_latency <<- as.numeric(difftime(
        clock(),
        started_at,
        units = "secs"
      ))
    }

    for (line in data_lines) {
      event_text <- sub("^data:\\s*", "", line)
      if (identical(event_text, "[DONE]")) {
        next
      }
      event <- parse_transport_json(event_text)
      if (!is.null(event)) {
        json_events[[length(json_events) + 1L]] <<- event
      }
    }
    TRUE
  }

  snapshot <- function(include_lines = FALSE) {
    list(
      raw_json = json_events,
      raw_lines = if (isTRUE(include_lines)) raw_lines else NULL,
      first_token_latency = first_token_latency
    )
  }

  finish <- function() {
    if (length(cache) > 0L) {
      pending <- cache
      cache <<- raw()
      feed(c(pending, as.raw(0x0a)))
    }
    invisible(TRUE)
  }

  list(feed = feed, finish = finish, snapshot = snapshot)
}

parse_transport_json <- function(text) {
  tryCatch(
    jsonlite::fromJSON(text, simplifyVector = FALSE),
    error = function(error) NULL
  )
}

# Compatibility executors retained for existing internal mocks.
do_nonstream_request <- function(url,
                                 headers,
                                 json_payload,
                                 timeout = 120,
                                 debug = FALSE) {
  payload <- transport_payload_text(json_payload)
  handle <- curl::new_handle()
  curl::handle_setheaders(handle, .list = headers)
  curl::handle_setopt(
    handle,
    customrequest = "POST",
    postfields = payload,
    timeout = as.integer(timeout)
  )

  response <- tryCatch(
    curl::curl_fetch_memory(url, handle = handle),
    error = function(error) error
  )
  if (inherits(response, "error")) {
    return(list(
      status = 599L,
      headers = NULL,
      raw_body = NULL,
      text = NULL,
      parsed = NULL,
      error = as.character(response$message)
    ))
  }

  text <- rawToChar(response$content)
  parsed <- parse_transport_json(text)
  if (isTRUE(debug)) {
    cat("----- [DEBUG non-stream] headers -----\n")
    print(headers)
    cat("----- [DEBUG non-stream] body -----\n")
    cat(payload, "\n")
  }

  list(
    status = response$status_code %||% 200L,
    headers = response$headers %||% NULL,
    raw_body = response$content,
    text = text,
    parsed = parsed,
    error = NULL
  )
}

do_stream_request <- function(url,
                              headers,
                              json_payload,
                              timeout = 120,
                              debug = FALSE) {
  payload <- transport_payload_text(json_payload)
  collector <- new_sse_json_collector()
  handle <- curl::new_handle()
  curl::handle_setheaders(handle, .list = headers)
  curl::handle_setopt(
    handle,
    customrequest = "POST",
    postfields = payload,
    timeout = as.integer(timeout)
  )

  if (isTRUE(debug)) {
    cat("----- [DEBUG stream] headers -----\n")
    print(headers)
    cat("----- [DEBUG stream] body -----\n")
    cat(payload, "\n")
  }

  response <- tryCatch(
    curl::curl_fetch_stream(url, collector$feed, handle = handle),
    error = function(error) error
  )
  collector$finish()
  collected <- collector$snapshot(include_lines = debug)
  if (inherits(response, "error")) {
    return(c(
      list(status = 599L, headers = NULL),
      collected,
      list(error = as.character(response$message))
    ))
  }

  c(
    list(
      status = response$status_code %||% 200L,
      headers = response$headers %||% NULL
    ),
    collected,
    list(error = NULL)
  )
}

transport_payload_text <- function(payload) {
  if (is.list(payload)) {
    return(jsonlite::toJSON(
      payload,
      auto_unbox = TRUE,
      null = "null",
      na = "null"
    ))
  }
  as.character(payload %||% "")
}

llm_transport_abort <- function(message, transport_id = NULL,
                                reason = NULL) {
  condition <- structure(
    list(
      message = paste0("LLM transport failed: ", message),
      call = NULL,
      transport_id = transport_id,
      reason = reason
    ),
    class = c("llm_transport_error", "error", "condition")
  )
  stop(condition)
}
