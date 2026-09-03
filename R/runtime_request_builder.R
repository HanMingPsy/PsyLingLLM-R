# Runtime request construction ----------------------------------------------

# Capture call inputs before dispatching to a request builder. In particular,
# `optionals_missing` must be evaluated in llm_caller()'s call frame.
new_llm_call_context <- function(trial_prompt = NULL,
                                 material = NULL,
                                 system_content = NULL,
                                 assistant_content = NULL,
                                 api_key = NULL,
                                 optionals_missing,
                                 optionals_value = NULL,
                                 stream = NULL,
                                 role_mapping = NULL,
                                 api_url = NULL,
                                 timeout = 120) {
  list(
    trial_prompt = trial_prompt,
    material = material,
    system_content = system_content,
    assistant_content = assistant_content,
    api_key = api_key,
    optionals_missing = isTRUE(optionals_missing),
    optionals_value = optionals_value,
    stream = stream,
    role_mapping = role_mapping,
    api_url = api_url,
    timeout = timeout
  )
}

# Build a transport-neutral request through an allowlisted builder.
build_llm_request <- function(builder_id, entry, context) {
  builders <- llm_request_builders()
  if (!is.character(builder_id) || length(builder_id) != 1L ||
      is.na(builder_id) || !nzchar(builder_id)) {
    llm_request_builder_abort(
      "Builder ID must be a non-empty character scalar.",
      builder_id = builder_id,
      reason = "invalid_builder"
    )
  }
  builder <- builders[[builder_id]]
  if (is.null(builder)) {
    llm_request_builder_abort(
      sprintf(
        "Unknown request builder `%s`. Available builders: %s.",
        builder_id,
        paste(names(builders), collapse = ", ")
      ),
      builder_id = builder_id,
      reason = "unknown_builder"
    )
  }
  if (!is.list(entry) || !is.list(context)) {
    llm_request_builder_abort(
      "Registry entry and call context must be lists.",
      builder_id = builder_id,
      reason = "invalid_input"
    )
  }

  request <- builder(entry, context)
  validate_llm_request(request, builder_id)
  request
}

llm_request_builders <- function() {
  list(legacy_template_v1 = build_legacy_template_request)
}

build_legacy_template_request <- function(entry, context) {
  url <- resolve_api_url(
    api_url = context$api_url,
    provider = entry$provider,
    default_url = entry$input$default_url
  )

  body_template <- entry$input$body %||% list()
  message_keys <- detect_message_keys_from_template(body_template)
  supports_roles <- isTRUE(message_keys$supports_roles)

  if (!supports_roles &&
      (!is.null(context$system_content) ||
       !is.null(context$assistant_content))) {
    warning(
      paste0(
        "[llm_caller] Template has no ${ROLE}; ",
        "system/assistant content will be ignored."
      )
    )
  }

  use_role_mapping <- is.list(context$role_mapping) &&
    length(context$role_mapping) > 0L
  map_role <- function(role) {
    if (!use_role_mapping) {
      return(role)
    }
    context$role_mapping[[tolower(role)]] %||% role
  }

  user_content <- build_user_content(
    context$trial_prompt,
    context$material
  )
  if (!nzchar(user_content)) {
    stop("At least one of 'trial_prompt' or 'material' must be provided.")
  }

  body <- body_template
  if (supports_roles) {
    messages <- list()
    system_text <- context$system_content
    if (is.null(system_text)) {
      system_text <- entry$input$default_system %||% NULL
    }
    if (!is.null(system_text)) {
      messages[[length(messages) + 1L]] <- list(
        role = map_role("system"),
        content = system_text
      )
    }

    history <- normalize_history_messages(
      context$assistant_content,
      map_role
    )
    if (length(history) > 0L) {
      messages <- c(messages, history)
    }
    messages[[length(messages) + 1L]] <- list(
      role = map_role("user"),
      content = user_content
    )

    body[[message_keys$container_key]] <- lapply(messages, function(message) {
      item <- list()
      item[[message_keys$role_key]] <- message$role
      item[[message_keys$content_key]] <- message$content
      item
    })
  } else {
    body <- replace_placeholders(body, list(CONTENT = user_content))
  }

  optionals <- resolve_optionals_tristate(
    optionals_missing = context$optionals_missing,
    optionals_value = context$optionals_value,
    defaults = entry$input$optional_defaults %||% list()
  )
  body <- inject_optionals_anchor(body, optionals)

  stream <- if (!is.null(context$stream)) {
    isTRUE(context$stream)
  } else if ("stream" %in% names(optionals)) {
    isTRUE(optionals$stream)
  } else {
    isTRUE(entry$streaming$enabled)
  }
  if (stream) {
    stream_field <- entry$streaming$param_name
    if (is.character(stream_field) && length(stream_field) == 1L &&
        !is.na(stream_field) && nzchar(stream_field)) {
      body[[stream_field]] <- TRUE
    } else {
      body$stream <- TRUE
    }
  }

  headers <- entry$input$headers %||% list()
  if (!is.null(context$api_key)) {
    replacements <- list(API_KEY = context$api_key)
    headers <- replace_placeholders(headers, replacements)
    body <- replace_placeholders(body, replacements)
  }
  if (!supports_roles) {
    body <- replace_placeholders(body, list(CONTENT = user_content))
  }

  structure(
    list(
      method = "POST",
      url = url,
      headers = headers,
      body = body,
      encoding = "json",
      stream = stream,
      transport_id = if (stream) "sse_json" else "http_json",
      timeout = context$timeout
    ),
    class = c("psylingllm_request", "list")
  )
}

validate_llm_request <- function(request, builder_id = NULL) {
  required <- c(
    "method", "url", "headers", "body", "encoding", "stream",
    "transport_id", "timeout"
  )
  if (!is.list(request) || !identical(names(request), required)) {
    llm_request_builder_abort(
      "Builder returned an invalid request structure.",
      builder_id = builder_id,
      reason = "invalid_request"
    )
  }
  valid_method <- is.character(request$method) &&
    length(request$method) == 1L && identical(request$method, "POST")
  valid_url <- is.character(request$url) && length(request$url) == 1L &&
    !is.na(request$url) && nzchar(request$url)
  valid_encoding <- identical(request$encoding, "json")
  valid_stream <- is.logical(request$stream) &&
    length(request$stream) == 1L && !is.na(request$stream)
  valid_transport <- is.character(request$transport_id) &&
    length(request$transport_id) == 1L && !is.na(request$transport_id) &&
    request$transport_id %in% registry_v2_component_ids()$transports
  valid_timeout <- is.numeric(request$timeout) &&
    length(request$timeout) == 1L && !is.na(request$timeout) &&
    is.finite(request$timeout) && request$timeout >= 0

  if (!valid_method || !valid_url || !is.list(request$headers) ||
      !is.list(request$body) || !valid_encoding || !valid_stream ||
      !valid_transport || !valid_timeout) {
    llm_request_builder_abort(
      "Builder returned invalid request field values.",
      builder_id = builder_id,
      reason = "invalid_request"
    )
  }
  invisible(TRUE)
}

llm_request_builder_abort <- function(message, builder_id = NULL,
                                      reason = NULL) {
  condition <- structure(
    list(
      message = paste0("LLM request construction failed: ", message),
      call = NULL,
      builder_id = builder_id,
      reason = reason
    ),
    class = c("llm_request_builder_error", "error", "condition")
  )
  stop(condition)
}
