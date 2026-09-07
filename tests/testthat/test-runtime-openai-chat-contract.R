read_openai_chat_registry <- function() {
  yaml::read_yaml(test_path(
    "fixtures",
    "registry-v2-openai-chat.yaml"
  ))
}

make_openai_chat_context <- function(stream = NULL,
                                     optionals_missing = TRUE,
                                     optionals_value = NULL,
                                     provider_parameters = list()) {
  new_llm_call_context(
    trial_prompt = "Answer briefly.",
    material = "Fixture material",
    system_content = "Fixture system",
    assistant_content = "Earlier answer",
    api_key = "not-a-secret",
    optionals_missing = optionals_missing,
    optionals_value = optionals_value,
    stream = stream,
    timeout = 30,
    provider_parameters = provider_parameters
  )
}

build_openai_chat_fixture_request <- function(model_key, context) {
  registry <- read_openai_chat_registry()
  config <- resolve_registry_entry(model_key, registry = registry)
  request <- build_llm_request(
    config$interface$request$builder,
    runtime_request_builder_input(config, NULL),
    context
  )
  list(
    registry = registry,
    config = config,
    request = configure_llm_request_transport(request, config)
  )
}

test_that("OpenAI and DeepSeek reuse native OpenAI Chat components", {
  registry <- read_openai_chat_registry()

  expect_true(validate_registry_schema(registry))
  openai <- resolve_registry_entry("openai-fixture", registry = registry)
  deepseek <- resolve_registry_entry("deepseek-fixture", registry = registry)

  expect_identical(openai$interface$id, "openai-chat-openai-v1")
  expect_identical(deepseek$interface$id, "openai-chat-deepseek-v1")
  expect_identical(openai$interface$request$builder, "openai_chat")
  expect_identical(deepseek$interface$request$builder, "openai_chat")
  expect_identical(openai$interface$response$parser, "openai_chat")
  expect_identical(deepseek$interface$response$parser, "openai_chat")
  expect_identical(openai$interface$transport, deepseek$interface$transport)
  expect_false(openai$capabilities$values$reasoning)
  expect_true(deepseek$capabilities$values$reasoning)
})

test_that("native OpenAI Chat builder creates deterministic requests", {
  built <- build_openai_chat_fixture_request(
    "openai-chat-fixture",
    make_openai_chat_context()
  )
  request <- built$request

  expect_identical(
    request$url,
    "https://openai.example.invalid/v1/chat/completions"
  )
  expect_identical(request$transport_id, "http_json")
  expect_false(request$stream)
  expect_identical(request$headers$Authorization, "Bearer not-a-secret")
  expect_identical(request$body$model, "openai-chat-fixture")
  expect_identical(
    vapply(request$body$messages, `[[`, character(1), "role"),
    c("system", "assistant", "user")
  )
  expect_identical(
    request$body$messages[[3L]]$content,
    "Answer briefly.\n\nFixture material"
  )
  expect_identical(request$body$temperature, 0.2)
  expect_identical(request$body$max_completion_tokens, 128L)
  expect_false("stream" %in% names(request$body))
})

test_that("native builder preserves optionals and stream precedence", {
  built <- build_openai_chat_fixture_request(
    "deepseek-v4-pro-fixture",
    make_openai_chat_context(
      stream = TRUE,
      optionals_missing = FALSE,
      optionals_value = list(temperature = 0.7, stream = FALSE)
    )
  )

  expect_true(built$request$stream)
  expect_identical(built$request$transport_id, "sse_json")
  expect_identical(built$request$url, "https://deepseek.example.invalid/chat/completions")
  expect_identical(built$request$body$model, "deepseek-v4-pro")
  expect_identical(built$request$body$temperature, 0.7)
  expect_true(built$request$body$stream)
  expect_identical(built$request$body$thinking, list(type = "enabled"))
  expect_false("max_tokens" %in% names(built$request$body))
})

test_that("native builder warns and sends undeclared parameters unchanged", {
  registry <- read_openai_chat_registry()
  config <- resolve_registry_entry("openai-chat-fixture", registry = registry)

  expect_warning(
    request <- build_llm_request(
      "openai_chat",
      config,
      make_openai_chat_context(
        optionals_missing = FALSE,
        optionals_value = list(
          future_parameter = list(mode = "high"),
          nullable_parameter = NULL
        )
      )
    ),
    "will be sent unchanged"
  )

  expect_identical(request$body$future_parameter, list(mode = "high"))
  expect_true("nullable_parameter" %in% names(request$body))
  expect_null(request$body$nullable_parameter)

  invalid_type <- tryCatch(
    build_llm_request(
      "openai_chat",
      config,
      make_openai_chat_context(
        optionals_missing = FALSE,
        optionals_value = 0.5
      )
    ),
    llm_request_builder_error = identity
  )
  expect_identical(invalid_type$reason, "invalid_optionals")
})

test_that("native builder warns on duplicates and uses the last value", {
  registry <- read_openai_chat_registry()
  config <- resolve_registry_entry("openai-chat-fixture", registry = registry)

  expect_warning(
    request <- build_llm_request(
      "openai_chat",
      config,
      make_openai_chat_context(
        optionals_missing = FALSE,
        optionals_value = list(temperature = 0.4, temperature = 0.5),
        provider_parameters = list(temperature = 0.8)
      )
    ),
    "last value"
  )

  expect_identical(request$body$temperature, 0.8)
  expect_identical(sum(names(request$body) == "temperature"), 1L)
})

test_that("native builder protects protocol-owned request fields", {
  registry <- read_openai_chat_registry()
  config <- resolve_registry_entry("openai-chat-fixture", registry = registry)

  condition <- tryCatch(
    build_llm_request(
      "openai_chat",
      config,
      make_openai_chat_context(
        provider_parameters = list(model = "wrong-model")
      )
    ),
    llm_request_builder_error = identity
  )

  expect_s3_class(condition, "llm_request_builder_error")
  expect_identical(condition$reason, "protected_parameter")
})

test_that("resolved stream state cannot conflict with a configured body", {
  registry <- read_openai_chat_registry()
  interface_id <- "openai-chat-openai-v1"
  registry$interfaces[[interface_id]]$request$body <- list(stream = TRUE)
  config <- resolve_registry_entry("openai-chat-fixture", registry = registry)
  request <- build_llm_request(
    "openai_chat",
    config,
    make_openai_chat_context(stream = FALSE)
  )

  expect_false(request$stream)
  expect_false("stream" %in% names(request$body))
  expect_identical(request$transport_id, "http_json")
})

test_that("native OpenAI Chat contract completes without network access", {
  built <- build_openai_chat_fixture_request(
    "openai-chat-fixture",
    make_openai_chat_context()
  )
  response_fixture <- jsonlite::fromJSON(
    test_path("fixtures", "openai-chat-nonstream.json"),
    simplifyVector = FALSE
  )
  mock_transport <- function(request, payload, debug) {
    expect_identical(request$transport_id, "http_json")
    sent <- jsonlite::fromJSON(payload, simplifyVector = FALSE)
    expect_identical(sent$model, "openai-chat-fixture")
    list(status = 200L, parsed = response_fixture, error = NULL)
  }

  transport_response <- send_llm_request(
    built$request,
    transport = mock_transport
  )
  parsed_response <- parse_llm_response(
    transport_response,
    built$config$interface$response$parser,
    config = runtime_response_parser_config(built$config, NULL),
    streaming = built$request$stream
  )
  entry <- registry_project_compatibility_entry(
    list(merged = built$registry),
    built$config
  )
  result <- normalize_llm_result(
    built$config,
    entry,
    built$request,
    transport_response,
    parsed_response
  )

  expect_identical(result$status, 200L)
  expect_identical(result$model_key, "openai-chat-fixture")
  expect_identical(result$interface, "openai-chat-openai-v1")
  expect_identical(result$answer, "Fixture answer")
  expect_identical(result$thinking, "Fixture reasoning")
  expect_identical(result$usage$prompt, 12L)
  expect_identical(result$usage$completion, 6L)
  expect_identical(result$usage$id, "chatcmpl_fixture")
})

test_that("llm_caller runs a native v2 OpenAI Chat configuration", {
  registry <- read_openai_chat_registry()
  config <- resolve_registry_entry("openai-chat-fixture", registry = registry)
  response_fixture <- jsonlite::fromJSON(
    test_path("fixtures", "openai-chat-nonstream.json"),
    simplifyVector = FALSE
  )

  local_mocked_bindings(
    registry_resolve_compatibility_context = function(...) {
      list(bundle = list(merged = registry), resolved = config)
    },
    send_llm_request = function(request, debug) {
      expect_identical(request$body$model, "openai-chat-fixture")
      expect_identical(request$transport_id, "http_json")
      expect_identical(
        request$body$future_api_parameter,
        list(mode = "high")
      )
      normalize_llm_transport_response(
        list(status = 200L, parsed = response_fixture, error = NULL),
        request$transport_id,
        encode_llm_request_body(request)
      )
    },
    .package = "PsyLingLLM"
  )

  expect_warning(
    result <- llm_caller(
      model_key = "openai-chat-fixture",
      material = "Fixture material",
      api_key = "not-a-secret",
      stream = FALSE,
      future_api_parameter = list(mode = "high")
    ),
    "will be sent unchanged"
  )

  expect_identical(result$status, 200L)
  expect_identical(result$interface, "openai-chat-openai-v1")
  expect_identical(result$answer, "Fixture answer")
})

test_that("DeepSeek reuses the native streaming contract without network", {
  built <- build_openai_chat_fixture_request(
    "deepseek-v4-pro-fixture",
    make_openai_chat_context(stream = TRUE)
  )
  events <- jsonlite::fromJSON(
    test_path("fixtures", "deepseek-chat-stream.json"),
    simplifyVector = FALSE
  )
  mock_transport <- function(request, payload, debug) {
    expect_identical(request$transport_id, "sse_json")
    sent <- jsonlite::fromJSON(payload, simplifyVector = FALSE)
    expect_identical(sent$model, "deepseek-v4-pro")
    expect_identical(sent$thinking, list(type = "enabled"))
    expect_true(sent$stream)
    list(
      status = 200L,
      raw_json = events,
      first_token_latency = 0.05,
      error = NULL
    )
  }

  transport_response <- send_llm_request(
    built$request,
    transport = mock_transport
  )
  parsed_response <- parse_llm_response(
    transport_response,
    built$config$interface$response$parser,
    config = runtime_response_parser_config(built$config, NULL),
    streaming = TRUE
  )
  entry <- registry_project_compatibility_entry(
    list(merged = built$registry),
    built$config
  )
  result <- normalize_llm_result(
    built$config,
    entry,
    built$request,
    transport_response,
    parsed_response
  )

  expect_true(result$streaming)
  expect_identical(result$model_key, "deepseek-v4-pro-fixture")
  expect_identical(result$answer, "Hello world")
  expect_identical(result$thinking, "Think first")
  expect_identical(result$first_token_latency, 0.05)
})

test_that("a newly named model reuses the native interface without R changes", {
  registry <- read_openai_chat_registry()
  registry$models[["future-chat-fixture"]] <- list(
    provider = "openai-fixture",
    model_id = "future-chat-001",
    interfaces = "openai-chat-openai-v1",
    default_interface = "openai-chat-openai-v1",
    capabilities = list(reasoning = FALSE),
    defaults = list(max_completion_tokens = 64L)
  )

  config <- resolve_registry_entry("future-chat-fixture", registry = registry)
  request <- build_llm_request(
    config$interface$request$builder,
    config,
    make_openai_chat_context()
  )

  expect_identical(request$body$model, "future-chat-001")
  expect_identical(request$body$max_completion_tokens, 64L)
})
