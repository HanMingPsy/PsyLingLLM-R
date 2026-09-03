fixture_path <- function(name) {
  testthat::test_path("fixtures", name)
}

test_that("the bundled v1 registry loads its current model keys", {
  registry <- load_registry()

  expect_type(registry, "list")
  expect_setequal(
    names(registry),
    c("deepseek-chat", "deepseek-reasoner", "gpt-4o")
  )
})

test_that("a v1 user entry is selected and normalized", {
  entry <- get_registry_entry(
    "fixture-model",
    generation_interface = "chat",
    path = fixture_path("registry-v1-minimal.yaml")
  )

  expect_identical(entry$model_key, "fixture-model")
  expect_identical(entry$interface, "chat")
  expect_identical(entry$provider, "fixture-provider")
  expect_true(entry$reasoning)
  expect_identical(
    entry$input$default_url,
    "https://example.invalid/v1/chat/completions"
  )
  expect_identical(entry$input$optional_defaults$temperature, 0.25)
  expect_identical(entry$input$optional_defaults$enabled, TRUE)
  expect_identical(entry$input$role_mapping$system, "developer")
  expect_identical(entry$input$role_mapping$user, "user")
  expect_identical(entry$input$role_mapping$assistant, "assistant")
  expect_null(entry$input$role_mapping$tool)
  expect_identical(
    entry$output$respond_path,
    "list(\"choices..message.content\")"
  )
  expect_false(entry$streaming$enabled)
  expect_identical(
    entry$streaming$delta_path,
    "list(\"choices..delta.content\")"
  )
})

test_that("a v1 user model takes precedence over the bundled model", {
  entry <- get_registry_entry(
    "deepseek-chat",
    generation_interface = "chat",
    path = fixture_path("registry-v1-user-override.yaml")
  )

  expect_identical(entry$provider, "fixture-proxy")
  expect_identical(
    entry$input$default_url,
    "https://example.invalid/proxy/chat/completions"
  )
})

test_that("registry lookup falls back to the bundled registry", {
  temporary_directory <- withr::local_tempdir()
  missing_user_registry <- file.path(temporary_directory, "missing.yaml")

  entry <- get_registry_entry(
    "deepseek-chat",
    generation_interface = "chat",
    path = missing_user_registry
  )

  expect_identical(entry$model_key, "deepseek-chat")
  expect_identical(entry$interface, "chat")
  expect_identical(entry$provider, "official")
})

test_that("v1 interface selection preserves current errors", {
  registry_path <- fixture_path("registry-v1-multiple-interfaces.yaml")

  expect_error(
    get_registry_entry("fixture-multi", path = registry_path),
    "Multiple interfaces available"
  )
  expect_error(
    get_registry_entry(
      "fixture-multi",
      generation_interface = "missing",
      path = registry_path
    ),
    "Interface 'missing' not found"
  )
  expect_error(
    get_registry_entry(
      "missing-model",
      generation_interface = "chat",
      path = registry_path
    ),
    "not found in user or system registry"
  )
})

test_that("v1 single-interface selection remains implicit", {
  entry <- get_registry_entry(
    "fixture-model",
    path = fixture_path("registry-v1-minimal.yaml")
  )

  expect_identical(entry$interface, "chat")
})

test_that("get_model_config resolves explicit flat registries", {
  exact <- list(marker = "exact")
  alias <- list(marker = "alias", aliases = c("friendly-name"))
  registry <- list(
    "provider-model" = exact,
    "alias-model" = alias
  )

  expect_identical(get_model_config("provider-model", registry), exact)
  expect_identical(get_model_config("provider/model", registry), exact)
  expect_identical(get_model_config("friendly-name", registry), alias)
  expect_error(
    get_model_config("unknown-model", registry),
    "model 'unknown-model' not found in registry"
  )
})
