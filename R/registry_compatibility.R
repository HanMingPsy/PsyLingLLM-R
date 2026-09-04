# Registry compatibility conversion -----------------------------------------

# Convert a supported registry document to the Registry v2 intermediate form.
# This is intentionally internal until the Phase 2 resolver contract is fixed.
as_registry_v2 <- function(registry) {
  validate_registry_schema(registry)

  if ("schema_version" %in% names(registry)) {
    return(registry)
  }

  converted <- convert_registry_v1_to_v2(registry)
  validate_registry_schema(converted)
  converted
}

convert_registry_v1_to_v2 <- function(registry) {
  providers <- list()
  interfaces <- list()
  models <- list()

  for (model_key in names(registry)) {
    legacy_interfaces <- registry[[model_key]]
    provider <- convert_legacy_provider(model_key, legacy_interfaces)
    provider_id <- provider$id
    provider$id <- NULL

    if (!is.null(providers[[provider_id]]) &&
        !identical(providers[[provider_id]], provider)) {
      provider_id <- paste0(provider_id, ".", registry_compatibility_slug(model_key))
    }
    providers[[provider_id]] <- provider

    interface_ids <- character()
    reasoning <- FALSE
    streaming <- FALSE

    for (interface_name in names(legacy_interfaces)) {
      interface_id <- paste(
        "legacy",
        registry_compatibility_slug(model_key),
        registry_compatibility_slug(interface_name),
        sep = "."
      )
      if (interface_id %in% names(interfaces)) {
        registry_schema_abort(
          "Legacy names produce a duplicate interface identifier.",
          "interfaces", interface_id, "id"
        )
      }

      legacy_entry <- legacy_interfaces[[interface_name]]
      converted <- convert_legacy_interface(legacy_entry, interface_name)
      interfaces[[interface_id]] <- converted
      interface_ids <- c(interface_ids, interface_id)
      reasoning <- reasoning || registry_compatibility_bool(legacy_entry$reasoning)
      streaming <- streaming || !is.null(legacy_entry$streaming$delta_path)
    }

    first_entry <- legacy_interfaces[[1L]]
    model <- list(
      provider = provider_id,
      model_id = registry_compatibility_model_id(model_key, first_entry),
      interfaces = interface_ids,
      capabilities = list(
        reasoning = reasoning,
        streaming = streaming
      ),
      metadata = list(source_schema_version = 1L)
    )
    if (length(interface_ids) == 1L) {
      model$default_interface <- interface_ids[[1L]]
      model <- model[c(
        "provider", "model_id", "interfaces", "default_interface",
        "capabilities", "metadata"
      )]
    }
    models[[model_key]] <- model
  }

  list(
    schema_version = 2L,
    providers = providers,
    interfaces = interfaces,
    capabilities = list(
      reasoning = list(value_type = "logical", default = FALSE),
      streaming = list(value_type = "logical", default = FALSE)
    ),
    models = models
  )
}

convert_legacy_provider <- function(model_key, interfaces) {
  labels <- vapply(
    interfaces,
    function(entry) as.character(entry$provider %||% "unknown")[[1L]],
    character(1)
  )
  urls <- vapply(
    interfaces,
    function(entry) as.character(entry$input$default_url %||% "")[[1L]],
    character(1)
  )
  identity <- registry_compatibility_provider_identity(
    model_key, labels[[1L]], urls[[1L]]
  )

  list(
    id = identity,
    type = registry_compatibility_provider_type(labels),
    metadata = list(
      legacy_provider_labels = as.list(stats::setNames(labels, names(interfaces)))
    )
  )
}

convert_legacy_interface <- function(entry, interface_name) {
  input <- entry$input %||% list()
  output <- entry$output %||% list()
  stream <- entry$streaming %||% list()
  defaults <- unwrap_typed_defaults(input$optional_defaults %||% list())
  stream_parameter <- as.character(stream$param_name %||% "stream")[[1L]]
  parameter_names <- unique(c(names(defaults), stream_parameter))
  parameter_map <- as.list(stats::setNames(parameter_names, parameter_names))

  request <- list(
    builder = "legacy_template_v1",
    method = "POST",
    encoding = "json",
    headers = input$headers %||% list(),
    body = input$body %||% list(),
    parameter_map = parameter_map,
    defaults = defaults
  )
  if (!is.null(input$default_url) && nzchar(as.character(input$default_url)[[1L]])) {
    request$url <- as.character(input$default_url)[[1L]]
    request <- request[c(
      "builder", "method", "encoding", "url", "headers", "body",
      "parameter_map", "defaults"
    )]
  }
  if (!is.null(input$fallback_body)) {
    request$fallback_body <- input$fallback_body
  }
  if (!is.null(input$default_system)) {
    request$default_system <- as.character(input$default_system)[[1L]]
  }
  if (!is.null(input$role_mapping)) {
    request$role_mapping <- registry_compatibility_role_mapping(
      input$role_mapping
    )
  }

  selectors <- registry_compatibility_selectors(output, stream)
  transport <- list(non_stream = "http_json")
  if (!is.null(stream$delta_path)) {
    transport$stream <- "sse_json"
  }

  interface <- list(
    protocol = "legacy_v1",
    request = request,
    transport = transport,
    response = list(parser = "legacy_paths_v1", selectors = selectors),
    streaming = list(
      supported = !is.null(stream$delta_path),
      request_parameter = stream_parameter,
      request_value = TRUE
    ),
    metadata = list(
      source_schema_version = 1L,
      legacy_interface = interface_name,
      legacy_provider_label = as.character(entry$provider %||% "unknown")[[1L]],
      legacy_streaming_enabled = registry_compatibility_bool(stream$enabled)
    )
  )
  if (registry_compatibility_bool(entry$reasoning)) {
    interface$capabilities <- list(
      reasoning = list(response_channel = "reasoning")
    )
  }

  interface
}

registry_compatibility_role_mapping <- function(mapping) {
  if (!is.list(mapping) || is.null(names(mapping))) {
    return(list())
  }
  keep <- vapply(mapping, function(value) {
    is.character(value) && length(value) == 1L &&
      !is.na(value) && nzchar(value)
  }, logical(1))
  mapping[keep]
}

registry_compatibility_selectors <- function(output, stream) {
  paths <- list(
    answer = output$respond_path,
    reasoning = output$thinking_path,
    request_id = output$id_path,
    object = output$object_path,
    usage_prompt = output$token_usage_path$prompt,
    usage_completion = output$token_usage_path$completion,
    answer_delta = stream$delta_path,
    reasoning_delta = stream$thinking_delta_path
  )
  selectors <- lapply(paths, registry_compatibility_path)
  selectors[!vapply(selectors, is.null, logical(1))]
}

registry_compatibility_path <- function(path) {
  if (is.null(path) || length(path) == 0L) {
    return(NULL)
  }

  raw_segments <- coerce_path_segments(path)
  segments <- unlist(lapply(raw_segments, function(segment) {
    if (!is.character(segment)) {
      return(segment)
    }
    parts <- strsplit(segment, ".", fixed = TRUE)[[1L]]
    parts[parts == ""] <- "*"
    parts
  }), recursive = FALSE, use.names = FALSE)

  if (length(segments) == 0L) NULL else segments
}

registry_compatibility_provider_identity <- function(model_key, label, url) {
  deployment_labels <- c("official", "proxy", "local", "custom", "unknown")
  label_slug <- registry_compatibility_slug(label)
  if (!label_slug %in% deployment_labels) {
    return(label_slug)
  }

  host <- sub("^https?://", "", url, ignore.case = TRUE)
  host <- sub("[/:].*$", "", host)
  host_parts <- strsplit(tolower(host), ".", fixed = TRUE)[[1L]]
  host_parts <- setdiff(host_parts, c("", "www", "api", "v1", "com", "org", "net"))
  if (length(host_parts) > 0L) {
    return(registry_compatibility_slug(host_parts[[length(host_parts)]]))
  }

  paste0("legacy.", registry_compatibility_slug(model_key))
}

registry_compatibility_provider_type <- function(labels) {
  labels <- tolower(labels)
  if (all(labels == "official")) return("official")
  if (any(grepl("local", labels, fixed = TRUE))) return("local")
  if (any(grepl("proxy", labels, fixed = TRUE))) return("proxy")
  "custom"
}

registry_compatibility_model_id <- function(model_key, entry) {
  body_model <- entry$input$body$model
  if (is.character(body_model) && length(body_model) == 1L && nzchar(body_model)) {
    return(body_model)
  }
  sub("@.*$", "", model_key)
}

registry_compatibility_slug <- function(value) {
  value <- tolower(as.character(value)[[1L]])
  value <- gsub("[^a-z0-9._-]+", "-", value)
  value <- gsub("^[^a-z]+", "", value)
  value <- gsub("-+$", "", value)
  if (!nzchar(value)) "legacy" else value
}

registry_compatibility_bool <- function(value) {
  if (is.logical(value) && length(value) == 1L) {
    return(isTRUE(value))
  }
  if (is.numeric(value) && length(value) == 1L) {
    return(!is.na(value) && value != 0)
  }
  if (is.character(value) && length(value) == 1L) {
    return(tolower(trimws(value)) %in% c("true", "t", "yes", "y", "on", "1"))
  }
  FALSE
}
