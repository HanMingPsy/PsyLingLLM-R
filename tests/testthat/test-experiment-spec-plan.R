experiment_plan_fixture <- function() {
  text <- paste(
    readLines(
      testthat::test_path(
        "fixtures", "experiment-spec", "valid-trial-v1.json"
      ),
      warn = FALSE
    ),
    collapse = "\n"
  )
  parse_experiment_spec(text)
}

experiment_plan_registry <- function() {
  load_registry_bundle(user_path = tempfile("missing-user-registry-"))
}

test_that("valid Experiment Spec normalizes to deterministic trial data", {
  plan <- normalize_experiment_spec(experiment_plan_fixture())

  expect_s3_class(plan, "psylingllm_experiment_plan")
  expect_identical(
    names(plan$data),
    c("Item", "Condition", "Material", "TrialPrompt")
  )
  expect_identical(plan$data$Item, 1:2)
  expect_identical(plan$data$Condition, c("Control", "Anomalous"))
  expect_identical(plan$data$Material, c(
    "The teacher praised the student.",
    "The sandwich frightened the doctor."
  ))
  expect_true(all(is.na(plan$data$TrialPrompt)))
  expect_identical(plan$task$trial_prompt, "Is this sentence natural? Answer only Y or N.")
  expect_identical(plan$runtime$repeats, 1L)
  expect_identical(plan$runtime$timeout, 120L)
})

test_that("normalization rejects invalid specs before producing trial data", {
  spec <- experiment_plan_fixture()
  spec$materials[[2L]]$item <- 1L

  expect_error(
    normalize_experiment_spec(spec),
    "item values must be unique",
    class = "experiment_spec_error"
  )
})

test_that("condition columns require stable scalar types", {
  spec <- experiment_plan_fixture()
  spec$materials[[2L]]$conditions$Condition <- 2
  validation <- validate_experiment_spec(spec)
  codes <- vapply(validation$errors, `[[`, character(1), "code")

  expect_false(validation$valid)
  expect_contains(codes, "inconsistent_condition_types")
})

test_that("review verifies source fidelity and Registry identity", {
  plan <- normalize_experiment_spec(experiment_plan_fixture())
  review <- review_experiment_plan(
    plan,
    source_materials = plan$data$Material,
    required_condition_names = "Condition",
    registry = experiment_plan_registry()
  )

  expect_s3_class(review, "psylingllm_experiment_review")
  expect_true(review$valid)
  expect_identical(review$preview$function_name, "trial_experiment")
  expect_identical(review$preview$projected_runs, 2L)
  expect_identical(review$preview$resolved$model_key, "deepseek-flash")
  expect_identical(review$preview$resolved$interface_id, "deepseek-chat-v1")
  expect_identical(
    review$preview$parameter_names,
    c("max_tokens", "thinking")
  )
})

test_that("review rejects changed materials and unresolved interfaces", {
  spec <- experiment_plan_fixture()
  spec$runtime$generation_interface <- "missing-interface"
  plan <- normalize_experiment_spec(spec)
  review <- review_experiment_plan(
    plan,
    source_materials = rev(plan$data$Material),
    required_condition_names = "WrongCondition",
    registry = experiment_plan_registry()
  )
  codes <- vapply(review$errors, `[[`, character(1), "code")

  expect_false(review$valid)
  expect_contains(codes, "material_fidelity_failure")
  expect_contains(codes, "condition_schema_mismatch")
  expect_contains(codes, "registry_resolution_failure")
})

test_that("review rejects a normalized plan changed after validation", {
  plan <- normalize_experiment_spec(experiment_plan_fixture())
  plan$runtime$repeats <- 10L
  review <- review_experiment_plan(
    plan,
    source_materials = plan$data$Material,
    registry = experiment_plan_registry()
  )
  codes <- vapply(review$errors, `[[`, character(1), "code")

  expect_false(review$valid)
  expect_contains(codes, "plan_integrity_failure")
  expect_null(review$preview)
})

test_that("approval records an explicit human decision without execution data", {
  plan <- normalize_experiment_spec(experiment_plan_fixture())
  review <- review_experiment_plan(
    plan,
    source_materials = plan$data$Material,
    required_condition_names = "Condition",
    registry = experiment_plan_registry()
  )
  rejected <- approve_experiment_plan(review, approved = FALSE)
  approved <- approve_experiment_plan(
    review,
    approved = TRUE,
    note = "Reviewed in an offline test."
  )

  expect_s3_class(approved, "psylingllm_experiment_approval")
  expect_false(rejected$approved)
  expect_true(approved$approved)
  expect_identical(approved$note, "Reviewed in an offline test.")
  expect_false(any(c("api_key", "api_url", "output_path") %in% names(approved)))
  expect_error(
    approve_experiment_plan(review, approved = NA),
    class = "experiment_spec_error"
  )
})
