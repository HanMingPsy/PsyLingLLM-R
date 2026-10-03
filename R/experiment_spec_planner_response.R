process_experiment_planner_response <- function(
    call,
    result,
    source_materials = NULL,
    required_condition_names = NULL,
    registry = NULL) {
  if (!inherits(call, "psylingllm_experiment_planner_call")) {
    experiment_spec_abort(
      "call must be produced by prepare_experiment_planner_call().",
      reason = "invalid_planner_call"
    )
  }
  response_error <- validate_experiment_planner_llm_result(result)
  request_id <- experiment_planner_request_id(result)
  if (!is.null(response_error)) {
    return(experiment_planner_response_result(
      FALSE,
      call$turn,
      list(response_error),
      request_id = request_id
    ))
  }

  if (identical(call$turn, "onboarding")) {
    validation <- validate_experiment_planner_acknowledgement(result$answer)
    errors <- lapply(
      validation$errors,
      function(message) {
        list(
          code = "invalid_planner_acknowledgement",
          path = "$",
          message = message
        )
      }
    )
    return(experiment_planner_response_result(
      validation$valid,
      call$turn,
      errors,
      acknowledgement = if (isTRUE(validation$valid)) result$answer else NULL,
      request_id = request_id
    ))
  }

  assert_experiment_planner_materials(source_materials)
  parsed <- tryCatch(
    parse_experiment_spec(result$answer),
    error = function(error) error
  )
  if (inherits(parsed, "error")) {
    return(experiment_planner_response_result(
      FALSE,
      call$turn,
      list(list(
        code = "invalid_json",
        path = "$",
        message = conditionMessage(parsed)
      )),
      request_id = request_id
    ))
  }

  validation <- validate_experiment_spec(parsed)
  if (!isTRUE(validation$valid)) {
    return(experiment_planner_response_result(
      FALSE,
      call$turn,
      validation$errors,
      spec = parsed,
      request_id = request_id
    ))
  }

  plan <- normalize_experiment_spec(parsed)
  review <- review_experiment_plan(
    plan,
    source_materials = source_materials,
    required_condition_names = required_condition_names,
    registry = registry
  )
  experiment_planner_response_result(
    review$valid,
    call$turn,
    review$errors,
    spec = parsed,
    plan = plan,
    review = review,
    request_id = request_id
  )
}

validate_experiment_planner_llm_result <- function(result) {
  if (!is.list(result)) {
    return(list(
      code = "invalid_llm_result",
      path = "$",
      message = "Planner result must be a normalized llm_caller() result."
    ))
  }
  status <- suppressWarnings(as.integer(result$status %||% NA_integer_))
  response_status <- result$response_status %||% ""
  if (length(status) != 1L || is.na(status) || status != 200L ||
      !identical(response_status, "OK")) {
    provider_message <- result$error$message %||% ""
    message <- paste0(
      "Planner API call did not return a usable response (status ",
      if (length(status) == 1L && !is.na(status)) status else "unknown",
      ", response_status ", response_status %||% "unknown", ")."
    )
    if (is.character(provider_message) && length(provider_message) == 1L &&
        !is.na(provider_message) && nzchar(provider_message)) {
      message <- paste(message, provider_message)
    }
    return(list(
      code = "planner_api_failure",
      path = "$",
      message = message
    ))
  }
  if (!is.character(result$answer) || length(result$answer) != 1L ||
      is.na(result$answer) || !nzchar(trimws(result$answer))) {
    return(list(
      code = "empty_planner_response",
      path = "$.answer",
      message = "Planner API response did not contain one non-empty answer."
    ))
  }
  NULL
}

experiment_planner_request_id <- function(result) {
  request_id <- result$usage$id %||% NULL
  if (!is.character(request_id) || length(request_id) != 1L ||
      is.na(request_id) || !nzchar(request_id)) {
    return(NULL)
  }
  request_id
}

experiment_planner_response_result <- function(
    valid,
    turn,
    errors,
    acknowledgement = NULL,
    spec = NULL,
    plan = NULL,
    review = NULL,
    request_id = NULL) {
  structure(
    list(
      valid = isTRUE(valid),
      turn = turn,
      errors = errors,
      acknowledgement = acknowledgement,
      spec = spec,
      plan = plan,
      review = review,
      request_id = request_id
    ),
    class = c("psylingllm_experiment_planner_response", "list")
  )
}

experiment_planner_validation_feedback <- function(response) {
  if (!inherits(response, "psylingllm_experiment_planner_response") ||
      isTRUE(response$valid) || length(response$errors) == 0L) {
    experiment_spec_abort(
      "feedback requires an invalid processed planner response.",
      reason = "invalid_planner_feedback_input"
    )
  }
  errors <- vapply(
    response$errors,
    function(error) {
      sprintf(
        "- %s at %s: %s",
        error$code %||% "validation_error",
        error$path %||% "$",
        error$message %||% "Invalid value."
      )
    },
    character(1)
  )
  paste(
    "The previous JSON failed deterministic PsyLingLLM validation.",
    paste(errors, collapse = "\n"),
    "Return one corrected Experiment Spec v1 JSON object only.",
    "Do not change the source material strings or their order.",
    sep = "\n"
  )
}
