public_registry_fixture_path <- function(name) {
  testthat::test_path("fixtures", name)
}

test_that("get_registry_entry preserves the v1 normalized return contract", {
  registry <- yaml::read_yaml(
    public_registry_fixture_path("registry-v1-minimal.yaml")
  )
  expected <- normalize_registry_entry(
    registry[["fixture-model"]]$chat,
    "fixture-model",
    "chat"
  )

  actual <- get_registry_entry(
    "fixture-model",
    generation_interface = "chat",
    path = public_registry_fixture_path("registry-v1-minimal.yaml")
  )

  expect_identical(actual, expected)
})

test_that("get_registry_entry accepts native v2 keys aliases and protocols", {
  system_path <- public_registry_fixture_path("registry-v2-valid.yaml")
  missing_user <- file.path(withr::local_tempdir(), "missing.yaml")
  local_mocked_bindings(
    get_system_registry_path = function() system_path,
    .package = "PsyLingLLM"
  )

  entry <- get_registry_entry(
    "FIXTURE",
    generation_interface = "openai_chat",
    path = missing_user
  )

  expect_identical(entry$model_key, "fixture-model")
  expect_identical(entry$interface, "openai_chat_v1")
  expect_identical(entry$provider, "official")
  expect_true(entry$reasoning)
  expect_false(entry$streaming$enabled)
  expect_identical(entry$streaming$param_name, "stream")
  expect_identical(
    entry$input$default_url,
    "https://example.invalid/v1/chat/completions"
  )
  expect_identical(
    entry$input$optional_defaults,
    list(temperature = 0.2, max_tokens = 256L)
  )
})

test_that("v2 selectors project to paths understood by the legacy caller", {
  registry <- yaml::read_yaml(
    public_registry_fixture_path("registry-v2-equivalent-to-v1.yaml")
  )
  temporary_directory <- withr::local_tempdir()
  system_path <- file.path(temporary_directory, "system.yaml")
  yaml::write_yaml(registry, system_path)
  missing_user <- file.path(temporary_directory, "missing.yaml")
  local_mocked_bindings(
    get_system_registry_path = function() system_path,
    .package = "PsyLingLLM"
  )

  entry <- get_registry_entry("fixture-model", path = missing_user)

  expect_identical(
    entry$output$respond_path,
    list("choices", "", "message", "content")
  )
  expect_identical(
    normalize_path_key(entry$output$respond_path),
    "choices..message.content"
  )
  expect_identical(
    normalize_path_key(entry$streaming$delta_path),
    "choices..delta.content"
  )
})

test_that("get_registry_entry retains compatibility error wording", {
  system_path <- public_registry_fixture_path(
    "registry-v1-multiple-interfaces.yaml"
  )
  missing_user <- file.path(withr::local_tempdir(), "missing.yaml")
  local_mocked_bindings(
    get_system_registry_path = function() system_path,
    .package = "PsyLingLLM"
  )

  expect_error(
    get_registry_entry("fixture-multi", path = missing_user),
    "Multiple interfaces available: chat, responses"
  )
  expect_error(
    get_registry_entry(
      "fixture-multi",
      generation_interface = "missing",
      path = missing_user
    ),
    "Interface 'missing' not found. Available: chat, responses",
    fixed = TRUE
  )
  expect_error(
    get_registry_entry("absent", path = missing_user),
    "Model 'absent' not found in user or system registry.",
    fixed = TRUE
  )
})

test_that("get_model_config delegates strict key and alias matching", {
  registry <- yaml::read_yaml(
    public_registry_fixture_path("registry-v2-valid.yaml")
  )

  exact <- get_model_config("fixture-model", registry)
  normalized <- get_model_config("fixture/model", registry)
  aliased <- get_model_config("FIXTURE", registry)

  expect_identical(exact, registry$models[["fixture-model"]])
  expect_identical(normalized, exact)
  expect_identical(aliased, exact)
})

test_that("get_model_config accepts the unified loader bundle", {
  bundle <- load_registry_bundle(
    system_path = public_registry_fixture_path("registry-v1-minimal.yaml"),
    user_path = file.path(withr::local_tempdir(), "missing.yaml")
  )

  config <- get_model_config("fixture-model", bundle)

  expect_identical(config, bundle$merged$models[["fixture-model"]])
})

test_that("get_model_config retains legacy heuristic fallbacks", {
  openai_default <- list(marker = "compatibility-default")
  registry <- list("openai:default" = openai_default)

  expect_warning(
    guessed <- get_model_config("gpt-future", registry),
    "guessed vendor 'openai'"
  )
  expect_identical(guessed, openai_default)

  expect_warning(
    final <- get_model_config("unknown-future", registry),
    "fallback to OpenAI default"
  )
  expect_identical(final, openai_default)
})

test_that("invalid user YAML is rejected before model resolution", {
  condition <- tryCatch(
    get_registry_entry(
      "deepseek-chat",
      path = public_registry_fixture_path("registry-invalid.yaml")
    ),
    registry_load_error = identity
  )

  expect_s3_class(condition, "registry_load_error")
  expect_identical(condition$source, "user")
  expect_identical(condition$reason, "parse_error")
})
