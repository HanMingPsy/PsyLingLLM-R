build_structured_output_parameters <- function(
    config,
    schema = NULL,
    mode = NULL,
    schema_name = "psylingllm_experiment_spec",
    strict = TRUE) {
  if (!inherits(config, "psylingllm_model_config") ||
      !is.list(config$interface)) {
    structured_output_abort(
      "config must be a resolved PsyLingLLM model configuration.",
      reason = "invalid_config"
    )
  }
  structured_output <- config$interface$structured_output
  if (!is.list(structured_output) || length(structured_output) == 0L) {
    structured_output_abort(
      "The selected Registry interface does not declare structured output.",
      interface = config$interface$id,
      reason = "structured_output_not_configured"
    )
  }

  selected_mode <- mode %||% structured_output$default_mode
  if (!is.character(selected_mode) || length(selected_mode) != 1L ||
      is.na(selected_mode) || !nzchar(selected_mode)) {
    structured_output_abort(
      "Structured-output mode must be one non-empty string.",
      interface = config$interface$id,
      reason = "invalid_mode"
    )
  }
  binding <- structured_output$modes[[selected_mode]]
  if (is.null(binding)) {
    structured_output_abort(
      sprintf(
        "Structured-output mode `%s` is not configured for this interface.",
        selected_mode
      ),
      interface = config$interface$id,
      mode = selected_mode,
      reason = "unsupported_mode"
    )
  }

  adapters <- llm_structured_output_adapters()
  adapter_id <- binding$adapter
  adapter <- adapters[[adapter_id]]
  if (is.null(adapter)) {
    structured_output_abort(
      sprintf("Unknown structured-output adapter `%s`.", adapter_id),
      interface = config$interface$id,
      mode = selected_mode,
      adapter = adapter_id,
      reason = "unknown_adapter"
    )
  }
  parameters <- adapter(
    schema = schema,
    schema_name = schema_name,
    strict = strict
  )
  if (!is.list(parameters) || is.null(names(parameters)) ||
      anyNA(names(parameters)) || any(!nzchar(names(parameters))) ||
      anyDuplicated(names(parameters))) {
    structured_output_abort(
      "Structured-output adapter returned invalid provider parameters.",
      interface = config$interface$id,
      mode = selected_mode,
      adapter = adapter_id,
      reason = "invalid_adapter_result"
    )
  }

  structure(
    list(
      mode = selected_mode,
      adapter = adapter_id,
      parameters = parameters
    ),
    class = c("psylingllm_structured_output", "list")
  )
}

llm_structured_output_adapters <- function() {
  list(
    openai_chat_json_object = structured_output_openai_chat_json_object,
    openai_chat_json_schema = structured_output_openai_chat_json_schema,
    openai_responses_json_object = structured_output_openai_responses_json_object,
    openai_responses_json_schema = structured_output_openai_responses_json_schema
  )
}

structured_output_openai_chat_json_object <- function(
    schema,
    schema_name,
    strict) {
  list(response_format = list(type = "json_object"))
}

structured_output_openai_chat_json_schema <- function(
    schema,
    schema_name,
    strict) {
  structured_output_assert_schema(schema, schema_name, strict)
  list(
    response_format = list(
      type = "json_schema",
      json_schema = list(
        name = schema_name,
        strict = strict,
        schema = schema
      )
    )
  )
}

structured_output_openai_responses_json_object <- function(
    schema,
    schema_name,
    strict) {
  list(text = list(format = list(type = "json_object")))
}

structured_output_openai_responses_json_schema <- function(
    schema,
    schema_name,
    strict) {
  structured_output_assert_schema(schema, schema_name, strict)
  list(
    text = list(
      format = list(
        type = "json_schema",
        name = schema_name,
        strict = strict,
        schema = schema
      )
    )
  )
}

structured_output_assert_schema <- function(schema, schema_name, strict) {
  valid_schema <- is.list(schema) && !is.null(names(schema)) &&
    !anyNA(names(schema)) && all(nzchar(names(schema))) &&
    !anyDuplicated(names(schema))
  if (!valid_schema) {
    structured_output_abort(
      "JSON Schema must be a named JSON object.",
      reason = "invalid_json_schema"
    )
  }
  serializable <- tryCatch(
    {
      jsonlite::toJSON(schema, auto_unbox = TRUE, null = "null", digits = NA)
      TRUE
    },
    error = function(error) FALSE
  )
  if (!serializable) {
    structured_output_abort(
      "JSON Schema must contain only JSON-serializable values.",
      reason = "invalid_json_schema"
    )
  }
  valid_name <- is.character(schema_name) && length(schema_name) == 1L &&
    !is.na(schema_name) &&
    grepl("^[A-Za-z0-9_-]{1,64}$", schema_name)
  if (!valid_name) {
    structured_output_abort(
      "schema_name must contain 1-64 letters, numbers, `_`, or `-`.",
      reason = "invalid_schema_name"
    )
  }
  if (!is.logical(strict) || length(strict) != 1L || is.na(strict)) {
    structured_output_abort(
      "strict must be one non-missing logical value.",
      reason = "invalid_strict_value"
    )
  }
  invisible(TRUE)
}

structured_output_abort <- function(
    message,
    interface = NULL,
    mode = NULL,
    adapter = NULL,
    reason = NULL) {
  condition <- structure(
    list(
      message = message,
      call = NULL,
      interface = interface,
      mode = mode,
      adapter = adapter,
      reason = reason
    ),
    class = c("structured_output_error", "error", "condition")
  )
  stop(condition)
}
