test_that("llm_caller delegates the complete runtime pipeline in order", {
  calls <- character()
  config <- list(
    interface = list(
      request = list(builder = "fixture_builder"),
      response = list(parser = "fixture_parser")
    )
  )
  registry_context <- list(bundle = list(), resolved = config)
  compatibility_entry <- list(
    model_key = "fixture-model",
    interface = "chat"
  )
  request <- list(stream = FALSE)
  transport_response <- list(transport = TRUE)
  parsed_response <- list(parsed = TRUE)
  expected <- list(result = "normalized")

  local_mocked_bindings(
    registry_resolve_compatibility_context = function(...) {
      calls <<- c(calls, "resolve")
      registry_context
    },
    registry_project_compatibility_entry = function(bundle, resolved) {
      calls <<- c(calls, "project")
      expect_identical(resolved, config)
      compatibility_entry
    },
    build_llm_request = function(builder_id, entry, context) {
      calls <<- c(calls, "build")
      expect_identical(builder_id, "fixture_builder")
      expect_false(context$optionals_missing)
      expect_null(context$optionals_value)
      request
    },
    configure_llm_request_transport = function(value, resolved) {
      calls <<- c(calls, "configure_transport")
      expect_identical(value, request)
      request
    },
    send_llm_request = function(value, debug) {
      calls <<- c(calls, "send")
      expect_identical(value, request)
      transport_response
    },
    parse_llm_response = function(response,
                                  parser_id,
                                  config,
                                  streaming) {
      calls <<- c(calls, "parse")
      expect_identical(response, transport_response)
      expect_identical(parser_id, "fixture_parser")
      expect_false(streaming)
      parsed_response
    },
    normalize_llm_result = function(config,
                                    compatibility_entry,
                                    request,
                                    transport_response,
                                    parsed_response,
                                    return_raw) {
      calls <<- c(calls, "normalize")
      expect_false(return_raw)
      expected
    },
    .package = "PsyLingLLM"
  )

  result <- llm_caller(
    model_key = "fixture-model",
    material = "Material",
    optionals = NULL
  )

  expect_identical(result, expected)
  expect_identical(
    calls,
    c(
      "resolve", "project", "build", "configure_transport", "send",
      "parse", "normalize"
    )
  )
})

test_that("bundled v1 models run through the canonical pipeline offline", {
  captured_url <- NULL
  local_user_registry <- file.path(
    withr::local_tempdir(),
    "registry.yaml"
  )

  local_mocked_bindings(
    get_registry_path = function() local_user_registry,
    do_nonstream_request = function(url,
                                    headers,
                                    json_payload,
                                    timeout,
                                    debug) {
      captured_url <<- url
      parsed <- list(
        id = "offline-request",
        choices = list(list(message = list(content = "Offline answer"))),
        usage = list(prompt_tokens = 4L, completion_tokens = 2L)
      )
      list(
        status = 200L,
        text = jsonlite::toJSON(parsed, auto_unbox = TRUE),
        parsed = parsed,
        error = NULL
      )
    },
    .package = "PsyLingLLM"
  )

  result <- llm_caller(
    model_key = "deepseek-chat",
    material = "Offline fixture",
    api_key = "TEST_TOKEN_PLACEHOLDER",
    stream = FALSE
  )

  expect_identical(
    captured_url,
    "https://api.deepseek.com/chat/completions"
  )
  expect_identical(result$interface, "chat")
  expect_identical(result$model_key, "deepseek-chat")
  expect_identical(result$answer, "Offline answer")
  expect_identical(
    result$usage,
    list(prompt = 4L, completion = 2L, id = "offline-request")
  )
})
