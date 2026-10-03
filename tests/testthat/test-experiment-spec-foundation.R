experiment_spec_fixture <- function(filename) {
  testthat::test_path("fixtures", "experiment-spec", filename)
}

test_that("Experiment Spec v1 schema asset is readable and versioned", {
  path <- experiment_spec_schema_path()
  schema <- read_experiment_spec_schema()
  json <- experiment_spec_schema_json()

  expect_true(file.exists(path))
  expect_identical(
    schema$`$schema`,
    "http://json-schema.org/draft-07/schema#"
  )
  expect_identical(schema$properties$experiment_type$enum, list("trial"))
  expect_match(json, "PsyLingLLM Experiment Spec v1", fixed = TRUE)
  expect_error(
    experiment_spec_schema_path(2L),
    class = "experiment_spec_error"
  )
})

test_that("Experiment Spec JSON parser returns exact nested values", {
  text <- paste(
    readLines(experiment_spec_fixture("valid-trial-v1.json"), warn = FALSE),
    collapse = "\n"
  )
  spec <- parse_experiment_spec(text)

  expect_identical(spec$schema_version, 1L)
  expect_identical(spec$experiment_type, "trial")
  expect_identical(spec$materials[[1L]]$item, 1L)
  expect_identical(
    spec$runtime$parameters$thinking,
    list(type = "disabled")
  )
  expect_error(parse_experiment_spec("not-json"), class = "experiment_spec_error")
})

test_that("R semantic validator accepts the canonical trial fixture", {
  text <- paste(
    readLines(experiment_spec_fixture("valid-trial-v1.json"), warn = FALSE),
    collapse = "\n"
  )
  validation <- validate_experiment_spec(parse_experiment_spec(text))

  expect_s3_class(validation, "psylingllm_experiment_spec_validation")
  expect_true(validation$valid)
  expect_length(validation$errors, 0L)
})

test_that("R semantic validator rejects unknown and protected fields", {
  text <- paste(
    readLines(
      experiment_spec_fixture("invalid-extra-field-v1.json"),
      warn = FALSE
    ),
    collapse = "\n"
  )
  validation <- validate_experiment_spec(parse_experiment_spec(text))
  codes <- vapply(validation$errors, `[[`, character(1), "code")

  expect_false(validation$valid)
  expect_contains(codes, "unknown_field")
  expect_contains(codes, "forbidden_parameter")
})

test_that("R semantic validator enforces cross-field trial invariants", {
  text <- paste(
    readLines(experiment_spec_fixture("valid-trial-v1.json"), warn = FALSE),
    collapse = "\n"
  )
  spec <- parse_experiment_spec(text)
  spec$materials[[2L]]$item <- 1L
  spec$materials[[2L]]$conditions <- list(Group = "Mismatch")
  spec$runtime$parameter_policy <- "none"

  validation <- validate_experiment_spec(spec)
  codes <- vapply(validation$errors, `[[`, character(1), "code")

  expect_false(validation$valid)
  expect_contains(codes, "duplicate_item")
  expect_contains(codes, "inconsistent_condition_fields")
  expect_contains(codes, "unexpected_parameters")
})

test_that("R semantic validator does not coerce schema versions", {
  text <- paste(
    readLines(experiment_spec_fixture("valid-trial-v1.json"), warn = FALSE),
    collapse = "\n"
  )
  spec <- parse_experiment_spec(text)

  spec$schema_version <- "1"
  expect_false(validate_experiment_spec(spec)$valid)

  spec$schema_version <- 1.5
  expect_false(validate_experiment_spec(spec)$valid)
})

test_that("parameter policy none accepts an explicit empty JSON object", {
  text <- paste(
    readLines(experiment_spec_fixture("valid-trial-v1.json"), warn = FALSE),
    collapse = "\n"
  )
  spec <- parse_experiment_spec(text)
  spec$runtime$parameter_policy <- "none"
  spec$runtime$parameters <- structure(list(), names = character())

  validation <- validate_experiment_spec(spec)
  expect_true(validation$valid)
})

test_that("JSON Schema and R validator agree on canonical fixtures", {
  skip_if_not_installed("jsonvalidate")
  schema <- jsonvalidate::json_schema$new(
    experiment_spec_schema_path(),
    engine = "ajv",
    strict = TRUE
  )
  valid_json <- paste(
    readLines(experiment_spec_fixture("valid-trial-v1.json"), warn = FALSE),
    collapse = "\n"
  )
  invalid_json <- paste(
    readLines(
      experiment_spec_fixture("invalid-extra-field-v1.json"),
      warn = FALSE
    ),
    collapse = "\n"
  )

  expect_true(schema$validate(valid_json))
  expect_false(schema$validate(invalid_json))
  expect_true(validate_experiment_spec(parse_experiment_spec(valid_json))$valid)
  expect_false(validate_experiment_spec(parse_experiment_spec(invalid_json))$valid)
})
