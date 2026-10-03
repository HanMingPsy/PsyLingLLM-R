nl_allow_json_mode_advisory <- function(expr) {
  withCallingHandlers(
    force(expr),
    warning = function(warning) {
      message <- conditionMessage(warning)
      if (grepl("response_format", message, fixed = TRUE) &&
          grepl("will be sent unchanged", message, fixed = TRUE)) {
        invokeRestart("muffleWarning")
      }
    }
  )
}

nl_acknowledgement_schema <- function() {
  list(
    `$schema` = "https://json-schema.org/draft/2020-12/schema",
    type = "object",
    additionalProperties = FALSE,
    required = c("status", "toolbox", "rules_acknowledged"),
    properties = list(
      status = list(type = "string", enum = list("understood")),
      toolbox = list(type = "string", enum = list("PsyLingLLM")),
      rules_acknowledged = list(
        type = "array",
        items = list(
          type = "string",
          enum = c(
            "structured_materials",
            "deterministic_validation",
            "human_approval",
            "no_secrets"
          )
        ),
        minItems = 4L,
        maxItems = 4L
      )
    )
  )
}

nl_trial_plan_schema <- function() {
  scalar_condition <- list(
    anyOf = list(
      list(type = "string"),
      list(type = "number"),
      list(type = "boolean")
    )
  )
  list(
    `$schema` = "https://json-schema.org/draft/2020-12/schema",
    type = "object",
    additionalProperties = FALSE,
    required = c("status", "document", "experiment"),
    properties = list(
      status = list(type = "string", enum = list("ready")),
      document = list(
        type = "object",
        additionalProperties = FALSE,
        required = c("schema_version", "experiment_type", "task", "rows"),
        properties = list(
          schema_version = list(type = "integer", enum = list(1L)),
          experiment_type = list(type = "string", enum = list("trial")),
          task = list(
            type = "object",
            additionalProperties = FALSE,
            required = list("trial_prompt"),
            properties = list(
              trial_prompt = list(type = "string", minLength = 1L)
            )
          ),
          rows = list(
            type = "array",
            minItems = 1L,
            items = list(
              type = "object",
              additionalProperties = FALSE,
              required = c("item", "material", "conditions"),
              properties = list(
                item = list(type = "integer", minimum = 1L),
                material = list(type = "string", minLength = 1L),
                conditions = list(
                  type = "object",
                  minProperties = 1L,
                  additionalProperties = scalar_condition
                ),
                trial_prompt = list(type = c("string", "null"))
              )
            )
          )
        )
      ),
      experiment = list(
        type = "object",
        additionalProperties = FALSE,
        required = c(
          "spec_version", "type", "model_key", "generation_interface",
          "system_content", "repeats", "random", "stream", "timeout",
          "parameter_policy", "parameters"
        ),
        properties = list(
          spec_version = list(type = "integer", enum = list(1L)),
          type = list(type = "string", enum = list("trial")),
          model_key = list(type = "string", minLength = 1L),
          generation_interface = list(type = "string", minLength = 1L),
          system_content = list(type = "string", minLength = 1L),
          repeats = list(type = "integer", minimum = 1L, maximum = 10L),
          random = list(type = "boolean"),
          stream = list(type = "boolean"),
          timeout = list(type = "integer", minimum = 1L, maximum = 600L),
          parameter_policy = list(
            type = "string",
            enum = c("explicit", "none")
          ),
          parameters = list(type = "object")
        )
      )
    )
  )
}

nl_psylingllm_toolbox_prompt <- function() {
  acknowledgement_schema <- jsonlite::toJSON(
    nl_acknowledgement_schema(),
    auto_unbox = TRUE,
    pretty = TRUE
  )
  trial_plan_schema <- jsonlite::toJSON(
    nl_trial_plan_schema(),
    auto_unbox = TRUE,
    pretty = TRUE
  )
  paste(
    "You are the PsyLingLLM experiment planning assistant.",
    "PsyLingLLM is an R package for controlled LLM experiments.",
    "You describe a validated experiment plan; PsyLingLLM executes it.",
    "Never write or execute R code, call an API, invent results, or expose secrets.",
    "Return exactly one JSON object without Markdown or explanatory text.",
    "Do not rewrite user-supplied materials unless explicitly requested.",
    "",
    "Toolbox model:",
    "Registry v2 separates model, provider, interface, and capability.",
    "Provider-native parameter names and nested values must remain unchanged.",
    "llm_caller() resolves, builds, sends, parses, and normalizes one request.",
    "generate_llm_experiment_list() and trial_experiment() run ordinary trials.",
    "generate_llm_factorial_experiment_list() and factorial_trial_experiment()",
    "run factorial designs. conversation_experiment() runs ordered turns,",
    "conversation_experiment_with_feedback() adds feedback, and",
    "multi_model_experiment() compares models.",
    "",
    "Input schemas:",
    "Trial rows require Item and Material; TrialPrompt and condition columns are optional.",
    "Factorial inputs combine base materials with named factor definitions locally.",
    "Conversation rows require ConversationId, Turn, and Material; TrialPrompt is optional.",
    "Run is generated locally and must never be supplied by the planner.",
    "Experiment outputs include Response, Think, timing, token usage, TrialStatus,",
    "ResponseStatus, Streaming, Timestamp, and RequestID.",
    "",
    "For the first onboarding turn, return exactly this shape:",
    '{"status":"understood","toolbox":"PsyLingLLM","rules_acknowledged":["structured_materials","deterministic_validation","human_approval","no_secrets"]}',
    "",
    "For a compile request, this simulation supports ordinary trial experiments only.",
    "Return this envelope:",
    '{"status":"ready","document":{...},"experiment":{...}}',
    "",
    "document must contain:",
    "schema_version: integer 1",
    'experiment_type: string "trial"',
    "task: object with one non-empty string field named trial_prompt",
    "rows: a non-empty array of row objects",
    "Each row requires a unique positive integer item, a non-empty material string",
    "copied exactly from the user, and a conditions object with consistently named",
    "scalar values. A row may contain a non-empty trial_prompt or JSON null.",
    "",
    "experiment must contain:",
    "spec_version: integer 1",
    'type: string "trial"',
    "model_key: non-empty PsyLingLLM Registry model key",
    "generation_interface: non-empty interface label",
    "system_content: non-empty participant instruction",
    "repeats: positive integer no greater than 10",
    "random: boolean",
    "stream: boolean",
    "timeout: integer seconds from 1 through 600",
    'parameter_policy: string "explicit" or "none"',
    "parameters: named object of provider-native parameters when policy is explicit,",
    "or an empty object when policy is none.",
    "",
    "Never include Run, Response, Think, ModelName, results, an API key, an API URL,",
    "an output path, arbitrary function names, or executable code. Structural request",
    "fields model, messages, input, and system cannot be provider parameters.",
    "Human approval and deterministic local validation are required before execution.",
    "",
    "The authoritative onboarding JSON Schema is:",
    acknowledgement_schema,
    "",
    "The authoritative trial-plan JSON Schema is:",
    trial_plan_schema,
    sep = "\n"
  )
}

nl_extract_json_object <- function(text) {
  if (!is.character(text) || length(text) != 1L || is.na(text) ||
      !nzchar(trimws(text))) {
    stop("Planner response must be one non-empty character string.")
  }

  start <- regexpr("{", text, fixed = TRUE)[[1L]]
  ends <- gregexpr("}", text, fixed = TRUE)[[1L]]
  if (start < 1L || identical(ends, -1L)) {
    stop("Planner response does not contain a JSON object.")
  }
  json <- substr(text, start, max(ends))
  tryCatch(
    jsonlite::fromJSON(json, simplifyVector = FALSE),
    error = function(error) {
      stop("Planner response contains invalid JSON: ", conditionMessage(error))
    }
  )
}

nl_validate_toolbox_acknowledgement <- function(envelope) {
  required_rules <- c(
    "structured_materials",
    "deterministic_validation",
    "human_approval",
    "no_secrets"
  )
  is_valid <- is.list(envelope) &&
    identical(envelope$status, "understood") &&
    identical(envelope$toolbox, "PsyLingLLM") &&
    is.list(envelope$rules_acknowledged) &&
    setequal(unlist(envelope$rules_acknowledged), required_rules)

  list(
    valid = isTRUE(is_valid),
    errors = if (isTRUE(is_valid)) {
      list()
    } else {
      list(list(
        code = "invalid_toolbox_acknowledgement",
        path = "$",
        message = "The planner did not acknowledge the required toolbox rules."
      ))
    }
  )
}

nl_validate_material_document <- function(envelope) {
  errors <- list()
  add_error <- function(code, path, message) {
    errors[[length(errors) + 1L]] <<- list(
      code = code,
      path = path,
      message = message
    )
  }
  scalar_text <- function(value) {
    is.character(value) && length(value) == 1L && !is.na(value) &&
      nzchar(trimws(value))
  }
  scalar_condition <- function(value) {
    (is.character(value) || is.numeric(value) || is.logical(value)) &&
      length(value) == 1L && !is.na(value)
  }

  if (!is.list(envelope)) {
    add_error("invalid_envelope", "$", "Envelope must be a JSON object.")
    return(list(valid = FALSE, errors = errors))
  }
  if (!identical(envelope$status, "ready")) {
    add_error(
      "planner_not_ready",
      "$.status",
      "Planner status must be `ready` before materials can be compiled."
    )
  }

  document <- envelope$document
  if (!is.list(document)) {
    add_error("missing_document", "$.document", "Document must be an object.")
    return(list(valid = FALSE, errors = errors))
  }
  if (!identical(as.integer(document$schema_version), 1L)) {
    add_error(
      "unsupported_schema_version",
      "$.document.schema_version",
      "Only material schema version 1 is supported by this simulation."
    )
  }
  if (!identical(document$experiment_type, "trial")) {
    add_error(
      "unsupported_experiment_type",
      "$.document.experiment_type",
      "Only ordinary trial materials are supported by this simulation."
    )
  }
  if (!is.list(document$task) ||
      !scalar_text(document$task$trial_prompt)) {
    add_error(
      "invalid_trial_prompt",
      "$.document.task.trial_prompt",
      "A non-empty trial_prompt is required."
    )
  }

  rows <- document$rows
  if (!is.list(rows) || length(rows) == 0L) {
    add_error("missing_rows", "$.document.rows", "Rows must be a non-empty array.")
    return(list(valid = FALSE, errors = errors))
  }

  allowed_row_fields <- c("item", "material", "conditions", "trial_prompt")
  forbidden_fields <- c(
    "run", "response", "think", "modelname", "api_key", "api_url",
    "optionals", "parameters"
  )
  item_values <- integer(length(rows))
  expected_condition_names <- NULL

  for (index in seq_along(rows)) {
    row <- rows[[index]]
    path <- paste0("$.document.rows[", index, "]")
    if (!is.list(row) || is.null(names(row))) {
      add_error("invalid_row", path, "Each row must be a named object.")
      next
    }
    unknown <- setdiff(names(row), allowed_row_fields)
    if (length(unknown)) {
      code <- if (any(tolower(unknown) %in% forbidden_fields)) {
        "forbidden_material_field"
      } else {
        "unknown_material_field"
      }
      add_error(
        code,
        path,
        paste("Unsupported row field(s):", paste(unknown, collapse = ", "))
      )
    }

    item <- suppressWarnings(as.integer(row$item))
    if (length(item) != 1L || is.na(item) || item < 1L ||
        !identical(as.numeric(item), as.numeric(row$item))) {
      add_error("invalid_item", paste0(path, ".item"), "Item must be a positive integer.")
    } else {
      item_values[[index]] <- item
    }
    if (!scalar_text(row$material)) {
      add_error(
        "invalid_material",
        paste0(path, ".material"),
        "Material must be a non-empty string."
      )
    }
    if (!is.null(row$trial_prompt) && !scalar_text(row$trial_prompt)) {
      add_error(
        "invalid_row_prompt",
        paste0(path, ".trial_prompt"),
        "Row trial_prompt must be null or a non-empty string."
      )
    }

    conditions <- row$conditions
    if (!is.list(conditions) || is.null(names(conditions)) ||
        any(!nzchar(names(conditions))) || anyDuplicated(names(conditions))) {
      add_error(
        "invalid_conditions",
        paste0(path, ".conditions"),
        "Conditions must be an object with unique, non-empty names."
      )
      next
    }
    if (!all(vapply(conditions, scalar_condition, logical(1)))) {
      add_error(
        "invalid_condition_value",
        paste0(path, ".conditions"),
        "Condition values must be non-missing character, numeric, or logical scalars."
      )
    }
    condition_names <- sort(names(conditions))
    if (is.null(expected_condition_names)) {
      expected_condition_names <- condition_names
    } else if (!identical(condition_names, expected_condition_names)) {
      add_error(
        "inconsistent_condition_fields",
        paste0(path, ".conditions"),
        "Every row must use the same condition fields."
      )
    }
  }

  valid_items <- item_values[item_values > 0L]
  if (anyDuplicated(valid_items)) {
    add_error("duplicate_item", "$.document.rows", "Item values must be unique.")
  }

  list(valid = length(errors) == 0L, errors = errors)
}

nl_validate_experiment_spec <- function(experiment) {
  errors <- list()
  add_error <- function(code, path, message) {
    errors[[length(errors) + 1L]] <<- list(
      code = code,
      path = path,
      message = message
    )
  }
  scalar_text <- function(value) {
    is.character(value) && length(value) == 1L && !is.na(value) &&
      nzchar(trimws(value))
  }
  scalar_integer <- function(value, minimum, maximum) {
    is.numeric(value) && length(value) == 1L && !is.na(value) &&
      value == as.integer(value) && value >= minimum && value <= maximum
  }

  if (!is.list(experiment) || is.null(names(experiment))) {
    add_error("missing_experiment", "$.experiment", "Experiment must be an object.")
    return(list(valid = FALSE, errors = errors))
  }

  allowed_fields <- c(
    "spec_version", "type", "model_key", "generation_interface",
    "system_content", "repeats", "random", "stream", "timeout",
    "parameter_policy", "parameters"
  )
  unknown <- setdiff(names(experiment), allowed_fields)
  if (length(unknown)) {
    add_error(
      "unknown_experiment_field",
      "$.experiment",
      paste("Unsupported experiment field(s):", paste(unknown, collapse = ", "))
    )
  }
  if (!identical(as.integer(experiment$spec_version), 1L)) {
    add_error(
      "unsupported_spec_version",
      "$.experiment.spec_version",
      "Only experiment spec version 1 is supported by this simulation."
    )
  }
  if (!identical(experiment$type, "trial")) {
    add_error(
      "unsupported_experiment_type",
      "$.experiment.type",
      "Only trial_experiment() is supported by this simulation."
    )
  }
  for (field in c("model_key", "generation_interface", "system_content")) {
    if (!scalar_text(experiment[[field]])) {
      add_error(
        paste0("invalid_", field),
        paste0("$.experiment.", field),
        paste(field, "must be one non-empty string.")
      )
    }
  }
  if (!scalar_integer(experiment$repeats, 1L, 10L)) {
    add_error(
      "invalid_repeats",
      "$.experiment.repeats",
      "repeats must be an integer from 1 through 10."
    )
  }
  for (field in c("random", "stream")) {
    value <- experiment[[field]]
    if (!is.logical(value) || length(value) != 1L || is.na(value)) {
      add_error(
        paste0("invalid_", field),
        paste0("$.experiment.", field),
        paste(field, "must be one boolean value.")
      )
    }
  }
  if (!scalar_integer(experiment$timeout, 1L, 600L)) {
    add_error(
      "invalid_timeout",
      "$.experiment.timeout",
      "timeout must be an integer from 1 through 600 seconds."
    )
  }

  policy <- experiment$parameter_policy
  if (!is.character(policy) || length(policy) != 1L ||
      !(policy %in% c("explicit", "none"))) {
    add_error(
      "invalid_parameter_policy",
      "$.experiment.parameter_policy",
      "parameter_policy must be `explicit` or `none`."
    )
  }
  parameters <- experiment$parameters
  if (!is.list(parameters) || is.null(names(parameters)) ||
      any(!nzchar(names(parameters))) || anyDuplicated(names(parameters))) {
    add_error(
      "invalid_parameters",
      "$.experiment.parameters",
      "parameters must be an object with unique, non-empty names."
    )
  } else {
    forbidden_parameters <- c(
      "model", "messages", "input", "system", "api_key", "api_url",
      "output_path"
    )
    forbidden <- intersect(names(parameters), forbidden_parameters)
    if (length(forbidden)) {
      add_error(
        "forbidden_parameter",
        "$.experiment.parameters",
        paste("Structural or secret field(s) are forbidden:", paste(forbidden, collapse = ", "))
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
      add_error(
        "unserializable_parameters",
        "$.experiment.parameters",
        "parameters must be JSON-serializable."
      )
    }
  }
  if (identical(policy, "none") && length(parameters) > 0L) {
    add_error(
      "unexpected_parameters",
      "$.experiment.parameters",
      "parameters must be empty when parameter_policy is `none`."
    )
  }

  list(valid = length(errors) == 0L, errors = errors)
}

nl_normalize_material_document <- function(envelope) {
  validation <- nl_validate_material_document(envelope)
  if (!validation$valid) {
    messages <- vapply(
      validation$errors,
      function(error) paste0(error$path, ": ", error$message),
      character(1)
    )
    stop("Invalid PsyLingLLM material document: ", paste(messages, collapse = "; "))
  }

  document <- envelope$document
  rows <- document$rows
  condition_names <- names(rows[[1L]]$conditions)
  result <- data.frame(
    Item = vapply(rows, function(row) as.integer(row$item), integer(1)),
    stringsAsFactors = FALSE
  )
  for (name in condition_names) {
    result[[name]] <- vapply(
      rows,
      function(row) as.character(row$conditions[[name]]),
      character(1)
    )
  }
  result$Material <- vapply(rows, function(row) row$material, character(1))
  default_prompt <- document$task$trial_prompt
  result$TrialPrompt <- vapply(
    rows,
    function(row) row$trial_prompt %||% default_prompt,
    character(1)
  )
  result
}

nl_prepare_experiment <- function(planner_text) {
  envelope <- nl_extract_json_object(planner_text)
  material_validation <- nl_validate_material_document(envelope)
  experiment_validation <- nl_validate_experiment_spec(envelope$experiment)
  errors <- c(material_validation$errors, experiment_validation$errors)
  valid <- length(errors) == 0L

  list(
    valid = valid,
    errors = errors,
    envelope = envelope,
    data = if (valid) nl_normalize_material_document(envelope) else NULL,
    experiment = if (valid) envelope$experiment else NULL
  )
}

nl_try_prepare_experiment <- function(planner_text) {
  tryCatch(
    nl_prepare_experiment(planner_text),
    error = function(error) {
      list(
        valid = FALSE,
        errors = list(list(
          code = "invalid_planner_json",
          path = "$",
          message = conditionMessage(error)
        )),
        envelope = NULL,
        data = NULL,
        experiment = NULL
      )
    }
  )
}

nl_validation_feedback <- function(prepared) {
  if (is.list(prepared) && isTRUE(prepared$valid)) {
    return(NULL)
  }
  errors <- if (is.list(prepared)) prepared$errors else list()
  error_payload <- lapply(errors, function(error) {
    list(code = error$code, path = error$path, message = error$message)
  })
  paste(
    "The previous JSON plan was rejected by deterministic local validation.",
    "Correct only the listed errors. Preserve the source materials exactly.",
    "Return one complete corrected JSON object and no other text.",
    jsonlite::toJSON(error_payload, auto_unbox = TRUE, pretty = TRUE),
    sep = "\n"
  )
}

nl_review_experiment <- function(
    prepared,
    source_materials,
    required_condition_names
) {
  errors <- if (is.list(prepared)) prepared$errors else list()
  add_error <- function(code, path, message) {
    errors[[length(errors) + 1L]] <<- list(
      code = code,
      path = path,
      message = message
    )
  }

  if (!is.list(prepared) || !isTRUE(prepared$valid)) {
    add_error(
      "plan_not_validated",
      "$",
      "The plan must pass structural validation before review."
    )
    return(list(valid = FALSE, errors = errors, prepared = prepared))
  }
  if (!is.character(source_materials) || anyNA(source_materials)) {
    add_error(
      "invalid_source_materials",
      "$.review.source_materials",
      "Source materials must be a non-missing character vector."
    )
  } else if (!identical(prepared$data$Material, source_materials)) {
    add_error(
      "material_fidelity_failure",
      "$.document.rows",
      "Planned materials differ from the submitted materials or their order."
    )
  }

  fixed_columns <- c("Item", "Material", "TrialPrompt")
  actual_condition_names <- setdiff(names(prepared$data), fixed_columns)
  if (!setequal(actual_condition_names, required_condition_names)) {
    add_error(
      "condition_schema_mismatch",
      "$.document.rows[*].conditions",
      paste(
        "Condition fields must be exactly:",
        paste(required_condition_names, collapse = ", ")
      )
    )
  }

  spec <- prepared$experiment
  projected_runs <- nrow(prepared$data) * as.integer(spec$repeats)
  max_tokens <- spec$parameters$max_tokens %||%
    spec$parameters$max_output_tokens %||%
    NA_integer_
  token_ceiling <- if (length(max_tokens) == 1L && is.numeric(max_tokens)) {
    projected_runs * as.numeric(max_tokens)
  } else {
    NA_real_
  }

  list(
    valid = length(errors) == 0L,
    errors = errors,
    prepared = prepared,
    preview = list(
      function_name = "trial_experiment",
      model_key = spec$model_key,
      generation_interface = spec$generation_interface,
      source_rows = nrow(prepared$data),
      repeats = as.integer(spec$repeats),
      projected_runs = projected_runs,
      random = spec$random,
      stream = spec$stream,
      timeout = as.integer(spec$timeout),
      parameter_names = names(spec$parameters),
      maximum_completion_token_ceiling = token_ceiling,
      condition_names = actual_condition_names
    )
  )
}

nl_approve_experiment <- function(review, approved, note = NULL) {
  if (!is.list(review) || !isTRUE(review$valid)) {
    stop("Only a valid reviewed plan can be approved.")
  }
  if (!is.logical(approved) || length(approved) != 1L || is.na(approved)) {
    stop("approved must be one non-missing logical value.")
  }
  list(
    approved = approved,
    note = note,
    review = review
  )
}

nl_compile_trial_call <- function(approval, api_key, output_path) {
  if (!is.list(approval) || !isTRUE(approval$approved) ||
      !isTRUE(approval$review$valid)) {
    stop("Only a validated PsyLingLLM experiment plan can be compiled.")
  }
  if (!is.character(api_key) || length(api_key) != 1L || !nzchar(api_key)) {
    stop("A non-empty local API key is required at execution time.")
  }
  prepared <- approval$review$prepared
  spec <- prepared$experiment
  optionals <- if (identical(spec$parameter_policy, "none")) {
    NULL
  } else {
    spec$parameters
  }

  list(
    function_name = "trial_experiment",
    arguments = list(
      model_key = spec$model_key,
      generation_interface = spec$generation_interface,
      api_key = api_key,
      data = prepared$data,
      system_content = spec$system_content,
      optionals = optionals,
      stream = spec$stream,
      timeout = as.integer(spec$timeout),
      repeats = as.integer(spec$repeats),
      random = spec$random,
      delay = 0,
      output_path = output_path,
      overwrite = TRUE
    )
  )
}

nl_validate_execution_result <- function(approval, result, api_key) {
  errors <- list()
  add_error <- function(code, path, message) {
    errors[[length(errors) + 1L]] <<- list(
      code = code,
      path = path,
      message = message
    )
  }
  if (!is.list(approval) || !isTRUE(approval$approved)) {
    add_error("missing_approval", "$.approval", "Execution was not approved.")
    return(list(valid = FALSE, errors = errors, summary = NULL))
  }
  required_columns <- c(
    "Material", "Response", "Think", "ModelName", "TotalResponseTime",
    "PromptTokens", "CompletionTokens", "TrialStatus", "ResponseStatus",
    "Streaming", "Timestamp", "RequestID"
  )
  missing_columns <- setdiff(required_columns, names(result))
  if (length(missing_columns)) {
    add_error(
      "missing_result_columns",
      "$.result",
      paste("Missing result column(s):", paste(missing_columns, collapse = ", "))
    )
  }
  expected_runs <- approval$review$preview$projected_runs
  if (!is.data.frame(result) || nrow(result) != expected_runs) {
    add_error(
      "unexpected_result_rows",
      "$.result",
      paste("Expected", expected_runs, "result rows.")
    )
  }
  if (all(c("TrialStatus", "ResponseStatus") %in% names(result))) {
    if (!all(result$TrialStatus == "SUCCESS")) {
      add_error("trial_failure", "$.result.TrialStatus", "At least one trial failed.")
    }
    if (!all(result$ResponseStatus == "OK")) {
      add_error(
        "response_failure",
        "$.result.ResponseStatus",
        "At least one response was not OK."
      )
    }
  }
  if ("Response" %in% names(result) &&
      any(is.na(result$Response) | !nzchar(trimws(result$Response)))) {
    add_error("empty_response", "$.result.Response", "At least one response is empty.")
  }
  serialized <- tryCatch(
    jsonlite::toJSON(result, auto_unbox = TRUE, null = "null"),
    error = function(error) ""
  )
  if (nzchar(api_key) && grepl(api_key, serialized, fixed = TRUE)) {
    add_error("secret_exposure", "$.result", "The API key appears in the result.")
  }

  list(
    valid = length(errors) == 0L,
    errors = errors,
    summary = list(
      planned_runs = expected_runs,
      completed_runs = if (is.data.frame(result)) nrow(result) else 0L,
      trial_status = if ("TrialStatus" %in% names(result)) {
        unname(table(result$TrialStatus))
      } else {
        integer()
      },
      response_status = if ("ResponseStatus" %in% names(result)) {
        unname(table(result$ResponseStatus))
      } else {
        integer()
      }
    )
  )
}

nl_execution_receipt <- function(
    approval,
    result,
    planner_request_ids = character()
) {
  review <- approval$review
  spec <- review$prepared$experiment
  list(
    workflow_version = 1L,
    material_schema_version = 1L,
    experiment_spec_version = as.integer(spec$spec_version),
    function_name = review$preview$function_name,
    model_key = spec$model_key,
    generation_interface = spec$generation_interface,
    planned_runs = review$preview$projected_runs,
    completed_runs = nrow(result),
    planner_request_ids = planner_request_ids[nzchar(planner_request_ids)],
    experiment_request_ids = unique(result$RequestID[!is.na(result$RequestID)]),
    trial_status = as.list(table(result$TrialStatus)),
    response_status = as.list(table(result$ResponseStatus))
  )
}
