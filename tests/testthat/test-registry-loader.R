loader_fixture_path <- function(name) {
  testthat::test_path("fixtures", name)
}

test_that("registry bundle keeps source and merged views distinct", {
  missing_user <- file.path(withr::local_tempdir(), "missing.yaml")
  system_path <- loader_fixture_path("registry-v1-minimal.yaml")
  bundle <- load_registry_bundle(
    system_path = system_path,
    user_path = missing_user
  )

  expect_named(
    bundle,
    c("system", "user", "default", "merged", "raw", "versions", "paths")
  )
  expect_identical(bundle$versions[["system"]], 1L)
  expect_true(is.na(bundle$versions[["user"]]))
  expect_identical(bundle$raw$system, yaml::read_yaml(system_path))
  expect_length(bundle$user$models, 0L)
  expect_identical(bundle$merged, bundle$system)
})

test_that("registry merge uses default then system then user precedence", {
  system_path <- loader_fixture_path("registry-v1-multiple-interfaces.yaml")
  user_path <- loader_fixture_path("registry-v1-model-override.yaml")
  default <- yaml::read_yaml(system_path)
  default[["fixture-multi"]]$chat$provider <- "default-provider"

  bundle <- load_registry_bundle(
    system_path = system_path,
    user_path = user_path,
    default_registry = default
  )
  model <- bundle$merged$models[["fixture-multi"]]
  interface <- bundle$merged$interfaces[[model$default_interface]]

  expect_identical(bundle$versions, c(system = 1L, user = 1L, default = 1L))
  expect_identical(model$provider, "user-proxy")
  expect_length(model$interfaces, 1L)
  expect_identical(interface$metadata$legacy_provider_label, "user-proxy")
  expect_false("legacy.fixture-multi.responses" %in% model$interfaces)
})

test_that("Registry v1 and v2 files normalize at the loader boundary", {
  missing_user <- file.path(withr::local_tempdir(), "missing.yaml")
  v1 <- load_registry_bundle(
    system_path = loader_fixture_path("registry-v1-minimal.yaml"),
    user_path = missing_user
  )
  v2 <- load_registry_bundle(
    system_path = loader_fixture_path("registry-v2-equivalent-to-v1.yaml"),
    user_path = missing_user
  )

  expect_identical(v1$system, v2$system)
  expect_identical(v1$merged, v2$merged)
  expect_identical(v2$versions[["system"]], 2L)
})

test_that("missing user registry is empty and missing system registry fails", {
  temporary_directory <- withr::local_tempdir()
  missing <- file.path(temporary_directory, "missing.yaml")

  bundle <- load_registry_bundle(
    system_path = loader_fixture_path("registry-v1-minimal.yaml"),
    user_path = missing
  )
  expect_length(bundle$user$models, 0L)

  condition <- tryCatch(
    load_registry_bundle(system_path = missing, user_path = NULL),
    registry_load_error = identity
  )
  expect_s3_class(condition, "registry_load_error")
  expect_identical(condition$source, "system")
  expect_identical(condition$reason, "missing_file")
})

test_that("malformed YAML reports its source and path", {
  invalid_path <- loader_fixture_path("registry-invalid.yaml")
  condition <- tryCatch(
    load_registry_bundle(
      system_path = loader_fixture_path("registry-v1-minimal.yaml"),
      user_path = invalid_path
    ),
    registry_load_error = identity
  )

  expect_s3_class(condition, "registry_load_error")
  expect_identical(condition$source, "user")
  expect_identical(condition$path, invalid_path)
  expect_identical(condition$reason, "parse_error")
})

test_that("loading registries does not modify source files", {
  system_path <- loader_fixture_path("registry-v1-minimal.yaml")
  user_path <- loader_fixture_path("registry-v1-model-override.yaml")
  before <- tools::md5sum(c(system_path, user_path))

  load_registry_bundle(system_path = system_path, user_path = user_path)

  expect_identical(tools::md5sum(c(system_path, user_path)), before)
})

test_that("public load_registry keeps its existing flat return contract", {
  registry <- load_registry()

  expect_false("merged" %in% names(registry))
  expect_setequal(
    names(registry),
    c("deepseek-chat", "deepseek-reasoner", "gpt-4o")
  )
  expect_identical(basename(get_system_registry_path()), "system_registry.yaml")
})

test_that("public load_registry preserves NULL for an empty YAML file", {
  empty_registry <- tempfile(fileext = ".yaml")
  file.create(empty_registry)

  local_mocked_bindings(
    get_system_registry_path = function() empty_registry,
    .package = "PsyLingLLM"
  )

  expect_null(load_registry())
})

test_that("legacy and standard user Registry paths merge without migration", {
  temporary_directory <- withr::local_tempdir()
  standard_path <- file.path(temporary_directory, "config", "model_registry.yaml")
  legacy_path <- file.path(temporary_directory, "legacy", "model_registry.yaml")
  dir.create(dirname(standard_path), recursive = TRUE)
  dir.create(dirname(legacy_path), recursive = TRUE)
  file.copy(
    loader_fixture_path("registry-v1-user-override.yaml"),
    standard_path
  )
  file.copy(
    loader_fixture_path("registry-v1-minimal.yaml"),
    legacy_path
  )
  before <- tools::md5sum(c(standard_path, legacy_path))

  bundle <- load_registry_bundle(
    system_path = loader_fixture_path("registry-v1-multiple-interfaces.yaml"),
    user_path = standard_path,
    legacy_user_path = legacy_path
  )

  expect_true(all(c("fixture-model", "deepseek-chat") %in%
    names(bundle$user$models)))
  expect_identical(tools::md5sum(c(standard_path, legacy_path)), before)
})

test_that("the standard user Registry overrides the legacy Registry", {
  temporary_directory <- withr::local_tempdir()
  standard_path <- file.path(temporary_directory, "config.yaml")
  legacy_path <- file.path(temporary_directory, "legacy.yaml")
  legacy <- yaml::read_yaml(loader_fixture_path("registry-v1-minimal.yaml"))
  standard <- legacy
  standard[["fixture-model"]]$chat$provider <- "standard-user"
  yaml::write_yaml(legacy, legacy_path)
  yaml::write_yaml(standard, standard_path)

  bundle <- load_registry_bundle(
    system_path = loader_fixture_path("registry-v1-minimal.yaml"),
    user_path = standard_path,
    legacy_user_path = legacy_path
  )
  model <- bundle$user$models[["fixture-model"]]
  interface <- bundle$user$interfaces[[model$default_interface]]

  expect_identical(model$provider, "standard-user")
  expect_identical(
    interface$metadata$legacy_provider_label,
    "standard-user"
  )
})
