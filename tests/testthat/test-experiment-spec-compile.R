experiment_compiler_spec <- function(parameter_policy = "explicit") {
  text <- paste(
    readLines(
      testthat::test_path(
        "fixtures", "experiment-spec", "valid-trial-v1.json"
      ),
      warn = FALSE
    ),
    collapse = "\n"
  )
  spec <- parse_experiment_spec(text)
  spec$runtime$parameter_policy <- parameter_policy
  if (identical(parameter_policy, "none")) {
    spec$runtime$parameters <- structure(list(), names = character())
  }
  spec
}

experiment_compiler_approval <- function(parameter_policy = "explicit") {
  plan <- normalize_experiment_spec(
    experiment_compiler_spec(parameter_policy)
  )
  registry <- load_registry_bundle(
    user_path = tempfile("missing-user-registry-")
  )
  review <- review_experiment_plan(
    plan,
    source_materials = plan$data$Material,
    required_condition_names = "Condition",
    registry = registry
  )
  approve_experiment_plan(review, approved = TRUE)
}

test_that("compiler emits only the allowlisted trial call contract", {
  compiled <- compile_experiment_plan(experiment_compiler_approval())

  expect_s3_class(compiled, "psylingllm_experiment_call")
  expect_identical(compiled$call_contract_version, 1L)
  expect_identical(compiled$function_name, "trial_experiment")
  expect_length(
    setdiff(names(compiled$arguments), names(formals(trial_experiment))),
    0L
  )
  expect_identical(compiled$arguments$model_key, "deepseek-flash")
  expect_identical(compiled$arguments$generation_interface, "chat")
  expect_identical(compiled$arguments$repeats, 1L)
  expect_identical(compiled$arguments$delay, 0)
  expect_identical(
    compiled$arguments$optionals,
    list(max_tokens = 512L, thinking = list(type = "disabled"))
  )
  expect_identical(compiled$resolved$interface_id, "deepseek-chat-v1")
})

test_that("compiler preserves the experiment-level optionals states", {
  explicit <- compile_experiment_plan(
    experiment_compiler_approval("explicit")
  )
  none <- compile_experiment_plan(experiment_compiler_approval("none"))

  expect_true("optionals" %in% names(explicit$arguments))
  expect_true("optionals" %in% names(none$arguments))
  expect_true(is.list(explicit$arguments$optionals))
  expect_null(none$arguments$optionals)
})

test_that("compiler keeps execution-owned values outside the plan", {
  compiled <- compile_experiment_plan(experiment_compiler_approval())
  protected <- c(
    "api_key", "api_url", "output_path", "overwrite", "return_raw"
  )

  expect_false(any(protected %in% names(compiled$arguments)))
  expect_identical(compiled$runtime_requirements$required, "api_key")
  expect_setequal(compiled$runtime_requirements$optional, protected[-1L])
})

test_that("compiled arguments can be injected into a local call boundary", {
  compiled <- compile_experiment_plan(experiment_compiler_approval())
  capture_trial_call <- function(
      model_key,
      generation_interface,
      api_key,
      data,
      trial_prompt,
      system_content,
      optionals,
      stream,
      timeout,
      repeats,
      random,
      delay) {
    list(
      model_key = model_key,
      generation_interface = generation_interface,
      api_key = api_key,
      rows = nrow(data),
      trial_prompt = trial_prompt,
      system_content = system_content,
      optionals = optionals,
      stream = stream,
      timeout = timeout,
      repeats = repeats,
      random = random,
      delay = delay
    )
  }
  runtime_arguments <- compiled$arguments
  runtime_arguments$api_key <- "local-test-key"
  captured <- do.call(capture_trial_call, runtime_arguments)

  expect_identical(captured$api_key, "local-test-key")
  expect_identical(captured$rows, 2L)
  expect_identical(captured$trial_prompt, compiled$arguments$trial_prompt)
  expect_identical(captured$optionals, compiled$arguments$optionals)
})

test_that("compiler rejects missing approval and modified reviews", {
  approval <- experiment_compiler_approval()
  rejected <- approval
  rejected$approved <- FALSE
  modified <- approval
  modified$review$preview$projected_runs <- 999L

  expect_error(
    compile_experiment_plan(rejected),
    class = "experiment_spec_error"
  )
  expect_error(
    compile_experiment_plan(modified),
    class = "experiment_spec_error"
  )
})
