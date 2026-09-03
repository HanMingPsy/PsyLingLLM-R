#' Validate a PsyLingLLM Registry Document
#'
#' Detects the registry version and validates its structure. Existing Registry
#' v1 documents are accepted through a compatibility-oriented structural check.
#' Registry v2 documents are checked strictly, including allowed fields, value
#' types, component identifiers, and cross-references.
#'
#' This function only validates registry data. It does not read or write files,
#' resolve credentials, check network access, or verify that a runtime component
#' has already been implemented.
#'
#' @param entry A complete registry document represented as a named list.
#'
#' @return `TRUE`, invisibly, when the document is valid.
#' @export
validate_registry_schema <- function(entry) {
  if (!is.list(entry) || is.null(names(entry))) {
    registry_schema_abort("Registry document must be a named list.")
  }

  v2_domains <- c("providers", "interfaces", "capabilities", "models")
  has_version <- "schema_version" %in% names(entry)

  if (!has_version && any(v2_domains %in% names(entry))) {
    registry_schema_abort(
      "Registry v2 domains require `schema_version: 2`.",
      field = "schema_version"
    )
  }
  if (!has_version) {
    validate_registry_v1_document(entry)
    return(invisible(TRUE))
  }

  version <- entry$schema_version
  if (!is.numeric(version) || length(version) != 1L ||
      is.na(version) || version != 2) {
    registry_schema_abort(
      "Unsupported schema version; expected numeric value 2.",
      field = "schema_version"
    )
  }

  validate_registry_v2_document(entry)
  invisible(TRUE)
}

validate_registry_v1_document <- function(registry) {
  registry_schema_assert_named_list(registry, "models", allow_empty = FALSE)

  for (model_id in names(registry)) {
    interfaces <- registry[[model_id]]
    registry_schema_assert_named_list(
      interfaces, "models", model_id, "interfaces", allow_empty = FALSE
    )
    for (interface_id in names(interfaces)) {
      if (!is.list(interfaces[[interface_id]])) {
        registry_schema_abort(
          "Registry v1 interface must be a list.",
          "models", model_id, interface_id
        )
      }
    }
  }

  invisible(TRUE)
}

validate_registry_v2_document <- function(registry) {
  domains <- c("providers", "interfaces", "capabilities", "models")
  registry_schema_assert_fields(
    registry,
    required = c("schema_version", domains),
    allowed = c("schema_version", domains)
  )

  for (domain in domains) {
    registry_schema_assert_named_list(registry[[domain]], domain)
  }
  for (id in names(registry$providers)) {
    validate_registry_v2_provider(registry$providers[[id]], id)
  }
  for (id in names(registry$capabilities)) {
    validate_registry_v2_capability(registry$capabilities[[id]], id)
  }
  for (id in names(registry$interfaces)) {
    validate_registry_v2_interface(
      registry$interfaces[[id]], id, names(registry$capabilities)
    )
  }
  for (id in names(registry$models)) {
    validate_registry_v2_model(registry$models[[id]], id, registry)
  }

  invisible(TRUE)
}

validate_registry_v2_provider <- function(provider, id) {
  registry_schema_assert_id(id, "providers")
  registry_schema_assert_fields(
    provider,
    required = "type",
    allowed = c("type", "base_url", "auth", "headers", "metadata"),
    domain = "providers",
    entry_id = id
  )
  registry_schema_assert_choice(
    provider$type, c("official", "proxy", "local", "custom"),
    "providers", id, "type"
  )
  registry_schema_assert_optional_string(
    provider$base_url, "providers", id, "base_url"
  )
  registry_schema_assert_optional_string_map(
    provider$headers, "providers", id, "headers"
  )
  registry_schema_assert_optional_list(
    provider$metadata, "providers", id, "metadata"
  )

  if (!is.null(provider$auth)) {
    auth <- provider$auth
    registry_schema_assert_fields(
      auth,
      required = "scheme",
      allowed = c("scheme", "env_var", "header", "prefix"),
      domain = "providers",
      entry_id = id,
      field = "auth"
    )
    registry_schema_assert_choice(
      auth$scheme, c("none", "bearer", "header"),
      "providers", id, "auth.scheme"
    )
    if (!identical(auth$scheme, "none")) {
      registry_schema_assert_string(
        auth$env_var, "providers", id, "auth.env_var"
      )
    }
    if (identical(auth$scheme, "header")) {
      registry_schema_assert_string(
        auth$header, "providers", id, "auth.header"
      )
    }
    registry_schema_assert_optional_string(
      auth$prefix, "providers", id, "auth.prefix", allow_empty = TRUE
    )
  }

  invisible(TRUE)
}

validate_registry_v2_capability <- function(capability, id) {
  registry_schema_assert_id(id, "capabilities")
  registry_schema_assert_fields(
    capability,
    required = "value_type",
    allowed = c("value_type", "description", "allowed_values", "default"),
    domain = "capabilities",
    entry_id = id
  )
  registry_schema_assert_choice(
    capability$value_type,
    c("logical", "integer", "numeric", "character", "character_vector"),
    "capabilities", id, "value_type"
  )
  registry_schema_assert_optional_string(
    capability$description, "capabilities", id, "description"
  )

  if (!is.null(capability$allowed_values) &&
      length(capability$allowed_values) == 0L) {
    registry_schema_abort(
      "Allowed values must not be empty.",
      "capabilities", id, "allowed_values"
    )
  }
  if (!is.null(capability$allowed_values)) {
    allowed_values <- unlist(capability$allowed_values, use.names = FALSE)
    definition <- capability
    definition$allowed_values <- NULL
    for (value in as.list(allowed_values)) {
      registry_schema_assert_capability_value(
        value, definition, "capabilities", id, "allowed_values"
      )
    }
  }
  if ("default" %in% names(capability)) {
    registry_schema_assert_capability_value(
      capability$default, capability, "capabilities", id, "default"
    )
  }

  invisible(TRUE)
}

validate_registry_v2_interface <- function(interface, id, capability_ids) {
  registry_schema_assert_id(id, "interfaces")
  registry_schema_assert_fields(
    interface,
    required = c("protocol", "request", "transport", "response"),
    allowed = c(
      "protocol", "request", "transport", "response", "streaming",
      "capabilities", "defaults", "metadata"
    ),
    domain = "interfaces",
    entry_id = id
  )

  components <- registry_v2_component_ids()
  registry_schema_assert_choice(
    interface$protocol, components$protocols,
    "interfaces", id, "protocol"
  )

  request <- interface$request
  registry_schema_assert_fields(
    request,
    required = "builder",
    allowed = c(
      "builder", "method", "encoding", "path", "parameter_map", "defaults"
    ),
    domain = "interfaces",
    entry_id = id,
    field = "request"
  )
  registry_schema_assert_choice(
    request$builder, components$request_builders,
    "interfaces", id, "request.builder"
  )
  if (!is.null(request$method)) {
    registry_schema_assert_choice(
      request$method, "POST", "interfaces", id, "request.method"
    )
  }
  if (!is.null(request$encoding)) {
    registry_schema_assert_choice(
      request$encoding, "json", "interfaces", id, "request.encoding"
    )
  }
  registry_schema_assert_optional_string(
    request$path, "interfaces", id, "request.path"
  )
  if (!is.null(request$path) && !startsWith(request$path, "/")) {
    registry_schema_abort(
      "Request path must start with `/`.", "interfaces", id, "request.path"
    )
  }
  registry_schema_assert_optional_string_map(
    request$parameter_map, "interfaces", id, "request.parameter_map"
  )
  if (!is.null(request$defaults)) {
    registry_schema_assert_overrides(
      request$defaults, request, "interfaces", id, "request.defaults"
    )
  }

  transport <- interface$transport
  registry_schema_assert_fields(
    transport,
    required = "non_stream",
    allowed = c("non_stream", "stream"),
    domain = "interfaces",
    entry_id = id,
    field = "transport"
  )
  registry_schema_assert_choice(
    transport$non_stream, components$transports,
    "interfaces", id, "transport.non_stream"
  )
  if (!is.null(transport$stream)) {
    registry_schema_assert_choice(
      transport$stream, components$transports,
      "interfaces", id, "transport.stream"
    )
  }

  response <- interface$response
  registry_schema_assert_fields(
    response,
    required = "parser",
    allowed = c("parser", "selectors"),
    domain = "interfaces",
    entry_id = id,
    field = "response"
  )
  registry_schema_assert_choice(
    response$parser, components$response_parsers,
    "interfaces", id, "response.parser"
  )
  if (identical(response$parser, "legacy_paths_v1") &&
      is.null(response$selectors)) {
    registry_schema_abort(
      "The legacy parser requires explicit selectors.",
      "interfaces", id, "response.selectors"
    )
  }
  if (!is.null(response$selectors)) {
    registry_schema_assert_selectors(response$selectors, id)
  }

  validate_registry_v2_streaming(interface$streaming, transport, id)
  validate_registry_v2_interface_capabilities(
    interface$capabilities, capability_ids, id
  )
  if (!is.null(interface$defaults)) {
    registry_schema_assert_overrides(
      interface$defaults, request, "interfaces", id, "defaults"
    )
  }
  registry_schema_assert_optional_list(
    interface$metadata, "interfaces", id, "metadata"
  )

  invisible(TRUE)
}

validate_registry_v2_streaming <- function(streaming, transport, interface_id) {
  if (is.null(streaming)) {
    return(invisible(TRUE))
  }
  registry_schema_assert_fields(
    streaming,
    required = "supported",
    allowed = c("supported", "request_parameter", "request_value"),
    domain = "interfaces",
    entry_id = interface_id,
    field = "streaming"
  )
  supported <- streaming$supported
  if (!is.logical(supported) || length(supported) != 1L || is.na(supported)) {
    registry_schema_abort(
      "Streaming support must be TRUE or FALSE.",
      "interfaces", interface_id, "streaming.supported"
    )
  }
  if (isTRUE(supported) && is.null(transport$stream)) {
    registry_schema_abort(
      "A stream transport is required when streaming is supported.",
      "interfaces", interface_id, "transport.stream"
    )
  }
  registry_schema_assert_optional_string(
    streaming$request_parameter,
    "interfaces", interface_id, "streaming.request_parameter"
  )

  invisible(TRUE)
}

validate_registry_v2_interface_capabilities <- function(bindings,
                                                          capability_ids,
                                                          interface_id) {
  if (is.null(bindings)) {
    return(invisible(TRUE))
  }
  registry_schema_assert_named_list(
    bindings, "interfaces", interface_id, "capabilities"
  )
  registry_schema_assert_references(
    names(bindings), capability_ids, "interfaces", interface_id,
    "capabilities", allow_empty = TRUE
  )

  for (capability_id in names(bindings)) {
    binding <- bindings[[capability_id]]
    field <- paste0("capabilities.", capability_id)
    registry_schema_assert_fields(
      binding,
      required = character(),
      allowed = c("request_parameter", "response_channel", "modes"),
      domain = "interfaces",
      entry_id = interface_id,
      field = field
    )
    if (length(binding) == 0L) {
      registry_schema_abort(
        "Capability binding must declare at least one behavior.",
        "interfaces", interface_id, field
      )
    }
    registry_schema_assert_optional_string(
      binding$request_parameter,
      "interfaces", interface_id, paste0(field, ".request_parameter")
    )
    registry_schema_assert_optional_string(
      binding$response_channel,
      "interfaces", interface_id, paste0(field, ".response_channel")
    )
    if (!is.null(binding$modes)) {
      registry_schema_assert_string_vector(
        binding$modes, "interfaces", interface_id, paste0(field, ".modes")
      )
    }
  }

  invisible(TRUE)
}

validate_registry_v2_model <- function(model, id, registry) {
  if (!is.character(id) || length(id) != 1L || is.na(id) || !nzchar(id)) {
    registry_schema_abort(
      "Model identifier must be a non-empty string.", "models", id, "id"
    )
  }
  registry_schema_assert_fields(
    model,
    required = c(
      "provider", "model_id", "interfaces", "default_interface",
      "capabilities"
    ),
    allowed = c(
      "provider", "model_id", "aliases", "interfaces", "default_interface",
      "capabilities", "defaults", "metadata"
    ),
    domain = "models",
    entry_id = id
  )
  registry_schema_assert_string(model$provider, "models", id, "provider")
  registry_schema_assert_string(model$model_id, "models", id, "model_id")
  registry_schema_assert_references(
    model$provider, names(registry$providers), "models", id, "provider"
  )
  registry_schema_assert_references(
    model$interfaces, names(registry$interfaces), "models", id, "interfaces"
  )
  registry_schema_assert_string(
    model$default_interface, "models", id, "default_interface"
  )
  if (!model$default_interface %in% model$interfaces) {
    registry_schema_abort(
      "Default interface must be one of the model interfaces.",
      "models", id, "default_interface"
    )
  }

  registry_schema_assert_named_list(
    model$capabilities, "models", id, "capabilities"
  )
  registry_schema_assert_references(
    names(model$capabilities), names(registry$capabilities),
    "models", id, "capabilities", allow_empty = TRUE
  )
  for (capability_id in names(model$capabilities)) {
    registry_schema_assert_capability_value(
      model$capabilities[[capability_id]],
      registry$capabilities[[capability_id]],
      "models", id, paste0("capabilities.", capability_id)
    )
  }

  if (!is.null(model$aliases)) {
    registry_schema_assert_string_vector(
      model$aliases, "models", id, "aliases", unique = TRUE
    )
  }
  if (!is.null(model$defaults)) {
    request <- registry$interfaces[[model$default_interface]]$request
    registry_schema_assert_overrides(
      model$defaults, request, "models", id, "defaults"
    )
  }
  registry_schema_assert_optional_list(
    model$metadata, "models", id, "metadata"
  )

  invisible(TRUE)
}

registry_v2_component_ids <- function() {
  list(
    protocols = c(
      "legacy_v1", "openai_chat", "openai_responses", "anthropic_messages"
    ),
    request_builders = c(
      "legacy_template_v1", "openai_chat", "openai_responses",
      "anthropic_messages"
    ),
    transports = c("http_json", "sse_json"),
    response_parsers = c(
      "legacy_paths_v1", "openai_chat", "openai_responses",
      "anthropic_messages"
    )
  )
}

registry_schema_assert_fields <- function(value, required, allowed,
                                          domain = "registry",
                                          entry_id = NULL, field = NULL) {
  valid_names <- !is.null(names(value)) && !anyNA(names(value)) &&
    all(nzchar(names(value))) && !anyDuplicated(names(value))
  if (!is.list(value) || !valid_names) {
    registry_schema_abort("Expected a named list.", domain, entry_id, field)
  }
  missing <- setdiff(required, names(value))
  unknown <- setdiff(names(value), allowed)
  if (length(missing) > 0L) {
    registry_schema_abort(
      sprintf("Missing required field(s): %s.", paste(missing, collapse = ", ")),
      domain, entry_id, field
    )
  }
  if (length(unknown) > 0L) {
    registry_schema_abort(
      sprintf("Unknown field(s): %s.", paste(unknown, collapse = ", ")),
      domain, entry_id, field
    )
  }
  invisible(TRUE)
}

registry_schema_assert_named_list <- function(value, domain, entry_id = NULL,
                                              field = NULL,
                                              allow_empty = TRUE) {
  valid_names <- length(value) == 0L && allow_empty
  if (length(value) > 0L) {
    valid_names <- !is.null(names(value)) && !anyNA(names(value)) &&
      all(nzchar(names(value))) && !anyDuplicated(names(value))
  }
  if (!is.list(value) || !valid_names || (!allow_empty && length(value) == 0L)) {
    registry_schema_abort(
      "Expected a named list with unique, non-empty names.",
      domain, entry_id, field
    )
  }
  invisible(TRUE)
}

registry_schema_assert_id <- function(id, domain) {
  if (!is.character(id) || length(id) != 1L ||
      !grepl("^[a-z][a-z0-9._-]*$", id)) {
    registry_schema_abort(
      "Identifier must use lowercase letters, numbers, `.`, `_`, or `-`.",
      domain, id, "id"
    )
  }
  invisible(TRUE)
}

registry_schema_assert_string <- function(value, domain, entry_id, field,
                                          allow_empty = FALSE) {
  valid <- is.character(value) && length(value) == 1L && !is.na(value)
  if (!allow_empty) {
    valid <- valid && nzchar(value)
  }
  if (!valid) {
    registry_schema_abort(
      "Expected a single character value.", domain, entry_id, field
    )
  }
  invisible(TRUE)
}

registry_schema_assert_optional_string <- function(value, domain, entry_id,
                                                   field,
                                                   allow_empty = FALSE) {
  if (!is.null(value)) {
    registry_schema_assert_string(
      value, domain, entry_id, field, allow_empty = allow_empty
    )
  }
  invisible(TRUE)
}

registry_schema_assert_string_vector <- function(value, domain, entry_id,
                                                 field, unique = FALSE) {
  valid <- is.character(value) && length(value) > 0L &&
    !anyNA(value) && all(nzchar(value))
  if (unique) {
    valid <- valid && !anyDuplicated(value)
  }
  if (!valid) {
    registry_schema_abort(
      "Expected non-empty character values.", domain, entry_id, field
    )
  }
  invisible(TRUE)
}

registry_schema_assert_optional_string_map <- function(value, domain,
                                                       entry_id, field) {
  if (is.null(value)) {
    return(invisible(TRUE))
  }
  registry_schema_assert_named_list(as.list(value), domain, entry_id, field)
  valid <- vapply(
    value,
    function(item) {
      is.character(item) && length(item) == 1L && !is.na(item) && nzchar(item)
    },
    logical(1)
  )
  if (!all(valid)) {
    registry_schema_abort(
      "Expected named character values.", domain, entry_id, field
    )
  }
  invisible(TRUE)
}

registry_schema_assert_optional_list <- function(value, domain, entry_id,
                                                 field) {
  if (!is.null(value) && !is.list(value)) {
    registry_schema_abort("Expected a list.", domain, entry_id, field)
  }
  invisible(TRUE)
}

registry_schema_assert_choice <- function(value, choices, domain, entry_id,
                                          field) {
  registry_schema_assert_string(value, domain, entry_id, field)
  if (!value %in% choices) {
    registry_schema_abort(
      sprintf(
        "Unsupported value `%s`; expected one of: %s.",
        value, paste(choices, collapse = ", ")
      ),
      domain, entry_id, field
    )
  }
  invisible(TRUE)
}

registry_schema_assert_references <- function(value, known_ids, domain,
                                              entry_id, field,
                                              allow_empty = FALSE) {
  if (length(value) == 0L && allow_empty) {
    return(invisible(TRUE))
  }
  registry_schema_assert_string_vector(value, domain, entry_id, field, TRUE)
  unknown <- setdiff(value, known_ids)
  if (length(unknown) > 0L) {
    registry_schema_abort(
      sprintf("Unknown reference(s): %s.", paste(unknown, collapse = ", ")),
      domain, entry_id, field
    )
  }
  invisible(TRUE)
}

registry_schema_assert_overrides <- function(defaults, request, domain,
                                             entry_id, field) {
  registry_schema_assert_named_list(defaults, domain, entry_id, field)
  unknown <- setdiff(names(defaults), names(request$parameter_map))
  if (length(unknown) > 0L) {
    registry_schema_abort(
      sprintf(
        "Defaults contain undeclared parameter(s): %s.",
        paste(unknown, collapse = ", ")
      ),
      domain, entry_id, field
    )
  }
  invisible(TRUE)
}

registry_schema_assert_selectors <- function(selectors, interface_id) {
  registry_schema_assert_named_list(
    selectors, "interfaces", interface_id, "response.selectors",
    allow_empty = FALSE
  )
  for (selector_id in names(selectors)) {
    selector <- selectors[[selector_id]]
    segments <- as.list(selector)
    valid <- length(segments) > 0L && all(vapply(
      segments,
      function(segment) {
        (is.character(segment) || is.numeric(segment)) &&
          length(segment) == 1L && !is.na(segment)
      },
      logical(1)
    ))
    if (!valid) {
      registry_schema_abort(
        "Selector must be a non-empty sequence of path segments.",
        "interfaces", interface_id,
        paste0("response.selectors.", selector_id)
      )
    }
  }
  invisible(TRUE)
}

registry_schema_assert_capability_value <- function(value, definition, domain,
                                                    entry_id, field) {
  value_type <- definition$value_type
  valid <- switch(
    value_type,
    logical = is.logical(value) && length(value) == 1L && !is.na(value),
    integer = is.numeric(value) && length(value) == 1L && !is.na(value) &&
      is.finite(value) && value %% 1 == 0,
    numeric = is.numeric(value) && length(value) == 1L && !is.na(value) &&
      is.finite(value),
    character = is.character(value) && length(value) == 1L &&
      !is.na(value) && nzchar(value),
    character_vector = is.character(value) && length(value) > 0L &&
      !anyNA(value) && all(nzchar(value)),
    FALSE
  )
  if (!valid) {
    registry_schema_abort(
      sprintf("Value must have declared type `%s`.", value_type),
      domain, entry_id, field
    )
  }
  if (!is.null(definition$allowed_values) &&
      any(!value %in% unlist(definition$allowed_values, use.names = FALSE))) {
    registry_schema_abort(
      "Value is not included in the declared allowed values.",
      domain, entry_id, field
    )
  }
  invisible(TRUE)
}

registry_schema_abort <- function(message, domain = "registry",
                                  entry_id = NULL, field = NULL) {
  location <- domain
  if (!is.null(entry_id) && length(entry_id) == 1L &&
      !is.na(entry_id) && nzchar(entry_id)) {
    location <- paste0(location, "[", entry_id, "]")
  }
  if (!is.null(field) && nzchar(field)) {
    location <- paste0(location, "$", field)
  }

  condition <- structure(
    list(
      message = paste0("Registry validation failed at ", location, ": ", message),
      call = NULL,
      domain = domain,
      entry_id = entry_id,
      field = field
    ),
    class = c("registry_validation_error", "error", "condition")
  )
  stop(condition)
}
