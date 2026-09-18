test_that("bundled OpenAI Responses works in both transport modes", {
  live_api_require("OPENAI_API_KEY")
  live_api_use_system_registry()
  live_api_use_openai_proxy()
  key <- Sys.getenv("OPENAI_API_KEY")

  for (streaming in c(FALSE, TRUE)) {
    result <- llm_caller(
      model_key = "gpt-5.6-luna",
      material = "Reply with OK only.",
      api_key = key,
      optionals = list(
        max_output_tokens = 64L,
        reasoning = list(effort = "low")
      ),
      stream = streaming,
      timeout = 120,
      return_raw = TRUE
    )
    expect_live_success(result, key, streaming)
  }
})

test_that("bundled DeepSeek Chat works in both transport modes", {
  live_api_require("DEEPSEEK_API_KEY")
  live_api_use_system_registry()
  key <- Sys.getenv("DEEPSEEK_API_KEY")

  for (streaming in c(FALSE, TRUE)) {
    result <- llm_caller(
      model_key = "deepseek-flash",
      material = "Reply with OK only.",
      api_key = key,
      optionals = list(
        max_tokens = 512L,
        thinking = list(type = "disabled")
      ),
      stream = streaming,
      timeout = 120,
      return_raw = TRUE
    )
    expect_live_success(result, key, streaming)
  }
})

test_that("bundled DeepSeek Responses works in both transport modes", {
  live_api_require("DEEPSEEK_API_KEY")
  live_api_use_system_registry()
  key <- Sys.getenv("DEEPSEEK_API_KEY")

  for (streaming in c(FALSE, TRUE)) {
    result <- llm_caller(
      model_key = "deepseek-flash",
      generation_interface = "deepseek-responses-v1",
      material = "Reply with OK only.",
      api_key = key,
      optionals = list(
        max_output_tokens = 256L,
        reasoning = list(effort = "none")
      ),
      stream = streaming,
      timeout = 120,
      return_raw = TRUE
    )
    expect_live_success(result, key, streaming)
  }
})

test_that("bundled Qwen Chat works in both transport modes", {
  live_api_require(c("QWEN_API_KEY", "QWEN_OPENAI_BASE_URL"))
  live_api_use_system_registry()
  key <- Sys.getenv("QWEN_API_KEY")
  api_url <- live_api_endpoint(
    Sys.getenv("QWEN_OPENAI_BASE_URL"),
    "chat/completions"
  )

  for (streaming in c(FALSE, TRUE)) {
    result <- llm_caller(
      model_key = "qwen3.8-flash",
      generation_interface = "qwen-chat-completions-v1",
      material = "Reply with OK only.",
      api_key = key,
      api_url = api_url,
      optionals = list(max_tokens = 32L, enable_thinking = FALSE),
      stream = streaming,
      timeout = 120,
      return_raw = TRUE
    )
    expect_live_success(result, key, streaming)
  }
})

test_that("bundled Qwen Responses works in both transport modes", {
  live_api_require(c("QWEN_API_KEY", "QWEN_OPENAI_BASE_URL"))
  live_api_use_system_registry()
  key <- Sys.getenv("QWEN_API_KEY")
  api_url <- live_api_endpoint(
    Sys.getenv("QWEN_OPENAI_BASE_URL"),
    "responses"
  )

  for (streaming in c(FALSE, TRUE)) {
    result <- llm_caller(
      model_key = "qwen3.8-flash",
      generation_interface = "qwen-responses-v1",
      material = "Reply with OK only.",
      api_key = key,
      api_url = api_url,
      optionals = list(max_output_tokens = 64L),
      stream = streaming,
      timeout = 120,
      return_raw = TRUE
    )
    expect_live_success(result, key, streaming)
  }
})

test_that("bundled Qwen registry executes experiment data", {
  live_api_require(c("QWEN_API_KEY", "QWEN_OPENAI_BASE_URL"))
  live_api_use_system_registry()
  key <- Sys.getenv("QWEN_API_KEY")
  api_url <- live_api_endpoint(
    Sys.getenv("QWEN_OPENAI_BASE_URL"),
    "chat/completions"
  )
  output_directory <- withr::local_tempdir()

  invisible(capture.output(
    result <- trial_experiment(
      model_key = "qwen3.8-flash",
      generation_interface = "qwen-chat-completions-v1",
      api_key = key,
      api_url = api_url,
      data = data.frame(
        Item = 1L,
        Condition = "production-registry-smoke",
        TrialPrompt = "Reply with one word only:",
        Material = "OK",
        stringsAsFactors = FALSE
      ),
      optionals = list(max_tokens = 32L, enable_thinking = FALSE),
      stream = FALSE,
      random = FALSE,
      delay = 0,
      output_path = output_directory
    )
  ))

  expect_identical(nrow(result), 1L)
  expect_identical(result$TrialStatus, "SUCCESS")
  expect_true(nzchar(result$Response[[1L]]))
  expect_identical(result$Item, 1L)
  expect_identical(result$Condition, "production-registry-smoke")
})
