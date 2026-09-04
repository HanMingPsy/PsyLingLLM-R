#' Retrieve a registry interface entry (inputs / outputs / streaming)
#'
#' Look up a model first in the **user registry** (by default at
#' `get_registry_path()`), and if not found, fall back to the **system
#' registry** located at `inst/registry/system_registry.yaml`. Select an interface
#' (e.g., `"chat"`, `"completion"`) and return a **normalized** node ready for
#' request assembly.
#'
#' Normalization rules:
#' - `input.role_mapping` may be partially specified or absent; we keep it as is
#'   (possibly `NULL` per key). Downstream callers decide whether to apply it.
#' - Boolean-like values such as `"yes"/"no"`, `"true"/"false"`, `0/1` are
#'   coerced to logicals for `reasoning` and `streaming.enabled`.
#' - `optional_defaults` scalars are lightly normalized (numeric-like strings →
#'   numeric; boolean-like strings → logical) while preserving unknown vendor
#'   fields.
#' - Output path fields (e.g., `respond_path`, `delta_path`) are **left as-is**
#'   (e.g., `list("choices..message.content")`).
#'
#' Model key conventions:
#' - Official providers typically use keys **without** `@` (e.g., `"deepseek-chat"`).
#' - Non-official providers should use keys **with** `@provider`
#'   (e.g., `"deepseek-chat@proxy"`).
#'
#' @param model_key Character(1). Either `"<model>"` or `"<model>@<provider>"`.
#' @param generation_interface Character(1) or NULL. One of `"chat"`, `"completion"`,
#'   `"messages"`, `"conversation"`, `"responses"`, `"generate"`, `"inference"`.
#'   If `NULL` and the model has exactly one interface, that interface is selected.
#' @param path Character(1). User registry path. Defaults to `get_registry_path()`.
#'
#' @return A list with fields:
#' \describe{
#'   \item{model_key}{Resolved key (may include `@provider`).}
#'   \item{interface}{Selected interface name.}
#'   \item{provider}{Provider label from the registry node (normalized to lower).}
#'   \item{reasoning}{Logical. Whether the provider exposes reasoning fields.}
#'   \item{input}{List with `default_url`, `headers`, `body`, `fallback_body`,
#'   `optional_defaults`, `default_system`, and `role_mapping` (kept as provided).}
#'   \item{output}{List with `respond_path`, `thinking_path`, `id_path`,
#'   `object_path`, and optional `token_usage_path`.}
#'   \item{streaming}{List with `enabled`, `delta_path`, `thinking_delta_path`.}
#'   \item{interfaces}{Character vector of available interfaces for this model.}
#' }
#' @examples
#' \dontrun{
#'   ent <- get_registry_entry("deepseek-chat", generation_interface = "chat")
#'   ent$input$role_mapping$user
#'   ent$output$respond_path
#' }
#' @export
get_registry_entry <- function(model_key,
                               generation_interface = NULL,
                               path = get_registry_path()) {
  if (!requireNamespace("yaml", quietly = TRUE)) {
    stop("Package 'yaml' is required for get_registry_entry().")
  }

  context <- registry_resolve_compatibility_context(
    model_key,
    generation_interface,
    path
  )
  registry_project_compatibility_entry(context$bundle, context$resolved)
}

registry_resolve_compatibility_context <- function(
    model_key,
    generation_interface = NULL,
    path = get_registry_path()) {
  bundle <- load_registry_bundle(
    system_path = get_system_registry_path(),
    user_path = path
  )
  resolved <- tryCatch(
    resolve_registry_entry(
      model_key,
      generation_interface = generation_interface,
      registry = bundle
    ),
    registry_resolution_error = function(error) {
      registry_entry_compatibility_abort(
        error,
        generation_interface,
        bundle$merged$interfaces
      )
    }
  )
  list(bundle = bundle, resolved = resolved)
}

registry_project_compatibility_entry <- function(bundle, resolved) {
  legacy <- registry_find_legacy_entry(bundle, resolved)
  if (!is.null(legacy)) {
    return(normalize_registry_entry(
      legacy$entry,
      resolved$model$key,
      legacy$interface
    ))
  }

  registry_project_resolved_entry(resolved)
}

# ---- internal helpers -------------------------------------------------------

#' Normalize a raw registry entry (internal, legacy/export-free)
#'
#' Backward-compatible alias kept for older tests/fixtures that call this directly.
#' Prefer the closure `normalize_registry_entry()` inside `get_registry_entry()`.
#' @keywords internal
normalize_registry_entry <- function(entry, model_key, generation_interface) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
  boolify <- function(x) {
    if (is.logical(x)) return(x)
    if (is.character(x)) {
      lx <- tolower(trimws(x))
      if (lx %in% c("yes","true","y","1"))  return(TRUE)
      if (lx %in% c("no","false","n","0"))  return(FALSE)
    }
    if (is.numeric(x) && length(x) == 1) return(!is.na(x) && x != 0)
    isTRUE(x)
  }

  provider   <- tolower(as.character(entry$provider %||% "unknown"))
  reasoning  <- boolify(entry$reasoning %||% FALSE)

  inp <- entry$input %||% list()

  optional_defaults_raw <- inp$optional_defaults %||% list()
  opt <- unwrap_typed_defaults(optional_defaults_raw)


  role_mapping_raw <- inp$role_mapping %||% inp$role_map %||% NULL
  role_mapping <- {
    out <- list(system = NULL, user = NULL, assistant = NULL, tool = NULL)
    if (is.list(role_mapping_raw)) {
      nm <- tolower(names(role_mapping_raw))
      for (k in names(out)) {
        i <- which(nm == k)[1]
        if (length(i) && !is.na(i)) {
          val <- role_mapping_raw[[i]]
          if (is.character(val) && length(val) == 1 && nzchar(val)) out[[k]] <- val
        }
      }
    }
    out
  }

  list(
    model_key  = model_key,
    interface  = generation_interface,
    provider   = provider,
    reasoning  = reasoning,
    input      = list(
      default_url       = inp$default_url %||% NULL,
      headers           = inp$headers %||% list(),
      body              = inp$body %||% list(),
      fallback_body     = inp$fallback_body %||% NULL,
      optional_defaults = opt,
      default_system    = inp$default_system %||% NULL,
      role_mapping      = role_mapping
    ),
    output     = {
      out <- entry$output %||% list()
      list(
        respond_path     = out$respond_path %||% NULL,
        thinking_path    = out$thinking_path %||% NULL,
        id_path          = out$id_path %||% NULL,
        object_path      = out$object_path %||% NULL,
        token_usage_path = out$token_usage_path %||% NULL
      )
    },
    streaming  = {
      st <- entry$streaming %||% list()
      list(
        enabled             = boolify(st$enabled %||% FALSE),
        delta_path          = st$delta_path %||% NULL,
        thinking_delta_path = st$thinking_delta_path %||% NULL,
        param_name          = st$param_name %||% NULL
      )
    },
    interfaces = names(entry %||% list())
  )
}

registry_find_legacy_entry <- function(bundle, resolved) {
  interface_name <- resolved$interface$metadata$legacy_interface
  if (is.null(interface_name) || is.null(bundle$raw)) {
    return(NULL)
  }

  for (source in c("user", "system", "default")) {
    registry <- bundle$raw[[source]]
    if (is.null(registry) || length(registry) == 0L) {
      next
    }
    if ("schema_version" %in% names(registry)) {
      if (!is.null(registry$models[[resolved$model$key]])) {
        return(NULL)
      }
      next
    }
    model <- registry[[resolved$model$key]]
    if (!is.null(model)) {
      entry <- model[[interface_name]]
      if (is.null(entry)) {
        return(NULL)
      }
      return(list(entry = entry, interface = interface_name))
    }
  }

  NULL
}

registry_project_resolved_entry <- function(resolved) {
  request <- resolved$interface$request
  selectors <- resolved$interface$response$selectors %||% list()
  token_usage_path <- list(
    prompt = registry_public_selector(selectors$usage_prompt),
    completion = registry_public_selector(selectors$usage_completion)
  )
  if (all(vapply(token_usage_path, is.null, logical(1)))) {
    token_usage_path <- NULL
  }

  list(
    model_key = resolved$model$key,
    interface = resolved$interface$id,
    provider = tolower(resolved$provider$type),
    reasoning = isTRUE(resolved$capabilities$values$reasoning),
    input = list(
      default_url = request$url %||% NULL,
      headers = request$headers %||% list(),
      body = request$body %||% list(),
      fallback_body = request$fallback_body %||% NULL,
      optional_defaults = resolved$defaults,
      default_system = request$default_system %||% NULL,
      role_mapping = registry_public_role_mapping(request$role_mapping)
    ),
    output = list(
      respond_path = registry_public_selector(selectors$answer),
      thinking_path = registry_public_selector(selectors$reasoning),
      id_path = registry_public_selector(selectors$request_id),
      object_path = registry_public_selector(selectors$object),
      token_usage_path = token_usage_path
    ),
    streaming = list(
      enabled = isTRUE(
        resolved$interface$metadata$legacy_streaming_enabled
      ),
      delta_path = registry_public_selector(selectors$answer_delta),
      thinking_delta_path = registry_public_selector(
        selectors$reasoning_delta
      ),
      param_name = resolved$interface$streaming$request_parameter %||% NULL
    ),
    interfaces = resolved$model$available_interfaces
  )
}

registry_public_selector <- function(selector) {
  if (is.null(selector)) {
    return(NULL)
  }
  segments <- as.list(selector)
  lapply(segments, function(segment) {
    if (identical(segment, "*")) "" else segment
  })
}

registry_public_role_mapping <- function(mapping) {
  out <- list(system = NULL, user = NULL, assistant = NULL, tool = NULL)
  if (!is.list(mapping)) {
    return(out)
  }
  for (name in intersect(names(out), tolower(names(mapping)))) {
    index <- which(tolower(names(mapping)) == name)[[1L]]
    value <- mapping[[index]]
    if (is.character(value) && length(value) == 1L && nzchar(value)) {
      out[[name]] <- value
    }
  }
  out
}

registry_entry_compatibility_abort <- function(error, requested_interface,
                                               interfaces) {
  available <- registry_public_interface_labels(
    error$candidates,
    interfaces
  )
  if (identical(error$reason, "model_not_found")) {
    stop(
      sprintf(
        "Model '%s' not found in user or system registry.",
        error$model_key
      ),
      call. = FALSE
    )
  }
  if (identical(error$reason, "interface_not_found")) {
    stop(
      sprintf(
        "Interface '%s' not found. Available: %s",
        requested_interface,
        paste(available, collapse = ", ")
      ),
      call. = FALSE
    )
  }
  if (identical(error$reason, "ambiguous_interface") &&
      is.null(requested_interface)) {
    stop(
      sprintf(
        paste0(
          "Multiple interfaces available: %s. ",
          "Please specify `generation_interface`."
        ),
        paste(available, collapse = ", ")
      ),
      call. = FALSE
    )
  }
  stop(error)
}

registry_public_interface_labels <- function(ids, interfaces) {
  vapply(ids %||% character(), function(id) {
    interfaces[[id]]$metadata$legacy_interface %||% id
  }, character(1))
}
