run_experiment_planner <- function(
    model_key,
    generation_interface = NULL,
    requirements,
    source_materials,
    api_key,
    parameters = list(),
    timeout = 120L,
    required_condition_names = NULL,
    registry = NULL,
    executor = llm_caller) {
  assert_experiment_planner_text(api_key, "api_key")
  if (!is.function(executor)) {
    experiment_spec_abort(
      "executor must be a function compatible with llm_caller().",
      reason = "invalid_planner_executor"
    )
  }

  onboarding_call <- prepare_experiment_planner_call(
    model_key = model_key,
    generation_interface = generation_interface,
    turn = "onboarding",
    parameters = parameters,
    timeout = timeout,
    registry = registry
  )
  onboarding_result <- execute_experiment_planner_call(
    onboarding_call,
    api_key,
    executor
  )
  onboarding <- process_experiment_planner_response(
    onboarding_call,
    onboarding_result,
    registry = registry
  )
  if (!isTRUE(onboarding$valid)) {
    return(experiment_planner_session_result(
      FALSE,
      "onboarding",
      onboarding$errors,
      onboarding_call$resolved,
      onboarding_request_id = onboarding$request_id
    ))
  }

  spec_call <- prepare_experiment_planner_call(
    model_key = model_key,
    generation_interface = generation_interface,
    turn = "spec",
    requirements = requirements,
    source_materials = source_materials,
    acknowledgement = onboarding$acknowledgement,
    parameters = parameters,
    timeout = timeout,
    registry = registry
  )
  spec_result <- execute_experiment_planner_call(spec_call, api_key, executor)
  planning <- process_experiment_planner_response(
    spec_call,
    spec_result,
    source_materials = source_materials,
    required_condition_names = required_condition_names,
    registry = registry
  )
  planning_request_ids <- planning$request_id
  attempts <- 1L

  has_previous_answer <- is.character(spec_result$answer) &&
    length(spec_result$answer) == 1L && !is.na(spec_result$answer) &&
    nzchar(trimws(spec_result$answer))
  repairable <- !isTRUE(planning$valid) && has_previous_answer &&
    !any(vapply(
      planning$errors,
      function(error) identical(error$code, "planner_api_failure"),
      logical(1)
    ))
  if (repairable) {
    repair_call <- prepare_experiment_planner_repair_call(
      spec_call,
      previous_answer = spec_result$answer,
      response = planning
    )
    repaired_result <- execute_experiment_planner_call(
      repair_call,
      api_key,
      executor
    )
    planning <- process_experiment_planner_response(
      repair_call,
      repaired_result,
      source_materials = source_materials,
      required_condition_names = required_condition_names,
      registry = registry
    )
    planning_request_ids <- c(
      planning_request_ids,
      planning$request_id
    )
    attempts <- 2L
  }

  experiment_planner_session_result(
    planning$valid,
    if (isTRUE(planning$valid)) "review" else "planning",
    planning$errors,
    spec_call$resolved,
    onboarding_request_id = onboarding$request_id,
    planning_request_ids = planning_request_ids,
    attempts = attempts,
    spec = planning$spec,
    plan = planning$plan,
    review = planning$review
  )
}

prepare_experiment_planner_repair_call <- function(
    call,
    previous_answer,
    response) {
  if (!inherits(call, "psylingllm_experiment_planner_call") ||
      !identical(call$turn, "spec")) {
    experiment_spec_abort(
      "Only a prepared planning call can be repaired.",
      reason = "invalid_planner_repair_call"
    )
  }
  assert_experiment_planner_text(previous_answer, "previous_answer")
  feedback <- experiment_planner_validation_feedback(response)
  history <- c(
    call$arguments$assistant_content,
    list(
      list(role = "user", content = call$arguments$material),
      list(role = "assistant", content = previous_answer)
    )
  )
  repaired <- call
  repaired$arguments$assistant_content <- history
  repaired$arguments$material <- feedback
  repaired
}

execute_experiment_planner_call <- function(call, api_key, executor) {
  tryCatch(
    do.call(executor, c(call$arguments, list(api_key = api_key))),
    error = function(error) {
      message <- conditionMessage(error)
      if (nzchar(api_key)) {
        message <- gsub(api_key, "[REDACTED]", message, fixed = TRUE)
      }
      list(
        status = 599L,
        response_status = "ERROR",
        answer = NULL,
        usage = list(id = NULL),
        error = list(message = redact_diagnostic_text(message))
      )
    }
  )
}

experiment_planner_session_result <- function(
    valid,
    stage,
    errors,
    resolved,
    onboarding_request_id = NULL,
    planning_request_ids = NULL,
    attempts = 0L,
    spec = NULL,
    plan = NULL,
    review = NULL) {
  request_ids <- c(onboarding_request_id, planning_request_ids)
  request_ids <- request_ids[
    !is.na(request_ids) & nzchar(request_ids)
  ]
  structure(
    list(
      valid = isTRUE(valid),
      stage = stage,
      errors = errors,
      resolved = resolved,
      attempts = as.integer(attempts),
      request_ids = unname(request_ids),
      spec = spec,
      plan = plan,
      review = review
    ),
    class = c("psylingllm_experiment_planner_session", "list")
  )
}
