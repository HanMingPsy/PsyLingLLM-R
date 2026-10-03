experiment_result_compiled_call <- function() {
  text <- paste(
    readLines(
      testthat::test_path(
        "fixtures", "experiment-spec", "valid-trial-v1.json"
      ),
      warn = FALSE
    ),
    collapse = "\n"
  )
  plan <- normalize_experiment_spec(parse_experiment_spec(text))
  registry <- load_registry_bundle(
    user_path = tempfile("missing-user-registry-")
  )
  review <- review_experiment_plan(
    plan,
    source_materials = plan$data$Material,
    required_condition_names = "Condition",
    registry = registry
  )
  compile_experiment_plan(approve_experiment_plan(review, approved = TRUE))
}

experiment_result_fixture <- function(compiled) {
  input <- experiment_result_expected_inputs(compiled)
  result <- data.frame(Run = seq_len(nrow(input)), input, check.names = FALSE)
  result$Response <- c("Y", "N")
  result$Think <- NA_character_
  result$ModelName <- compiled$arguments$model_key
  result$TotalResponseTime <- c(0.8, 0.9)
  result$FirstTokenLatency <- NA_real_
  result$PromptTokens <- c(20L, 22L)
  result$CompletionTokens <- c(1L, 1L)
  result$TrialStatus <- "SUCCESS"
  result$ResponseStatus <- "OK"
  result$Streaming <- compiled$arguments$stream
  result$Timestamp <- c("2026-10-03 12:00:00", "2026-10-03 12:00:01")
  result$RequestID <- c("request-1", "request-2")
  result
}

test_that("result validator accepts a complete trial result", {
  compiled <- experiment_result_compiled_call()
  result <- experiment_result_fixture(compiled)
  validation <- validate_experiment_result(compiled, result)

  expect_s3_class(
    validation,
    "psylingllm_experiment_result_validation"
  )
  expect_true(validation$valid)
  expect_identical(validation$summary$planned_runs, 2L)
  expect_identical(validation$summary$completed_runs, 2L)
  expect_identical(validation$summary$request_ids, c("request-1", "request-2"))
})

test_that("provider failures remain valid result evidence", {
  compiled <- experiment_result_compiled_call()
  result <- experiment_result_fixture(compiled)
  result$Response[[2L]] <- NA_character_
  result$TrialStatus[[2L]] <- "ERROR"
  result$ResponseStatus[[2L]] <- "ERROR"
  result$RequestID[[2L]] <- NA_character_
  validation <- validate_experiment_result(compiled, result)

  expect_true(validation$valid)
  expect_identical(validation$summary$trial_status$ERROR, 1L)
  expect_identical(validation$summary$trial_status$SUCCESS, 1L)
  expect_identical(validation$summary$response_status$ERROR, 1L)
})

test_that("result validator rejects contract and scientific mismatches", {
  compiled <- experiment_result_compiled_call()
  result <- experiment_result_fixture(compiled)
  result$CompletionTokens <- NULL
  result$Material[[1L]] <- "Changed material."
  result$ModelName[[2L]] <- "other-model"
  result$Response[[1L]] <- ""
  result$ResponseStatus[[2L]] <- "UNKNOWN"
  validation <- validate_experiment_result(compiled, result)
  codes <- vapply(validation$errors, `[[`, character(1), "code")

  expect_false(validation$valid)
  expect_contains(codes, "missing_result_columns")
  expect_contains(codes, "result_input_mismatch")
  expect_contains(codes, "model_identity_mismatch")
  expect_contains(codes, "invalid_response_status")
  expect_contains(codes, "empty_ok_response")
})

test_that("result validator rejects incompatible output column types", {
  compiled <- experiment_result_compiled_call()
  result <- experiment_result_fixture(compiled)
  result$PromptTokens <- as.character(result$PromptTokens)
  result$Run <- as.character(result$Run)
  validation <- validate_experiment_result(compiled, result)
  codes <- vapply(validation$errors, `[[`, character(1), "code")

  expect_false(validation$valid)
  expect_contains(codes, "invalid_result_column_type")
  expect_contains(codes, "invalid_run_sequence")
})

test_that("result validator rejects modified compiled contracts", {
  compiled <- experiment_result_compiled_call()
  result <- experiment_result_fixture(compiled)
  compiled$arguments$repeats <- "1"
  validation <- validate_experiment_result(compiled, result)

  expect_false(validation$valid)
  expect_identical(validation$errors[[1L]]$code, "invalid_compiled_call")
})

test_that("receipt contains identities and summaries but not experiment content", {
  compiled <- experiment_result_compiled_call()
  result <- experiment_result_fixture(compiled)
  receipt <- create_experiment_receipt(
    compiled,
    result,
    planner_request_ids = c("planner-1", "planner-1", "planner-2")
  )
  serialized <- jsonlite::toJSON(receipt, auto_unbox = TRUE, null = "null")

  expect_s3_class(receipt, "psylingllm_experiment_receipt")
  expect_identical(receipt$receipt_version, 1L)
  expect_identical(receipt$model$requested_key, "deepseek-flash")
  expect_identical(receipt$planned_runs, 2L)
  expect_identical(receipt$completed_runs, 2L)
  expect_identical(receipt$planner_request_ids, c("planner-1", "planner-2"))
  expect_identical(receipt$experiment_request_ids, c("request-1", "request-2"))
  expect_false(grepl("The teacher praised", serialized, fixed = TRUE))
  expect_false(grepl('"Response"', serialized, fixed = TRUE))
  expect_false(grepl("Answer using only Y or N", serialized, fixed = TRUE))
  expect_false(any(c("api_key", "api_url", "output_path") %in% names(receipt)))
})

test_that("receipt cannot be created from invalid results", {
  compiled <- experiment_result_compiled_call()
  result <- experiment_result_fixture(compiled)[1L, , drop = FALSE]

  expect_error(
    create_experiment_receipt(compiled, result),
    class = "experiment_spec_error"
  )
  expect_error(
    create_experiment_receipt(
      compiled,
      experiment_result_fixture(compiled),
      planner_request_ids = NA_character_
    ),
    class = "experiment_spec_error"
  )
})
