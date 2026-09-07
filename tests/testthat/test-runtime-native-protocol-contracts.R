read_native_protocol_registry <- function() {
  yaml::read_yaml(test_path(
    "fixtures",
    "registry-v2-native-protocols.yaml"
  ))
}

make_native_protocol_context <- function(stream = FALSE) {
  new_llm_call_context(
    trial_prompt = "Answer briefly.",
    material = "Fixture material",
    system_content = "Fixture system",
    assistant_content = "Earlier answer",
    api_key = "fake-provider-key",
    optionals_missing = TRUE,
    stream = stream,
    timeout = 30
  )
}

build_native_protocol_fixture <- function(model_key, stream = FALSE) {
  registry <- read_native_protocol_registry()
  config <- resolve_registry_entry(model_key, registry = registry)
  request <- build_llm_request(
    config$interface$request$builder,
    config,
    make_native_protocol_context(stream)
  )
  list(
    registry = registry,
    config = config,
    request = configure_llm_request_transport(request, config)
  )
}

test_that("OpenAI Responses request uses its native wire contract", {
  built <- build_native_protocol_fixture("openai-responses-fixture")
  request <- built$request

  expect_identical(request$url, "https://openai.example.invalid/v1/responses")
  expect_identical(request$body$model, "gpt-fixture")
  expect_identical(request$body$instructions, "Fixture system")
  expect_identical(
    vapply(request$body$input, `[[`, character(1), "role"),
    c("assistant", "user")
  )
  expect_identical(request$body$max_output_tokens, 128L)
  expect_false("max_tokens" %in% names(request$body))
  expect_identical(request$headers$Authorization, "Bearer fake-provider-key")
})

test_that("Anthropic Messages request uses its native wire contract", {
  built <- build_native_protocol_fixture("anthropic-messages-fixture")
  request <- built$request

  expect_identical(request$url, "https://anthropic.example.invalid/v1/messages")
  expect_identical(request$body$model, "claude-fixture")
  expect_identical(request$body$system, "Fixture system")
  expect_identical(request$body$max_tokens, 128L)
  expect_identical(
    vapply(request$body$messages, `[[`, character(1), "role"),
    c("assistant", "user")
  )
  expect_identical(request$headers$`x-api-key`, "fake-provider-key")
  expect_identical(request$headers$`anthropic-version`, "2023-06-01")
})

test_that("OpenAI Responses completes its network-free contract", {
  built <- build_native_protocol_fixture("openai-responses-fixture")
  fixture <- jsonlite::fromJSON(
    test_path("fixtures", "openai-responses-nonstream.json"),
    simplifyVector = FALSE
  )
  transport <- send_llm_request(
    built$request,
    transport = function(request, payload, debug) {
      sent <- jsonlite::fromJSON(payload, simplifyVector = FALSE)
      expect_identical(sent$max_output_tokens, 128L)
      list(status = 200L, parsed = fixture, error = NULL)
    }
  )
  parsed <- parse_llm_response(
    transport,
    built$config$interface$response$parser,
    runtime_response_parser_config(built$config, NULL)
  )

  expect_identical(parsed$answer, "First paragraph. Second paragraph.")
  expect_identical(parsed$reasoning, "Reasoning summary")
  expect_identical(parsed$request_id, "resp_fixture")
})

test_that("Anthropic Messages completes its streaming contract", {
  built <- build_native_protocol_fixture("anthropic-messages-fixture", TRUE)
  fixture <- jsonlite::fromJSON(
    test_path("fixtures", "anthropic-messages-stream.json"),
    simplifyVector = FALSE
  )
  transport <- send_llm_request(
    built$request,
    transport = function(request, payload, debug) {
      sent <- jsonlite::fromJSON(payload, simplifyVector = FALSE)
      expect_true(sent$stream)
      expect_identical(sent$max_tokens, 128L)
      list(
        status = 200L,
        raw_json = fixture,
        first_token_latency = 0.05,
        error = NULL
      )
    }
  )
  parsed <- parse_llm_response(
    transport,
    built$config$interface$response$parser,
    runtime_response_parser_config(built$config, NULL),
    streaming = TRUE
  )

  expect_identical(parsed$answer, "Hello Claude")
  expect_identical(parsed$reasoning, "Think carefully")
  expect_identical(parsed$request_id, "msg_stream_fixture")
})
