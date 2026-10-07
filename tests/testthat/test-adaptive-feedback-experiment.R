mock_adaptive_feedback_runtime <- function(.local_envir = parent.frame()) {
  state <- new.env(parent = emptyenv())
  state$calls <- list()
  state$logs <- list()

  local_mocked_bindings(
    get_registry_entry = function(...) {
      list(input = list(role_mapping = list(
        system = "system",
        user = "user",
        assistant = "assistant"
      )))
    },
    validate_experiment_config = function(...) TRUE,
    resolve_output_and_log = function(output_path, model) {
      list(
        result_file = file.path(tempdir(), "adaptive-results.csv"),
        log_file = file.path(tempdir(), "adaptive-results.log")
      )
    },
    write_experiment_log = function(...) {
      state$logs[[length(state$logs) + 1L]] <- list(...)
      invisible(TRUE)
    },
    update_progress_bar = function(...) invisible(TRUE),
    save_experiment_results = function(...) invisible(TRUE),
    llm_caller = function(...) {
      arguments <- list(...)
      state$calls[[length(state$calls) + 1L]] <- arguments
      index <- length(state$calls)
      list(
        status = 200L,
        answer = paste0("answer-", index),
        thinking = paste0("reasoning-", index),
        first_token_latency = index / 10,
        usage = list(
          prompt = 10L + index,
          completion = index,
          id = paste0("adaptive-request-", index)
        ),
        streaming = FALSE,
        error = NULL
      )
    },
    .package = "PsyLingLLM",
    .env = .local_envir
  )
  state
}

test_that("adaptive feedback replaces the next planned prompt", {
  state <- mock_adaptive_feedback_runtime()
  feedback <- function(response, row, context) {
    if (context$turn == 1L) {
      return(list(
        name = "follow_up",
        next_prompt = "Ask a harder follow-up.",
        meta = list(previous = response)
      ))
    }
    NULL
  }
  source <- data.frame(
    ConversationId = c("C1", "C1"),
    Turn = c(1L, 2L),
    Material = c("First material", "Second material"),
    stringsAsFactors = FALSE
  )

  result <- adaptive_feedback_experiment(
    model_key = "fixture-model",
    api_key = "not-a-real-key",
    data = source,
    feedback_fn = feedback,
    apply_mode = "replace_next",
    delay = 0,
    output_path = tempdir()
  )

  expect_identical(nrow(result), 2L)
  expect_identical(result$Material, source$Material)
  expect_identical(result$FeedbackDecision, c("follow_up", NA_character_))
  expect_identical(result$FeedbackStatus, c("APPLIED", "NO_CHANGE"))
  expect_identical(result$FeedbackApplied, c(TRUE, FALSE))
  expect_identical(
    result$FeedbackNextPrompt,
    c("Ask a harder follow-up.", NA_character_)
  )
  expect_match(
    state$calls[[2L]]$material,
    "Ask a harder follow-up.",
    fixed = TRUE
  )
  expect_false("optionals" %in% names(state$calls[[1L]]))
  expect_identical(result$RequestID, c(
    "adaptive-request-1", "adaptive-request-2"
  ))
})

test_that("adaptive feedback inserts bounded dynamic turns", {
  state <- mock_adaptive_feedback_runtime()
  feedback <- function(response, row, context) {
    if (context$turn < 3L) {
      return(list(
        name = paste0("step_", context$turn),
        next_prompt = paste("Dynamic prompt", context$turn + 1L),
        meta = list(turn = context$turn)
      ))
    }
    NULL
  }

  result <- adaptive_feedback_experiment(
    model_key = "fixture-model",
    api_key = "not-a-real-key",
    data = data.frame(
      ConversationId = "C1",
      Turn = 1L,
      Material = "Starting material",
      stringsAsFactors = FALSE
    ),
    feedback_fn = feedback,
    apply_mode = "insert_dynamic",
    max_turns = 3L,
    optionals = NULL,
    delay = 0,
    output_path = tempdir()
  )

  expect_identical(nrow(result), 3L)
  expect_identical(result$Turn, c(1L, 2L, 3L))
  expect_identical(result$Material, c("Starting material", "", ""))
  expect_identical(
    result$FeedbackDecision,
    c("step_1", "step_2", NA_character_)
  )
  expect_identical(result$FeedbackStatus, c(
    "APPLIED", "APPLIED", "NO_CHANGE"
  ))
  expect_identical(result$FeedbackApplied, c(TRUE, TRUE, FALSE))
  expect_length(state$calls, 3L)
  optionals_present <- vapply(
    state$calls,
    function(arguments) "optionals" %in% names(arguments),
    logical(1)
  )
  expect_true(
    all(optionals_present),
    info = paste(
      vapply(
        state$calls,
        function(x) paste(names(x), collapse = ","),
        character(1)
      ),
      collapse = " | "
    )
  )
  expect_true(all(vapply(
    state$calls,
    function(arguments) is.null(arguments$optionals),
    logical(1)
  )))
})

test_that("the legacy feedback name remains an exact compatibility alias", {
  expect_identical(
    conversation_experiment_with_feedback,
    adaptive_feedback_experiment
  )
  expect_identical(
    formals(conversation_experiment_with_feedback),
    formals(adaptive_feedback_experiment)
  )
})

test_that("dynamic feedback requires a finite execution cap", {
  expect_error(
    adaptive_feedback_experiment(
      model_key = "fixture-model",
      api_key = "not-a-real-key",
      data = data.frame(Material = "Starting material"),
      feedback_fn = function(...) NULL,
      apply_mode = "insert_dynamic"
    ),
    "max_turns.*required"
  )
})

test_that("feedback callback errors are recorded without stopping the run", {
  mock_adaptive_feedback_runtime()

  expect_warning(
    result <- adaptive_feedback_experiment(
      model_key = "fixture-model",
      api_key = "not-a-real-key",
      data = data.frame(Material = "Starting material"),
      feedback_fn = function(...) list(unexpected = TRUE),
      delay = 0,
      output_path = tempdir()
    ),
    "Unknown feedback field"
  )

  expect_identical(result$TrialStatus, "SUCCESS")
  expect_identical(result$FeedbackStatus, "ERROR")
  expect_false(result$FeedbackApplied)
  expect_match(result$FeedbackMessage, "Unknown feedback field")
})

test_that("conversation identifiers and turns are validated before requests", {
  expect_error(
    adaptive_feedback_experiment(
      model_key = "fixture-model",
      api_key = "not-a-real-key",
      data = data.frame(
        ConversationId = c("C1", "C1"),
        Turn = c(1L, 1L),
        Material = c("One", "Two")
      ),
      feedback_fn = function(...) NULL
    ),
    "combination must be unique"
  )
})

test_that("conversation experiments preserve all three optionals states", {
  state <- mock_adaptive_feedback_runtime()
  source <- data.frame(Material = "One turn")

  conversation_experiment(
    model_key = "fixture-model",
    api_key = "not-a-real-key",
    data = source,
    delay = 0,
    output_path = tempdir()
  )
  conversation_experiment(
    model_key = "fixture-model",
    api_key = "not-a-real-key",
    data = source,
    optionals = NULL,
    delay = 0,
    output_path = tempdir()
  )

  expect_false("optionals" %in% names(state$calls[[1L]]))
  expect_true("optionals" %in% names(state$calls[[2L]]))
  expect_null(state$calls[[2L]]$optionals)
})

test_that("conversation experiments reject invalid execution controls", {
  expect_error(
    conversation_experiment(
      model_key = "fixture-model",
      api_key = "not-a-real-key",
      data = data.frame(Material = "One turn"),
      repeats = 1.5
    ),
    "repeats.*positive integer"
  )
  expect_error(
    conversation_experiment(
      model_key = "fixture-model",
      api_key = "not-a-real-key",
      data = data.frame(Material = "One turn"),
      max_history_turns = -1L
    ),
    "max_history_turns"
  )
})
