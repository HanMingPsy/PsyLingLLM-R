#' Call an LLM via the registry
#'
#' Builds a protocol request from the resolved model registry entry. Provider-native
#' request parameters may be supplied through \code{optionals} or \code{...};
#' protocol-owned request fields remain controlled by the selected interface.
#' The user message is composed from \code{trial_prompt} and \code{material}. Optional
#' \code{system_content} and \code{assistant_content} are inserted before the user message
#' *only* if the registry template actually supports \code{"\${ROLE}"} in the messages shape.
#' Roles are not mapped by default; mapping is applied only when the caller supplies
#' \code{role_mapping}.
#'
#' URL resolution
#' \itemize{
#'   \item User-provided \code{api_url} always takes precedence;
#'   \item When \code{provider == "official"}, \code{api_url} is optional (falls back to
#'     registry \code{input.default_url});
#'   \item Otherwise (non-official), \code{api_url} is required.
#' }
#'
#' Provider parameters use a three-state contract:
#' \itemize{
#'   \item Missing: use registry \code{input.optional_defaults} if present; otherwise inject nothing;
#'   \item \code{NULL}: inject nothing;
#'   \item Named list: use user keys only (do not merge defaults).
#' }
#' Native Registry v2 builders send provider parameter names and values unchanged.
#' The legacy Registry v1 compatibility builder injects them through the
#' \code{"\${PARAMETER}"} template anchor when present.
#'
#' Response parsing is selected by the resolved registry interface. Native Registry v2
#' parsers interpret protocol-specific response and streaming event semantics; the
#' Registry v1 compatibility parser retains the historical path-based extraction rules.
#'
#' @param model_key Character(1). Registry key, e.g., \code{"deepseek-chat"} (official, no "@")
#'   or \code{"deepseek-chat@proxy"} (non-official, with "@provider").
#' @param generation_interface Character(1) or \code{NULL}. One of:
#'   \code{"chat"}, \code{"completion"}, \code{"messages"}, \code{"responses"},
#'   \code{"conversation"}, \code{"generate"}, or \code{"inference"}. If \code{NULL} and exactly
#'   one interface exists, it is selected automatically.
#' @param api_url Character(1) or \code{NULL}. Optional only when registry provider is
#'   \code{"official"} (falls back to \code{input.default_url}). For non-official providers,
#'   this is required. If provided, it always overrides the registry default.
#' @param trial_prompt Character(1) or \code{NULL}. Trial instruction text.
#' @param material Character(1) or \code{NULL}. Stimulus/item content to combine with
#'   \code{trial_prompt}.
#' @param system_content Character(1) or \code{NULL}. Optional system message to prepend.
#'   If \code{NULL} and registry \code{input.default_system} is set, that default is used.
#'   If both are missing and the template supports roles, a single warning is emitted and no
#'   system message is inserted.
#' @param assistant_content Optional static few-shot seed: character vector or a list of message
#'   objects (\code{list(role=..., content=...)}). These appear before rolling history and are
#'   preserved as-is.
#' @param api_key Character(1) or \code{NULL}. Injected into \code{"\${API_KEY}"} placeholders in
#'   headers/body.
#' @param optionals Missing, \code{NULL}, or a named list. Missing → use registry defaults if
#'   present; \code{NULL} → none; named list → user keys only (no merge).
#' @param stream Logical(1) or \code{NULL}. Overrides both \code{optionals$stream} and registry
#'   \code{streaming.enabled}.
#' @param role_mapping Named list or \code{NULL}. Optional override to map abstract roles
#'   ("system", "assistant", "user") to provider labels. By default, no mapping is applied.
#' @param timeout Numeric(1), default = 120. Request timeout in seconds.
#' @param return_raw Logical(1), default = \code{FALSE}. If \code{TRUE}, include raw request/response
#'   in the result.
#' @param debug Logical(1), default = \code{FALSE}. If \code{TRUE}, print diagnostic information.
#' @param ... Named provider-native request parameters. Names and values are
#'   sent unchanged. When the same name also appears in \code{optionals}, the
#'   value in \code{...} wins with a warning.
#'
#' @return A list with fields: \code{status}, \code{interface}, \code{model_key},
#'   \code{streaming}, \code{usage}, \code{answer}, \code{thinking}, and
#'   optionally \code{raw} or \code{error}. Transport and provider failures
#'   retain the compatibility status \code{599}; the original HTTP status and
#'   provider evidence remain available in \code{error}.
#'
#' @export
llm_caller <- function(model_key,
                       generation_interface = NULL,
                       api_url = NULL,
                       trial_prompt = NULL,
                       material = NULL,
                       system_content = NULL,
                       assistant_content = NULL,
                       api_key = NULL,
                       optionals,                 # no default: we need missing(optionals)
                       stream = NULL,
                       role_mapping = NULL,
                       timeout = 120,
                       return_raw = FALSE,
                       debug = FALSE,
                       ...) {
  if (!requireNamespace("jsonlite", quietly = TRUE) ||
      !requireNamespace("curl", quietly = TRUE)) {
    stop("Packages 'jsonlite' and 'curl' are required for llm_caller().")
  }

  # --- Resolve registry configuration ---------------------------------------
  registry_context <- registry_resolve_compatibility_context(
    model_key,
    generation_interface
  )
  config <- registry_context$resolved
  entry <- registry_project_compatibility_entry(
    registry_context$bundle,
    config
  )
  if (debug) message("[llm_caller] provider: ", entry$provider,
                     " | interface: ", entry$interface)

  call_context <- new_llm_call_context(
    trial_prompt = trial_prompt,
    material = material,
    system_content = system_content,
    assistant_content = assistant_content,
    api_key = api_key,
    optionals_missing = missing(optionals),
    optionals_value = if (missing(optionals)) NULL else optionals,
    stream = stream,
    role_mapping = role_mapping,
    api_url = api_url,
    timeout = timeout,
    provider_parameters = list(...)
  )
  request <- build_llm_request(
    builder_id = config$interface$request$builder,
    entry = runtime_request_builder_input(config, entry),
    context = call_context
  )
  request <- configure_llm_request_transport(request, config)
  if (debug) message("[llm_caller] url: ", request$url)

  # --- Transport, parsing, and result normalization -------------------------
  transport_response <- send_llm_request(request, debug = debug)
  parsed_response <- parse_llm_response(
    response = transport_response,
    parser_id = config$interface$response$parser,
    config = runtime_response_parser_config(config, entry),
    streaming = request$stream
  )
  normalize_llm_result(
    config = config,
    compatibility_entry = entry,
    request = request,
    transport_response = transport_response,
    parsed_response = parsed_response,
    return_raw = return_raw
  )
}

# ---- helpers (internal) -----------------------------------------------------

#' @keywords internal
resolve_api_url <- function(api_url, provider, default_url) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
  if (is.character(api_url) && length(api_url) == 1 && nzchar(api_url)) return(api_url)
  p <- tolower(trimws(provider %||% ""))
  if (identical(p, "official")) {
    if (is.character(default_url) && length(default_url) == 1 && nzchar(default_url)) return(default_url)
    stop("Official provider requires either a user api_url or a registry input.default_url.")
  }
  stop("Non-official provider requires api_url to be explicitly provided.")
}

#' @keywords internal
detect_message_keys_from_template <- function(body_tmpl) {
  out <- list(supports_roles = FALSE, container_key = "messages", role_key = "role", content_key = "content")
  if (!is.list(body_tmpl)) return(out)
  if (!("messages" %in% names(body_tmpl))) return(out)
  msgs <- body_tmpl$messages
  if (!is.list(msgs) || !length(msgs)) return(out)
  first <- msgs[[1]]
  if (!is.list(first)) return(out)
  nm <- names(first)
  rkey <- NULL; ckey <- NULL
  for (k in nm) {
    val <- first[[k]]
    if (is.character(val) && length(val) == 1) {
      if (identical(val, "${ROLE}"))    rkey <- k
      if (identical(val, "${CONTENT}")) ckey <- k
    }
  }
  if (!is.null(rkey) && !is.null(ckey)) {
    out$supports_roles <- TRUE
    out$role_key    <- rkey
    out$content_key <- ckey
  }
  out
}

#' @keywords internal
build_user_content <- function(trial_prompt, material) {
  tp <- if (!is.null(trial_prompt)) trimws(as.character(trial_prompt)) else ""
  mt <- if (!is.null(material))     trimws(as.character(material))     else ""
  if (nzchar(tp) && nzchar(mt)) return(paste0(tp, "\n\n", mt))
  if (nzchar(tp)) return(tp)
  if (nzchar(mt)) return(mt)
  ""
}

#' Resolve optionals tri-state at call site
#' @keywords internal
resolve_optionals_tristate <- function(optionals_missing, optionals_value, defaults = list()) {
  if (isTRUE(optionals_missing)) {
    return(if (length(defaults)) defaults else list())
  }
  if (is.null(optionals_value)) {
    return(list())  # NULL -> inject nothing
  }
  if (is.list(optionals_value)) {
    return(optionals_value)  # user only
  }
  list()
}

#' Inject optional parameters into a registry body via the \code{"\${PARAMETER}"} anchor
#'
#' This internal utility function merges a set of optional default values
#' into a model request body that contains a special anchor field
#' \code{"\${PARAMETER}"}.
#'
#' When the anchor is present, it is removed and replaced by each element
#' from the provided list of optionals, inserted as top-level fields in
#' the body.
#'
#' @param body A list representing the registry body, typically produced by
#'   a standardization or analysis step.
#' @param opt A named list of optional parameters to inject (e.g.,
#'   \code{list(stream = TRUE, temperature = 0.7)}).
#'
#' @return A modified copy of \code{body} with the anchor removed and optional
#'   parameters merged in. If the anchor is absent, the input is returned
#'   unchanged.
#'
#' @keywords internal
inject_optionals_anchor <- function(body, opt) {
  if (!is.list(body) || !"${PARAMETER}" %in% names(body)) {
    return(body)
  }

  body[["${PARAMETER}"]] <- NULL
  if (length(opt)) {
    for (k in names(opt)) {
      body[[k]] <- opt[[k]]
    }
  }
  body
}

#' Replace \code{"\${VARS}"} placeholders inside nested lists or atomic values
#'
#' This internal utility performs recursive placeholder substitution within a
#' nested R structure (lists or atomic vectors). Each occurrence of a placeholder
#' of the form \code{"\${VARNAME}"} is replaced by its corresponding value from
#' the provided mapping list. The function preserves input types where possible
#' (e.g., numeric, logical, or character) and leaves non-character atoms unchanged.
#'
#' @param x An R object (typically a list or character vector) that may contain
#'   placeholders such as \code{"\${MODEL}"} or \code{"\${CONTENT}"}.
#' @param mapping A named list providing key–value pairs for substitution, e.g.,
#'   \code{list(MODEL = "deepseek-chat", TEMPERATURE = 0.7)}.
#'
#' @return An object of the same structure as \code{x}, with placeholders replaced
#'   by corresponding values from \code{mapping}. Non-matching elements and
#'   non-character types are returned unchanged.
#'
#' @keywords internal
replace_placeholders <- function(x, mapping) {
  if (is.null(x)) return(NULL)

  # case 1: atomic and not character -> leave untouched
  if (is.atomic(x) && !is.character(x)) return(x)

  # case 2: single string element, perform substitution
  if (is.character(x) && length(x) == 1) {
    s <- x
    for (k in names(mapping)) {
      pat <- paste0("\\$\\{", k, "\\}")
      # if pattern not found, skip
      if (grepl(pat, s, perl = TRUE)) {
        val <- mapping[[k]]
        # numeric/logical → insert literal
        if (is.numeric(val) || is.logical(val)) {
          s <- sub(pat, val, s, perl = TRUE)
        } else {
          s <- sub(pat, as.character(val), s, perl = TRUE)
        }
      }
    }
    return(s)
  }

  # case 3: list → recurse
  if (is.list(x)) {
    for (i in seq_along(x)) x[[i]] <- replace_placeholders(x[[i]], mapping)
    return(x)
  }

  x
}


#' @title Check if an object is a message object
#' @description
#' Tests whether the input is a list that follows the message-object schema:
#' it must contain fields `role` and `content`, where `role` is a character
#' vector of length 1, and `content` is either a character vector or a list.
#'
#' @param x Any R object.
#'
#' @return A logical scalar. Returns `TRUE` if `x` conforms to the message
#' object structure; otherwise `FALSE`.
#'
#' @export
is_message_object <- function(x) {
  is.list(x) && !is.null(x$role) && !is.null(x$content) &&
    is.character(x$role) && length(x$role) == 1 &&
    (is.character(x$content) || is.list(x$content))
}

#' @title Normalize conversation history into message objects
#' @description
#' Converts various inputs (character vectors, lists of message objects,
#' or mixed lists) into a standardized list of message objects. This is
#' useful for constructing conversational contexts where heterogeneous
#' sources must be coerced into a uniform schema.
#'
#' Supported inputs:
#' \itemize{
#'   \item `NULL`: returns an empty list.
#'   \item character vector: each element becomes a message from the
#'         "assistant" role.
#'   \item list of message objects: preserved as-is, except roles are mapped.
#'   \item mixed list: keeps message objects; coerces string elements into
#'         assistant messages.
#' }
#'
#' @param x One of `NULL`, a character vector, or a list.
#' @param map_role A function that maps role names (e.g., `"assistant"`,
#'   `"user"`) to the target representation. Typically `tolower` or a custom
#'   mapper.
#'
#' @return A list of standardized message objects where each element is a
#' list with fields:
#' \describe{
#'   \item{role}{Character scalar indicating the message role.}
#'   \item{content}{Character vector or list holding the message content.}
#' }
#'
#' @seealso [is_message_object]
#'
#' @export
normalize_history_messages <- function(x, map_role) {
  out <- list()
  if (is.null(x)) return(out)

  # character vector: few-shot assistant texts
  if (is.character(x)) {
    for (s in as.vector(x)) {
      out[[length(out) + 1]] <- list(
        role    = map_role("assistant"),
        content = as.character(s)
      )
    }
    return(out)
  }

  # list: may contain message objects or raw strings
  if (is.list(x)) {
    # if *every* element is a message object, keep roles as-is (mapped)
    if (all(vapply(x, is_message_object, logical(1)))) {
      for (m in x) {
        out[[length(out) + 1]] <- list(
          role    = map_role(tolower(m$role)),
          content = m$content
        )
      }
      return(out)
    }
    # mixed list: preserve message objects; coerce others to assistant text
    for (m in x) {
      if (is_message_object(m)) {
        out[[length(out) + 1]] <- list(
          role    = map_role(tolower(m$role)),
          content = m$content
        )
      } else if (is.character(m) && length(m) == 1) {
        out[[length(out) + 1]] <- list(
          role    = map_role("assistant"),
          content = as.character(m)
        )
      }
    }
    return(out)
  }

  out
}
