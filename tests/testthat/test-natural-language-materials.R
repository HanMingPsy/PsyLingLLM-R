test_that("planner prompt describes the PsyLingLLM toolbox and strict boundary", {
  prompt <- nl_psylingllm_toolbox_prompt()

  expect_match(prompt, "Registry v2", fixed = TRUE)
  expect_match(prompt, "trial_experiment()", fixed = TRUE)
  expect_match(prompt, "factorial_trial_experiment()", fixed = TRUE)
  expect_match(prompt, "conversation_experiment()", fixed = TRUE)
  expect_match(prompt, "multi_model_experiment()", fixed = TRUE)
  expect_match(prompt, "ResponseStatus", fixed = TRUE)
  expect_match(prompt, "deterministic local validation", fixed = TRUE)
  expect_match(prompt, "Return exactly one JSON object", fixed = TRUE)
  expect_match(prompt, '"additionalProperties": false', fixed = TRUE)
})

test_that("planner contracts expose versioned JSON schemas", {
  acknowledgement_schema <- nl_acknowledgement_schema()
  trial_plan_schema <- nl_trial_plan_schema()

  expect_identical(
    acknowledgement_schema$`$schema`,
    "https://json-schema.org/draft/2020-12/schema"
  )
  expect_false(acknowledgement_schema$additionalProperties)
  expect_false(trial_plan_schema$additionalProperties)
  expect_identical(
    trial_plan_schema$properties$experiment$properties$type$enum,
    list("trial")
  )
})

test_that("JSON-mode wrapper muffles only the known Registry advisory", {
  expect_silent(nl_allow_json_mode_advisory({
    warning(
      paste(
        "Provider parameter(s) are not documented by this Registry entry",
        "and will be sent unchanged: response_format."
      ),
      call. = FALSE
    )
    "ok"
  }))
  expect_warning(
    nl_allow_json_mode_advisory({
      warning("A different warning must remain visible.", call. = FALSE)
      "ok"
    }),
    "different warning"
  )
})

test_that("simulated first turn acknowledges the complete toolbox contract", {
  acknowledgement <- nl_extract_json_object(jsonlite::toJSON(
    list(
      status = "understood",
      toolbox = "PsyLingLLM",
      rules_acknowledged = list(
        "structured_materials",
        "deterministic_validation",
        "human_approval",
        "no_secrets"
      )
    ),
    auto_unbox = TRUE
  ))

  validation <- nl_validate_toolbox_acknowledgement(acknowledgement)
  expect_true(validation$valid)
  expect_length(validation$errors, 0L)
})

test_that("simulated planner output compiles to an existing toolbox call", {
  planner_output <- jsonlite::toJSON(
    list(
      status = "ready",
      document = list(
        schema_version = 1L,
        experiment_type = "trial",
        task = list(
          trial_prompt = "Is this sentence natural? Answer only Y or N."
        ),
        rows = list(
          list(
            item = 1L,
            material = "The teacher praised the student.",
            conditions = list(Condition = "Control")
          ),
          list(
            item = 2L,
            material = "The child opened the window.",
            conditions = list(Condition = "Control")
          ),
          list(
            item = 3L,
            material = "The sandwich frightened the doctor.",
            conditions = list(Condition = "Anomalous")
          )
        )
      ),
      experiment = list(
        spec_version = 1L,
        type = "trial",
        model_key = "deepseek-flash",
        generation_interface = "chat",
        system_content = paste(
          "You are a participant in a psychology experiment.",
          "Answer using only Y or N, with no explanation or punctuation."
        ),
        repeats = 2L,
        random = FALSE,
        stream = FALSE,
        timeout = 120L,
        parameter_policy = "explicit",
        parameters = list(
          max_tokens = 512L,
          temperature = 0,
          thinking = list(type = "disabled")
        )
      )
    ),
    auto_unbox = TRUE,
    null = "null"
  )

  prepared <- nl_prepare_experiment(planner_output)
  expect_true(prepared$valid)
  expect_identical(
    names(prepared$data),
    c("Item", "Condition", "Material", "TrialPrompt")
  )
  expect_identical(prepared$data$Item, 1:3)
  expect_identical(
    prepared$data$Condition,
    c("Control", "Control", "Anomalous")
  )

  review <- nl_review_experiment(
    prepared,
    source_materials = c(
      "The teacher praised the student.",
      "The child opened the window.",
      "The sandwich frightened the doctor."
    ),
    required_condition_names = "Condition"
  )
  expect_true(review$valid)
  expect_identical(review$preview$projected_runs, 6L)
  expect_identical(
    review$preview$parameter_names,
    c("max_tokens", "temperature", "thinking")
  )

  rejected <- nl_approve_experiment(review, approved = FALSE)
  expect_error(
    nl_compile_trial_call(
      rejected,
      api_key = "local-test-key",
      output_path = tempdir()
    ),
    "validated PsyLingLLM experiment plan"
  )
  approval <- nl_approve_experiment(
    review,
    approved = TRUE,
    note = "Approved by the offline test harness."
  )
  compiled <- nl_compile_trial_call(
    approval,
    api_key = "local-test-key",
    output_path = tempdir()
  )
  expect_identical(compiled$function_name, "trial_experiment")
  expect_identical(compiled$arguments$model_key, "deepseek-flash")
  expect_identical(compiled$arguments$repeats, 2L)
  expect_false(compiled$arguments$random)
  expect_identical(
    compiled$arguments$optionals,
    list(
      max_tokens = 512L,
      temperature = 0L,
      thinking = list(type = "disabled")
    )
  )
  expect_identical(compiled$arguments$data$Material, prepared$data$Material)
})

test_that("simulated tool rejects unsafe or incomplete planner output", {
  invalid_output <- jsonlite::toJSON(
    list(
      status = "ready",
      document = list(
        schema_version = 1L,
        experiment_type = "trial",
        task = list(trial_prompt = "Answer Y or N."),
        rows = list(
          list(
            item = 1L,
            material = "Valid material.",
            conditions = list(Condition = "Control"),
            api_key = "must-not-be-accepted"
          ),
          list(
            item = 1L,
            material = "",
            conditions = list(Group = "Mismatch")
          )
        )
      ),
      experiment = list(
        spec_version = 1L,
        type = "trial",
        model_key = "deepseek-flash",
        generation_interface = "chat",
        system_content = "Answer only Y or N.",
        repeats = 1L,
        random = FALSE,
        stream = FALSE,
        timeout = 120L,
        parameter_policy = "explicit",
        parameters = list(
          max_tokens = 512L,
          api_key = "must-not-be-accepted"
        )
      )
    ),
    auto_unbox = TRUE
  )

  prepared <- nl_prepare_experiment(invalid_output)
  codes <- vapply(prepared$errors, `[[`, character(1), "code")

  expect_false(prepared$valid)
  expect_null(prepared$data)
  expect_null(prepared$experiment)
  expect_true(all(c(
    "forbidden_material_field",
    "invalid_material",
    "inconsistent_condition_fields",
    "duplicate_item",
    "forbidden_parameter"
  ) %in% codes))
  expect_match(
    nl_validation_feedback(prepared),
    "forbidden_parameter",
    fixed = TRUE
  )
})

test_that("review rejects silent source-material changes", {
  planner_output <- jsonlite::toJSON(
    list(
      status = "ready",
      document = list(
        schema_version = 1L,
        experiment_type = "trial",
        task = list(trial_prompt = "Answer Y or N."),
        rows = list(list(
          item = 1L,
          material = "The model changed this material.",
          conditions = list(Condition = "Control")
        ))
      ),
      experiment = list(
        spec_version = 1L,
        type = "trial",
        model_key = "deepseek-flash",
        generation_interface = "chat",
        system_content = "Answer only Y or N.",
        repeats = 1L,
        random = FALSE,
        stream = FALSE,
        timeout = 120L,
        parameter_policy = "explicit",
        parameters = list(max_tokens = 64L)
      )
    ),
    auto_unbox = TRUE
  )

  prepared <- nl_prepare_experiment(planner_output)
  expect_true(prepared$valid)
  review <- nl_review_experiment(
    prepared,
    source_materials = "The original material.",
    required_condition_names = "Condition"
  )
  codes <- vapply(review$errors, `[[`, character(1), "code")
  expect_false(review$valid)
  expect_contains(codes, "material_fidelity_failure")
})
