read_typed_response_fixture <- function(name) {
  jsonlite::fromJSON(
    test_path("fixtures", name),
    simplifyVector = FALSE
  )
}

make_typed_transport_response <- function(parsed = NULL,
                                          events = list(),
                                          streaming = FALSE,
                                          status = 200L,
                                          error = NULL,
                                          headers = NULL) {
  legacy <- if (streaming) {
    list(
      status = status,
      headers = headers,
      raw_json = events,
      raw_lines = NULL,
      first_token_latency = 0.1,
      error = error
    )
  } else {
    list(
      status = status,
      headers = headers,
      text = if (is.null(parsed)) NULL else jsonlite::toJSON(
        parsed, auto_unbox = TRUE
      ),
      parsed = parsed,
      error = error
    )
  }
  normalize_llm_transport_response(
    legacy,
    if (streaming) "sse_json" else "http_json",
    "{}"
  )
}

test_that("openai_chat parses typed non-stream responses", {
  response <- make_typed_transport_response(
    parsed = read_typed_response_fixture("openai-chat-nonstream.json")
  )

  result <- parse_llm_response(response, "openai_chat")

  expect_identical(result$answer, "Fixture answer")
  expect_identical(result$reasoning, "Fixture reasoning")
  expect_identical(result$usage, list(prompt = 12L, completion = 6L))
  expect_identical(result$request_id, "chatcmpl_fixture")
  expect_identical(result$finish_reason, "stop")
  expect_null(result$error)
})

test_that("openai_chat parses typed stream events", {
  response <- make_typed_transport_response(
    events = read_typed_response_fixture("openai-chat-stream.json"),
    streaming = TRUE
  )

  result <- parse_llm_response(
    response, "openai_chat", streaming = TRUE
  )

  expect_identical(result$answer, "Hello world")
  expect_identical(result$reasoning, "Think first")
  expect_identical(result$usage, list(prompt = 8L, completion = 4L))
  expect_identical(result$request_id, "chatcmpl_stream_fixture")
  expect_identical(result$finish_reason, "stop")
})

test_that("openai_responses parses typed output items", {
  response <- make_typed_transport_response(
    parsed = read_typed_response_fixture("openai-responses-nonstream.json")
  )

  result <- parse_llm_response(response, "openai_responses")

  expect_identical(
    result$answer,
    "First paragraph. Second paragraph."
  )
  expect_identical(result$reasoning, "Reasoning summary")
  expect_identical(result$usage, list(prompt = 15L, completion = 9L))
  expect_identical(result$request_id, "resp_fixture")
  expect_identical(result$finish_reason, "completed")
})

test_that("openai_responses parses typed stream events", {
  response <- make_typed_transport_response(
    events = read_typed_response_fixture("openai-responses-stream.json"),
    streaming = TRUE
  )

  result <- parse_llm_response(
    response, "openai_responses", streaming = TRUE
  )

  expect_identical(result$answer, "Hello responses")
  expect_identical(result$reasoning, "Plan carefully")
  expect_identical(result$usage, list(prompt = 11L, completion = 5L))
  expect_identical(result$request_id, "resp_stream_fixture")
  expect_identical(result$finish_reason, "completed")
})

test_that("anthropic_messages parses typed content blocks", {
  response <- make_typed_transport_response(
    parsed = read_typed_response_fixture("anthropic-messages-nonstream.json")
  )

  result <- parse_llm_response(response, "anthropic_messages")

  expect_identical(result$answer, "Fixture answer")
  expect_identical(result$reasoning, "Fixture thought")
  expect_identical(result$usage, list(prompt = 10L, completion = 7L))
  expect_identical(result$request_id, "msg_fixture")
  expect_identical(result$finish_reason, "end_turn")
})

test_that("anthropic_messages parses typed stream events", {
  response <- make_typed_transport_response(
    events = read_typed_response_fixture("anthropic-messages-stream.json"),
    streaming = TRUE
  )

  result <- parse_llm_response(
    response, "anthropic_messages", streaming = TRUE
  )

  expect_identical(result$answer, "Hello Claude")
  expect_identical(result$reasoning, "Think carefully")
  expect_identical(result$usage, list(prompt = 13L, completion = 8L))
  expect_identical(result$request_id, "msg_stream_fixture")
  expect_identical(result$finish_reason, "end_turn")
})

test_that("typed parsers surface provider errors and ignore unknown events", {
  openai_error <- make_typed_transport_response(
    parsed = list(error = list(message = "Rate limited")),
    status = 429L
  )
  error_result <- parse_llm_response(openai_error, "openai_chat")

  expect_identical(
    error_result$error[c("code", "message")],
    list(code = 429L, message = "Rate limited")
  )

  anthropic_events <- list(
    list(type = "ping"),
    list(type = "future_event", payload = list(value = 1)),
    list(
      type = "error",
      error = list(type = "overloaded_error", message = "Overloaded")
    )
  )
  anthropic_error <- parse_llm_response(
    make_typed_transport_response(
      events = anthropic_events,
      streaming = TRUE
    ),
    "anthropic_messages",
    streaming = TRUE
  )

  expect_identical(anthropic_error$answer, "")
  expect_identical(anthropic_error$status, 529L)
  expect_identical(
    anthropic_error$error[c("code", "message")],
    list(code = 529L, message = "Overloaded")
  )
})

test_that("unknown streaming provider errors cannot appear successful", {
  response <- make_typed_transport_response(
    events = list(list(
      type = "error",
      error = list(code = "unexpected", message = "Stream failed")
    )),
    streaming = TRUE
  )

  result <- parse_llm_response(
    response,
    "openai_responses",
    streaming = TRUE
  )

  expect_identical(result$status, 500L)
  expect_identical(
    result$error[c("code", "message")],
    list(code = 500L, message = "Stream failed")
  )
})

test_that("provider error evidence and header request IDs survive parsing", {
  body <- list(error = list(
    message = "Unsupported value",
    type = "invalid_request_error",
    param = "future_parameter",
    code = "unsupported_value"
  ))
  response <- make_typed_transport_response(
    parsed = body,
    status = 400L,
    headers = c(`x-request-id` = "request-from-header")
  )

  result <- parse_llm_response(response, "openai_chat")

  expect_identical(result$request_id, "request-from-header")
  expect_identical(result$error$code, 400L)
  expect_identical(result$error$message, "Unsupported value")
  expect_identical(result$error$type, "invalid_request_error")
  expect_identical(result$error$param, "future_parameter")
  expect_identical(result$error$provider_code, "unsupported_value")
  expect_identical(result$error$body, body)
  expect_identical(result$error$headers[["x-request-id"]], "request-from-header")
  expect_identical(result$error$request_id, "request-from-header")
})

test_that("plain-text provider errors remain actionable", {
  response <- normalize_llm_transport_response(
    list(status = 502L, text = "upstream gateway failed", error = NULL),
    "http_json",
    "{}"
  )

  result <- parse_llm_response(response, "openai_chat")

  expect_identical(result$error$code, 502L)
  expect_identical(result$error$message, "upstream gateway failed")
  expect_identical(result$error$body, "upstream gateway failed")
})

test_that("typed parsers normalize empty and malformed provider payloads", {
  for (parser_id in c(
    "openai_chat", "openai_responses", "anthropic_messages"
  )) {
    result <- parse_llm_response(
      make_typed_transport_response(parsed = list(unexpected = TRUE)),
      parser_id
    )

    expect_identical(result$answer, "")
    expect_null(result$reasoning)
    expect_identical(
      result$usage,
      list(prompt = NULL, completion = NULL)
    )
    expect_null(result$request_id)
    expect_null(result$error)
  }
})
