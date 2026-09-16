make_result_request <- function(streaming = FALSE) {
  structure(
    list(
      method = "POST",
      url = "https://example.invalid/v1/chat/completions",
      headers = list(`Content-Type` = "application/json"),
      body = list(model = "fixture-model"),
      encoding = "json",
      stream = streaming,
      transport_id = if (streaming) "sse_json" else "http_json",
      timeout = 30
    ),
    class = c("psylingllm_request", "list")
  )
}

make_result_config <- function() {
  list(interface = list(response = list(parser = "legacy_paths_v1")))
}

make_result_entry <- function() {
  list(model_key = "fixture-model", interface = "chat")
}

make_parsed_result <- function(streaming = FALSE) {
  structure(
    list(
      status = 200L,
      streaming = streaming,
      answer = if (streaming) "Hi" else "Answer",
      reasoning = if (streaming) "Thought" else NULL,
      usage = list(prompt = 3L, completion = 2L),
      request_id = "request-1",
      finish_reason = "stop",
      error = NULL
    ),
    class = c("psylingllm_parsed_response", "list")
  )
}

test_that("result normalizer preserves the non-stream public contract", {
  body <- list(
    id = "request-1",
    choices = list(list(message = list(content = "Answer")))
  )
  transport <- normalize_llm_transport_response(
    list(
      status = 200L,
      text = jsonlite::toJSON(body, auto_unbox = TRUE),
      parsed = body,
      error = NULL
    ),
    "http_json",
    '{"model":"fixture-model"}'
  )

  result <- normalize_llm_result(
    make_result_config(),
    make_result_entry(),
    make_result_request(),
    transport,
    make_parsed_result(),
    return_raw = TRUE
  )

  expect_identical(
    names(result),
    c(
      "status", "interface", "model_key", "streaming", "usage",
      "answer", "thinking", "raw", "error"
    )
  )
  expect_identical(
    result$usage,
    list(prompt = 3L, completion = 2L, id = "request-1")
  )
  expect_identical(result$raw$request$body$model, "fixture-model")
  expect_identical(result$raw$response$non_stream$parsed, body)
})

test_that("result normalizer preserves the stream public contract", {
  events <- list(list(choices = list(list(delta = list(content = "Hi")))))
  transport <- normalize_llm_transport_response(
    list(
      status = 200L,
      raw_json = events,
      raw_lines = NULL,
      first_token_latency = 0.25,
      error = NULL
    ),
    "sse_json",
    '{"model":"fixture-model","stream":true}'
  )

  result <- normalize_llm_result(
    make_result_config(),
    make_result_entry(),
    make_result_request(streaming = TRUE),
    transport,
    make_parsed_result(streaming = TRUE),
    return_raw = TRUE
  )

  expect_identical(
    names(result),
    c(
      "status", "interface", "model_key", "streaming", "usage",
      "answer", "thinking", "first_token_latency", "raw", "error"
    )
  )
  expect_true(result$streaming)
  expect_identical(result$first_token_latency, 0.25)
  expect_identical(result$raw$response$stream$raw_json, events)
})

test_that("result normalizer preserves legacy return_raw semantics", {
  request <- make_result_request()
  transport <- normalize_llm_transport_response(
    list(status = 200L, text = "{}", parsed = list(), error = NULL),
    "http_json",
    "{}"
  )

  legacy_false_values <- list(NA, NULL, 1, c(TRUE, FALSE))
  for (return_raw in legacy_false_values) {
    result <- normalize_llm_result(
      make_result_config(),
      make_result_entry(),
      request,
      transport,
      make_parsed_result(),
      return_raw = return_raw
    )
    expect_null(result$raw)
  }
})

test_that("provider errors keep evidence behind public status 599", {
  provider_error <- list(
    message = "Unsupported value",
    type = "invalid_request_error",
    param = "max_tokens",
    code = "invalid_type"
  )
  provider_body <- list(error = provider_error)
  provider_headers <- c(`x-request-id` = "provider-request")

  for (streaming in c(FALSE, TRUE)) {
    legacy <- if (streaming) {
      list(
        status = 400L,
        headers = provider_headers,
        raw_json = list(provider_body),
        raw_lines = NULL,
        first_token_latency = 0.1,
        error = NULL
      )
    } else {
      list(
        status = 400L,
        headers = provider_headers,
        text = jsonlite::toJSON(provider_body, auto_unbox = TRUE),
        parsed = provider_body,
        error = NULL
      )
    }
    transport <- normalize_llm_transport_response(
      legacy,
      if (streaming) "sse_json" else "http_json",
      "{}"
    )
    parsed <- parse_llm_response(
      transport,
      "openai_chat",
      streaming = streaming
    )

    result <- normalize_llm_result(
      make_result_config(),
      make_result_entry(),
      make_result_request(streaming = streaming),
      transport,
      parsed,
      return_raw = TRUE
    )

    expect_identical(result$status, 599L)
    expect_identical(result$error, parsed$error)
    expect_identical(result$error$code, 400L)
    expect_identical(result$error$request_id, "provider-request")
    expect_identical(
      result$error$headers[["x-request-id"]],
      "provider-request"
    )
  }
})

test_that("transport status 599 remains a timeout-compatible result", {
  transport <- normalize_llm_transport_response(
    list(status = 599L, text = NULL, parsed = NULL, error = "Timed out"),
    "http_json",
    "{}"
  )
  parsed <- make_parsed_result()
  parsed$status <- 599L
  parsed$answer <- ""
  parsed$error <- list(code = 599L, message = "Timed out")

  result <- normalize_llm_result(
    make_result_config(),
    make_result_entry(),
    make_result_request(),
    transport,
    parsed
  )

  expect_identical(result$status, 599L)
  expect_identical(result$error$code, 599L)
})
