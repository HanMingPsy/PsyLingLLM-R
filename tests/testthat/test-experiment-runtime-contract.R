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

      if (call_index == 2L) {
        return(list(
          status = 599L,
          answer = "",
          thinking = NULL,
          first_token_latency = NA_real_,
          usage = list(prompt = NULL, completion = NULL, id = NULL),
          streaming = FALSE,
          error = list(code = 599L, message = "Fixture timeout")
        ))
      }

      if (call_index == 3L) return(list(
        status = 599L,
        answer = "",
        thinking = NULL,
        first_token_latency = NA_real_,
        usage = list(prompt = NULL, completion = NULL, id = NULL),
        streaming = FALSE,
        error = list(
          code = 429L,
          message = "Rate limited",
          type = "rate_limit_error",
          param = NULL,
          provider_code = "rate_limit",
          body = list(error = list(message = "Rate limited")),
          headers = c(`x-request-id` = "request-rate-limit"),
          request_id = "request-rate-limit"
        )
      ))

      list(
        status = 200L,
        answer = "  ",
        thinking = "Reasoning without a final answer",
        first_token_latency = NA_real_,
        usage = list(prompt = 5L, completion = 8L, id = "request-empty"),
        streaming = FALSE,
        error = NULL
      )
    },
    .package = "PsyLingLLM"
  )

  result <- trial_experiment(
    model_key = "fixture-model",
    api_key = "not-a-real-key",
    data = data.frame(Material = c("First", "Second", "Third", "Fourth")),
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
    "ResponseStatus",
    "Streaming",
    "Timestamp",
    "RequestID"
  )

  expect_true(all(expected_result_fields %in% names(result)))
  expect_identical(
    result$TrialStatus,
    c("SUCCESS", "TIMEOUT", "ERROR", "SUCCESS")
  )
  expect_identical(
    result$ResponseStatus,
    c("OK", "TIMEOUT", "ERROR", "EMPTY_RESPONSE")
  )
  expect_identical(result$Response[[1]], "Fixture answer")
  expect_true(is.na(result$Response[[2]]))
  expect_true(is.na(result$Response[[3]]))
  expect_identical(result$Response[[4]], "  ")
  expect_identical(result$Think[[1]], "Fixture reasoning")
  expect_true(is.na(result$Think[[2]]))
  expect_true(is.na(result$Think[[3]]))
  expect_identical(result$PromptTokens[[1]], 8L)
  expect_identical(result$CompletionTokens[[1]], 3L)
  expect_identical(result$RequestID[[1]], "request-success")
  expect_true(is.na(result$RequestID[[2]]))
  expect_true(is.na(result$RequestID[[3]]))
  expect_identical(result$Streaming, c(FALSE, FALSE, FALSE, FALSE))
})

test_that("normalized failures distinguish timeouts from provider errors", {
  timeout <- classify_llm_result(list(
    status = 599L,
    error = list(code = 599L, message = "Timed out")
  ))
  provider <- classify_llm_result(list(
    status = 599L,
    error = list(code = 401L, message = "Invalid key")
  ))
  legacy_http <- classify_llm_result(list(
    status = 500L,
    error = list(code = 500L, message = "Server error")
  ))

  expect_identical(timeout$category, "TIMEOUT")
  expect_identical(timeout$provider_status, 599L)
  expect_identical(provider$category, "ERROR")
  expect_identical(provider$provider_status, 401L)
  expect_identical(provider$message, "Invalid key")
  expect_identical(legacy_http$category, "ERROR")
  expect_identical(legacy_http$provider_status, 500L)
  expect_identical(timeout$response_status, "TIMEOUT")
  expect_identical(provider$response_status, "ERROR")
})
