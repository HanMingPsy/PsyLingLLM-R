parse_experiment_spec <- function(text) {
  if (!is.character(text) || length(text) != 1L || is.na(text) ||
      !nzchar(trimws(text))) {
    experiment_spec_abort(
      "Experiment Spec input must be one non-empty JSON string.",
      reason = "invalid_json_input"
    )
  }

  tryCatch(
    jsonlite::fromJSON(text, simplifyVector = FALSE),
    error = function(error) {
      experiment_spec_abort(
        paste("Experiment Spec contains invalid JSON:", conditionMessage(error)),
        reason = "invalid_json"
      )
    }
  )
}

validate_experiment_spec <- function(spec) {
  errors <- list()
  add_error <- function(code, path, message) {
    errors[[length(errors) + 1L]] <<- list(
      code = code,
      path = path,
      message = message
    )
  }
  scalar_text <- function(value, nullable = FALSE) {
    if (nullable && is.null(value)) {
      return(TRUE)
    }
    is.character(value) && length(value) == 1L && !is.na(value) &&
      nzchar(trimws(value))
  }
  scalar_logical <- function(value) {
    is.logical(value) && length(value) == 1L && !is.na(value)
  }
  scalar_integer <- function(value, minimum, maximum) {
    is.numeric(value) && length(value) == 1L && !is.na(value) &&
      is.finite(value) && value == as.integer(value) &&
      value >= minimum && value <= maximum
  }
  named_object <- function(value) {
    is.list(value) && !is.null(names(value)) && !anyNA(names(value)) &&
      all(nzchar(names(value))) && !anyDuplicated(names(value))
  }
  assert_fields <- function(value, required, allowed, path) {
    if (!named_object(value)) {
      add_error("invalid_object", path, "Expected an object with unique field names.")
      return(FALSE)
    }
    missing <- setdiff(required, names(value))
    unknown <- setdiff(names(value), allowed)
    if (length(missing)) {
      add_error(
        "missing_field",
        path,
        paste("Missing required field(s):", paste(missing, collapse = ", "))
      )
    }
    if (length(unknown)) {
      add_error(
        "unknown_field",
        path,
        paste("Unknown field(s):", paste(unknown, collapse = ", "))
      )
    }
    length(missing) == 0L
  }

  root_fields <- c(
    "schema_version", "experiment_type", "task", "materials", "runtime"
  )
  if (!assert_fields(spec, root_fields, root_fields, "$")) {
    return(experiment_spec_validation_result(FALSE, errors, spec))
  }
  if (!scalar_integer(spec$schema_version, 1L, 1L)) {
    add_error(
      "unsupported_schema_version",
      "$.schema_version",
      "Only Experiment Spec schema version 1 is supported."
    )
  }
  if (!identical(spec$experiment_type, "trial")) {
    add_error(
      "unsupported_experiment_type",
      "$.experiment_type",
      "Experiment Spec v1 supports only ordinary trial experiments."
    )
  }

  task_fields <- "trial_prompt"
  if (assert_fields(spec$task, task_fields, task_fields, "$.task") &&
      !scalar_text(spec$task$trial_prompt, nullable = TRUE)) {
    add_error(
      "invalid_trial_prompt",
      "$.task.trial_prompt",
      "trial_prompt must be null or one non-empty string."
    )
  }

  materials <- spec$materials
  if (!is.list(materials) || length(materials) == 0L) {
    add_error(
      "invalid_materials",
      "$.materials",
      "materials must be a non-empty array."
    )
  } else {
    item_values <- integer(length(materials))
    expected_condition_names <- NULL
    expected_condition_types <- NULL
    for (index in seq_along(materials)) {
      row <- materials[[index]]
      path <- sprintf("$.materials[%d]", index)
      row_required <- c("item", "material")
      row_allowed <- c(row_required, "conditions", "trial_prompt")
      if (!assert_fields(row, row_required, row_allowed, path)) {
        next
      }
      if (!scalar_integer(row$item, 1L, .Machine$integer.max)) {
        add_error("invalid_item", paste0(path, ".item"), "item must be a positive integer.")
      } else {
        item_values[[index]] <- as.integer(row$item)
      }
      if (!scalar_text(row$material)) {
        add_error(
          "invalid_material",
          paste0(path, ".material"),
          "material must be one non-empty string."
        )
      }
      if ("trial_prompt" %in% names(row) &&
          !scalar_text(row$trial_prompt, nullable = TRUE)) {
        add_error(
          "invalid_row_trial_prompt",
          paste0(path, ".trial_prompt"),
          "trial_prompt must be null or one non-empty string."
        )
      }
      conditions <- row$conditions
      if (is.null(conditions)) {
        condition_names <- character()
        condition_types <- character()
      } else if (!named_object(conditions)) {
        add_error(
          "invalid_conditions",
          paste0(path, ".conditions"),
          "conditions must be an object with unique field names."
        )
        condition_names <- character()
        condition_types <- character()
      } else {
        scalar_condition <- vapply(
          conditions,
          function(value) {
            if (length(value) != 1L || is.na(value)) {
              return(FALSE)
            }
            if (is.character(value) || is.logical(value)) {
              return(TRUE)
            }
            is.numeric(value) && is.finite(value)
          },
          logical(1)
        )
        if (!all(scalar_condition)) {
          add_error(
            "invalid_condition_value",
            paste0(path, ".conditions"),
            "Condition values must be non-missing scalar strings, numbers, or booleans."
          )
        }
        condition_names <- sort(names(conditions))
        condition_types <- vapply(
          conditions[condition_names],
          function(value) {
            if (is.character(value)) {
              return("string")
            }
            if (is.logical(value)) {
              return("boolean")
            }
            if (is.numeric(value)) {
              return("number")
            }
            "invalid"
          },
          character(1)
        )
      }
      if (is.null(expected_condition_names)) {
        expected_condition_names <- condition_names
        expected_condition_types <- condition_types
      } else if (!identical(condition_names, expected_condition_names)) {
        add_error(
          "inconsistent_condition_fields",
          paste0(path, ".conditions"),
          "Every material row must use the same condition fields."
        )
      } else if (!identical(condition_types, expected_condition_types)) {
        add_error(
          "inconsistent_condition_types",
          paste0(path, ".conditions"),
          "Every condition field must use one consistent scalar type."
        )
      }
    }
    valid_items <- item_values[item_values > 0L]
    if (anyDuplicated(valid_items)) {
      add_error("duplicate_item", "$.materials", "item values must be unique.")
    }
  }

  runtime_fields <- c(
    "model_key", "generation_interface", "system_content", "repeats",
    "random", "stream", "timeout", "parameter_policy", "parameters"
  )
  if (assert_fields(spec$runtime, runtime_fields, runtime_fields, "$.runtime")) {
    runtime <- spec$runtime
    for (field in c("model_key", "generation_interface")) {
      if (!scalar_text(runtime[[field]])) {
        add_error(
          paste0("invalid_", field),
          paste0("$.runtime.", field),
          paste(field, "must be one non-empty string.")
        )
      }
    }
    if (!scalar_text(runtime$system_content, nullable = TRUE)) {
      add_error(
        "invalid_system_content",
        "$.runtime.system_content",
        "system_content must be null or one non-empty string."
      )
    }
    if (!scalar_integer(runtime$repeats, 1L, 10L)) {
      add_error(
        "invalid_repeats",
        "$.runtime.repeats",
        "repeats must be an integer from 1 through 10."
      )
    }
    for (field in c("random", "stream")) {
      if (!scalar_logical(runtime[[field]])) {
        add_error(
          paste0("invalid_", field),
          paste0("$.runtime.", field),
          paste(field, "must be one boolean value.")
        )
      }
    }
    if (!scalar_integer(runtime$timeout, 1L, 600L)) {
      add_error(
        "invalid_timeout",
        "$.runtime.timeout",
        "timeout must be an integer from 1 through 600."
      )
    }
    if (!is.character(runtime$parameter_policy) ||
        length(runtime$parameter_policy) != 1L ||
        !(runtime$parameter_policy %in% c("explicit", "none"))) {
      add_error(
        "invalid_parameter_policy",
        "$.runtime.parameter_policy",
        "parameter_policy must be `explicit` or `none`."
      )
    }
    parameters <- runtime$parameters
    if (!named_object(parameters)) {
      add_error(
        "invalid_parameters",
        "$.runtime.parameters",
        "parameters must be an object with unique field names."
      )
    } else {
      forbidden <- intersect(
        names(parameters),
        c("model", "messages", "input", "system", "api_key", "api_url", "output_path")
      )
      if (length(forbidden)) {
        add_error(
          "forbidden_parameter",
          "$.runtime.parameters",
          paste("Protected parameter field(s):", paste(forbidden, collapse = ", "))
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
          "$.runtime.parameters",
          "parameters must be JSON-serializable."
        )
      }
    }
    if (identical(runtime$parameter_policy, "none") && length(parameters)) {
      add_error(
        "unexpected_parameters",
        "$.runtime.parameters",
        "parameters must be empty when parameter_policy is `none`."
      )
    }
  }

  experiment_spec_validation_result(length(errors) == 0L, errors, spec)
}

experiment_spec_validation_result <- function(valid, errors, spec) {
  structure(
    list(valid = isTRUE(valid), errors = errors, spec = spec),
    class = "psylingllm_experiment_spec_validation"
  )
}

experiment_spec_abort <- function(message, reason = "invalid_experiment_spec") {
  condition <- structure(
    list(message = message, call = NULL, reason = reason),
    class = c("experiment_spec_error", "error", "condition")
  )
  stop(condition)
}
