resolver_fixture_path <- function(name) {
  testthat::test_path("fixtures", name)
}

read_resolver_fixture <- function(name) {
  yaml::read_yaml(resolver_fixture_path(name))
}

test_that("v1 and equivalent v2 registries resolve identically", {
  v1 <- resolve_registry_entry(
    "fixture-model",
    generation_interface = "chat",
    registry = read_resolver_fixture("registry-v1-minimal.yaml")
  )
  v2 <- resolve_registry_entry(
    "fixture-model",
    generation_interface = "legacy.fixture-model.chat",
    registry = read_resolver_fixture("registry-v2-equivalent-to-v1.yaml")
  )

  expect_s3_class(v1, "psylingllm_model_config")
  expect_identical(v1, v2)
  expect_identical(v1$model$key, "fixture-model")
  expect_identical(v1$model$id, "fixture-model")
  expect_identical(v1$provider$id, "fixture-provider")
  expect_identical(v1$interface$id, "legacy.fixture-model.chat")
})

test_that("resolver accepts loaded bundles without reading other sources", {
  bundle <- load_registry_bundle(
    system_path = resolver_fixture_path("registry-v1-minimal.yaml"),
    user_path = file.path(withr::local_tempdir(), "missing.yaml")
  )

  config <- resolve_registry_entry("fixture-model", registry = bundle)

  expect_identical(config$model$key, "fixture-model")
  expect_identical(config$model$matched_by, "key")
})

test_that("resolver uses the bundle's model-level source precedence", {
  bundle <- load_registry_bundle(
    system_path = resolver_fixture_path(
      "registry-v1-multiple-interfaces.yaml"
    ),
    user_path = resolver_fixture_path("registry-v1-model-override.yaml")
  )

  config <- resolve_registry_entry("fixture-multi", registry = bundle)

  expect_identical(config$provider$id, "user-proxy")
  expect_identical(
    config$interface$metadata$legacy_provider_label,
    "user-proxy"
  )
  expect_identical(
    config$model$available_interfaces,
    "legacy.fixture-multi.chat"
  )
})

test_that("a v1 model named merged is not mistaken for a loaded bundle", {
  registry <- read_resolver_fixture("registry-v1-minimal.yaml")
  registry$merged <- registry[["fixture-model"]]
  registry[["fixture-model"]] <- NULL

  config <- resolve_registry_entry("merged", registry = registry)

  expect_identical(config$model$key, "merged")
  expect_identical(config$model$id, "fixture-model")
})

test_that("model resolution supports normalized keys and explicit aliases", {
  registry <- read_resolver_fixture("registry-v2-valid.yaml")

  normalized <- resolve_registry_entry("fixture/model", registry = registry)
  aliased <- resolve_registry_entry("FIXTURE", registry = registry)

  expect_identical(normalized$model$key, "fixture-model")
  expect_identical(normalized$model$matched_by, "normalized_key")
  expect_identical(aliased$model$key, "fixture-model")
  expect_identical(aliased$model$matched_by, "alias")
})

test_that("resolver rejects unknown models instead of guessing a provider", {
  registry <- read_resolver_fixture("registry-v2-valid.yaml")
  condition <- tryCatch(
    resolve_registry_entry("gpt-future", registry = registry),
    registry_resolution_error = identity
  )

  expect_s3_class(condition, "registry_resolution_error")
  expect_identical(condition$reason, "model_not_found")
  expect_match(condition$message, "explicit alias", fixed = TRUE)
})

test_that("resolver rejects aliases shared by multiple models", {
  registry <- read_resolver_fixture("registry-v2-valid.yaml")
  second <- registry$models[["fixture-model"]]
  second$model_id <- "fixture-model-2"
  second$aliases <- "fixture"
  registry$models[["fixture-model-2"]] <- second

  condition <- tryCatch(
    resolve_registry_entry("fixture", registry = registry),
    registry_resolution_error = identity
  )

  expect_s3_class(condition, "registry_resolution_error")
  expect_identical(condition$reason, "ambiguous_alias")
  expect_setequal(
    condition$candidates,
    c("fixture-model", "fixture-model-2")
  )
})

test_that("interface selection uses defaults and rejects ambiguity", {
  registry <- read_resolver_fixture("registry-v2-valid.yaml")
  default <- resolve_registry_entry("fixture-model", registry = registry)
  by_protocol <- resolve_registry_entry(
    "fixture-model",
    generation_interface = "openai_chat",
    registry = registry
  )

  expect_identical(default$interface$id, "openai_chat_v1")
  expect_identical(by_protocol$interface$id, "openai_chat_v1")

  registry$interfaces$openai_chat_v2 <- registry$interfaces$openai_chat_v1
  registry$models[["fixture-model"]]$interfaces <- c(
    "openai_chat_v1", "openai_chat_v2"
  )
  registry$models[["fixture-model"]]$default_interface <- NULL
  registry$models[["fixture-model"]]$defaults <- NULL

  condition <- tryCatch(
    resolve_registry_entry("fixture-model", registry = registry),
    registry_resolution_error = identity
  )
  expect_s3_class(condition, "registry_resolution_error")
  expect_identical(condition$reason, "ambiguous_interface")
})

test_that("canonical config compiles endpoint headers and defaults", {
  registry <- read_resolver_fixture("registry-v2-valid.yaml")
  registry$providers$fixture$headers <- list(
    Accept = "application/json",
    `X-Source` = "provider"
  )
  registry$interfaces$openai_chat_v1$request$headers <- list(
    `Content-Type` = "application/json",
    `X-Source` = "interface"
  )
  registry$interfaces$openai_chat_v1$request$defaults <- list(
    temperature = 0.1
  )

  config <- resolve_registry_entry("fixture-model", registry = registry)

  expect_identical(
    config$interface$request$url,
    "https://example.invalid/v1/chat/completions"
  )
  expect_identical(config$interface$request$headers$Accept, "application/json")
  expect_identical(config$interface$request$headers$`X-Source`, "interface")
  expect_identical(
    config$interface$request$headers$`Content-Type`,
    "application/json"
  )
  expect_identical(
    config$defaults,
    list(temperature = 0.2, max_tokens = 256L)
  )
  expect_identical(config$interface$request$defaults, config$defaults)
})

test_that("canonical config resolves capability values and bindings", {
  config <- resolve_registry_entry(
    "fixture-model",
    registry = read_resolver_fixture("registry-v2-valid.yaml")
  )

  expect_true(config$capabilities$values$reasoning)
  expect_identical(
    config$capabilities$bindings$reasoning$response_channel,
    "reasoning"
  )
  expect_identical(
    config$capabilities$definitions$reasoning$value_type,
    "logical"
  )
})

test_that("resolver does not read credentials or modify registry data", {
  registry <- read_resolver_fixture("registry-v2-valid.yaml")
  before <- registry
  old_key <- Sys.getenv("FIXTURE_API_KEY", unset = NA_character_)

  config <- resolve_registry_entry("fixture-model", registry = registry)

  expect_identical(registry, before)
  expect_identical(Sys.getenv("FIXTURE_API_KEY", unset = NA_character_), old_key)
  expect_identical(config$provider$auth$env_var, "FIXTURE_API_KEY")
  expect_false("value" %in% names(config$provider$auth))
})

test_that("missing interface reports available candidates", {
  condition <- tryCatch(
    resolve_registry_entry(
      "fixture-model",
      generation_interface = "anthropic_messages",
      registry = read_resolver_fixture("registry-v2-valid.yaml")
    ),
    registry_resolution_error = identity
  )

  expect_s3_class(condition, "registry_resolution_error")
  expect_identical(condition$reason, "interface_not_found")
  expect_identical(condition$candidates, "openai_chat_v1")
})
