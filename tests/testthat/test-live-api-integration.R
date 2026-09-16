test_that("live OpenAI Responses runtime works in both transport modes", {
  live_api_require("OPENAI_API_KEY")
  live_api_use_registry()
  live_api_use_openai_proxy()
  key <- Sys.getenv("OPENAI_API_KEY")

  for (streaming in c(FALSE, TRUE)) {
    result <- llm_caller(
      model_key = "live_openai",
      generation_interface = "responses",
      material = "Reply with OK only.",
      api_key = key,
      optionals = list(max_output_tokens = 64L),
      stream = streaming,
      timeout = 90,
      return_raw = TRUE
    )
    expect_live_success(result, key, streaming)
  }
})

test_that("live DeepSeek Chat runtime works in both transport modes", {
  live_api_require("DEEPSEEK_API_KEY")
  live_api_use_registry()
  key <- Sys.getenv("DEEPSEEK_API_KEY")

  for (streaming in c(FALSE, TRUE)) {
    result <- llm_caller(
      model_key = "live_deepseek",
      material = "Reply with OK only.",
      api_key = key,
      optionals = list(max_tokens = 128L),
      stream = streaming,
      timeout = 90,
      return_raw = TRUE
    )
    expect_live_success(result, key, streaming)
  }
})

test_that("live Qwen supports OpenAI and Anthropic protocol adapters", {
  live_api_require(c(
    "QWEN_API_KEY", "QWEN_OPENAI_BASE_URL", "QWEN_ANTHROPIC_BASE_URL"
  ))
  live_api_use_registry()
  key <- Sys.getenv("QWEN_API_KEY")

  openai_result <- llm_caller(
    model_key = "live_qwen_openai",
    material = "Reply with OK only.",
    api_key = key,
    stream = FALSE,
    timeout = 90,
    return_raw = TRUE,
    max_tokens = 32L,
    enable_thinking = FALSE
  )
  expect_live_success(openai_result, key, FALSE)

  anthropic_result <- llm_caller(
    model_key = "live_qwen_anthropic",
    material = "Reply with OK only.",
    api_key = key,
    optionals = list(
      max_tokens = 32L,
      thinking = list(type = "disabled")
    ),
    stream = TRUE,
    timeout = 90,
    return_raw = TRUE
  )
  expect_live_success(anthropic_result, key, TRUE)
})

test_that("live provider errors retain evidence behind status 599", {
  live_api_require(c("QWEN_API_KEY", "QWEN_OPENAI_BASE_URL"))
  live_api_use_registry()
  key <- Sys.getenv("QWEN_API_KEY")

  result <- suppressWarnings(llm_caller(
    model_key = "live_qwen_openai",
    material = "Reply with OK only.",
    api_key = key,
    optionals = list(max_tokens = "invalid"),
    stream = FALSE,
    timeout = 90,
    return_raw = TRUE
  ))

  expect_identical(result$status, 599L)
  expect_true(is.list(result$error))
  expect_true(result$error$code >= 400L && result$error$code < 600L)
  expect_true(is.character(result$error$message) && nzchar(result$error$message))
  expect_false(is.null(result$error$body))
  expect_false(is.null(result$error$headers))
  serialized <- jsonlite::toJSON(result, auto_unbox = TRUE, null = "null")
  expect_false(grepl(key, serialized, fixed = TRUE))
})

test_that("live APIs execute trial and conversation experiment data", {
  live_api_require(c(
    "QWEN_API_KEY", "QWEN_OPENAI_BASE_URL", "QWEN_ANTHROPIC_BASE_URL"
  ))
  live_api_use_registry()
  key <- Sys.getenv("QWEN_API_KEY")
  output_directory <- withr::local_tempdir()

  invisible(capture.output(
    trial_result <- trial_experiment(
      model_key = "live_qwen_anthropic",
      api_key = key,
      data = data.frame(
        Item = 1L,
        Condition = "smoke",
        TrialPrompt = "Reply with one word only:",
        Material = "OK",
        stringsAsFactors = FALSE
      ),
      optionals = list(
        max_tokens = 16L,
        thinking = list(type = "disabled")
      ),
      stream = FALSE,
      random = FALSE,
      delay = 0,
      output_path = output_directory
    )
  ))

  expect_identical(nrow(trial_result), 1L)
  expect_identical(trial_result$TrialStatus, "SUCCESS")
  expect_true(nzchar(trial_result$Response[[1L]]))
  expect_identical(trial_result$Item, 1L)
  expect_identical(trial_result$Condition, "smoke")

  invisible(capture.output(
    conversation_result <- conversation_experiment(
      model_key = "live_qwen_openai",
      api_key = key,
      data = data.frame(
        ConversationId = c("C1", "C1"),
        Turn = c(1L, 2L),
        Material = c("Reply with ONE.", "Reply with TWO."),
        stringsAsFactors = FALSE
      ),
      optionals = list(max_tokens = 16L, enable_thinking = FALSE),
      history_mode = "all",
      stream = FALSE,
      random = FALSE,
      delay = 0,
      output_path = output_directory
    )
  ))

  expect_identical(nrow(conversation_result), 2L)
  expect_identical(
    conversation_result$TrialStatus,
    c("SUCCESS", "SUCCESS")
  )
  expect_true(all(nzchar(conversation_result$Response)))
  expect_identical(conversation_result$HistoryUsedMsgs, c(0L, 2L))
})
