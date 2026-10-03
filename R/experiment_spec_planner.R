experiment_planner_rules <- function() {
  c(
    "exact_material_fidelity",
    "deterministic_local_validation",
    "explicit_human_approval",
    "no_secrets"
  )
}

experiment_planner_system_prompt <- function(version = 1L) {
  schema <- experiment_spec_schema_json(version)
  paste(
    "You are the planning component for the PsyLingLLM R package.",
    "PsyLingLLM runs controlled psychological, psycholinguistic, cognitive,",
    "and educational experiments with large language models.",
    "The toolbox includes trial_experiment(), factorial_trial_experiment(),",
    "conversation_experiment(), adaptive_feedback_experiment(), and",
    "multi_model_experiment(). Experiment Spec v1 may compile only an ordinary",
    "trial_experiment(); never claim that another experiment type is supported",
    "by this schema.",
    "Models and interfaces are selected through Registry v2. Use the requested",
    "model_key, generation_interface, and provider-native parameters exactly.",
    "Never invent, rename, map, or repair provider parameters.",
    "Never request or return an API key, API URL, authorization header, output",
    "path, executable R code, arbitrary function name, or experiment result.",
    "Preserve every submitted material string exactly and in the same order.",
    "Do not translate, correct, normalize, paraphrase, or silently omit material.",
    "JSON Schema is only a structural boundary. PsyLingLLM performs deterministic",
    "local semantic validation, Registry resolution, material-fidelity review,",
    "execution preview, and explicit human approval before compilation.",
    "For onboarding: Return exactly one JSON object using the acknowledgement",
    "contract in the user message. For planning, return exactly one JSON object",
    "that conforms to the following JSON Schema. Do not use Markdown fences or",
    "include prose before or after the JSON object.",
    "Experiment Spec v1 JSON Schema:",
    schema,
    sep = "\n"
  )
}

experiment_planner_onboarding_prompt <- function() {
  rules <- paste(experiment_planner_rules(), collapse = ", ")
  paste(
    "Read and understand the complete PsyLingLLM toolbox contract and",
    "Experiment Spec v1 schema in the system message.",
    "Return exactly one JSON object with this shape:",
    '{"status":"understood","toolbox":"PsyLingLLM","schema_version":1,',
    paste0('"rules_acknowledged":["', gsub(", ", '\",\"', rules), '"]}'),
    "The array must contain every rule exactly once and in the shown order.",
    sep = "\n"
  )
}

experiment_planner_material_prompt <- function(requirements, source_materials) {
  assert_experiment_planner_text(requirements, "requirements")
  assert_experiment_planner_materials(source_materials)
  materials_json <- jsonlite::toJSON(
    unname(as.list(source_materials)),
    auto_unbox = TRUE,
    null = "null",
    pretty = TRUE
  )
  paste(
    "Create one Experiment Spec v1 JSON object from the requirements and exact",
    "source materials below. Preserve every source string byte-for-byte and in",
    "the same order. Return JSON only.",
    "Requirements:",
    requirements,
    "Exact source materials (JSON array):",
    materials_json,
    sep = "\n"
  )
}

prepare_experiment_planner_call <- function(
    model_key,
    generation_interface = NULL,
    turn = c("onboarding", "spec"),
    requirements = NULL,
    source_materials = NULL,
    acknowledgement = NULL,
    parameters = list(),
    timeout = 120L,
    registry = NULL) {
  turn <- match.arg(turn)
  config <- resolve_registry_entry(
    model_key,
    generation_interface = generation_interface,
    registry = registry
  )
  structured <- build_structured_output_parameters(
    config,
    mode = "json_object"
  )
  optionals <- merge_experiment_planner_parameters(
    parameters,
    structured$parameters
  )
  if (!is.numeric(timeout) || length(timeout) != 1L || is.na(timeout) ||
      !is.finite(timeout) || timeout != as.integer(timeout) ||
      timeout < 1L || timeout > 600L) {
    experiment_spec_abort(
      "Planner timeout must be an integer from 1 through 600.",
      reason = "invalid_planner_timeout"
    )
  }

  if (identical(turn, "onboarding")) {
    material <- experiment_planner_onboarding_prompt()
    history <- NULL
  } else {
    material <- experiment_planner_material_prompt(
      requirements,
      source_materials
    )
    acknowledgement <- assert_experiment_planner_acknowledgement_text(
      acknowledgement
    )
    history <- list(
      list(role = "user", content = experiment_planner_onboarding_prompt()),
      list(role = "assistant", content = acknowledgement)
    )
  }

  arguments <- list(
    model_key = model_key,
    generation_interface = config$interface$id,
    system_content = experiment_planner_system_prompt(),
    material = material,
    optionals = optionals,
    stream = FALSE,
    timeout = as.integer(timeout)
  )
  if (!is.null(history)) {
    arguments$assistant_content <- history
  }

  structure(
    list(
      function_name = "llm_caller",
      arguments = arguments,
      turn = turn,
      structured_output = list(
        mode = structured$mode,
        adapter = structured$adapter
      ),
      resolved = list(
        model_key = config$model$key,
        model_id = config$model$id,
        provider_id = config$provider$id,
        interface_id = config$interface$id,
        protocol = config$interface$protocol
      )
    ),
    class = c("psylingllm_experiment_planner_call", "list")
  )
}

merge_experiment_planner_parameters <- function(parameters, structured) {
  valid_parameters <- is.list(parameters) &&
    (length(parameters) == 0L ||
      (!is.null(names(parameters)) && !anyNA(names(parameters)) &&
        all(nzchar(names(parameters))) && !anyDuplicated(names(parameters))))
  if (!valid_parameters) {
    experiment_spec_abort(
      "Planner parameters must be a named list with unique non-empty names.",
      reason = "invalid_planner_parameters"
    )
  }
  serializable <- tryCatch(
    {
      jsonlite::toJSON(parameters, auto_unbox = TRUE, null = "null")
      TRUE
    },
    error = function(error) FALSE
  )
  if (!serializable) {
    experiment_spec_abort(
      "Planner parameters must contain only JSON-serializable values.",
      reason = "invalid_planner_parameters"
    )
  }
  collisions <- intersect(names(parameters), names(structured))
  if (length(collisions)) {
    experiment_spec_abort(
      paste(
        "Planner parameters must not override Registry structured-output fields:",
        paste(collisions, collapse = ", ")
      ),
      reason = "structured_output_parameter_collision"
    )
  }
  c(parameters, structured)
}

assert_experiment_planner_text <- function(value, field) {
  if (!is.character(value) || length(value) != 1L || is.na(value) ||
      !nzchar(trimws(value))) {
    experiment_spec_abort(
      sprintf("%s must be one non-empty string.", field),
      reason = paste0("invalid_", field)
    )
  }
  invisible(value)
}

assert_experiment_planner_materials <- function(source_materials) {
  if (!is.character(source_materials) || length(source_materials) == 0L ||
      anyNA(source_materials) || any(!nzchar(trimws(source_materials)))) {
    experiment_spec_abort(
      "source_materials must be a non-empty vector of non-empty strings.",
      reason = "invalid_source_materials"
    )
  }
  invisible(source_materials)
}

assert_experiment_planner_acknowledgement_text <- function(value) {
  assert_experiment_planner_text(value, "acknowledgement")
  validation <- validate_experiment_planner_acknowledgement(value)
  if (!isTRUE(validation$valid)) {
    experiment_spec_abort(
      paste(
        "Planner acknowledgement is invalid:",
        paste(validation$errors, collapse = "; ")
      ),
      reason = "invalid_planner_acknowledgement"
    )
  }
  value
}

validate_experiment_planner_acknowledgement <- function(value) {
  object <- tryCatch(
    if (is.character(value)) parse_experiment_spec(value) else value,
    error = function(error) error
  )
  errors <- character()
  if (inherits(object, "error") || !is.list(object) ||
      is.null(names(object)) || anyDuplicated(names(object))) {
    errors <- c(errors, "Acknowledgement must be exactly one JSON object.")
  } else {
    expected_fields <- c(
      "status", "toolbox", "schema_version", "rules_acknowledged"
    )
    if (!identical(names(object), expected_fields)) {
      errors <- c(errors, "Acknowledgement fields or field order are invalid.")
    }
    if (!identical(object$status, "understood")) {
      errors <- c(errors, "status must be `understood`.")
    }
    if (!identical(object$toolbox, "PsyLingLLM")) {
      errors <- c(errors, "toolbox must be `PsyLingLLM`.")
    }
    if (!is.numeric(object$schema_version) ||
        !identical(as.integer(object$schema_version), 1L)) {
      errors <- c(errors, "schema_version must be 1.")
    }
    acknowledged <- unlist(object$rules_acknowledged, use.names = FALSE)
    if (!identical(acknowledged, experiment_planner_rules())) {
      errors <- c(errors, "rules_acknowledged is incomplete or out of order.")
    }
  }
  structure(
    list(valid = length(errors) == 0L, errors = errors, acknowledgement = object),
    class = c("psylingllm_planner_acknowledgement_validation", "list")
  )
}
