make_experiment_success <- function(answer, request_id, streaming = FALSE) {
  list(
    status = 200L,
    answer = answer,
    thinking = NULL,
    first_token_latency = if (streaming) 0.05 else NA_real_,
    usage = list(prompt = 4L, completion = 1L, id = request_id),
    streaming = streaming,
    error = NULL
  )
}

mock_experiment_side_effects <- function(output_directory) {
  local_mocked_bindings(
    validate_experiment_config = function(...) TRUE,
    get_registry_entry = function(...) {
      list(input = list(role_mapping = list(
        system = "system",
        user = "user",
        assistant = "assistant"
      )))
    },
    resolve_output_and_log = function(output_path, model) {
      list(
        result_file = file.path(output_directory, paste0(model, ".csv")),
        log_file = file.path(output_directory, paste0(model, ".log"))
      )
    },
    write_experiment_log = function(...) invisible(TRUE),
    update_progress_bar = function(...) invisible(TRUE),
    save_experiment_results = function(...) invisible(TRUE),
    .package = "PsyLingLLM",
    .env = parent.frame()
  )
}

test_that("conversation experiments preserve ordered data and history", {
  output_directory <- withr::local_tempdir()
  mock_experiment_side_effects(output_directory)
  calls <- list()

  local_mocked_bindings(
    llm_caller = function(material, assistant_content, ...) {
      calls[[length(calls) + 1L]] <<- list(
        material = material,
        assistant_content = assistant_content
      )
      make_experiment_success(
        paste0("answer-", length(calls)),
        paste0("request-", length(calls))
      )
    },
    .package = "PsyLingLLM"
  )

  result <- conversation_experiment(
    model_key = "fixture-model",
    api_key = "not-a-real-key",
    data = data.frame(
      ConversationId = c("C1", "C1"),
      Turn = c(2L, 1L),
      Material = c("Second material", "First material"),
      stringsAsFactors = FALSE
    ),
    trial_prompt = "Prompt",
    random = FALSE,
    delay = 0,
    output_path = output_directory
  )

  expect_identical(result$Turn, c(1L, 2L))
  expect_identical(result$Response, c("answer-1", "answer-2"))
  expect_identical(result$TrialStatus, c("SUCCESS", "SUCCESS"))
  expect_identical(result$HistoryUsedMsgs, c(0L, 2L))
  expect_identical(result$RequestID, c("request-1", "request-2"))
  expect_length(calls[[1L]]$assistant_content, 0L)
  expect_length(calls[[2L]]$assistant_content, 2L)
  expect_match(calls[[1L]]$material, "First material", fixed = TRUE)
  expect_match(calls[[2L]]$material, "Second material", fixed = TRUE)
})

test_that("factorial experiments preserve generated conditions and stimuli", {
  output_directory <- withr::local_tempdir()
  mock_experiment_side_effects(output_directory)

  local_mocked_bindings(
    llm_caller = function(material, ...) {
      make_experiment_success(material, paste0("request-", material))
    },
    .package = "PsyLingLLM"
  )

  result <- factorial_trial_experiment(
    model_key = "fixture-model",
    api_key = "not-a-real-key",
    data = data.frame(
      Material = "Condition is {LEVEL}.",
      stringsAsFactors = FALSE
    ),
    factors = list(Level = c("A", "B")),
    fill_method = function(condition, material, word) {
      sub("{LEVEL}", condition$Level, material, fixed = TRUE)
    },
    random = FALSE,
    delay = 0,
    output_path = output_directory
  )

  expect_identical(result$Level, c("A", "B"))
  expect_identical(
    result$Stimulus,
    c("Condition is A.", "Condition is B.")
  )
  expect_identical(result$Response, result$Stimulus)
  expect_identical(
    result$ConditionLabel,
    c("Level=A", "Level=B")
  )
  expect_identical(result$TrialStatus, c("SUCCESS", "SUCCESS"))
  expect_true(all(!is.na(result$RequestID)))
})
