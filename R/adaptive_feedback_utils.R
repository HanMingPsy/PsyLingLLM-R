validate_conversation_experiment_arguments <- function(
    data,
    repeats,
    random,
    max_history_turns,
    delay) {
  if (!is.numeric(repeats) || length(repeats) != 1L || is.na(repeats) ||
      !is.finite(repeats) || repeats != floor(repeats) || repeats < 1L ||
      repeats > .Machine$integer.max) {
    stop("`repeats` must be one positive integer.", call. = FALSE)
  }
  if (!is.logical(random) || length(random) != 1L || is.na(random)) {
    stop("`random` must be one non-missing logical value.", call. = FALSE)
  }
  history_valid <- is.numeric(max_history_turns) &&
    length(max_history_turns) == 1L && !is.na(max_history_turns) &&
    max_history_turns >= 0 &&
    (is.infinite(max_history_turns) ||
      (max_history_turns == floor(max_history_turns) &&
        max_history_turns <= .Machine$integer.max))
  if (!history_valid) {
    stop(
      "`max_history_turns` must be a non-negative integer or Inf.",
      call. = FALSE
    )
  }
  if (!is.numeric(delay) || length(delay) != 1L || is.na(delay) ||
      !is.finite(delay) || delay < 0) {
    stop("`delay` must be one non-negative finite number.", call. = FALSE)
  }
  if (anyNA(data$ConversationId) ||
      any(!nzchar(trimws(data$ConversationId)))) {
    stop("`ConversationId` values must be non-empty and non-missing.", call. = FALSE)
  }
  turn_valid <- is.numeric(data$Turn) && !anyNA(data$Turn) &&
    all(is.finite(data$Turn)) && all(data$Turn == floor(data$Turn)) &&
    all(data$Turn >= 1L) && all(data$Turn <= .Machine$integer.max)
  if (!turn_valid) {
    stop("`Turn` values must be positive integers.", call. = FALSE)
  }
  turn_keys <- paste(data$ConversationId, as.integer(data$Turn), sep = "\r")
  if (anyDuplicated(turn_keys)) {
    stop(
      "Each `ConversationId` and `Turn` combination must be unique.",
      call. = FALSE
    )
  }

  invisible(TRUE)
}

validate_adaptive_feedback_arguments <- function(
    data,
    feedback_fn,
    apply_mode,
    max_turns,
    repeats,
    random,
    max_history_turns,
    delay) {
  validate_conversation_experiment_arguments(
    data = data,
    repeats = repeats,
    random = random,
    max_history_turns = max_history_turns,
    delay = delay
  )
  if (!is.function(feedback_fn)) {
    stop("`feedback_fn` must be a function.", call. = FALSE)
  }

  if (identical(apply_mode, "insert_dynamic")) {
    if (is.null(max_turns)) {
      stop(
        "`max_turns` is required for `apply_mode = \"insert_dynamic\"`.",
        call. = FALSE
      )
    }
    max_turns_valid <- is.numeric(max_turns) && length(max_turns) == 1L &&
      !is.na(max_turns) && is.finite(max_turns) &&
      max_turns == floor(max_turns) && max_turns >= 1L &&
      max_turns <= .Machine$integer.max
    if (!max_turns_valid) {
      stop("`max_turns` must be one positive integer.", call. = FALSE)
    }
    initial_counts <- table(data$ConversationId)
    if (any(initial_counts > as.integer(max_turns))) {
      stop(
        "`max_turns` cannot be smaller than an initial conversation.",
        call. = FALSE
      )
    }
  }
  invisible(TRUE)
}

evaluate_adaptive_feedback <- function(feedback_fn, response, row, context) {
  tryCatch(
    list(
      feedback = normalize_adaptive_feedback(feedback_fn(response, row, context)),
      error = NULL
    ),
    error = function(error) {
      message <- redact_diagnostic_text(conditionMessage(error))
      warning("feedback_fn error: ", message, call. = FALSE)
      list(feedback = NULL, error = message)
    }
  )
}

normalize_adaptive_feedback <- function(feedback) {
  if (is.null(feedback)) {
    return(NULL)
  }
  if (!is.list(feedback) || is.null(names(feedback)) ||
      anyNA(names(feedback)) || any(!nzchar(names(feedback))) ||
      anyDuplicated(names(feedback))) {
    stop("feedback_fn must return NULL or a named list.", call. = FALSE)
  }
  unknown <- setdiff(names(feedback), c("name", "next_prompt", "meta"))
  if (length(unknown)) {
    stop(
      paste("Unknown feedback field(s):", paste(unknown, collapse = ", ")),
      call. = FALSE
    )
  }
  scalar_text_or_null <- function(value) {
    is.null(value) ||
      (is.character(value) && length(value) == 1L && !is.na(value) &&
        nzchar(trimws(value)))
  }
  if (!scalar_text_or_null(feedback$name)) {
    stop("feedback `name` must be NULL or one non-empty string.", call. = FALSE)
  }
  if (!scalar_text_or_null(feedback$next_prompt)) {
    stop(
      "feedback `next_prompt` must be NULL or one non-empty string.",
      call. = FALSE
    )
  }
  if (!is.null(feedback$meta)) {
    tryCatch(
      jsonlite::toJSON(
        feedback$meta,
        auto_unbox = TRUE,
        null = "null",
        digits = NA
      ),
      error = function(error) {
        stop("feedback `meta` must be JSON-serializable.", call. = FALSE)
      }
    )
  }
  list(
    name = feedback$name %||% NULL,
    next_prompt = feedback$next_prompt %||% NULL,
    meta = feedback$meta %||% NULL
  )
}

serialize_adaptive_feedback_meta <- function(meta) {
  if (is.null(meta)) {
    return(NA_character_)
  }
  as.character(jsonlite::toJSON(
    meta,
    auto_unbox = TRUE,
    null = "null",
    digits = NA
  ))
}
