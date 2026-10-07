test_that("live DeepSeek executes ordinary conversation history", {
  live_api_require("DEEPSEEK_API_KEY")
  live_api_use_system_registry()
  key <- Sys.getenv("DEEPSEEK_API_KEY")
  output_directory <- withr::local_tempdir()

  invisible(capture.output(
    result <- conversation_experiment(
      model_key = "deepseek-flash",
      api_key = key,
      data = data.frame(
        ConversationId = c("C1", "C1"),
        Turn = c(1L, 2L),
        Material = c(
          "Remember the codeword ORCHID. Reply exactly: STORED",
          "What codeword did I ask you to remember? Reply with it only."
        ),
        stringsAsFactors = FALSE
      ),
      system_content = paste(
        "You are participating in a deterministic API integration test.",
        "Follow each response-format instruction exactly."
      ),
      optionals = list(max_tokens = 64L),
      history_mode = "all",
      stream = FALSE,
      random = FALSE,
      delay = 0,
      output_path = output_directory
    )
  ))

  expect_identical(result$TrialStatus, c("SUCCESS", "SUCCESS"))
  expect_identical(result$HistoryUsedMsgs, c(0L, 2L))
  expect_true(all(nzchar(result$RequestID)))
  expect_match(toupper(result$Response[[2L]]), "ORCHID", fixed = TRUE)
})

test_that("live DeepSeek executes bounded adaptive feedback", {
  live_api_require("DEEPSEEK_API_KEY")
  live_api_use_system_registry()
  key <- Sys.getenv("DEEPSEEK_API_KEY")
  output_directory <- withr::local_tempdir()

  feedback <- function(response, row, context) {
    if (context$turn == 1L) {
      return(list(
        name = "live_follow_up",
        next_prompt = "Reply exactly with the single word ADAPTED.",
        meta = list(trigger_response = response)
      ))
    }
    NULL
  }

  invisible(capture.output(
    result <- adaptive_feedback_experiment(
      model_key = "deepseek-flash",
      api_key = key,
      data = data.frame(
        ConversationId = "C1",
        Turn = 1L,
        Material = "Reply exactly with the single word BASE.",
        stringsAsFactors = FALSE
      ),
      system_content = paste(
        "You are participating in a deterministic API integration test.",
        "Follow each response-format instruction exactly."
      ),
      optionals = list(max_tokens = 64L),
      apply_mode = "insert_dynamic",
      max_turns = 2L,
      stream = FALSE,
      random = FALSE,
      delay = 0,
      feedback_fn = feedback,
      output_path = output_directory
    )
  ))

  expect_identical(nrow(result), 2L)
  expect_identical(result$TrialStatus, c("SUCCESS", "SUCCESS"))
  expect_identical(result$HistoryUsedMsgs, c(0L, 2L))
  expect_identical(result$FeedbackStatus, c("APPLIED", "NO_CHANGE"))
  expect_identical(result$FeedbackApplied, c(TRUE, FALSE))
  expect_match(
    result$FeedbackNextPrompt[[1L]],
    "ADAPTED",
    fixed = TRUE
  )
  expect_match(result$RequestMessages[[2L]], "ADAPTED", fixed = TRUE)
  expect_match(toupper(result$Response[[2L]]), "ADAPTED", fixed = TRUE)
})
