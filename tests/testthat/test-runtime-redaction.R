test_that("diagnostic redaction is recursive and leaves source unchanged", {
  source <- list(
    Authorization = "Bearer fake-secret-123",
    nested = list(api_key = "fake-body-key", max_tokens = 10L),
    text = 'Bearer echoed-secret api_key="echoed-key"'
  )

  redacted <- redact_llm_diagnostics(source)

  expect_identical(source$Authorization, "Bearer fake-secret-123")
  expect_identical(redacted$Authorization, "[REDACTED]")
  expect_identical(redacted$nested$api_key, "[REDACTED]")
  expect_identical(redacted$nested$max_tokens, 10L)
  expect_false(grepl("echoed-secret|echoed-key", redacted$text))
})

test_that("raw diagnostic headers redact credential-bearing lines", {
  headers <- charToRaw(paste0(
    "HTTP/1.1 400 Bad Request\r\n",
    "x-request-id: request-1\r\n",
    "set-cookie: fake-session-secret\r\n"
  ))

  redacted <- rawToChar(redact_llm_diagnostics(headers))

  expect_match(redacted, "x-request-id: request-1", fixed = TRUE)
  expect_false(grepl("fake-session-secret", redacted, fixed = TRUE))
  expect_match(redacted, "set-cookie: [REDACTED]", fixed = TRUE)
})

test_that("debug output is redacted while transport input remains intact", {
  headers <- list(
    Authorization = "Bearer fake-header-secret",
    `Content-Type` = "application/json"
  )
  payload <- '{"api_key":"fake-body-secret","input":"hello"}'

  local_mocked_bindings(
    new_handle = function() structure(list(), class = "curl_handle"),
    handle_setheaders = function(...) invisible(NULL),
    handle_setopt = function(...) invisible(NULL),
    curl_fetch_memory = function(url, handle) {
      list(status_code = 200L, headers = raw(), content = charToRaw("{}"))
    },
    .package = "curl"
  )

  output <- capture.output(
    do_nonstream_request(
      "https://example.invalid",
      headers,
      payload,
      debug = TRUE
    )
  )

  expect_false(any(grepl("fake-header-secret|fake-body-secret", output)))
  expect_true(any(grepl("REDACTED", output)))
  expect_identical(headers$Authorization, "Bearer fake-header-secret")
  expect_match(payload, "fake-body-secret", fixed = TRUE)
})

test_that("return_raw redacts request and echoed response secrets", {
  request <- structure(
    list(
      method = "POST",
      url = "https://example.invalid/v1/chat/completions",
      headers = list(`Content-Type` = "application/json"),
      body = list(model = "fixture-model"),
      encoding = "json",
      stream = FALSE,
      transport_id = "http_json",
      timeout = 30
    ),
    class = c("psylingllm_request", "list")
  )
  request$headers$Authorization <- "Bearer fake-request-secret"
  request$body$api_key <- "fake-body-secret"
  response_body <- list(
    echoed = list(api_key = "fake-response-secret"),
    message = "Bearer fake-text-secret"
  )
  transport <- normalize_llm_transport_response(
    list(
      status = 200L,
      text = jsonlite::toJSON(response_body, auto_unbox = TRUE),
      parsed = response_body,
      error = NULL
    ),
    "http_json",
    jsonlite::toJSON(request$body, auto_unbox = TRUE)
  )

  result <- normalize_llm_result(
    list(interface = list(response = list(parser = "legacy_paths_v1"))),
    list(model_key = "fixture-model", interface = "chat"),
    request,
    transport,
    structure(
      list(
        status = 200L,
        streaming = FALSE,
        answer = "Answer",
        reasoning = NULL,
        usage = list(prompt = NULL, completion = NULL),
        request_id = NULL,
        finish_reason = NULL,
        error = NULL
      ),
      class = c("psylingllm_parsed_response", "list")
    ),
    return_raw = TRUE
  )
  rendered <- paste(capture.output(str(result$raw)), collapse = "\n")

  expect_false(grepl("fake-request-secret", rendered, fixed = TRUE))
  expect_false(grepl("fake-body-secret", rendered, fixed = TRUE))
  expect_false(grepl("fake-response-secret", rendered, fixed = TRUE))
  expect_false(grepl("fake-text-secret", rendered, fixed = TRUE))
  expect_match(rendered, "REDACTED", fixed = TRUE)
})
