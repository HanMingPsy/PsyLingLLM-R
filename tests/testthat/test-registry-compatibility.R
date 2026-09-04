read_compatibility_fixture <- function(name) {
  yaml::read_yaml(testthat::test_path("fixtures", name))
}

test_that("v1 and equivalent v2 fixtures produce one canonical registry", {
  v1 <- read_compatibility_fixture("registry-v1-minimal.yaml")
  v2 <- read_compatibility_fixture("registry-v2-equivalent-to-v1.yaml")

  expect_identical(as_registry_v2(v1), as_registry_v2(v2))
})

test_that("v2 compatibility conversion is validation-only and lossless", {
  registry <- read_compatibility_fixture("registry-v2-valid.yaml")

  expect_identical(as_registry_v2(registry), registry)
})

test_that("the bundled v1 registry converts without changing production YAML", {
  registry <- load_registry()
  original <- registry
  converted <- as_registry_v2(registry)

  expect_identical(registry, original)
  expect_identical(converted$schema_version, 2L)
  expect_setequal(names(converted$models), names(registry))
  expect_invisible(validate_registry_schema(converted))
})

test_that("legacy provider identity and deployment metadata are preserved", {
  registry <- read_compatibility_fixture("registry-v1-minimal.yaml")
  converted <- as_registry_v2(registry)
  provider <- converted$providers[["fixture-provider"]]

  expect_identical(provider$type, "custom")
  expect_identical(
    provider$metadata$legacy_provider_labels$chat,
    "Fixture-Provider"
  )
  expect_identical(
    converted$interfaces[["legacy.fixture-model.chat"]]$metadata$
      legacy_provider_label,
    "Fixture-Provider"
  )
})

test_that("legacy request templates and typed defaults remain explicit", {
  registry <- read_compatibility_fixture("registry-v1-minimal.yaml")
  request <- as_registry_v2(registry)$interfaces[[
    "legacy.fixture-model.chat"
  ]]$request

  expect_identical(request$builder, "legacy_template_v1")
  expect_identical(
    request$url,
    "https://example.invalid/v1/chat/completions"
  )
  expect_identical(request$body$model, "fixture-model")
  expect_identical(request$defaults$temperature, 0.25)
  expect_true(request$defaults$enabled)
  expect_identical(request$role_mapping$system, "developer")
})

test_that("legacy NULL role mappings remain compatible with strict v2", {
  registry <- read_compatibility_fixture("registry-v1-minimal.yaml")
  registry[["fixture-model"]]$chat$input$role_mapping <- list(
    system = "developer",
    user = "user",
    assistant = "assistant",
    tool = NULL
  )

  converted <- as_registry_v2(registry)
  mapping <- converted$interfaces[[
    "legacy.fixture-model.chat"
  ]]$request$role_mapping

  expect_identical(
    mapping,
    list(system = "developer", user = "user", assistant = "assistant")
  )
  expect_true(validate_registry_schema(converted))
})

test_that("legacy response paths become explicit selector segments", {
  registry <- read_compatibility_fixture("registry-v1-minimal.yaml")
  interface <- as_registry_v2(registry)$interfaces[[
    "legacy.fixture-model.chat"
  ]]

  expect_identical(
    interface$response$selectors$answer,
    c("choices", "*", "message", "content")
  )
  expect_identical(
    interface$response$selectors$usage_prompt,
    c("usage", "prompt_tokens")
  )
  expect_identical(
    interface$response$selectors$answer_delta,
    c("choices", "*", "delta", "content")
  )
})

test_that("legacy stream metadata preserves support and enabled separately", {
  registry <- read_compatibility_fixture("registry-v1-minimal.yaml")
  interface <- as_registry_v2(registry)$interfaces[[
    "legacy.fixture-model.chat"
  ]]

  expect_true(interface$streaming$supported)
  expect_false(interface$metadata$legacy_streaming_enabled)
  expect_identical(interface$transport$stream, "sse_json")
})

test_that("multi-interface v1 models preserve explicit selection semantics", {
  registry <- read_compatibility_fixture(
    "registry-v1-multiple-interfaces.yaml"
  )
  model <- as_registry_v2(registry)$models[["fixture-multi"]]

  expect_length(model$interfaces, 2L)
  expect_null(model$default_interface)
})

test_that("legacy non-official entries may rely on a runtime URL override", {
  registry <- read_compatibility_fixture("registry-v1-minimal.yaml")
  registry[["fixture-model"]]$chat$input$default_url <- NULL
  converted <- as_registry_v2(registry)
  request <- converted$interfaces[["legacy.fixture-model.chat"]]$request

  expect_null(request$url)
  expect_identical(request$body$model, "fixture-model")
  expect_invisible(validate_registry_schema(converted))
})

test_that("compatibility conversion rejects mixed and unsupported documents", {
  mixed <- read_compatibility_fixture("registry-v1-minimal.yaml")
  mixed$models <- list()
  expect_error(as_registry_v2(mixed), class = "registry_validation_error")

  unsupported <- read_compatibility_fixture("registry-v2-valid.yaml")
  unsupported$schema_version <- 3
  expect_error(
    as_registry_v2(unsupported),
    class = "registry_validation_error"
  )
})
