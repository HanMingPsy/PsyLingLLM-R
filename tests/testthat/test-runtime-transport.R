make_transport_request <- function(stream = FALSE) {
  structure(
    list(
      method = "POST",
      url = "https://example.invalid/v1/chat/completions",
      headers = list(`Content-Type` = "application/json"),
      body = list(model = "fixture-model", input = "Hello"),
      encoding = "json",
      stream = stream,
      transport_id = if (stream) "sse_json" else "http_json",
      timeout = 30
    ),
    class = c("psylingllm_request", "list")
  )
}

test_that("injected transport receives the request and encoded payload once", {
  calls <- 0L
  captured <- NULL
  executor <- function(request, payload, debug) {
    calls <<- calls + 1L
    captured <<- list(request = request, payload = payload, debug = debug)
    list(
      status = 201L,
      text = '{"ok":true}',
      parsed = list(ok = TRUE),
      error = NULL
    )
  }

  response <- send_llm_request(
    make_transport_request(),
    debug = TRUE,
    transport = executor
  )

  expect_identical(calls, 1L)
  expect_identical(captured$request$method, "POST")
  expect_true(grepl('"model":"fixture-model"', captured$payload))
  expect_true(captured$debug)
  expect_s3_class(response, "psylingllm_transport_response")
  expect_identical(response$status, 201L)
  expect_true(response$parsed$ok)
  expect_null(response$error)
})

test_that("http_json dispatcher preserves non-stream response fields", {
  local_mocked_bindings(
    do_nonstream_request = function(url,
                                    headers,
                                    json_payload,
                                    timeout,
                                    debug) {
      expect_identical(url, "https://example.invalid/v1/chat/completions")
      expect_identical(headers$`Content-Type`, "application/json")
      expect_identical(timeout, 30)
      expect_false(debug)
      list(
        status = 200L,
        text = '{"answer":"ok"}',
        parsed = list(answer = "ok"),
        error = NULL
      )
    },
    .package = "PsyLingLLM"
  )

  response <- send_llm_request(make_transport_request())
  legacy <- as_legacy_nonstream_response(response)

  expect_identical(response$transport_id, "http_json")
  expect_identical(response$text, '{"answer":"ok"}')
  expect_identical(response$parsed$answer, "ok")
  expect_identical(
    legacy,
    list(
      status = 200L,
      text = '{"answer":"ok"}',
      parsed = list(answer = "ok"),
      error = NULL
    )
  )
})

test_that("sse_json dispatcher preserves events frames and timing", {
  legacy_response <- list(
    status = 200L,
    raw_json = list(list(delta = "Hello"), list(delta = " world")),
    raw_lines = c('data: {"delta":"Hello"}', "data: [DONE]"),
    first_token_latency = 0.125,
    error = NULL
  )
  local_mocked_bindings(
    do_stream_request = function(...) legacy_response,
    .package = "PsyLingLLM"
  )

  response <- send_llm_request(
    make_transport_request(stream = TRUE),
    debug = TRUE
  )
  legacy <- as_legacy_stream_response(response)

  expect_identical(response$transport_id, "sse_json")
  expect_identical(response$events, legacy_response$raw_json)
  expect_identical(response$frames, legacy_response$raw_lines)
  expect_identical(response$timing$first_token_latency, 0.125)
  expect_identical(legacy, legacy_response)
})

test_that("transport errors are structured while status 599 is preserved", {
  response <- send_llm_request(
    make_transport_request(),
    transport = function(...) {
      list(
        status = 599L,
        text = NULL,
        parsed = NULL,
        error = "Fixture timeout"
      )
    }
  )

  expect_identical(response$status, 599L)
  expect_identical(
    response$error,
    list(type = "connection", message = "Fixture timeout")
  )
  expect_identical(
    as_legacy_nonstream_response(response)$error,
    "Fixture timeout"
  )
})

test_that("HTTP error status receives a structured generic error", {
  response <- send_llm_request(
    make_transport_request(),
    transport = function(...) {
      list(
        status = 429L,
        text = '{"error":"rate limited"}',
        parsed = list(error = "rate limited"),
        error = NULL
      )
    }
  )

  expect_identical(response$status, 429L)
  expect_identical(
    response$error,
    list(type = "http", message = "HTTP error")
  )
  expect_identical(response$parsed$error, "rate limited")
})

test_that("HTTP transports apply the caller timeout to connection setup", {
  captured <- list()
  local_mocked_bindings(
    new_handle = function() structure(list(), class = "curl_handle"),
    handle_setheaders = function(...) invisible(NULL),
    handle_setopt = function(handle, ...) {
      captured[[length(captured) + 1L]] <<- list(...)
      invisible(NULL)
    },
    curl_fetch_memory = function(url, handle) {
      list(status_code = 200L, headers = raw(), content = charToRaw("{}"))
    },
    curl_fetch_stream = function(url, fun, handle) {
      fun(charToRaw("data: [DONE]\n\n"))
      list(status_code = 200L, headers = raw())
    },
    .package = "curl"
  )

  do_nonstream_request(
    "https://example.invalid",
    list(`Content-Type` = "application/json"),
    "{}",
    timeout = 73L
  )
  do_stream_request(
    "https://example.invalid",
    list(`Content-Type` = "application/json"),
    "{}",
    timeout = 73L
  )

  expect_length(captured, 2L)
  for (options in captured) {
    expect_identical(options$timeout, 73L)
    expect_identical(options$connecttimeout, 73L)
  }
})

test_that("SSE collector handles arbitrary line chunk boundaries", {
  times <- as.POSIXct("2020-01-01 00:00:00", tz = "UTC") + c(0, 0.25)
  index <- 0L
  clock <- function() {
    index <<- index + 1L
    times[[index]]
  }
  collector <- new_sse_json_collector(clock)

  expect_true(collector$feed(charToRaw('data: {"delta":"Hel')))
  expect_true(collector$feed(charToRaw('lo"}\n\ndata: {bad}\n')))
  expect_true(collector$feed(charToRaw('data: {"delta":" world"}\n')))
  expect_true(collector$feed(charToRaw("data: [DONE]\n")))
  result <- collector$snapshot(include_lines = TRUE)

  expect_identical(
    result$raw_json,
    list(list(delta = "Hello"), list(delta = " world"))
  )
  expect_true(any(grepl("{bad}", result$raw_lines, fixed = TRUE)))
  expect_identical(result$first_token_latency, 0.25)
})

test_that("SSE collector preserves UTF-8 split across raw chunks", {
  collector <- new_sse_json_collector()
  encoded <- charToRaw('data: {"delta":"你好"}\n')
  multibyte_start <- which(as.integer(encoded) > 127L)[[1L]]

  collector$feed(encoded[seq_len(multibyte_start)])
  collector$feed(encoded[(multibyte_start + 1L):length(encoded)])
  result <- collector$snapshot()

  expect_identical(result$raw_json, list(list(delta = "你好")))
})

test_that("SSE collector flushes a final event without a newline", {
  collector <- new_sse_json_collector()

  collector$feed(charToRaw('data: {"delta":"final"}'))
  expect_identical(collector$snapshot()$raw_json, list())

  collector$finish()
  result <- collector$snapshot(include_lines = TRUE)

  expect_identical(result$raw_json, list(list(delta = "final")))
  expect_identical(result$raw_lines, 'data: {"delta":"final"}')
})

test_that("SSE collector ignores a final DONE marker without a newline", {
  collector <- new_sse_json_collector()

  collector$feed(charToRaw("data: [DONE]"))
  collector$finish()
  result <- collector$snapshot()

  expect_identical(result$raw_json, list())
})

test_that("transport response keeps semantic interpretation out of scope", {
  event <- list(
    choices = list(
      list(delta = list(content = "answer", reasoning_content = "trace"))
    ),
    usage = list(prompt_tokens = 3L)
  )
  response <- send_llm_request(
    make_transport_request(stream = TRUE),
    transport = function(...) {
      list(
        status = 200L,
        raw_json = list(event),
        raw_lines = NULL,
        first_token_latency = 0.1,
        error = NULL
      )
    }
  )

  expect_identical(response$events, list(event))
  expect_false("answer" %in% names(response))
  expect_false("reasoning" %in% names(response))
  expect_false("usage" %in% names(response))
})

test_that("invalid injected transports and responses fail before parsing", {
  expect_error(
    send_llm_request(make_transport_request(), transport = "invalid"),
    class = "llm_transport_error"
  )
  expect_error(
    send_llm_request(
      make_transport_request(),
      transport = function(...) "invalid"
    ),
    class = "llm_transport_error"
  )
})

test_that("invalid transport status and error fields fail consistently", {
  invalid_responses <- list(
    list(status = "200", error = NULL),
    list(status = NA_real_, error = NULL),
    list(status = 200.5, error = NULL),
    list(status = 599L, error = character()),
    list(status = 599L, error = NA_character_),
    list(status = 599L, error = "")
  )

  for (response in invalid_responses) {
    expect_error(
      send_llm_request(
        make_transport_request(),
        transport = function(...) response
      ),
      class = "llm_transport_error"
    )
  }
})
