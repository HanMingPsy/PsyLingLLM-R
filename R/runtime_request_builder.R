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
                                 timeout = 120,
                                 provider_parameters = list()) {
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
    timeout = timeout,
    provider_parameters = provider_parameters
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
  list(
    legacy_template_v1 = build_legacy_template_request,
    openai_chat = build_openai_chat_request,
    openai_responses = build_openai_responses_request,
    anthropic_messages = build_anthropic_messages_request
  )
}

runtime_request_builder_input <- function(config, compatibility_entry) {
  builder_id <- config$interface$request$builder
  if (identical(builder_id, "legacy_template_v1")) {
    return(compatibility_entry)
  }
  config
}

configure_llm_request_transport <- function(request, config) {
  transport_id <- if (request$stream) {
    config$interface$transport$stream
  } else {
    config$interface$transport$non_stream
  }
  if (is.null(transport_id) &&
      identical(config$interface$protocol, "legacy_v1")) {
    transport_id <- request$transport_id
  }
  if (is.null(transport_id)) {
    llm_request_builder_abort(
      "The selected interface does not define the required transport.",
      builder_id = config$interface$request$builder,
      reason = "missing_transport"
    )
  }
  request$transport_id <- transport_id
  validate_llm_request(request, config$interface$request$builder)
  request
}

build_openai_chat_request <- function(config, context) {
  builder_id <- "openai_chat"
  request_config <- config$interface$request
  url <- context$api_url %||% request_config$url
  if (!is.character(url) || length(url) != 1L || is.na(url) || !nzchar(url)) {
    llm_request_builder_abort(
      "The resolved interface does not define a request URL.",
      builder_id = builder_id,
      reason = "missing_url"
    )
  }

  user_content <- build_user_content(
    context$trial_prompt,
    context$material
  )
  if (!nzchar(user_content)) {
    llm_request_builder_abort(
      "At least one of `trial_prompt` or `material` must be provided.",
      builder_id = builder_id,
      reason = "missing_user_content"
    )
  }

  role_mapping <- request_config$role_mapping %||% list()
  if (is.list(context$role_mapping) && length(context$role_mapping) > 0L) {
    role_mapping <- context$role_mapping
  }
  map_role <- function(role) {
    role_mapping[[tolower(role)]] %||% role
  }

  messages <- list()
  system_text <- context$system_content %||% request_config$default_system
  if (!is.null(system_text)) {
    messages[[length(messages) + 1L]] <- list(
      role = map_role("system"),
      content = system_text
    )
  }
  history <- normalize_history_messages(context$assistant_content, map_role)
  if (length(history) > 0L) {
    messages <- c(messages, history)
  }
  messages[[length(messages) + 1L]] <- list(
    role = map_role("user"),
    content = user_content
  )

  if (!isTRUE(context$optionals_missing) &&
      !is.null(context$optionals_value) &&
      !is.list(context$optionals_value)) {
    llm_request_builder_abort(
      "Optional parameters must be a named list or NULL.",
      builder_id = builder_id,
      reason = "invalid_optionals"
    )
  }
  optionals <- resolve_native_request_parameters(
    context = context,
    defaults = config$defaults,
    declared_names = unique(c(
      names(config$defaults %||% list()),
      names(request_config$body %||% list()),
      names(request_config$parameters %||% list())
    )),
    protected_names = c("model", "messages", "input", "system"),
    builder_id = builder_id
  )
  stream <- if (!is.null(context$stream)) {
    isTRUE(context$stream)
  } else if ("stream" %in% names(optionals)) {
    isTRUE(optionals$stream)
  } else {
    FALSE
  }
  optionals$stream <- NULL

  if (stream && !isTRUE(config$interface$streaming$supported)) {
    llm_request_builder_abort(
      "The selected interface does not support streaming.",
      builder_id = builder_id,
      reason = "unsupported_streaming"
    )
  }

  body <- request_config$body %||% list()
  body$model <- config$model$id
  body$messages <- messages
  for (name in names(optionals)) {
    body[name] <- list(optionals[[name]])
  }
  stream_parameter <- config$interface$streaming$request_parameter
  if (!is.null(stream_parameter)) {
    body[[stream_parameter]] <- NULL
  }
  if (stream) {
    if (is.null(stream_parameter)) {
      llm_request_builder_abort(
        "The streaming request parameter is not configured.",
        builder_id = builder_id,
        reason = "missing_stream_parameter"
      )
    }
    body[[stream_parameter]] <-
      config$interface$streaming$request_value %||% TRUE
  }

  headers <- apply_registry_auth(
    request_config$headers %||% list(),
    config$provider$auth,
    context$api_key,
    builder_id
  )

  structure(
    list(
      method = request_config$method %||% "POST",
      url = url,
      headers = headers,
      body = body,
      encoding = request_config$encoding %||% "json",
      stream = stream,
      transport_id = if (stream) {
        config$interface$transport$stream
      } else {
        config$interface$transport$non_stream
      },
      timeout = context$timeout
    ),
    class = c("psylingllm_request", "list")
  )
}

build_openai_responses_request <- function(config, context) {
  builder_id <- "openai_responses"
  request_config <- config$interface$request
  url <- native_request_url(request_config, context, builder_id)
  user_content <- native_user_content(context, builder_id)
  map_role <- native_role_mapper(request_config, context)

  input <- normalize_history_messages(context$assistant_content, map_role)
  input[[length(input) + 1L]] <- list(
    role = map_role("user"),
    content = user_content
  )
  optionals <- resolve_native_request_parameters(
    context = context,
    defaults = config$defaults,
    declared_names = unique(c(
      names(config$defaults %||% list()),
      names(request_config$body %||% list()),
      names(request_config$parameters %||% list())
    )),
    protected_names = c("model", "input", "instructions", "messages", "system"),
    builder_id = builder_id
  )
  stream <- native_stream_value(optionals, context, config, builder_id)
  optionals$stream <- NULL

  body <- request_config$body %||% list()
  body$model <- config$model$id
  body$input <- input
  instructions <- context$system_content %||% request_config$default_system
  if (!is.null(instructions)) {
    body$instructions <- instructions
  }
  body <- append_native_parameters(body, optionals)
  body <- apply_native_stream(body, stream, config, builder_id)

  new_native_request(
    request_config,
    config,
    context,
    body,
    url,
    stream,
    builder_id
  )
}

build_anthropic_messages_request <- function(config, context) {
  builder_id <- "anthropic_messages"
  request_config <- config$interface$request
  url <- native_request_url(request_config, context, builder_id)
  user_content <- native_user_content(context, builder_id)
  map_role <- native_role_mapper(request_config, context)

  messages <- normalize_history_messages(context$assistant_content, map_role)
  if (any(vapply(
    messages,
    function(message) identical(message$role, "system"),
    logical(1)
  ))) {
    llm_request_builder_abort(
      "Anthropic message history cannot contain the `system` role.",
      builder_id = builder_id,
      reason = "invalid_history_role"
    )
  }
  messages[[length(messages) + 1L]] <- list(
    role = map_role("user"),
    content = user_content
  )
  optionals <- resolve_native_request_parameters(
    context = context,
    defaults = config$defaults,
    declared_names = unique(c(
      names(config$defaults %||% list()),
      names(request_config$body %||% list()),
      names(request_config$parameters %||% list())
    )),
    protected_names = c("model", "messages", "system", "input", "instructions"),
    builder_id = builder_id
  )
  stream <- native_stream_value(optionals, context, config, builder_id)
  optionals$stream <- NULL

  body <- request_config$body %||% list()
  body$model <- config$model$id
  body$messages <- messages
  system_text <- context$system_content %||% request_config$default_system
  if (!is.null(system_text)) {
    body$system <- system_text
  }
  body <- append_native_parameters(body, optionals)
  body <- apply_native_stream(body, stream, config, builder_id)

  new_native_request(
    request_config,
    config,
    context,
    body,
    url,
    stream,
    builder_id
  )
}

native_request_url <- function(request_config, context, builder_id) {
  url <- context$api_url %||% request_config$url
  if (!is.character(url) || length(url) != 1L || is.na(url) || !nzchar(url)) {
    llm_request_builder_abort(
      "The resolved interface does not define a request URL.",
      builder_id = builder_id,
      reason = "missing_url"
    )
  }
  url
}

native_user_content <- function(context, builder_id) {
  content <- build_user_content(context$trial_prompt, context$material)
  if (!nzchar(content)) {
    llm_request_builder_abort(
      "At least one of `trial_prompt` or `material` must be provided.",
      builder_id = builder_id,
      reason = "missing_user_content"
    )
  }
  content
}

native_role_mapper <- function(request_config, context) {
  role_mapping <- request_config$role_mapping %||% list()
  if (is.list(context$role_mapping) && length(context$role_mapping) > 0L) {
    role_mapping <- context$role_mapping
  }
  function(role) role_mapping[[tolower(role)]] %||% role
}

native_stream_value <- function(optionals, context, config, builder_id) {
  stream <- if (!is.null(context$stream)) {
    isTRUE(context$stream)
  } else if ("stream" %in% names(optionals)) {
    isTRUE(optionals$stream)
  } else {
    FALSE
  }
  if (stream && !isTRUE(config$interface$streaming$supported)) {
    llm_request_builder_abort(
      "The selected interface does not support streaming.",
      builder_id = builder_id,
      reason = "unsupported_streaming"
    )
  }
  stream
}

append_native_parameters <- function(body, parameters) {
  for (name in names(parameters)) {
    body[name] <- list(parameters[[name]])
  }
  body
}

apply_native_stream <- function(body, stream, config, builder_id) {
  stream_parameter <- config$interface$streaming$request_parameter
  if (!is.null(stream_parameter)) {
    body[[stream_parameter]] <- NULL
  }
  if (!stream) {
    return(body)
  }
  if (is.null(stream_parameter)) {
    llm_request_builder_abort(
      "The streaming request parameter is not configured.",
      builder_id = builder_id,
      reason = "missing_stream_parameter"
    )
  }
  body[[stream_parameter]] <-
    config$interface$streaming$request_value %||% TRUE
  body
}

new_native_request <- function(request_config, config, context, body, url,
                               stream, builder_id) {
  headers <- apply_registry_auth(
    request_config$headers %||% list(),
    config$provider$auth,
    context$api_key,
    builder_id
  )
  structure(
    list(
      method = request_config$method %||% "POST",
      url = url,
      headers = headers,
      body = body,
      encoding = request_config$encoding %||% "json",
      stream = stream,
      transport_id = if (stream) {
        config$interface$transport$stream
      } else {
        config$interface$transport$non_stream
      },
      timeout = context$timeout
    ),
    class = c("psylingllm_request", "list")
  )
}

resolve_native_request_parameters <- function(context, defaults,
                                              declared_names,
                                              protected_names,
                                              builder_id) {
  dots <- context$provider_parameters %||% list()
  validate_parameter_collection(dots, "Provider parameters", builder_id)
  optionals <- context$optionals_value
  if (!isTRUE(context$optionals_missing) && !is.null(optionals)) {
    validate_parameter_collection(optionals, "Optional parameters", builder_id)
  }

  user_supplied <- !isTRUE(context$optionals_missing) || length(dots) > 0L
  values <- if (!user_supplied) {
    defaults %||% list()
  } else if (is.null(optionals)) {
    list()
  } else {
    optionals
  }
  values <- c(values, dots)

  duplicate_names <- unique(names(values)[duplicated(names(values))])
  if (length(duplicate_names) > 0L) {
    warning(
      sprintf(
        "Duplicate provider parameter(s) use the last value: %s.",
        paste(duplicate_names, collapse = ", ")
      ),
      call. = FALSE
    )
  }
  values <- collapse_named_parameters(values)

  protected <- intersect(names(values), protected_names)
  if (length(protected) > 0L) {
    llm_request_builder_abort(
      sprintf(
        "Provider parameters cannot replace protocol field(s): %s.",
        paste(protected, collapse = ", ")
      ),
      builder_id = builder_id,
      reason = "protected_parameter"
    )
  }

  unknown <- setdiff(names(values), c(declared_names, "stream"))
  if (length(unknown) > 0L) {
    warning(
      sprintf(
        paste0(
          "Provider parameter(s) are not documented by this Registry ",
          "entry and will be sent unchanged: %s."
        ),
        paste(unknown, collapse = ", ")
      ),
      call. = FALSE
    )
  }
  values
}

validate_parameter_collection <- function(value, label, builder_id) {
  valid <- is.list(value) &&
    (length(value) == 0L || (
      !is.null(names(value)) && !anyNA(names(value)) &&
      all(nzchar(names(value)))
    ))
  if (!valid) {
    llm_request_builder_abort(
      sprintf("%s must be a named list.", label),
      builder_id = builder_id,
      reason = "invalid_optionals"
    )
  }
  invisible(TRUE)
}

collapse_named_parameters <- function(values) {
  result <- list()
  for (index in seq_along(values)) {
    result[names(values)[[index]]] <- list(values[[index]])
  }
  result
}

apply_registry_auth <- function(headers, auth, api_key, builder_id) {
  if (is.null(auth) || identical(auth$scheme, "none")) {
    return(headers)
  }
  valid_key <- is.character(api_key) && length(api_key) == 1L &&
    !is.na(api_key) && nzchar(api_key)
  if (!valid_key) {
    llm_request_builder_abort(
      "The selected provider requires an API key.",
      builder_id = builder_id,
      reason = "missing_api_key"
    )
  }

  if (identical(auth$scheme, "bearer")) {
    header <- auth$header %||% "Authorization"
    prefix <- auth$prefix %||% "Bearer "
  } else if (identical(auth$scheme, "header")) {
    header <- auth$header
    prefix <- auth$prefix %||% ""
  } else {
    llm_request_builder_abort(
      "The selected provider uses an unsupported authentication scheme.",
      builder_id = builder_id,
      reason = "unsupported_auth"
    )
  }
  headers[[header]] <- paste0(prefix, api_key)
  headers
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
  dots <- context$provider_parameters %||% list()
  validate_parameter_collection(dots, "Provider parameters", "legacy_template_v1")
  if (length(dots) > 0L) {
    duplicate_names <- intersect(names(optionals), names(dots))
    if (length(duplicate_names) > 0L) {
      warning(
        sprintf(
          "Duplicate provider parameter(s) use the last value: %s.",
          paste(unique(duplicate_names), collapse = ", ")
        ),
        call. = FALSE
      )
    }
    optionals <- collapse_named_parameters(c(optionals, dots))
  }
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
