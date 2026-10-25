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

      if (call_index == 4L) return(list(
        status = 599L,
        answer = "",
        thinking = NULL,
        response_status = "PARSE_ERROR",
        first_token_latency = NA_real_,
        usage = list(prompt = NULL, completion = NULL, id = NULL),
        streaming = FALSE,
        error = list(
          code = 599L,
          message = "Provider response could not be parsed as JSON",
          type = "parser_error",
          reason = "invalid_json",
          http_status = 200L
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
    data = data.frame(
      Material = c("First", "Second", "Third", "Fourth", "Fifth")
    ),
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
    c("SUCCESS", "TIMEOUT", "ERROR", "ERROR", "SUCCESS")
  )
  expect_identical(
    result$ResponseStatus,
    c("OK", "TIMEOUT", "ERROR", "PARSE_ERROR", "EMPTY_RESPONSE")
  )
  expect_identical(result$Response[[1]], "Fixture answer")
  expect_true(is.na(result$Response[[2]]))
  expect_true(is.na(result$Response[[3]]))
  expect_true(is.na(result$Response[[4]]))
  expect_identical(result$Response[[5]], "  ")
  expect_identical(result$Think[[1]], "Fixture reasoning")
  expect_true(is.na(result$Think[[2]]))
  expect_true(is.na(result$Think[[3]]))
  expect_true(is.na(result$Think[[4]]))
  expect_identical(result$PromptTokens[[1]], 8L)
  expect_identical(result$CompletionTokens[[1]], 3L)
  expect_identical(result$RequestID[[1]], "request-success")
  expect_true(is.na(result$RequestID[[2]]))
  expect_true(is.na(result$RequestID[[3]]))
  expect_identical(result$Streaming, rep(FALSE, 5L))
  expect_false("raw" %in% names(result))
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
  parser <- classify_llm_result(list(
    status = 599L,
    response_status = "PARSE_ERROR",
    error = list(
      code = 599L,
      message = "Invalid JSON",
      type = "parser_error",
      reason = "invalid_json",
      http_status = 200L
    )
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
  expect_identical(parser$category, "ERROR")
  expect_identical(parser$response_status, "PARSE_ERROR")
  expect_identical(parser$provider_status, 200L)
})

test_that("trial experiments preserve ordered raw evidence outside flat result files", {
  call_index <- 0L
  output_directory <- withr::local_tempdir(
    pattern = "trial-raw-",
    tmpdir = getwd()
  )
  result_file <- file.path(output_directory, "results.csv")
  raw_result_file <- file.path(output_directory, "results-with-raw.rds")
  api_key <- "must-not-be-persisted"

  local_mocked_bindings(
    load_registry = function() list(),
    validate_experiment_config = function(...) TRUE,
    resolve_output_and_log = function(output_path, model) {
      list(
        result_file = result_file,
        log_file = file.path(output_directory, "results.log")
      )
    },
    write_experiment_log = function(...) invisible(TRUE),
    update_progress_bar = function(...) invisible(TRUE),
    llm_caller = function(...) {
      arguments <- list(...)
      expect_true(arguments$return_raw)
      call_index <<- call_index + 1L
      request_id <- paste0("request-", call_index)
      provider_body <- list(
        id = request_id,
        usage = list(
          prompt_tokens = 8L,
          completion_tokens = 3L,
          completion_tokens_details = list(reasoning_tokens = call_index)
        ),
        choices = list(list(
          logprobs = list(content = list(list(
            token = if (call_index %% 2L == 0L) "N" else "Y",
            logprob = -0.1 * call_index,
            top_logprobs = list(
              list(token = "Y", logprob = -0.2),
              list(token = "N", logprob = -1.2)
            )
          )))
        ))
      )
      raw <- list(
        request = list(
          url = "https://example.invalid/v1/chat/completions",
          headers = list(Authorization = "[REDACTED]"),
          body = list(material = arguments$material)
        ),
        response = list(non_stream = list(parsed = provider_body))
      )

      if (call_index == 3L) {
        raw$response$non_stream$parsed$error <- list(message = "Rate limited")
        return(list(
          status = 599L,
          answer = "",
          thinking = NULL,
          first_token_latency = NA_real_,
          usage = list(prompt = NULL, completion = NULL, id = NULL),
          streaming = FALSE,
          raw = raw,
          error = list(code = 429L, message = "Rate limited")
        ))
      }

      list(
        status = 200L,
        answer = if (call_index %% 2L == 0L) "N" else "Y",
        thinking = paste("Fixture reasoning", call_index),
        first_token_latency = NA_real_,
        usage = list(
          prompt = 8L,
          completion = 3L,
          id = if (call_index == 4L) NULL else request_id
        ),
        streaming = FALSE,
        raw = raw,
        error = NULL
      )
    },
    .package = "PsyLingLLM"
  )

  result <- suppressMessages(
    trial_experiment(
      model_key = "fixture-model",
      api_key = api_key,
      data = data.frame(Material = c("First", "Second")),
      repeats = 2L,
      random = FALSE,
      output_path = result_file,
      delay = 0,
      return_raw = TRUE,
      raw_output_path = raw_result_file
    )
  )

  expect_true("raw" %in% names(result))
  expect_length(result$raw, nrow(result))
  expect_identical(nrow(result), 4L)
  expect_identical(result$Material, c("First", "Second", "First", "Second"))
  expect_identical(
    vapply(result$raw, function(x) x$request$body$material, character(1)),
    result$Material
  )
  expect_identical(
    vapply(result$raw, function(x) x$response$non_stream$parsed$id, character(1)),
    paste0("request-", seq_len(4L))
  )
  expect_identical(result$TrialStatus, c("SUCCESS", "SUCCESS", "ERROR", "SUCCESS"))
  expect_true(is.na(result$RequestID[[4L]]))
  expect_identical(
    result$raw[[3]]$response$non_stream$parsed$error$message,
    "Rate limited"
  )
  expect_identical(
    result$raw[[1]]$response$non_stream$parsed$usage$
      completion_tokens_details$reasoning_tokens,
    1L
  )
  expect_length(
    result$raw[[1]]$response$non_stream$parsed$choices[[1]]$logprobs$
      content[[1]]$top_logprobs,
    2L
  )

  expect_true(file.exists(result_file))
  csv_result <- readr::read_csv(result_file, show_col_types = FALSE)
  expect_false("raw" %in% names(csv_result))
  expect_equal(csv_result$Run, result$Run)
  expect_equal(csv_result$Item, result$Item)
  expect_identical(csv_result$Material, result$Material)
  expect_identical(csv_result$TrialStatus, result$TrialStatus)

  expect_true(file.exists(raw_result_file))
  restored <- readRDS(raw_result_file)
  expect_identical(nrow(restored), nrow(result))
  expect_identical(restored$raw, result$raw)
  expect_length(restored$raw, 4L)

  rendered_raw <- paste(capture.output(str(restored$raw)), collapse = "\n")
  expect_false(grepl(api_key, rendered_raw, fixed = TRUE))
  expect_false(grepl("Bearer ", rendered_raw, fixed = TRUE))
  expect_true(grepl("[REDACTED]", rendered_raw, fixed = TRUE))
})

test_that("RAW archive conflicts fail before the first provider call", {
  output_directory <- withr::local_tempdir(
    pattern = "trial-raw-preflight-",
    tmpdir = getwd()
  )
  raw_result_file <- file.path(output_directory, "existing.rds")
  saveRDS(list(existing = TRUE), raw_result_file)
  calls <- 0L

  local_mocked_bindings(
    llm_caller = function(...) {
      calls <<- calls + 1L
      stop("Provider call must not run")
    },
    .package = "PsyLingLLM"
  )

  expect_error(
    trial_experiment(
      model_key = "fixture-model",
      api_key = "not-a-real-key",
      data = data.frame(Material = "Fixture"),
      output_path = file.path(output_directory, "results.csv"),
      overwrite = FALSE,
      return_raw = TRUE,
      raw_output_path = raw_result_file
    ),
    "already exists"
  )
  expect_identical(calls, 0L)
})

test_that("trial_experiment appends only the reviewed RAW archive argument", {
  expect_identical(
    names(formals(trial_experiment)),
    c(
      "model_key",
      "generation_interface",
      "api_key",
      "api_url",
      "data",
      "trial_prompt",
      "system_content",
      "assistant_content",
      "optionals",
      "role_mapping",
      "stream",
      "timeout",
      "repeats",
      "random",
      "delay",
      "output_path",
      "overwrite",
      "return_raw",
      "raw_output_path"
    )
  )
})
