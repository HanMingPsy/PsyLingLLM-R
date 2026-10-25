make_raw_analysis_result <- function() {
  result <- data.frame(
    TrialKey = c("trial-1", "trial-2", "trial-3"),
    RequestID = c("request-1", "request-2", NA_character_),
    stringsAsFactors = FALSE
  )
  result$raw <- list(
    list(response = list(non_stream = list(
      parsed = list(
        usage = list(
          prompt_tokens = 8L,
          completion_tokens = 3L,
          completion_tokens_details = list(reasoning_tokens = 2L)
        ),
        choices = list(list(
          finish_reason = "stop",
          logprobs = list(content = list(list(
            token = "Y",
            bytes = list(89L),
            logprob = -0.1,
            top_logprobs = list(
              list(token = "Y", bytes = list(89L), logprob = -0.1),
              list(token = "N", bytes = list(78L), logprob = -1.2)
            )
          )))
        ))
      ),
      parse_recovery = list(method = "escape_control_bytes")
    ))),
    list(response = list(non_stream = list(
      parsed = list(
        usage = list(prompt_tokens = 6L, completion_tokens = 1L),
        choices = list(list(finish_reason = "stop"))
      )
    ))),
    NULL
  )
  result
}

test_that("get_trial_raw locates one RDS-compatible record by result row", {
  result <- make_raw_analysis_result()

  record <- get_trial_raw(result, 1L)

  expect_true(is.list(record))
  expect_identical(
    record$response$non_stream$parsed$usage$prompt_tokens,
    8L
  )
  expect_null(get_trial_raw(result, 3L))
  expect_error(get_trial_raw(result, 0L), "positive result-row")
  expect_error(get_trial_raw(result[, setdiff(names(result), "raw")]),
               "raw.*list-column")
})

test_that("extract_token_probabilities preserves selected and top-k evidence", {
  tokens <- extract_token_probabilities(make_raw_analysis_result())

  expect_identical(nrow(tokens), 2L)
  expect_identical(tokens$Token, c("Y", "N"))
  expect_identical(tokens$Selected, c(TRUE, FALSE))
  expect_equal(tokens$LogProb, c(-0.1, -1.2))
  expect_equal(tokens$Probability, exp(c(-0.1, -1.2)))
  expect_identical(tokens$CandidateRank, c(1L, 2L))
  expect_identical(tokens$TokenBytes, c("89", "78"))
  expect_true(all(tokens$Channel == "answer"))
  expect_identical(
    nrow(extract_token_probabilities(make_raw_analysis_result(), 2L)),
    0L
  )
})

test_that("token extraction reads the parsed response rather than request data", {
  result <- make_raw_analysis_result()[1, , drop = FALSE]
  result$raw[[1]]$request <- list(
    logprobs = list(token = "REQUEST", logprob = 0)
  )

  tokens <- extract_token_probabilities(result)

  expect_identical(tokens$Token, c("Y", "N"))
  expect_false(any(tokens$Token == "REQUEST"))
})

test_that("process summaries do not expand large top-k token tables", {
  result <- make_raw_analysis_result()[1, , drop = FALSE]
  entry <- result$raw[[1]]$response$non_stream$parsed$choices[[1]]$
    logprobs$content[[1]]
  result$raw[[1]]$response$non_stream$parsed$choices[[1]]$
    logprobs$content <- rep(list(entry), 1000L)

  metrics <- extract_process_metrics(result)

  expect_identical(metrics$ReturnedTokenCount, 1000L)
  expect_identical(metrics$AnswerToken, "Y")
  expect_true(metrics$LogprobsAvailable)
})

test_that("extract_process_metrics keeps missing process evidence explicit", {
  metrics <- extract_process_metrics(make_raw_analysis_result())

  expect_identical(nrow(metrics), 3L)
  expect_identical(metrics$InputTokens, c(8L, 6L, NA_integer_))
  expect_identical(metrics$OutputTokens, c(3L, 1L, NA_integer_))
  expect_identical(metrics$ReasoningTokens, c(2L, NA_integer_, NA_integer_))
  expect_identical(metrics$ReasoningTokensAvailable, c(TRUE, FALSE, FALSE))
  expect_identical(metrics$AnswerToken, c("Y", NA_character_, NA_character_))
  expect_equal(metrics$AnswerLogProb[[1L]], -0.1)
  expect_identical(metrics$LogprobsAvailable, c(TRUE, FALSE, FALSE))
  expect_identical(metrics$ReturnedTokenCount, c(1L, 0L, 0L))
  expect_identical(
    metrics$ProcessMetricsStatus,
    c("OK", "METRICS_UNAVAILABLE", "RAW_UNAVAILABLE")
  )
  expect_identical(metrics$ParseRecovery[[1L]], "escape_control_bytes")
})

test_that("RAW analysis survives an RDS round trip", {
  path <- tempfile(fileext = ".rds")
  saveRDS(make_raw_analysis_result(), path)
  restored <- readRDS(path)

  expect_identical(get_trial_raw(restored, 1L),
                   get_trial_raw(make_raw_analysis_result(), 1L))
  expect_identical(
    extract_process_metrics(restored),
    extract_process_metrics(make_raw_analysis_result())
  )
})

test_that("empty RAW archives retain stable analysis schemas", {
  result <- data.frame(RequestID = character())
  result$raw <- vector("list", 0L)

  metrics <- extract_process_metrics(result)
  tokens <- extract_token_probabilities(result)

  expect_s3_class(metrics, "data.frame")
  expect_identical(nrow(metrics), 0L)
  expect_true(all(c(
    "ResultRow", "ReasoningTokens", "LogprobsAvailable",
    "ProcessMetricsStatus"
  ) %in% names(metrics)))
  expect_s3_class(tokens, "data.frame")
  expect_identical(nrow(tokens), 0L)
})
