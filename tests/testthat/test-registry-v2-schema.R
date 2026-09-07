read_registry_fixture <- function(name) {
  yaml::read_yaml(testthat::test_path("fixtures", name))
}

expect_registry_validation_error <- function(object, field = NULL) {
  condition <- tryCatch(
    object,
    registry_validation_error = identity
  )

  expect_s3_class(condition, "registry_validation_error")
  if (!is.null(field)) {
    expect_identical(condition$field, field)
  }
  invisible(condition)
}

test_that("public schema validation accepts existing v1 registries", {
  expect_invisible(validate_registry_schema(load_registry()))
  expect_invisible(
    validate_registry_schema(
      read_registry_fixture("registry-v1-minimal.yaml")
    )
  )
})

test_that("a complete Registry v2 fixture passes strict validation", {
  registry <- read_registry_fixture("registry-v2-valid.yaml")

  expect_invisible(validate_registry_schema(registry))
})

test_that("an empty but structurally complete Registry v2 bundle is valid", {
  registry <- list(
    schema_version = 2,
    providers = list(),
    interfaces = list(),
    capabilities = list(),
    models = list()
  )

  expect_invisible(validate_registry_schema(registry))
})

test_that("Registry v2 requires an explicit supported version", {
  registry <- read_registry_fixture("registry-v2-valid.yaml")
  registry$schema_version <- NULL

  expect_registry_validation_error(
    validate_registry_schema(registry),
    "schema_version"
  )

  registry$schema_version <- 3
  expect_registry_validation_error(
    validate_registry_schema(registry),
    "schema_version"
  )
})

test_that("Registry v2 rejects missing and unknown top-level fields", {
  registry <- read_registry_fixture("registry-v2-valid.yaml")
  registry$providers <- NULL
  expect_registry_validation_error(validate_registry_schema(registry))

  registry <- read_registry_fixture("registry-v2-valid.yaml")
  registry$provider <- list()
  expect_registry_validation_error(validate_registry_schema(registry))
})

test_that("Registry v2 rejects broken cross-references", {
  registry <- read_registry_fixture("registry-v2-broken-reference.yaml")
  condition <- expect_registry_validation_error(
    validate_registry_schema(registry),
    "provider"
  )

  expect_identical(condition$domain, "models")
  expect_identical(condition$entry_id, "fixture-model")

  registry <- read_registry_fixture("registry-v2-valid.yaml")
  registry$models[["fixture-model"]]$interfaces <- "missing_interface"
  expect_registry_validation_error(
    validate_registry_schema(registry),
    "interfaces"
  )

  registry <- read_registry_fixture("registry-v2-valid.yaml")
  registry$interfaces$openai_chat_v1$capabilities$unknown <- list(
    response_channel = "unknown"
  )
  expect_registry_validation_error(
    validate_registry_schema(registry),
    "capabilities"
  )
})

test_that("Registry v2 accepts only declared component identifiers", {
  registry <- read_registry_fixture("registry-v2-unknown-component.yaml")

  expect_registry_validation_error(
    validate_registry_schema(registry),
    "request.builder"
  )
})

test_that("Registry v2 internal identifiers use the restricted syntax", {
  registry <- read_registry_fixture("registry-v2-valid.yaml")
  names(registry$interfaces) <- "Unsafe Interface"
  registry$models[["fixture-model"]]$interfaces <- "Unsafe Interface"
  registry$models[["fixture-model"]]$default_interface <- "Unsafe Interface"

  expect_registry_validation_error(
    validate_registry_schema(registry),
    "id"
  )
})

test_that("Registry v2 validates capability value types", {
  registry <- read_registry_fixture("registry-v2-valid.yaml")
  registry$models[["fixture-model"]]$capabilities$reasoning <- "yes"

  expect_registry_validation_error(
    validate_registry_schema(registry),
    "capabilities.reasoning"
  )
})

test_that("Registry v2 permits models without optional capabilities", {
  registry <- read_registry_fixture("registry-v2-valid.yaml")
  registry$capabilities <- list()
  registry$interfaces$openai_chat_v1$capabilities <- list()
  registry$models[["fixture-model"]]$capabilities <- list()

  expect_invisible(validate_registry_schema(registry))
})

test_that("Registry v2 validates capability allowed value types", {
  registry <- read_registry_fixture("registry-v2-valid.yaml")
  registry$capabilities$reasoning$allowed_values <- c("yes", "no")

  expect_registry_validation_error(
    validate_registry_schema(registry),
    "allowed_values"
  )
})

test_that("native Registry v2 accepts provider-native defaults", {
  registry <- read_registry_fixture("registry-v2-valid.yaml")
  registry$models[["fixture-model"]]$defaults$future_parameter <- list(
    mode = "high"
  )

  expect_true(validate_registry_schema(registry))
})

test_that("Registry v2 parameter help is advisory metadata", {
  registry <- read_registry_fixture("registry-v2-valid.yaml")
  registry$interfaces$openai_chat_v1$request$parameters <- list(
    future_parameter = list(
      description = "An upstream provider parameter.",
      docs_url = "https://example.invalid/api"
    )
  )

  expect_true(validate_registry_schema(registry))
})

test_that("native Registry v2 rejects cross-provider parameter maps", {
  registry <- read_registry_fixture("registry-v2-valid.yaml")
  registry$interfaces$openai_chat_v1$request$parameter_map <- list(
    max_tokens = "max_completion_tokens"
  )

  expect_registry_validation_error(
    validate_registry_schema(registry),
    "request.parameter_map"
  )
})

test_that("Registry v2 rejects non-serializable defaults", {
  registry <- read_registry_fixture("registry-v2-valid.yaml")
  registry$models[["fixture-model"]]$defaults$invalid <- environment()

  expect_registry_validation_error(
    validate_registry_schema(registry),
    "defaults"
  )
})

test_that("Registry v2 streaming requires a declared stream transport", {
  registry <- read_registry_fixture("registry-v2-valid.yaml")
  registry$interfaces$openai_chat_v1$transport$stream <- NULL

  expect_registry_validation_error(
    validate_registry_schema(registry),
    "transport.stream"
  )
})

test_that("Registry v2 rejects unknown nested fields", {
  registry <- read_registry_fixture("registry-v2-valid.yaml")
  registry$interfaces$openai_chat_v1$request$function_name <- "unsafe"

  expect_registry_validation_error(
    validate_registry_schema(registry),
    "request"
  )
})
