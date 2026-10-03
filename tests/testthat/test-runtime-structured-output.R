structured_output_registry <- function(protocol = "openai_chat") {
  fixture <- if (identical(protocol, "openai_chat")) {
    "registry-v2-valid.yaml"
  } else {
    "registry-v2-native-protocols.yaml"
  }
  registry <- yaml::read_yaml(testthat::test_path("fixtures", fixture))
  interface_id <- if (identical(protocol, "openai_chat")) {
    "openai_chat_v1"
  } else {
    "openai-responses-v1"
  }
  prefix <- if (identical(protocol, "openai_chat")) {
    "openai_chat"
  } else {
    "openai_responses"
  }
  registry$interfaces[[interface_id]]$structured_output <- list(
    default_mode = "json_schema",
    modes = list(
      json_object = list(adapter = paste0(prefix, "_json_object")),
      json_schema = list(adapter = paste0(prefix, "_json_schema"))
    )
  )
  parameter_name <- if (identical(protocol, "openai_chat")) {
    "response_format"
  } else {
    "text"
  }
  registry$interfaces[[interface_id]]$request$parameters[[parameter_name]] <- list(
    description = "Provider-native structured-output configuration."
  )
  registry
}

structured_output_config <- function(protocol = "openai_chat") {
  registry <- structured_output_registry(protocol)
  model_key <- if (identical(protocol, "openai_chat")) {
    "fixture-model"
  } else {
    "openai-responses-fixture"
  }
  resolve_registry_entry(model_key, registry = registry)
}

test_that("Registry validates and resolves structured-output components", {
  registry <- structured_output_registry()
  expect_invisible(validate_registry_schema(registry))

  config <- resolve_registry_entry("fixture-model", registry = registry)
  expect_identical(
    config$interface$structured_output$default_mode,
    "json_schema"
  )
  expect_identical(
    config$interface$structured_output$modes$json_object$adapter,
    "openai_chat_json_object"
  )
})

test_that("Registry rejects unknown and protocol-mismatched adapters", {
  registry <- structured_output_registry()
  registry$interfaces$openai_chat_v1$structured_output$modes$json_object$adapter <-
    "unknown_adapter"
  expect_error(
    validate_registry_schema(registry),
    class = "registry_validation_error"
  )

  registry <- structured_output_registry()
  registry$interfaces$openai_chat_v1$structured_output$modes$json_object$adapter <-
    "openai_responses_json_object"
  expect_error(
    validate_registry_schema(registry),
    class = "registry_validation_error"
  )
})

test_that("OpenAI Chat adapters produce current provider-native shapes", {
  config <- structured_output_config("openai_chat")
  schema <- read_experiment_spec_schema()
  json_object <- build_structured_output_parameters(
    config,
    mode = "json_object"
  )
  json_schema <- build_structured_output_parameters(
    config,
    schema = schema,
    schema_name = "psylingllm_trial_v1"
  )

  expect_identical(
    json_object$parameters,
    list(response_format = list(type = "json_object"))
  )
  expect_identical(
    json_schema$parameters$response_format$type,
    "json_schema"
  )
  expect_identical(
    json_schema$parameters$response_format$json_schema$name,
    "psylingllm_trial_v1"
  )
  expect_true(json_schema$parameters$response_format$json_schema$strict)
  expect_identical(
    json_schema$parameters$response_format$json_schema$schema,
    schema
  )
})

test_that("OpenAI Responses adapters use text.format", {
  config <- structured_output_config("openai_responses")
  schema <- read_experiment_spec_schema()
  json_object <- build_structured_output_parameters(
    config,
    mode = "json_object"
  )
  json_schema <- build_structured_output_parameters(
    config,
    schema = schema,
    schema_name = "psylingllm_trial_v1"
  )

  expect_identical(
    json_object$parameters,
    list(text = list(format = list(type = "json_object")))
  )
  expect_identical(json_schema$parameters$text$format$type, "json_schema")
  expect_identical(json_schema$parameters$text$format$name, "psylingllm_trial_v1")
  expect_identical(json_schema$parameters$text$format$schema, schema)
})

test_that("structured-output parameters reach native request builders unchanged", {
  for (protocol in c("openai_chat", "openai_responses")) {
    config <- structured_output_config(protocol)
    structured <- build_structured_output_parameters(
      config,
      schema = read_experiment_spec_schema(),
      schema_name = "psylingllm_trial_v1"
    )
    context <- new_llm_call_context(
      trial_prompt = "Return the requested JSON object.",
      material = "Test material.",
      api_key = "not-a-real-key",
      optionals_missing = FALSE,
      optionals_value = structured$parameters,
      stream = FALSE
    )
    request <- build_llm_request(
      config$interface$request$builder,
      config,
      context
    )

    if (identical(protocol, "openai_chat")) {
      expect_identical(
        request$body$response_format,
        structured$parameters$response_format
      )
    } else {
      expect_identical(request$body$text, structured$parameters$text)
    }
  }
})

test_that("structured-output builder fails before transport on invalid input", {
  config <- structured_output_config()
  expect_error(
    build_structured_output_parameters(config, schema = list()),
    class = "structured_output_error"
  )
  expect_error(
    build_structured_output_parameters(
      config,
      schema = read_experiment_spec_schema(),
      schema_name = "invalid name"
    ),
    class = "structured_output_error"
  )
  expect_error(
    build_structured_output_parameters(config, mode = "tool_input"),
    class = "structured_output_error"
  )

  unconfigured <- yaml::read_yaml(
    testthat::test_path("fixtures", "registry-v2-valid.yaml")
  )
  unconfigured <- resolve_registry_entry(
    "fixture-model",
    registry = unconfigured
  )
  expect_error(
    build_structured_output_parameters(unconfigured),
    class = "structured_output_error"
  )
})
