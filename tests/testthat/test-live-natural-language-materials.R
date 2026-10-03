test_that("live two-turn planner drives the complete toolbox experiment path", {
  live_api_require("DEEPSEEK_API_KEY")
  live_api_use_system_registry()
  key <- Sys.getenv("DEEPSEEK_API_KEY")
  system_prompt <- nl_psylingllm_toolbox_prompt()
  source_materials <- c(
    "The teacher praised the student.",
    "The child opened the window.",
    "The sandwich frightened the doctor."
  )
  onboarding <- paste(
    "Read and understand the complete PsyLingLLM toolbox contract and schemas.",
    "Return the required onboarding acknowledgement JSON only."
  )

  acknowledgement <- nl_allow_json_mode_advisory(llm_caller(
    model_key = "deepseek-flash",
    generation_interface = "chat",
    system_content = system_prompt,
    material = onboarding,
    api_key = key,
    optionals = list(
      max_tokens = 512L,
      temperature = 0,
      thinking = list(type = "disabled"),
      response_format = list(type = "json_object")
    ),
    stream = FALSE,
    timeout = 90
  ))
  expect_identical(acknowledgement$status, 200L)
  expect_identical(acknowledgement$response_status, "OK")
  acknowledgement_json <- nl_extract_json_object(acknowledgement$answer)
  acknowledgement_validation <- nl_validate_toolbox_acknowledgement(
    acknowledgement_json
  )
  expect_true(
    acknowledgement_validation$valid,
    info = "The live planner did not acknowledge the full toolbox contract."
  )

  material_request <- paste(
    "Prepare a validated ordinary-trial plan from these exact materials and requirements.",
    "Do not rewrite any sentence.",
    "Use exactly one condition field named Condition.",
    "Items 1 and 2 are Control; item 3 is Anomalous.",
    "Trial prompt: Is this sentence natural? Answer only Y or N.",
    "Model key: deepseek-flash. Generation interface: chat.",
    "System content: You are a participant in a psychology experiment. Answer using",
    "only Y or N, with no explanation or punctuation.",
    "Use one repeat, no randomization, non-streaming, and a 120 second timeout.",
    "Use explicit provider parameters max_tokens=512, temperature=0, and",
    "thinking={type: disabled}.",
    "1. The teacher praised the student.",
    "2. The child opened the window.",
    "3. The sandwich frightened the doctor.",
    "Return the required compile JSON only.",
    sep = "\n"
  )
  planner_result <- nl_allow_json_mode_advisory(llm_caller(
    model_key = "deepseek-flash",
    generation_interface = "chat",
    system_content = system_prompt,
    assistant_content = list(
      list(role = "user", content = onboarding),
      list(role = "assistant", content = acknowledgement$answer)
    ),
    material = material_request,
    api_key = key,
    optionals = list(
      max_tokens = 2048L,
      temperature = 0,
      thinking = list(type = "disabled"),
      response_format = list(type = "json_object")
    ),
    stream = FALSE,
    timeout = 120
  ))
  expect_identical(planner_result$status, 200L)
  expect_identical(planner_result$response_status, "OK")

  prepared <- nl_try_prepare_experiment(planner_result$answer)
  planner_request_ids <- c(
    acknowledgement$usage$id %||% "",
    planner_result$usage$id %||% ""
  )
  if (!prepared$valid) {
    correction <- nl_validation_feedback(prepared)
    repaired_result <- nl_allow_json_mode_advisory(llm_caller(
      model_key = "deepseek-flash",
      generation_interface = "chat",
      system_content = system_prompt,
      assistant_content = list(
        list(role = "user", content = onboarding),
        list(role = "assistant", content = acknowledgement$answer),
        list(role = "user", content = material_request),
        list(role = "assistant", content = planner_result$answer %||% "{}")
      ),
      material = correction,
      api_key = key,
      optionals = list(
        max_tokens = 2048L,
        temperature = 0,
        thinking = list(type = "disabled"),
        response_format = list(type = "json_object")
      ),
      stream = FALSE,
      timeout = 120
    ))
    expect_identical(repaired_result$status, 200L)
    expect_identical(repaired_result$response_status, "OK")
    prepared <- nl_try_prepare_experiment(repaired_result$answer)
    planner_request_ids <- c(
      planner_request_ids,
      repaired_result$usage$id %||% ""
    )
  }
  expect_true(prepared$valid, info = paste(
    vapply(prepared$errors, `[[`, character(1), "message"),
    collapse = "; "
  ))
  expect_identical(nrow(prepared$data), 3L)
  expect_identical(
    prepared$data$Material,
    source_materials
  )
  expect_identical(
    prepared$data$Condition,
    c("Control", "Control", "Anomalous")
  )
  expect_identical(prepared$experiment$model_key, "deepseek-flash")
  expect_identical(prepared$experiment$generation_interface, "chat")
  expect_identical(prepared$experiment$parameter_policy, "explicit")

  review <- nl_review_experiment(
    prepared,
    source_materials = source_materials,
    required_condition_names = "Condition"
  )
  expect_true(review$valid, info = paste(
    vapply(review$errors, `[[`, character(1), "message"),
    collapse = "; "
  ))
  expect_identical(review$preview$projected_runs, 3L)
  approval <- nl_approve_experiment(
    review,
    approved = TRUE,
    note = "Explicit approval by the opt-in live test harness."
  )

  output_directory <- withr::local_tempdir()
  compiled <- nl_compile_trial_call(
    approval,
    api_key = key,
    output_path = output_directory
  )
  expect_identical(compiled$function_name, "trial_experiment")
  expect_identical(compiled$arguments$model_key, prepared$experiment$model_key)
  expect_identical(
    compiled$arguments$optionals,
    prepared$experiment$parameters
  )

  invisible(capture.output(
    experiment_result <- do.call(trial_experiment, compiled$arguments)
  ))

  expect_identical(nrow(experiment_result), 3L)
  expect_identical(experiment_result$Material, prepared$data$Material)
  expect_identical(experiment_result$Condition, prepared$data$Condition)
  expect_true(all(experiment_result$TrialStatus == "SUCCESS"))
  expect_true(all(experiment_result$ResponseStatus == "OK"))
  expect_true(all(grepl("^[YN]$", trimws(experiment_result$Response))))
  expect_true(all(experiment_result$ModelName == prepared$experiment$model_key))
  expect_true(all(!is.na(experiment_result$TotalResponseTime)))
  result_validation <- nl_validate_execution_result(
    approval,
    experiment_result,
    api_key = key
  )
  expect_true(result_validation$valid, info = paste(
    vapply(result_validation$errors, `[[`, character(1), "message"),
    collapse = "; "
  ))

  receipt <- nl_execution_receipt(
    approval,
    experiment_result,
    planner_request_ids = planner_request_ids
  )
  expect_identical(receipt$planned_runs, 3L)
  expect_identical(receipt$completed_runs, 3L)
  expect_true(length(receipt$planner_request_ids) >= 2L)
  expect_true(length(receipt$experiment_request_ids) == 3L)
  expect_false(grepl(
    key,
    jsonlite::toJSON(receipt, auto_unbox = TRUE, null = "null"),
    fixed = TRUE
  ))
})
