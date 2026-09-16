system_registry_v1_fixture <- function() {
  yaml::read_yaml(test_path("fixtures", "system-registry-v1.yaml"))
}

system_registry_v2_fixture <- function() {
  yaml::read_yaml(get_system_registry_path())
}

system_registry_cases <- function() {
  list(
    c("deepseek-chat", "chat"),
    c("deepseek-reasoner", "chat"),
    c("gpt-4o", "chat"),
    c("gpt-4o", "responses")
  )
}

system_registry_v1_equivalence_cases <- function() {
  list(
    c("gpt-4o", "chat"),
    c("gpt-4o", "responses")
  )
}

test_that("the bundled production registry is a valid v2 bundle", {
  registry <- system_registry_v2_fixture()

  expect_identical(registry$schema_version, 2L)
  expect_true(validate_registry_schema(registry))
  expect_true(all(c("deepseek-chat", "deepseek-reasoner", "gpt-4o") %in%
    names(registry$models)))
  expect_error(
    resolve_registry_entry("gpt-4o", registry = registry),
    class = "registry_resolution_error"
  )
})

test_that("every bundled model interface resolves and builds offline", {
  registry <- system_registry_v2_fixture()
  context <- new_llm_call_context(
    material = "Offline fixture",
    api_key = "TEST_TOKEN_PLACEHOLDER",
    optionals_missing = FALSE,
    optionals_value = NULL,
    stream = FALSE,
    timeout = 30
  )

  for (model_key in names(registry$models)) {
    model <- registry$models[[model_key]]
    for (interface_id in model$interfaces) {
      config <- resolve_registry_entry(
        model_key,
        interface_id,
        registry = registry
      )
      entry <- registry_project_resolved_entry(config)
      request_context <- context
      if (identical(model_key, "azure-gpt-4.1-nano")) {
        request_context$api_url <- paste0(
          "https://example.openai.azure.com/openai/v1/",
          if (identical(config$interface$protocol, "openai_responses")) {
            "responses"
          } else {
            "chat/completions"
          }
        )
      }
      request <- build_llm_request(
        config$interface$request$builder,
        runtime_request_builder_input(config, entry),
        request_context
      )
      request <- configure_llm_request_transport(request, config)

      expect_true(nzchar(request$url), info = model_key)
      expect_identical(request$body$model, config$model$id)
    }
  }
})

test_that("the v2 public projection preserves the bundled v1 contract", {
  old <- system_registry_v1_fixture()
  current <- load_registry()

  expect_true(all(names(old) %in% names(current)))
  for (case in system_registry_v1_equivalence_cases()) {
    model_key <- case[[1L]]
    interface <- case[[2L]]
    old_entry <- normalize_registry_entry(
      old[[model_key]][[interface]], model_key, interface
    )
    current_entry <- normalize_registry_entry(
      current[[model_key]][[interface]], model_key, interface
    )
    expect_equal(current_entry, old_entry)
  }
})

test_that("v1 and bundled v2 generate equivalent requests", {
  old <- system_registry_v1_fixture()
  current <- system_registry_v2_fixture()
  contexts <- list(
    new_llm_call_context(
      material = "Offline fixture",
      api_key = "TEST_TOKEN_PLACEHOLDER",
      optionals_missing = TRUE,
      timeout = 30
    ),
    new_llm_call_context(
      material = "Offline fixture",
      api_key = "TEST_TOKEN_PLACEHOLDER",
      optionals_missing = FALSE,
      optionals_value = NULL,
      timeout = 30
    ),
    new_llm_call_context(
      material = "Offline fixture",
      api_key = "TEST_TOKEN_PLACEHOLDER",
      optionals_missing = FALSE,
      optionals_value = NULL,
      stream = FALSE,
      timeout = 30
    )
  )

  for (case in system_registry_v1_equivalence_cases()) {
    model_key <- case[[1L]]
    interface <- case[[2L]]
    old_config <- resolve_registry_entry(
      model_key, interface, registry = old
    )
    new_config <- resolve_registry_entry(
      model_key, interface, registry = current
    )
    old_entry <- normalize_registry_entry(
      old[[model_key]][[interface]], model_key, interface
    )
    new_entry <- registry_project_resolved_entry(new_config)

    for (context in contexts) {
      old_request <- build_llm_request(
        old_config$interface$request$builder, old_entry, context
      )
      old_request <- configure_llm_request_transport(old_request, old_config)
      new_request <- build_llm_request(
        new_config$interface$request$builder,
        runtime_request_builder_input(new_config, new_entry),
        context
      )
      new_request <- configure_llm_request_transport(new_request, new_config)

      new_body <- new_request$body[sort(names(new_request$body))]
      old_body <- old_request$body[sort(names(old_request$body))]
      new_request$body <- NULL
      old_request$body <- NULL
      expect_equal(unclass(new_request), unclass(old_request))
      expect_equal(new_body, old_body)
    }
  }
})

test_that("a v1 user model still overrides the bundled v2 model", {
  user_path <- test_path("fixtures", "registry-v1-user-override.yaml")
  before <- tools::md5sum(user_path)
  bundle <- load_registry_bundle(
    system_path = get_system_registry_path(),
    user_path = user_path
  )
  resolved <- resolve_registry_entry(
    "deepseek-chat", "chat", registry = bundle
  )

  expect_identical(resolved$provider$type, "proxy")
  expect_identical(
    resolved$interface$metadata$legacy_provider_label,
    "fixture-proxy"
  )
  expect_identical(
    resolved$interface$request$url,
    "https://example.invalid/proxy/chat/completions"
  )
  expect_identical(tools::md5sum(user_path), before)
})

test_that("every bundled interface completes the offline caller pipeline", {
  local_user_registry <- file.path(withr::local_tempdir(), "registry.yaml")
  chat_payload <- jsonlite::fromJSON(
    test_path("fixtures", "openai-chat-nonstream.json"),
    simplifyVector = FALSE
  )
  responses_payload <- jsonlite::fromJSON(
    test_path("fixtures", "openai-responses-nonstream.json"),
    simplifyVector = FALSE
  )

  local_mocked_bindings(
    get_registry_path = function() local_user_registry,
    do_nonstream_request = function(url, headers, json_payload, timeout, debug) {
      parsed <- if (grepl("/responses$", url)) {
        responses_payload
      } else {
        chat_payload
      }
      list(
        status = 200L,
        text = jsonlite::toJSON(parsed, auto_unbox = TRUE, null = "null"),
        parsed = parsed,
        error = NULL
      )
    },
    .package = "PsyLingLLM"
  )

  for (case in system_registry_cases()) {
    result <- llm_caller(
      model_key = case[[1L]],
      generation_interface = case[[2L]],
      material = "Offline fixture",
      api_key = "TEST_TOKEN_PLACEHOLDER",
      optionals = NULL,
      stream = FALSE
    )
    expect_identical(result$status, 200L)
    expect_identical(result$interface, case[[2L]])
    expect_true(nzchar(result$answer))
  }
})
