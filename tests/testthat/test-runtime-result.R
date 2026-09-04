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
