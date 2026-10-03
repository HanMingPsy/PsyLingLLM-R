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

test_that("processed planner responses reach reviewed Experiment Spec plans", {
  acknowledgement_call <- prepare_experiment_planner_call(
    "deepseek-chat",
    "chat"
  )
  acknowledgement_response <- process_experiment_planner_response(
    acknowledgement_call,
    list(
      status = 200L,
      response_status = "OK",
      answer = planner_acknowledgement_json(),
      usage = list(id = "planner-onboarding-id")
    )
  )
  expect_true(acknowledgement_response$valid)
  expect_identical(
    acknowledgement_response$acknowledgement,
    planner_acknowledgement_json()
  )
  expect_identical(
    acknowledgement_response$request_id,
    "planner-onboarding-id"
  )

  source_materials <- c(
    "The teacher praised the student.",
    "The sandwich frightened the doctor."
  )
  spec_call <- prepare_experiment_planner_call(
    "deepseek-chat",
    "chat",
    turn = "spec",
    requirements = "Use one condition field named Condition.",
    source_materials = source_materials,
    acknowledgement = planner_acknowledgement_json()
  )
  spec_json <- paste(
    readLines(
      test_path("fixtures", "experiment-spec", "valid-trial-v1.json"),
      warn = FALSE,
      encoding = "UTF-8"
    ),
    collapse = "\n"
  )
  spec_response <- process_experiment_planner_response(
    spec_call,
    list(
      status = 200L,
      response_status = "OK",
      answer = spec_json,
      usage = list(id = "planner-spec-id")
    ),
    source_materials = source_materials,
    required_condition_names = "Condition"
  )

  expect_true(spec_response$valid)
  expect_s3_class(spec_response$plan, "psylingllm_experiment_plan")
  expect_s3_class(spec_response$review, "psylingllm_experiment_review")
  expect_identical(spec_response$plan$data$Material, source_materials)
  expect_identical(spec_response$review$preview$projected_runs, 2L)
  expect_identical(spec_response$request_id, "planner-spec-id")
})

test_that("processed planner responses reject API and fidelity failures", {
  call <- prepare_experiment_planner_call(
    "deepseek-chat",
    "chat",
    turn = "spec",
    requirements = "Create one trial.",
    source_materials = "Exact material.",
    acknowledgement = planner_acknowledgement_json()
  )
  api_failure <- process_experiment_planner_response(
    call,
    list(
      status = 599L,
      response_status = "ERROR",
      answer = NULL,
      error = list(message = "Provider rejected the request."),
      usage = list(id = "failed-request-id")
    ),
    source_materials = "Exact material."
  )
  expect_false(api_failure$valid)
  expect_identical(api_failure$errors[[1L]]$code, "planner_api_failure")
  expect_null(api_failure$spec)

  invalid_json <- process_experiment_planner_response(
    call,
    list(
      status = 200L,
      response_status = "OK",
      answer = "```json\n{}\n```",
      usage = list(id = "invalid-json-id")
    ),
    source_materials = "Exact material."
  )
  expect_false(invalid_json$valid)
  expect_identical(invalid_json$errors[[1L]]$code, "invalid_json")
  expect_match(
    experiment_planner_validation_feedback(invalid_json),
    "Return one corrected Experiment Spec v1 JSON object only.",
    fixed = TRUE
  )

  fixture_path <- test_path(
    "fixtures", "experiment-spec", "valid-trial-v1.json"
  )
  changed_material <- process_experiment_planner_response(
    call,
    list(
      status = 200L,
      response_status = "OK",
      answer = paste(readLines(fixture_path, warn = FALSE), collapse = "\n"),
      usage = list()
    ),
    source_materials = c(
      "The teacher praised the student.",
      "The doctor was frightened by a sandwich."
    ),
    required_condition_names = "Condition"
  )
  expect_false(changed_material$valid)
  expect_identical(
    changed_material$errors[[1L]]$code,
    "material_fidelity_failure"
  )
})

test_that("two-turn planner produces a review without exposing credentials", {
  spec_json <- paste(
    readLines(
      test_path("fixtures", "experiment-spec", "valid-trial-v1.json"),
      warn = FALSE,
      encoding = "UTF-8"
    ),
    collapse = "\n"
  )
  calls <- list()
  executor <- function(...) {
    arguments <- list(...)
    calls[[length(calls) + 1L]] <<- arguments
    answer <- if (length(calls) == 1L) {
      planner_acknowledgement_json()
    } else {
      spec_json
    }
    list(
      status = 200L,
      response_status = "OK",
      answer = answer,
      usage = list(id = paste0("request-", length(calls)))
    )
  }
  secret <- "test-secret-must-not-escape"
  source_materials <- c(
    "The teacher praised the student.",
    "The sandwich frightened the doctor."
  )

  session <- run_experiment_planner(
    model_key = "deepseek-chat",
    generation_interface = "chat",
    requirements = "Use one condition field named Condition.",
    source_materials = source_materials,
    api_key = secret,
    parameters = list(max_tokens = 2048L),
    required_condition_names = "Condition",
    executor = executor
  )

  expect_true(session$valid)
  expect_identical(session$stage, "review")
  expect_identical(session$attempts, 1L)
  expect_identical(session$request_ids, c("request-1", "request-2"))
  expect_s3_class(session$review, "psylingllm_experiment_review")
  expect_identical(session$plan$data$Material, source_materials)
  expect_length(calls, 2L)
  expect_true(all(vapply(calls, function(call) call$api_key == secret, logical(1))))
  session_json <- jsonlite::toJSON(session, auto_unbox = TRUE, null = "null")
  expect_false(grepl(secret, session_json, fixed = TRUE))
})

test_that("two-turn planner repairs one invalid plan and then stops", {
  valid_json <- paste(
    readLines(
      test_path("fixtures", "experiment-spec", "valid-trial-v1.json"),
      warn = FALSE,
      encoding = "UTF-8"
    ),
    collapse = "\n"
  )
  answers <- list(
    planner_acknowledgement_json(),
    "not json",
    valid_json
  )
  calls <- list()
  executor <- function(...) {
    calls[[length(calls) + 1L]] <<- list(...)
    list(
      status = 200L,
      response_status = "OK",
      answer = answers[[length(calls)]],
      usage = list(id = paste0("repair-", length(calls)))
    )
  }
  source_materials <- c(
    "The teacher praised the student.",
    "The sandwich frightened the doctor."
  )

  session <- run_experiment_planner(
    model_key = "deepseek-chat",
    generation_interface = "chat",
    requirements = "Use one condition field named Condition.",
    source_materials = source_materials,
    api_key = "local-test-key",
    required_condition_names = "Condition",
    executor = executor
  )

  expect_true(session$valid)
  expect_identical(session$attempts, 2L)
  expect_length(calls, 3L)
  expect_length(calls[[3L]]$assistant_content, 4L)
  expect_match(
    calls[[3L]]$material,
    "previous JSON failed deterministic PsyLingLLM validation",
    fixed = TRUE
  )
})

test_that("planner does not retry provider failures", {
  calls <- 0L
  executor <- function(...) {
    calls <<- calls + 1L
    if (calls == 1L) {
      return(list(
        status = 200L,
        response_status = "OK",
        answer = planner_acknowledgement_json(),
        usage = list(id = "onboarding-id")
      ))
    }
    list(
      status = 599L,
      response_status = "ERROR",
      answer = NULL,
      error = list(message = "Provider failure."),
      usage = list(id = "failed-id")
    )
  }

  session <- run_experiment_planner(
    model_key = "deepseek-chat",
    generation_interface = "chat",
    requirements = "Create one trial.",
    source_materials = "Exact material.",
    api_key = "local-test-key",
    executor = executor
  )

  expect_false(session$valid)
  expect_identical(session$stage, "planning")
  expect_identical(session$attempts, 1L)
  expect_identical(calls, 2L)
  expect_identical(session$errors[[1L]]$code, "planner_api_failure")
})

test_that("planner does not try to repair an empty response", {
  calls <- 0L
  executor <- function(...) {
    calls <<- calls + 1L
    list(
      status = 200L,
      response_status = "OK",
      answer = if (calls == 1L) planner_acknowledgement_json() else "",
      usage = list(id = paste0("empty-", calls))
    )
  }

  session <- run_experiment_planner(
    model_key = "deepseek-chat",
    generation_interface = "chat",
    requirements = "Create one trial.",
    source_materials = "Exact material.",
    api_key = "local-test-key",
    executor = executor
  )

  expect_false(session$valid)
  expect_identical(session$attempts, 1L)
  expect_identical(calls, 2L)
  expect_identical(session$errors[[1L]]$code, "empty_planner_response")
})
