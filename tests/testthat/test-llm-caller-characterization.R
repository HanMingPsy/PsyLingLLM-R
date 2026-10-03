make_characterization_entry <- function(streaming = FALSE,
                                        provider = "official") {
  body <- list(
    model = "fixture-model",
    messages = list(
      list(role = "${ROLE}", content = "${CONTENT}")
    )
  )
  body[["${PARAMETER}"]] <- "${VALUE}"

  list(
    model_key = "fixture-model",
    interface = "chat",
    provider = provider,
    reasoning = TRUE,
    input = list(
      default_url = "https://example.invalid/v1/chat/completions",
      headers = list(`Content-Type` = "application/json"),
      body = body,
      fallback_body = NULL,
      optional_defaults = list(temperature = 0.2, stream = FALSE),
      default_system = "Default system message.",
      role_mapping = list(
        system = "system",
        user = "user",
        assistant = "assistant",
        tool = NULL
      )
    ),
    output = list(
      respond_path = 'list("choices..message.content")',
      thinking_path = 'list("choices..message.reasoning_content")',
      id_path = "id",
      object_path = "object",
      token_usage_path = list(
        prompt = "usage.prompt_tokens",
        completion = "usage.completion_tokens"
      )
    ),
    streaming = list(
      enabled = streaming,
      delta_path = 'list("choices..delta.content")',
      thinking_delta_path = 'list("choices..delta.reasoning_content")',
      param_name = "stream"
    )
  )
}

make_characterization_registry_context <- function(streaming = FALSE,
                                                   provider = "official") {
  entry <- make_characterization_entry(streaming, provider)
  registry_v1 <- list(`fixture-model` = list(chat = entry))
  registry_v2 <- as_registry_v2(registry_v1)
  list(
    bundle = list(
      raw = list(user = registry_v1, system = list(), default = list()),
      merged = registry_v2
    ),
    resolved = resolve_registry_entry(
      "fixture-model",
      generation_interface = "chat",
      registry = registry_v2
    )
  )
}

make_nonstream_response <- function(status = 200L,
                                    error = NULL) {
  parsed <- list(
    id = "request-nonstream",
    object = "chat.completion",
    choices = list(
      list(
        message = list(
          content = "Fixture answer",
          reasoning_content = "Fixture reasoning"
        )
      )
    ),
    usage = list(
      prompt_tokens = 11L,
      completion_tokens = 7L
    )
  )

  list(
    status = status,
    text = jsonlite::toJSON(parsed, auto_unbox = TRUE),
    parsed = parsed,
    error = error
  )
}

test_that("optionals retain their three-state resolution contract", {
  resolve_optionals <- getFromNamespace(
    "resolve_optionals_tristate",
    "PsyLingLLM"
  )
  defaults <- list(temperature = 0.2, stream = FALSE)

  expect_identical(resolve_optionals(TRUE, NULL, defaults), defaults)
  expect_identical(resolve_optionals(FALSE, NULL, defaults), list())
  expect_identical(
    resolve_optionals(FALSE, list(top_p = 0.9), defaults),
    list(top_p = 0.9)
  )
})

test_that("non-stream calls preserve message order and normalized results", {
  captured_request <- NULL

  local_mocked_bindings(
    registry_resolve_compatibility_context = function(...) {
      make_characterization_registry_context()
    },
    do_nonstream_request = function(url,
                                    headers,
                                    json_payload,
                                    timeout,
                                    debug) {
      captured_request <<- list(
        url = url,
        headers = headers,
        body = jsonlite::fromJSON(json_payload, simplifyVector = FALSE),
        timeout = timeout,
        debug = debug
      )
      make_nonstream_response()
    },
    .package = "PsyLingLLM"
  )

  result <- llm_caller(
    model_key = "fixture-model",
    trial_prompt = "Instruction",
    material = "Material",
    assistant_content = list(
      list(role = "user", content = "Earlier question"),
      list(role = "assistant", content = "Earlier answer")
    ),
    role_mapping = list(
      system = "developer",
      user = "human",
      assistant = "model"
    ),
    timeout = 45,
    return_raw = TRUE
  )

  expect_identical(
    vapply(captured_request$body$messages, `[[`, character(1), "role"),
    c("developer", "human", "model", "human")
  )
  expect_identical(
    vapply(captured_request$body$messages, `[[`, character(1), "content"),
    c(
      "Default system message.",
      "Earlier question",
      "Earlier answer",
      "Instruction\n\nMaterial"
    )
  )
  expect_identical(captured_request$body$temperature, 0.2)
  expect_identical(captured_request$body$stream, FALSE)
  expect_identical(captured_request$timeout, 45)

  expect_identical(
    names(result),
    c(
      "status",
      "interface",
      "model_key",
      "streaming",
      "usage",
      "answer",
      "thinking",
      "response_status",
      "raw",
      "error"
    )
  )
  expect_identical(result$status, 200L)
  expect_false(result$streaming)
  expect_identical(result$answer, "Fixture answer")
  expect_identical(result$thinking, "Fixture reasoning")
  expect_identical(result$usage$prompt, 11L)
  expect_identical(result$usage$completion, 7L)
  expect_identical(result$usage$id, "request-nonstream")
  expect_null(result$error)
  expect_identical(result$raw$request$url, captured_request$url)
})

test_that("named optionals replace rather than merge registry defaults", {
  captured_body <- NULL

  local_mocked_bindings(
    registry_resolve_compatibility_context = function(...) {
      make_characterization_registry_context()
    },
    do_nonstream_request = function(url,
                                    headers,
                                    json_payload,
                                    timeout,
                                    debug) {
      captured_body <<- jsonlite::fromJSON(
        json_payload,
        simplifyVector = FALSE
      )
      make_nonstream_response()
    },
    .package = "PsyLingLLM"
  )

  llm_caller(
    model_key = "fixture-model",
    material = "Material",
    optionals = list(top_p = 0.9)
  )

  expect_identical(captured_body$top_p, 0.9)
  expect_false("temperature" %in% names(captured_body))
})

test_that("legacy callers may add provider parameters through dots", {
  captured_body <- NULL

  local_mocked_bindings(
    registry_resolve_compatibility_context = function(...) {
      make_characterization_registry_context()
    },
    do_nonstream_request = function(url,
                                    headers,
                                    json_payload,
                                    timeout,
                                    debug) {
      captured_body <<- jsonlite::fromJSON(
        json_payload,
        simplifyVector = FALSE
      )
      make_nonstream_response()
    },
    .package = "PsyLingLLM"
  )

  expect_warning(
    llm_caller(
      model_key = "fixture-model",
      material = "Material",
      optionals = list(top_p = 0.8),
      top_p = 0.9,
      future_nested = list(mode = "high")
    ),
    "last value"
  )

  expect_identical(captured_body$top_p, 0.9)
  expect_identical(captured_body$future_nested, list(mode = "high"))
  expect_false("temperature" %in% names(captured_body))
})

test_that("stream precedence favors the explicit argument", {
  transport_used <- NULL

  local_mocked_bindings(
    registry_resolve_compatibility_context = function(...) {
      make_characterization_registry_context(streaming = TRUE)
    },
    do_nonstream_request = function(...) {
      transport_used <<- "nonstream"
      make_nonstream_response()
    },
    do_stream_request = function(...) {
      transport_used <<- "stream"
      stop("The explicit stream argument was not honored.")
    },
    .package = "PsyLingLLM"
  )

  result <- llm_caller(
    model_key = "fixture-model",
    material = "Material",
    optionals = list(stream = TRUE),
    stream = FALSE
  )

  expect_identical(transport_used, "nonstream")
  expect_false(result$streaming)
})

test_that("streaming responses retain delta and latency behavior", {
  stream_response <- list(
    status = 200L,
    raw_json = list(
      list(
        id = "request-stream",
        choices = list(
          list(delta = list(reasoning_content = "Reason "))
        )
      ),
      list(
        choices = list(
          list(delta = list(reasoning_content = "trace"))
        )
      ),
      list(choices = list(list(delta = list(content = "Hello")))),
      list(choices = list(list(delta = list(content = " world")))),
      list(usage = list(prompt_tokens = 5L, completion_tokens = 2L))
    ),
    raw_lines = character(),
    first_token_latency = 0.125,
    error = NULL
  )

  local_mocked_bindings(
    registry_resolve_compatibility_context = function(...) {
      make_characterization_registry_context(streaming = TRUE)
    },
    do_stream_request = function(...) stream_response,
    .package = "PsyLingLLM"
  )

  result <- llm_caller(
    model_key = "fixture-model",
    material = "Material",
    stream = TRUE
  )

  expect_identical(
    names(result),
    c(
      "status",
      "interface",
      "model_key",
      "streaming",
      "usage",
      "answer",
      "thinking",
      "response_status",
      "first_token_latency",
      "raw",
      "error"
    )
  )
  expect_true(result$streaming)
  expect_identical(result$answer, "Hello world")
  expect_identical(result$thinking, "Reason trace")
  expect_identical(result$usage$prompt, 5L)
  expect_identical(result$usage$completion, 2L)
  expect_identical(result$usage$id, "request-stream")
  expect_identical(result$first_token_latency, 0.125)
  expect_null(result$error)
})

test_that("status 599 remains a normalized transport error", {
  local_mocked_bindings(
    registry_resolve_compatibility_context = function(...) {
      make_characterization_registry_context()
    },
    do_nonstream_request = function(...) {
      make_nonstream_response(
        status = 599L,
        error = "Fixture timeout"
      )
    },
    .package = "PsyLingLLM"
  )

  result <- llm_caller(
    model_key = "fixture-model",
    material = "Material",
    optionals = NULL
  )

  expect_identical(result$status, 599L)
  expect_identical(
    result$error[c("code", "message")],
    list(code = 599L, message = "Fixture timeout")
  )
})

test_that("API URL rules preserve explicit and provider precedence", {
  resolve_api_url <- getFromNamespace("resolve_api_url", "PsyLingLLM")

  expect_identical(
    resolve_api_url(
      "https://override.invalid/v1",
      "fixture-proxy",
      "https://default.invalid/v1"
    ),
    "https://override.invalid/v1"
  )
  expect_identical(
    resolve_api_url(NULL, "official", "https://default.invalid/v1"),
    "https://default.invalid/v1"
  )
  expect_error(
    resolve_api_url(NULL, "fixture-proxy", "https://default.invalid/v1"),
    "Non-official provider requires api_url"
  )
  expect_error(
    resolve_api_url(NULL, "official", NULL),
    "Official provider requires"
  )
})
