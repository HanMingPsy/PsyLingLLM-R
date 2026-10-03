compile_experiment_plan <- function(approval) {
  if (!inherits(approval, "psylingllm_experiment_approval") ||
      !identical(approval$approved, TRUE)) {
    experiment_spec_abort(
      "Only an explicitly approved Experiment Spec can be compiled.",
      reason = "experiment_not_approved"
    )
  }

  review <- approval$review
  if (!inherits(review, "psylingllm_experiment_review") ||
      !isTRUE(review$valid)) {
    experiment_spec_abort(
      "The approval does not contain a valid experiment review.",
      reason = "invalid_experiment_review"
    )
  }

  plan <- review$plan
  canonical_plan <- tryCatch(
    normalize_experiment_spec(plan$source_spec),
    error = function(error) error
  )
  if (inherits(canonical_plan, "error") || !identical(plan, canonical_plan)) {
    experiment_spec_abort(
      "The approved plan no longer matches its validated source spec.",
      reason = "plan_integrity_failure"
    )
  }

  preview <- review$preview
  condition_names <- setdiff(
    names(plan$data),
    c("Item", "Material", "TrialPrompt")
  )
  expected_preview <- list(
    function_name = "trial_experiment",
    source_rows = nrow(plan$data),
    repeats = plan$runtime$repeats,
    projected_runs = as.integer(nrow(plan$data) * plan$runtime$repeats),
    random = plan$runtime$random,
    stream = plan$runtime$stream,
    timeout = plan$runtime$timeout,
    parameter_names = names(plan$runtime$parameters),
    condition_names = condition_names
  )
  preview_matches <- is.list(preview) && all(vapply(
    names(expected_preview),
    function(name) identical(preview[[name]], expected_preview[[name]]),
    logical(1)
  ))
  resolved_fields <- c(
    "model_key", "model_id", "provider_id", "interface_id", "protocol"
  )
  resolved_identity <- if (is.list(preview)) preview$resolved else NULL
  resolved_matches <- is.list(resolved_identity) &&
    all(resolved_fields %in% names(resolved_identity)) &&
    all(vapply(
      resolved_identity[resolved_fields],
      function(value) {
        is.character(value) && length(value) == 1L && !is.na(value) &&
          nzchar(value)
      },
      logical(1)
    ))
  if (!preview_matches || !resolved_matches) {
    experiment_spec_abort(
      "The approved review preview is incomplete or has been modified.",
      reason = "review_integrity_failure"
    )
  }

  optionals <- if (identical(plan$runtime$parameter_policy, "none")) {
    NULL
  } else {
    plan$runtime$parameters
  }
  arguments <- list(
    model_key = plan$runtime$model_key,
    generation_interface = plan$runtime$generation_interface,
    data = plan$data,
    trial_prompt = plan$task$trial_prompt,
    system_content = plan$runtime$system_content,
    optionals = optionals,
    stream = plan$runtime$stream,
    timeout = plan$runtime$timeout,
    repeats = plan$runtime$repeats,
    random = plan$runtime$random,
    delay = 0
  )

  unknown_arguments <- setdiff(
    names(arguments),
    names(formals(trial_experiment))
  )
  if (length(unknown_arguments)) {
    experiment_spec_abort(
      paste(
        "The compiler produced unsupported trial_experiment() argument(s):",
        paste(unknown_arguments, collapse = ", ")
      ),
      reason = "compiler_contract_failure"
    )
  }

  structure(
    list(
      call_contract_version = 1L,
      function_name = "trial_experiment",
      arguments = arguments,
      resolved = resolved_identity,
      runtime_requirements = list(
        required = "api_key",
        optional = c(
          "api_url", "output_path", "overwrite", "return_raw"
        )
      )
    ),
    class = c("psylingllm_experiment_call", "list")
  )
}
