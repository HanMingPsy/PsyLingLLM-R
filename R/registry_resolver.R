# Registry model resolution -------------------------------------------------

# Resolve one model into the canonical configuration consumed by runtime
# adapters. This function is internal until its Phase 2 contract is proven.
resolve_registry_entry <- function(model_key,
                                   generation_interface = NULL,
                                   registry = NULL,
                                   system_path = get_system_registry_path(),
                                   user_path = get_registry_path()) {
  registry_resolver_assert_string(model_key, "model_key")

  bundle <- registry_resolver_bundle(
    registry = registry,
    system_path = system_path,
    user_path = user_path
  )
  merged <- bundle$merged
  validate_registry_schema(merged)

  model_match <- registry_resolve_model_key(model_key, merged$models)
  model <- merged$models[[model_match$key]]
  interface_id <- registry_resolve_interface_id(
    generation_interface,
    model,
    merged$interfaces,
    model_match$key
  )
  interface <- merged$interfaces[[interface_id]]
  provider <- merged$providers[[model$provider]]

  defaults <- registry_resolve_defaults(model, interface, interface_id)
  request <- registry_compile_request(interface$request, provider, defaults)
  capabilities <- registry_resolve_capabilities(
    model,
    interface,
    merged$capabilities
  )

  config <- structure(
    list(
      schema_version = 2L,
      model = list(
        key = model_match$key,
        id = model$model_id,
        aliases = model$aliases %||% character(),
        matched_by = model_match$matched_by,
        available_interfaces = model$interfaces,
        metadata = model$metadata %||% list()
      ),
      provider = c(list(id = model$provider), provider),
      interface = list(
        id = interface_id,
        protocol = interface$protocol,
        request = request,
        transport = interface$transport,
        response = interface$response,
        streaming = interface$streaming %||% list(supported = FALSE),
        structured_output = interface$structured_output %||% list(),
        capabilities = interface$capabilities %||% list(),
        metadata = interface$metadata %||% list()
      ),
      capabilities = capabilities,
      defaults = defaults
    ),
    class = c("psylingllm_model_config", "list")
  )

  validate_resolved_registry_entry(config)
  config
}

registry_resolver_bundle <- function(registry, system_path, user_path) {
  if (is.null(registry)) {
    return(load_registry_bundle(
      system_path = system_path,
      user_path = user_path
    ))
  }

  if (!is.list(registry)) {
    registry_resolution_abort(
      "Registry input must be a registry document or loaded bundle.",
      reason = "invalid_registry"
    )
  }
  is_bundle <- "merged" %in% names(registry) &&
    is.list(registry$merged) &&
    identical(registry$merged$schema_version, 2L) &&
    all(c("providers", "interfaces", "capabilities", "models") %in%
      names(registry$merged))
  if (is_bundle) {
    validate_registry_schema(registry$merged)
    return(registry)
  }

  canonical <- if (length(registry) == 0L) {
    registry_empty_v2()
  } else {
    as_registry_v2(registry)
  }
  list(merged = canonical)
}

registry_resolve_model_key <- function(requested, models) {
  model_ids <- names(models)
  if (requested %in% model_ids) {
    return(list(key = requested, matched_by = "key"))
  }

  requested_normalized <- registry_normalize_lookup_key(requested)
  normalized_ids <- vapply(
    model_ids, registry_normalize_lookup_key, character(1)
  )
  key_matches <- model_ids[normalized_ids == requested_normalized]
  if (length(key_matches) == 1L) {
    return(list(key = key_matches[[1L]], matched_by = "normalized_key"))
  }
  if (length(key_matches) > 1L) {
    registry_resolution_abort(
      "Normalized model key matches more than one registry model.",
      model_key = requested,
      candidates = key_matches,
      reason = "ambiguous_model"
    )
  }

  alias_matches <- model_ids[vapply(models, function(model) {
    aliases <- model$aliases %||% character()
    any(vapply(
      aliases,
      function(alias) {
        identical(registry_normalize_lookup_key(alias), requested_normalized)
      },
      logical(1)
    ))
  }, logical(1))]

  if (length(alias_matches) == 1L) {
    return(list(key = alias_matches[[1L]], matched_by = "alias"))
  }
  if (length(alias_matches) > 1L) {
    registry_resolution_abort(
      "Model alias matches more than one registry model.",
      model_key = requested,
      candidates = alias_matches,
      reason = "ambiguous_alias"
    )
  }

  registry_resolution_abort(
    "Model was not found. Use a registry key or an explicit alias.",
    model_key = requested,
    reason = "model_not_found"
  )
}

registry_resolve_interface_id <- function(requested, model, interfaces,
                                          model_key) {
  available <- model$interfaces
  if (is.null(requested)) {
    if (!is.null(model$default_interface)) {
      return(model$default_interface)
    }
    if (length(available) == 1L) {
      return(available[[1L]])
    }
    registry_resolution_abort(
      "Multiple interfaces are available; specify `generation_interface`.",
      model_key = model_key,
      candidates = available,
      reason = "ambiguous_interface"
    )
  }
  registry_resolver_assert_string(
    requested, "generation_interface", model_key = model_key
  )

  if (requested %in% available) {
    return(requested)
  }

  requested_normalized <- registry_normalize_lookup_key(requested)
  candidates <- available[vapply(available, function(interface_id) {
    interface <- interfaces[[interface_id]]
    labels <- c(
      interface_id,
      interface$protocol,
      interface$metadata$legacy_interface %||% character()
    )
    any(vapply(
      labels,
      function(label) {
        identical(registry_normalize_lookup_key(label), requested_normalized)
      },
      logical(1)
    ))
  }, logical(1))]

  if (length(candidates) == 1L) {
    return(candidates[[1L]])
  }
  if (length(candidates) > 1L) {
    registry_resolution_abort(
      "Requested interface matches more than one model interface.",
      model_key = model_key,
      interface = requested,
      candidates = candidates,
      reason = "ambiguous_interface"
    )
  }

  registry_resolution_abort(
    "Requested interface is not available for this model.",
    model_key = model_key,
    interface = requested,
    candidates = available,
    reason = "interface_not_found"
  )
}

registry_resolve_defaults <- function(model, interface, interface_id) {
  defaults <- list()
  defaults <- registry_overlay_values(
    defaults, interface$request$defaults %||% list()
  )
  defaults <- registry_overlay_values(
    defaults, interface$defaults %||% list()
  )
  if (identical(interface_id, model$default_interface)) {
    defaults <- registry_overlay_values(defaults, model$defaults %||% list())
  }
  defaults
}

registry_compile_request <- function(request, provider, defaults) {
  provider_headers <- provider$headers %||% list()
  request_headers <- request$headers %||% list()
  request$headers <- registry_overlay_values(
    provider_headers, request_headers
  )
  request$defaults <- defaults
  request$url <- registry_resolve_request_url(request, provider)
  request
}

registry_resolve_request_url <- function(request, provider) {
  if (!is.null(request$url)) {
    return(request$url)
  }
  base_url <- provider$base_url
  path <- request$path
  if (is.null(base_url)) {
    return(NULL)
  }
  if (is.null(path)) {
    return(base_url)
  }
  paste0(sub("/+$", "", base_url), "/", sub("^/+", "", path))
}

registry_resolve_capabilities <- function(model, interface, definitions) {
  values <- lapply(definitions, function(definition) {
    if ("default" %in% names(definition)) definition$default else NULL
  })
  values <- registry_overlay_values(values, model$capabilities)

  list(
    values = values,
    definitions = definitions,
    bindings = interface$capabilities %||% list()
  )
}

registry_overlay_values <- function(base, override) {
  if (length(override) == 0L) {
    return(base)
  }
  for (name in names(override)) {
    base[name] <- list(override[[name]])
  }
  base
}

registry_normalize_lookup_key <- function(value) {
  value <- tolower(trimws(value))
  value <- gsub("[/:_\\s]+", "-", value)
  value <- gsub("-{2,}", "-", value)
  value <- sub("^-", "", value)
  sub("-$", "", value)
}

validate_resolved_registry_entry <- function(config) {
  required <- c(
    "schema_version", "model", "provider", "interface", "capabilities",
    "defaults"
  )
  if (!is.list(config) || !identical(names(config), required)) {
    registry_resolution_abort(
      "Compiled configuration has an invalid top-level structure.",
      reason = "invalid_compiled_config"
    )
  }
  if (!identical(config$schema_version, 2L)) {
    registry_resolution_abort(
      "Compiled configuration must use schema version 2.",
      reason = "invalid_compiled_config"
    )
  }
  registry_resolver_assert_string(config$model$key, "model.key")
  registry_resolver_assert_string(config$model$id, "model.id")
  registry_resolver_assert_string(config$provider$id, "provider.id")
  registry_resolver_assert_string(config$interface$id, "interface.id")

  components <- registry_v2_component_ids()
  if (!config$interface$protocol %in% components$protocols ||
      !config$interface$request$builder %in% components$request_builders ||
      !config$interface$transport$non_stream %in% components$transports ||
      !config$interface$response$parser %in% components$response_parsers) {
    registry_resolution_abort(
      "Compiled configuration contains an unsupported runtime component.",
      model_key = config$model$key,
      interface = config$interface$id,
      reason = "unsupported_component"
    )
  }
  if (!is.null(config$interface$request$url)) {
    registry_resolver_assert_string(
      config$interface$request$url,
      "interface.request.url",
      model_key = config$model$key
    )
  }
  if (!is.list(config$defaults) || !is.list(config$capabilities$values)) {
    registry_resolution_abort(
      "Compiled defaults and capability values must be lists.",
      model_key = config$model$key,
      reason = "invalid_compiled_config"
    )
  }

  invisible(TRUE)
}

registry_resolver_assert_string <- function(value, field, model_key = NULL) {
  valid <- is.character(value) && length(value) == 1L &&
    !is.na(value) && nzchar(value)
  if (!valid) {
    registry_resolution_abort(
      paste0("`", field, "` must be a non-empty character scalar."),
      model_key = model_key,
      reason = "invalid_argument"
    )
  }
  invisible(TRUE)
}

registry_resolution_abort <- function(message, model_key = NULL,
                                      interface = NULL, candidates = NULL,
                                      reason = NULL) {
  location <- "Registry resolution failed"
  if (!is.null(model_key)) {
    location <- paste0(location, " for model `", model_key, "`")
  }
  if (!is.null(interface)) {
    location <- paste0(location, " and interface `", interface, "`")
  }
  if (!is.null(candidates) && length(candidates) > 0L) {
    message <- paste0(
      message, " Candidates: ", paste(candidates, collapse = ", "), "."
    )
  }

  condition <- structure(
    list(
      message = paste0(location, ": ", message),
      call = NULL,
      model_key = model_key,
      interface = interface,
      candidates = candidates,
      reason = reason
    ),
    class = c("registry_resolution_error", "error", "condition")
  )
  stop(condition)
}
