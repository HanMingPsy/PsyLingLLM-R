test_that("trial experiments preserve success and timeout result fields", {
  call_index <- 0L
  output_directory <- withr::local_tempdir()

  local_mocked_bindings(
    load_registry = function() list(),
    validate_experiment_config = function(...) TRUE,
    resolve_output_and_log = function(output_path, model) {
      list(
        result_file = file.path(output_directory, "results.csv"),
        log_file = file.path(output_directory, "results.log")
      )
    },
    write_experiment_log = function(...) invisible(TRUE),
    update_progress_bar = function(...) invisible(TRUE),
    save_experiment_results = function(...) invisible(TRUE),
    llm_caller = function(...) {
      call_index <<- call_index + 1L
      if (call_index == 1L) {
        return(list(
          status = 200L,
          answer = "Fixture answer",
          thinking = "Fixture reasoning",
          first_token_latency = NA_real_,
          usage = list(
            prompt = 8L,
            completion = 3L,
            id = "request-success"
          ),
          streaming = FALSE,
          error = NULL
        ))
      }

      list(
        status = 599L,
        answer = "",
        thinking = NULL,
        first_token_latency = NA_real_,
        usage = list(prompt = NULL, completion = NULL, id = NULL),
        streaming = FALSE,
        error = list(code = 599L, message = "Fixture timeout")
      )
    },
    .package = "PsyLingLLM"
  )

  result <- trial_experiment(
    model_key = "fixture-model",
    api_key = "not-a-real-key",
    data = data.frame(Material = c("First", "Second")),
    output_path = output_directory,
    delay = 0
  )

  expected_result_fields <- c(
    "Response",
    "Think",
    "ModelName",
    "TotalResponseTime",
    "FirstTokenLatency",
    "PromptTokens",
    "CompletionTokens",
    "TrialStatus",
    "Streaming",
    "Timestamp",
    "RequestID"
  )

  expect_true(all(expected_result_fields %in% names(result)))
  expect_identical(result$TrialStatus, c("SUCCESS", "TIMEOUT"))
  expect_identical(result$Response[[1]], "Fixture answer")
  expect_true(is.na(result$Response[[2]]))
  expect_identical(result$Think[[1]], "Fixture reasoning")
  expect_true(is.na(result$Think[[2]]))
  expect_identical(result$PromptTokens[[1]], 8L)
  expect_identical(result$CompletionTokens[[1]], 3L)
  expect_identical(result$RequestID[[1]], "request-success")
  expect_true(is.na(result$RequestID[[2]]))
  expect_identical(result$Streaming, c(FALSE, FALSE))
})
