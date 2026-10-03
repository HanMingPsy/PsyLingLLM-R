test_that("live production planner drives the reviewed trial path", {
  live_api_require("DEEPSEEK_API_KEY")
  live_api_use_system_registry()
  key <- Sys.getenv("DEEPSEEK_API_KEY")
  source_materials <- c(
    "The teacher praised the student.",
    "The sandwich frightened the doctor."
  )
  requirements <- paste(
    "Create an ordinary trial experiment.",
    "Use exactly one condition field named Condition.",
    "The first item is Control and the second item is Anomalous.",
    "Use this global trial prompt: Is this sentence natural? Answer only Y or N.",
    "Use model_key deepseek-flash and generation_interface chat.",
    "Use this system_content: You are a participant in a psychology experiment.",
    "Answer using only Y or N, with no explanation or punctuation.",
    "Use one repeat, no randomization, non-streaming, and timeout 120.",
    "Use parameter_policy explicit with provider parameters max_tokens=64,",
    "temperature=0, and thinking={type: disabled}.",
    sep = "\n"
  )

  session <- run_experiment_planner(
    model_key = "deepseek-flash",
    generation_interface = "chat",
    requirements = requirements,
    source_materials = source_materials,
    api_key = key,
    parameters = list(
      max_tokens = 2048L,
      temperature = 0,
      thinking = list(type = "disabled")
    ),
    timeout = 120L,
    required_condition_names = "Condition"
  )
  expect_true(session$valid, info = paste(
    vapply(session$errors, `[[`, character(1), "message"),
    collapse = "; "
  ))
  expect_identical(session$stage, "review")
  expect_identical(session$plan$data$Material, source_materials)
  expect_identical(
    session$plan$data$Condition,
    c("Control", "Anomalous")
  )

  approval <- approve_experiment_plan(
    session$review,
    approved = TRUE,
    note = "Explicit approval by the opt-in live test harness."
  )
  compiled <- compile_experiment_plan(approval)
  expect_identical(compiled$function_name, "trial_experiment")
  expect_identical(compiled$arguments$data$Material, source_materials)

  output_directory <- withr::local_tempdir()
  runtime_arguments <- c(
    compiled$arguments,
    list(api_key = key, output_path = output_directory)
  )
  invisible(capture.output(
    experiment_result <- do.call(trial_experiment, runtime_arguments)
  ))

  validation <- validate_experiment_result(compiled, experiment_result)
  expect_true(validation$valid, info = paste(
    vapply(validation$errors, `[[`, character(1), "message"),
    collapse = "; "
  ))
  expect_identical(experiment_result$Material, source_materials)
  expect_identical(
    experiment_result$Condition,
    c("Control", "Anomalous")
  )
  expect_true(all(experiment_result$TrialStatus == "SUCCESS"))
  expect_true(all(experiment_result$ResponseStatus == "OK"))
  expect_true(all(grepl("^[YN]$", trimws(experiment_result$Response))))

  receipt <- create_experiment_receipt(
    compiled,
    experiment_result,
    planner_request_ids = session$request_ids
  )
  expect_identical(receipt$planned_runs, 2L)
  expect_identical(receipt$completed_runs, 2L)
  expect_true(length(receipt$planner_request_ids) >= 2L)
  serialized <- jsonlite::toJSON(receipt, auto_unbox = TRUE, null = "null")
  expect_false(grepl(key, serialized, fixed = TRUE))
})
