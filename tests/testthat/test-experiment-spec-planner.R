planner_acknowledgement_json <- function() {
  jsonlite::toJSON(
    list(
      status = "understood",
      toolbox = "PsyLingLLM",
      schema_version = 1L,
      rules_acknowledged = as.list(experiment_planner_rules())
    ),
    auto_unbox = TRUE
  )
}

test_that("planner prompt teaches the toolbox and strict local boundary", {
  prompt <- experiment_planner_system_prompt()

  expect_match(prompt, "PsyLingLLM R package", fixed = TRUE)
  expect_match(prompt, "trial_experiment()", fixed = TRUE)
  expect_match(prompt, "factorial_trial_experiment()", fixed = TRUE)
  expect_match(prompt, "conversation_experiment()", fixed = TRUE)
  expect_match(prompt, "multi_model_experiment()", fixed = TRUE)
  expect_match(prompt, "Registry v2", fixed = TRUE)
  expect_match(prompt, "deterministic", fixed = TRUE)
  expect_match(prompt, "explicit human approval", fixed = TRUE)
  expect_match(prompt, "Return exactly one JSON object", fixed = TRUE)
  expect_match(
    prompt,
    '"$schema": "http://json-schema.org/draft-07/schema#"',
    fixed = TRUE
  )
})

test_that("onboarding acknowledgement is exact and machine validated", {
  valid <- validate_experiment_planner_acknowledgement(
    planner_acknowledgement_json()
  )
  expect_true(valid$valid)
  expect_length(valid$errors, 0L)

  invalid <- validate_experiment_planner_acknowledgement(jsonlite::toJSON(
    list(
      status = "understood",
      toolbox = "PsyLingLLM",
      schema_version = 1L,
      rules_acknowledged = list("no_secrets")
    ),
    auto_unbox = TRUE
  ))
  expect_false(invalid$valid)
  expect_match(invalid$errors, "incomplete", fixed = TRUE)
})

test_that("planner calls use Registry-selected structured output", {
  onboarding <- prepare_experiment_planner_call(
    model_key = "deepseek-chat",
    generation_interface = "chat",
    turn = "onboarding",
    parameters = list(
      max_tokens = 512L,
      temperature = 0,
      thinking = list(type = "disabled")
    )
  )

  expect_s3_class(onboarding, "psylingllm_experiment_planner_call")
  expect_identical(onboarding$function_name, "llm_caller")
  expect_identical(
    onboarding$structured_output$adapter,
    "openai_chat_json_object"
  )
  expect_identical(
    onboarding$arguments$optionals$response_format,
    list(type = "json_object")
  )
  expect_false("api_key" %in% names(onboarding$arguments))
  expect_false("api_url" %in% names(onboarding$arguments))
  expect_false("output_path" %in% names(onboarding$arguments))
  expect_false(onboarding$arguments$stream)

  without_parameters <- prepare_experiment_planner_call(
    model_key = "deepseek-chat",
    generation_interface = "chat"
  )
  expect_identical(
    without_parameters$arguments$optionals,
    list(response_format = list(type = "json_object"))
  )

  spec <- prepare_experiment_planner_call(
    model_key = "gpt-5.6-luna",
    turn = "spec",
    requirements = paste(
      "Use Condition as the only condition field.",
      "Use one repeat and no randomization."
    ),
    source_materials = c("First exact item.", "Second exact item."),
    acknowledgement = planner_acknowledgement_json(),
    parameters = list(max_output_tokens = 2048L)
  )

  expect_identical(
    spec$structured_output$adapter,
    "openai_responses_json_object"
  )
  expect_identical(
    spec$arguments$optionals$text,
    list(format = list(type = "json_object"))
  )
  expect_identical(
    spec$arguments$assistant_content[[2L]]$content,
    planner_acknowledgement_json()
  )
  expect_match(spec$arguments$material, '"First exact item."', fixed = TRUE)
  expect_match(spec$arguments$material, '"Second exact item."', fixed = TRUE)
})

test_that("planner preparation rejects unsafe or ambiguous inputs", {
  expect_error(
    prepare_experiment_planner_call(
      "deepseek-chat",
      "chat",
      parameters = list(response_format = list(type = "text"))
    ),
    class = "experiment_spec_error"
  )
  expect_error(
    prepare_experiment_planner_call(
      "deepseek-chat",
      "chat",
      turn = "spec",
      requirements = "Create a trial.",
      source_materials = "Exact item.",
      acknowledgement = "not json"
    ),
    class = "experiment_spec_error"
  )
  expect_error(
    prepare_experiment_planner_call(
      "deepseek-chat",
      "chat",
      turn = "spec",
      requirements = "Create a trial.",
      source_materials = character(),
      acknowledgement = planner_acknowledgement_json()
    ),
    class = "experiment_spec_error"
  )
})
