validate_experiment_result <- function(compiled, result) {
  errors <- list()
  add_error <- function(code, path, message) {
    errors[[length(errors) + 1L]] <<- list(
      code = code,
      path = path,
      message = message
    )
  }

  if (!experiment_call_contract_valid(compiled)) {
    add_error(
      "invalid_compiled_call",
      "$.compiled",
      "compiled must be an unmodified PsyLingLLM trial call specification."
    )
    return(experiment_result_validation_result(FALSE, errors, NULL))
  }
  if (!is.data.frame(result)) {
    add_error("invalid_result", "$.result", "result must be a data.frame.")
    return(experiment_result_validation_result(FALSE, errors, NULL))
  }

  required_output_columns <- c(
    "Response", "Think", "ModelName", "TotalResponseTime",
    "FirstTokenLatency", "PromptTokens", "CompletionTokens",
    "TrialStatus", "ResponseStatus", "Streaming", "Timestamp", "RequestID"
  )
  required_input_columns <- c("Run", names(compiled$arguments$data))
  missing_columns <- setdiff(
    c(required_input_columns, required_output_columns),
    names(result)
  )
  if (length(missing_columns)) {
    add_error(
      "missing_result_columns",
      "$.result",
      paste("Missing result column(s):", paste(missing_columns, collapse = ", "))
    )
  }

  type_checks <- list(
    Response = is.character,
    Think = is.character,
    TotalResponseTime = is.numeric,
    FirstTokenLatency = is.numeric,
    PromptTokens = is.numeric,
    CompletionTokens = is.numeric
  )
  invalid_types <- names(type_checks)[vapply(
    names(type_checks),
    function(name) {
      name %in% names(result) && !type_checks[[name]](result[[name]])
    },
    logical(1)
  )]
  if (length(invalid_types)) {
    add_error(
      "invalid_result_column_type",
      "$.result",
      paste(
        "Unexpected result column type(s):",
        paste(invalid_types, collapse = ", ")
      )
    )
  }

  expected <- experiment_result_expected_inputs(compiled)
  expected_runs <- nrow(expected)
  if (nrow(result) != expected_runs) {
    add_error(
      "unexpected_result_rows",
      "$.result",
      sprintf("Expected %d result row(s), received %d.", expected_runs, nrow(result))
    )
  }

  comparable_columns <- intersect(names(expected), names(result))
  if (nrow(result) == expected_runs && length(comparable_columns)) {
    actual_inputs <- result[, comparable_columns, drop = FALSE]
    expected_inputs <- expected[, comparable_columns, drop = FALSE]
    inputs_match <- if (isTRUE(compiled$arguments$random)) {
      identical(
        sort(experiment_result_row_signatures(actual_inputs)),
        sort(experiment_result_row_signatures(expected_inputs))
      )
    } else {
      all(vapply(
        comparable_columns,
        function(name) identical(actual_inputs[[name]], expected_inputs[[name]]),
        logical(1)
      ))
    }
    if (!inputs_match) {
      add_error(
        "result_input_mismatch",
        "$.result",
        "Result input columns do not match the compiled experiment plan."
      )
    }
  }

  if ("Run" %in% names(result) &&
      (!is.numeric(result$Run) || anyNA(result$Run) ||
       !identical(as.integer(result$Run), seq_len(nrow(result))))) {
    add_error(
      "invalid_run_sequence",
      "$.result.Run",
      "Run must be a sequential index beginning at 1."
    )
  }
  if ("ModelName" %in% names(result) &&
      (!is.character(result$ModelName) || anyNA(result$ModelName) ||
       !all(result$ModelName == compiled$arguments$model_key))) {
    add_error(
      "model_identity_mismatch",
      "$.result.ModelName",
      "Every ModelName must match the compiled model_key."
    )
  }

  allowed_trial_status <- c("SUCCESS", "ERROR", "TIMEOUT")
  allowed_response_status <- c("OK", "EMPTY_RESPONSE", "ERROR", "TIMEOUT")
  trial_status_valid <- experiment_result_allowed_values(
    result,
    "TrialStatus",
    allowed_trial_status
  )
  response_status_valid <- experiment_result_allowed_values(
    result,
    "ResponseStatus",
    allowed_response_status
  )
  if (!trial_status_valid) {
    add_error(
      "invalid_trial_status",
      "$.result.TrialStatus",
      "TrialStatus contains missing or unsupported values."
    )
  }
  if (!response_status_valid) {
    add_error(
      "invalid_response_status",
      "$.result.ResponseStatus",
      "ResponseStatus contains missing or unsupported values."
    )
  }
  if (trial_status_valid && response_status_valid) {
    expected_trial_status <- ifelse(
      result$ResponseStatus == "TIMEOUT",
      "TIMEOUT",
      ifelse(result$ResponseStatus == "ERROR", "ERROR", "SUCCESS")
    )
    if (!identical(result$TrialStatus, expected_trial_status)) {
      add_error(
        "inconsistent_result_status",
        "$.result",
        "TrialStatus and ResponseStatus contain inconsistent outcomes."
      )
    }
  }
  if ("ResponseStatus" %in% names(result) &&
      "Response" %in% names(result) &&
      is.character(result$ResponseStatus) &&
      is.character(result$Response)) {
    ok <- result$ResponseStatus == "OK"
    if (any(ok & (is.na(result$Response) | !nzchar(trimws(result$Response))))) {
      add_error(
        "empty_ok_response",
        "$.result.Response",
        "Responses classified as OK must contain non-empty text."
      )
    }
  }
  if ("Streaming" %in% names(result) &&
      (!is.logical(result$Streaming) || anyNA(result$Streaming) ||
       !all(result$Streaming == compiled$arguments$stream))) {
    add_error(
      "streaming_mismatch",
      "$.result.Streaming",
      "Streaming must match the compiled stream setting."
    )
  }
  if ("Timestamp" %in% names(result) &&
      (!is.character(result$Timestamp) || anyNA(result$Timestamp) ||
       any(!nzchar(trimws(result$Timestamp))))) {
    add_error(
      "invalid_timestamp",
      "$.result.Timestamp",
      "Timestamp values must be non-empty strings."
    )
  }
  if ("RequestID" %in% names(result) && !is.character(result$RequestID)) {
    add_error(
      "invalid_request_id",
      "$.result.RequestID",
      "RequestID must be a character column and may contain NA."
    )
  }

  summary <- experiment_result_summary(compiled, result)
  experiment_result_validation_result(length(errors) == 0L, errors, summary)
}

create_experiment_receipt <- function(
    compiled,
    result,
    planner_request_ids = character()) {
  validation <- validate_experiment_result(compiled, result)
  if (!isTRUE(validation$valid)) {
    messages <- vapply(
      validation$errors,
      function(error) paste0(error$path, ": ", error$message),
      character(1)
    )
    experiment_spec_abort(
      paste("Experiment result validation failed:", paste(messages, collapse = "; ")),
      reason = "experiment_result_validation_failed"
    )
  }
  if (!is.character(planner_request_ids) || anyNA(planner_request_ids)) {
    experiment_spec_abort(
      "planner_request_ids must be a character vector without missing values.",
      reason = "invalid_planner_request_ids"
    )
  }
  planner_request_ids <- unique(planner_request_ids[nzchar(planner_request_ids)])

  structure(
    list(
      receipt_version = 1L,
      experiment_schema_version = 1L,
      call_contract_version = compiled$call_contract_version,
      function_name = "trial_experiment",
      model = list(
        requested_key = compiled$arguments$model_key,
        resolved_key = compiled$resolved$model_key,
        model_id = compiled$resolved$model_id,
        provider_id = compiled$resolved$provider_id,
        interface_id = compiled$resolved$interface_id,
        protocol = compiled$resolved$protocol
      ),
      planned_runs = validation$summary$planned_runs,
      completed_runs = validation$summary$completed_runs,
      trial_status = validation$summary$trial_status,
      response_status = validation$summary$response_status,
      planner_request_ids = planner_request_ids,
      experiment_request_ids = validation$summary$request_ids
    ),
    class = c("psylingllm_experiment_receipt", "list")
  )
}

experiment_call_contract_valid <- function(compiled) {
  required_arguments <- c(
    "model_key", "generation_interface", "data", "trial_prompt",
    "system_content", "optionals", "stream", "timeout", "repeats",
    "random", "delay"
  )
  if (!inherits(compiled, "psylingllm_experiment_call") ||
      !identical(compiled$call_contract_version, 1L) ||
      !identical(compiled$function_name, "trial_experiment") ||
      !is.list(compiled$arguments) ||
      !identical(names(compiled$arguments), required_arguments) ||
      !is.list(compiled$resolved)) {
    return(FALSE)
  }

  arguments <- compiled$arguments
  scalar_text <- function(value, nullable = FALSE) {
    if (nullable && is.null(value)) {
      return(TRUE)
    }
    is.character(value) && length(value) == 1L && !is.na(value) &&
      nzchar(value)
  }
  scalar_integer <- function(value, minimum, maximum) {
    is.numeric(value) && length(value) == 1L && !is.na(value) &&
      is.finite(value) && value == as.integer(value) &&
      value >= minimum && value <= maximum
  }
  named_parameters <- is.null(arguments$optionals) ||
    (is.list(arguments$optionals) && !is.null(names(arguments$optionals)) &&
     !anyNA(names(arguments$optionals)) &&
     all(nzchar(names(arguments$optionals))) &&
     !anyDuplicated(names(arguments$optionals)))
  data_valid <- is.data.frame(arguments$data) && nrow(arguments$data) > 0L &&
    all(c("Item", "Material", "TrialPrompt") %in% names(arguments$data)) &&
    is.character(arguments$data$Material) &&
    is.character(arguments$data$TrialPrompt)
  prompts_valid <- data_valid &&
    (!any(is.na(arguments$data$TrialPrompt) |
          !nzchar(arguments$data$TrialPrompt)) ||
     scalar_text(arguments$trial_prompt))
  resolved_fields <- c(
    "model_key", "model_id", "provider_id", "interface_id", "protocol"
  )
  resolved_valid <- all(resolved_fields %in% names(compiled$resolved)) &&
    all(vapply(
      compiled$resolved[resolved_fields],
      scalar_text,
      logical(1)
    ))

  scalar_text(arguments$model_key) &&
    scalar_text(arguments$generation_interface) &&
    scalar_text(arguments$system_content, nullable = TRUE) &&
    named_parameters &&
    data_valid &&
    prompts_valid &&
    is.logical(arguments$stream) && length(arguments$stream) == 1L &&
    !is.na(arguments$stream) &&
    scalar_integer(arguments$timeout, 1L, 600L) &&
    scalar_integer(arguments$repeats, 1L, 10L) &&
    is.logical(arguments$random) && length(arguments$random) == 1L &&
    !is.na(arguments$random) &&
    is.numeric(arguments$delay) && length(arguments$delay) == 1L &&
    !is.na(arguments$delay) && arguments$delay >= 0 &&
    resolved_valid
}

experiment_result_expected_inputs <- function(compiled) {
  source <- compiled$arguments$data
  missing_prompt <- is.na(source$TrialPrompt) | !nzchar(source$TrialPrompt)
  source$TrialPrompt[missing_prompt] <- compiled$arguments$trial_prompt
  source <- source[
    rep(seq_len(nrow(source)), times = compiled$arguments$repeats),
    ,
    drop = FALSE
  ]
  rownames(source) <- NULL
  source
}

experiment_result_row_signatures <- function(data) {
  vapply(
    seq_len(nrow(data)),
    function(index) {
      jsonlite::toJSON(
        as.list(data[index, , drop = FALSE]),
        auto_unbox = TRUE,
        na = "null",
        null = "null"
      )
    },
    character(1)
  )
}

experiment_result_allowed_values <- function(result, column, allowed) {
  column %in% names(result) &&
    is.character(result[[column]]) &&
    !anyNA(result[[column]]) &&
    all(result[[column]] %in% allowed)
}

experiment_result_summary <- function(compiled, result) {
  status_counts <- function(column) {
    if (!(column %in% names(result)) || !is.character(result[[column]])) {
      return(list())
    }
    as.list(table(result[[column]], useNA = "no"))
  }
  request_ids <- if ("RequestID" %in% names(result) &&
                     is.character(result$RequestID)) {
    unique(result$RequestID[!is.na(result$RequestID) & nzchar(result$RequestID)])
  } else {
    character()
  }
  list(
    planned_runs = as.integer(
      nrow(compiled$arguments$data) * compiled$arguments$repeats
    ),
    completed_runs = nrow(result),
    trial_status = status_counts("TrialStatus"),
    response_status = status_counts("ResponseStatus"),
    request_ids = request_ids
  )
}

experiment_result_validation_result <- function(valid, errors, summary) {
  structure(
    list(valid = isTRUE(valid), errors = errors, summary = summary),
    class = c("psylingllm_experiment_result_validation", "list")
  )
}
