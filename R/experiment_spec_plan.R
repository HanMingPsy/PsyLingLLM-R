normalize_experiment_spec <- function(spec) {
  validation <- validate_experiment_spec(spec)
  if (!isTRUE(validation$valid)) {
    messages <- vapply(
      validation$errors,
      function(error) paste0(error$path, ": ", error$message),
      character(1)
    )
    experiment_spec_abort(
      paste("Experiment Spec validation failed:", paste(messages, collapse = "; ")),
      reason = "experiment_spec_validation_failed"
    )
  }

  materials <- spec$materials
  first_conditions <- materials[[1L]]$conditions
  condition_names <- if (is.null(first_conditions)) {
    character()
  } else {
    names(first_conditions)
  }

  data <- data.frame(
    Item = vapply(materials, function(row) as.integer(row$item), integer(1)),
    stringsAsFactors = FALSE
  )
  for (name in condition_names) {
    values <- lapply(materials, function(row) row$conditions[[name]])
    if (all(vapply(values, is.character, logical(1)))) {
      data[[name]] <- vapply(values, identity, character(1))
    } else if (all(vapply(values, is.logical, logical(1)))) {
      data[[name]] <- vapply(values, identity, logical(1))
    } else {
      data[[name]] <- vapply(values, as.numeric, numeric(1))
    }
  }
  data$Material <- vapply(materials, function(row) row$material, character(1))
  data$TrialPrompt <- vapply(
    materials,
    function(row) {
      if (is.null(row$trial_prompt)) NA_character_ else row$trial_prompt
    },
    character(1)
  )

  runtime <- spec$runtime
  runtime$repeats <- as.integer(runtime$repeats)
  runtime$timeout <- as.integer(runtime$timeout)

  structure(
    list(
      schema_version = 1L,
      experiment_type = "trial",
      task = list(trial_prompt = spec$task$trial_prompt),
      data = data,
      runtime = runtime,
      source_spec = spec
    ),
    class = c("psylingllm_experiment_plan", "list")
  )
}

review_experiment_plan <- function(
    plan,
    source_materials,
    required_condition_names = NULL,
    registry = NULL) {
  errors <- list()
  add_error <- function(code, path, message) {
    errors[[length(errors) + 1L]] <<- list(
      code = code,
      path = path,
      message = message
    )
  }

  if (!inherits(plan, "psylingllm_experiment_plan")) {
    add_error(
      "invalid_plan",
      "$",
      "The plan must be produced by normalize_experiment_spec()."
    )
    return(experiment_plan_review_result(FALSE, errors, plan, NULL))
  }

  canonical_plan <- tryCatch(
    normalize_experiment_spec(plan$source_spec),
    error = function(error) error
  )
  if (inherits(canonical_plan, "error") || !identical(plan, canonical_plan)) {
    add_error(
      "plan_integrity_failure",
      "$",
      "The normalized plan no longer matches its validated source spec."
    )
    return(experiment_plan_review_result(FALSE, errors, plan, NULL))
  }

  if (!is.character(source_materials) || length(source_materials) == 0L ||
      anyNA(source_materials) ||
      any(!nzchar(trimws(source_materials)))) {
    add_error(
      "invalid_source_materials",
      "$.review.source_materials",
      "source_materials must be a non-missing vector of non-empty strings."
    )
  } else if (!identical(plan$data$Material, source_materials)) {
    add_error(
      "material_fidelity_failure",
      "$.materials",
      "Planned materials differ from the submitted materials or their order."
    )
  }

  fixed_columns <- c("Item", "Material", "TrialPrompt")
  condition_names <- setdiff(names(plan$data), fixed_columns)
  if (!is.null(required_condition_names)) {
    valid_required_names <- is.character(required_condition_names) &&
      !anyNA(required_condition_names) &&
      all(nzchar(required_condition_names)) &&
      !anyDuplicated(required_condition_names)
    if (!valid_required_names) {
      add_error(
        "invalid_required_condition_names",
        "$.review.required_condition_names",
        "required_condition_names must contain unique non-empty strings."
      )
    } else if (!setequal(condition_names, required_condition_names)) {
      add_error(
        "condition_schema_mismatch",
        "$.materials[*].conditions",
        paste(
          "Condition fields must be exactly:",
          paste(required_condition_names, collapse = ", ")
        )
      )
    }
  }

  resolved <- tryCatch(
    resolve_registry_entry(
      plan$runtime$model_key,
      generation_interface = plan$runtime$generation_interface,
      registry = registry
    ),
    error = function(error) error
  )
  if (inherits(resolved, "error")) {
    add_error(
      "registry_resolution_failure",
      "$.runtime",
      conditionMessage(resolved)
    )
    resolved_identity <- NULL
  } else {
    resolved_identity <- list(
      model_key = resolved$model$key,
      model_id = resolved$model$id,
      provider_id = resolved$provider$id,
      interface_id = resolved$interface$id,
      protocol = resolved$interface$protocol
    )
  }

  projected_runs <- nrow(plan$data) * plan$runtime$repeats
  preview <- list(
    function_name = "trial_experiment",
    source_rows = nrow(plan$data),
    repeats = plan$runtime$repeats,
    projected_runs = as.integer(projected_runs),
    random = plan$runtime$random,
    stream = plan$runtime$stream,
    timeout = plan$runtime$timeout,
    parameter_names = names(plan$runtime$parameters),
    condition_names = condition_names,
    resolved = resolved_identity
  )

  experiment_plan_review_result(length(errors) == 0L, errors, plan, preview)
}

approve_experiment_plan <- function(review, approved, note = NULL) {
  if (!inherits(review, "psylingllm_experiment_review") ||
      !isTRUE(review$valid)) {
    experiment_spec_abort(
      "Only a valid reviewed Experiment Spec can be approved.",
      reason = "invalid_experiment_review"
    )
  }
  if (!is.logical(approved) || length(approved) != 1L || is.na(approved)) {
    experiment_spec_abort(
      "approved must be one non-missing logical value.",
      reason = "invalid_approval"
    )
  }
  if (!is.null(note) &&
      (!is.character(note) || length(note) != 1L || is.na(note) ||
       !nzchar(trimws(note)))) {
    experiment_spec_abort(
      "note must be NULL or one non-empty string.",
      reason = "invalid_approval_note"
    )
  }

  structure(
    list(approved = approved, note = note, review = review),
    class = c("psylingllm_experiment_approval", "list")
  )
}

experiment_plan_review_result <- function(valid, errors, plan, preview) {
  structure(
    list(
      valid = isTRUE(valid),
      errors = errors,
      plan = plan,
      preview = preview
    ),
    class = c("psylingllm_experiment_review", "list")
  )
}
