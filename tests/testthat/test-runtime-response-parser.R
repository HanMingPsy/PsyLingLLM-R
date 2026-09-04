make_parser_transport_response <- function(streaming = FALSE,
                                           status = 200L,
                                           parsed = NULL,
                                           events = list(),
                                           error = NULL) {
  legacy <- if (streaming) {
    list(
      status = status,
      raw_json = events,
      raw_lines = NULL,
      first_token_latency = 0.125,
      error = error
    )
  } else {
    list(
      status = status,
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

make_legacy_parser_config <- function() {
  list(
    selectors = list(
      answer = 'list("choices..message.content")',
      reasoning = 'list("choices..message.reasoning_content")',
      request_id = "id",
      usage_prompt = "usage.prompt_tokens",
      usage_completion = "usage.completion_tokens",
      answer_delta = 'list("choices..delta.content")',
      reasoning_delta = 'list("choices..delta.reasoning_content")'
    )
  )
}

test_that("legacy parser normalizes a non-stream response", {
  response <- make_parser_transport_response(parsed = list(
    id = "request-1",
    choices = list(list(message = list(
      content = "Answer",
      reasoning_content = "Reasoning"
    ))),
    usage = list(prompt_tokens = 9L, completion_tokens = 4L)
  ))

  result <- parse_llm_response(
    response,
    "legacy_paths_v1",
    make_legacy_parser_config()
  )

  expect_s3_class(result, "psylingllm_parsed_response")
  expect_identical(result$status, 200L)
  expect_false(result$streaming)
  expect_identical(result$answer, "Answer")
  expect_identical(result$reasoning, "Reasoning")
  expect_identical(result$usage, list(prompt = 9L, completion = 4L))
  expect_identical(result$request_id, "request-1")
  expect_null(result$finish_reason)
  expect_null(result$error)
})

test_that("legacy parser reconstructs stream channels independently", {
  events <- list(
    list(id = "stream-1", choices = list(list(
      delta = list(reasoning_content = "Think ")
    ))),
    list(choices = list(list(
      delta = list(reasoning_content = "carefully")
    ))),
    list(choices = list(list(delta = list(content = "Hello")))),
    list(choices = list(list(delta = list(content = " world")))),
    list(usage = list(prompt_tokens = 5L, completion_tokens = 2L))
  )
  response <- make_parser_transport_response(
    streaming = TRUE,
    events = events
  )

  result <- parse_llm_response(
    response,
    "legacy_paths_v1",
    make_legacy_parser_config(),
    streaming = TRUE
  )

  expect_true(result$streaming)
  expect_identical(result$answer, "Hello world")
  expect_identical(result$reasoning, "Think carefully")
  expect_identical(result$usage, list(prompt = 5L, completion = 2L))
  expect_identical(result$request_id, "stream-1")
})

test_that("legacy parser preserves empty and missing field semantics", {
  config <- make_legacy_parser_config()
  response <- make_parser_transport_response(parsed = list())

  result <- parse_llm_response(
    response,
    "legacy_paths_v1",
    config
  )

  expect_identical(result$answer, "")
  expect_null(result$reasoning)
  expect_true(is.na(result$usage$prompt))
  expect_true(is.na(result$usage$completion))
  expect_identical(result$request_id, "")

  config$selectors$reasoning_delta <- NULL
  stream_result <- parse_llm_response(
    make_parser_transport_response(streaming = TRUE),
    "legacy_paths_v1",
    config,
    streaming = TRUE
  )
  expect_identical(stream_result$answer, "")
  expect_null(stream_result$reasoning)
})

test_that("legacy parser preserves transport error compatibility", {
  response <- make_parser_transport_response(
    status = 599L,
    error = "Fixture timeout"
  )

  result <- parse_llm_response(
    response,
    "legacy_paths_v1",
    make_legacy_parser_config()
  )

  expect_identical(result$status, 599L)
  expect_identical(
    result$error,
    list(code = 599L, message = "Fixture timeout")
  )
})

test_that("parser IDs and configuration fail before semantic parsing", {
  response <- make_parser_transport_response(parsed = list())

  expect_error(
    parse_llm_response(response, "unknown", list()),
    class = "llm_response_parser_error"
  )
  expect_error(
    parse_llm_response(response, "legacy_paths_v1", list()),
    class = "llm_response_parser_error"
  )
  expect_error(
    parse_llm_response(
      response,
      "legacy_paths_v1",
      make_legacy_parser_config(),
      streaming = NA
    ),
    class = "llm_response_parser_error"
  )
})
