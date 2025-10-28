#' Safe excerpt for logs
#' @param x character
#' @param n max chars
#' @keywords internal
trim_excerpt <- function(x, n = 160) {
  if (is.null(x) || !length(x)) return("")
  s <- as.character(x[[1]])
  if (!nzchar(s)) return("")
  if (nchar(s) > n) paste0(substr(s, 1, n), " \u2026") else s
}


#' Extract usage field names from a parsed non-streaming response
#'
#' Returns the names of fields inside the `usage` object if present.
#' Safely handles absent/unnamed/atomic cases and always returns a character vector.
#'
#' @param ns_parsed A parsed JSON-like list (e.g., `res$non_stream$parsed`).
#' @return A character vector of usage field names (possibly length 0).
#' @examples
#' # extract_usage_fields(list(usage = list(prompt_tokens=12, total_tokens=34)))
#' # -> c("prompt_tokens","total_tokens")
#' @export
extract_usage_fields <- function(ns_parsed) {
  if (is.null(ns_parsed)) return(character())
  usage <- tryCatch(ns_parsed$usage, error = function(e) NULL)
  if (is.null(usage)) return(character())

  nm <- names(usage)
  if (length(nm)) return(unique(as.character(nm)))

  # Fallbacks for rare unnamed structures
  if (is.list(usage)) {
    # try to infer names from typical OpenAI-like fields if present
    known <- c("prompt_tokens", "completion_tokens", "total_tokens")
    present <- intersect(known, unlist(lapply(usage, function(x) names(x)), use.names = FALSE))
    return(unique(as.character(present)))
  }
  character()
}


#' Does a value contain any non-empty textual content?
#'
#' Robustly checks lists, vectors, raw, and scalars. Returns a single TRUE/FALSE.
#'
#' @param val Any R object (e.g., result of json_get_by_path()).
#' @return logical(1)
#' @examples
#' has_nonempty_text("hi")         # TRUE
#' has_nonempty_text(c("", "x"))   # TRUE
#' has_nonempty_text(character())  # FALSE
#' has_nonempty_text(NULL)         # FALSE
#' @export
has_nonempty_text <- function(val) {
  if (is.null(val) || length(val) == 0) return(FALSE)
  if (is.raw(val)) val <- rawToChar(val)
  if (is.list(val)) val <- unlist(val, recursive = TRUE, use.names = FALSE)
  if (length(val) == 0) return(FALSE)
  ch <- suppressWarnings(as.character(val))
  if (length(ch) == 0) return(FALSE)
  any(nzchar(ch) & !is.na(ch))
}


#' Normalize any path spec to a flat key AND, if needed, a regex with wildcard index
#' @param path mixed (list("a","b"), "a.b", 'list("a","b")')
#' @return list(key=character(1), regex=character(1) or NA)
#' @export
normalize_path_key_with_regex <- function(path) {
  key <- normalize_path_key(path)
  if (!nzchar(key)) return(list(key = "", regex = NA_character_))
  if (grepl("\\.\\.", key, fixed = TRUE)) {
    return(list(key = key, regex = flat_key_to_regex(key)))
  }
  list(key = key, regex = NA_character_)
}


#' Turn a flat key with ".." into a regex for any numeric index
#' "choices..delta.content" -> "^choices\\.[0-9]+\\.delta\\.content$"
#' Handles start/middle/end ".." safely.
#' @param key character(1) flat key
#' @return character(1) regex
#' @keywords internal
#' @export
flat_key_to_regex <- function(key) {
  if (!nzchar(key)) return("^$")
  rx <- key
  # escape regex meta except the wildcard we will inject
  rx <- gsub("\\.", "\\\\.", rx, fixed = TRUE)
  # replace escaped double dot with numeric index wildcard
  rx <- gsub("\\\\\\.\\\\\\.", "\\\\.[0-9]+\\\\.", rx)
  # in case the key ended with "..something" or started with "something.."
  rx <- gsub("\\\\\\.$", "\\\\.[0-9]+", rx)           # trailing dot (rare)
  rx <- gsub("^\\\\\\.", "[0-9]+\\\\.", rx)           # leading dot (rare)
  paste0("^", rx, "$")
}


#' Normalize a path into the flat key format used by flatten_json_paths()
#' Accepts: list("a","b"), c("a","b"), "a.b", 'list("a","b")', numeric segments
#' @param path mixed
#' @return character(1) like "choices.0.delta.content"
#' @keywords internal
#' @export
normalize_path_key <- function(path) {
  segs <- coerce_path_segments(path)
  if (!length(segs)) return("")
  segs_chr <- vapply(segs, function(s) {
    # keep numbers as-is to match flatten_json_paths(keep_numeric=TRUE)
    if (is.numeric(s)) as.character(as.integer(s)) else as.character(s)
  }, character(1))
  paste(segs_chr, collapse = ".")
}


#' Reconstruct stream text from raw_json using exact or wildcard-index matching
#' Falls back to regex (for ".." wildcard) if exact match finds nothing.
#' @param raw_json list of event JSON objects
#' @param path path spec (list/"a.b"/'list("a","b")')
#' @importFrom stats na.omit
#' @return single character concatenation ("" if none)
#' @export
stream_reconstruct_text <- function(raw_json, path) {
  if (is.null(raw_json) || !length(raw_json)) return("")
  nr <- normalize_path_key_with_regex(path)
  key <- nr$key
  rx  <- nr$regex

  out <- character()
  for (ev in seq_along(raw_json)) {
    flat <- tryCatch(
      flatten_json_paths(raw_json[[ev]], keep_numeric = TRUE),
      error = function(e) data.frame()
    )
    if (!nrow(flat) || !("path" %in% names(flat)) || !("value" %in% names(flat))) next
    p <- as.character(flat$path)

    # 1) exact match first
    hit <- flat$value[p == key]
    # 2) wildcard-index fallback
    if ((!length(hit) || all(is.na(hit))) && !is.na(rx)) {
      hit <- flat$value[grepl(rx, p)]
    }

    if (length(hit)) {
      ch <- suppressWarnings(as.character(unlist(hit, recursive = TRUE, use.names = FALSE)))
      if (length(ch)) out <- c(out, ch)
    }
  }
  paste(na.omit(out), collapse = "")
}


#' Escape replacement string for gsub(perl=TRUE) (escapes '\' and '$')
#' @keywords internal
escape_replacement <- function(x) {
  if (!is_scalar_chr(x)) return("")
  s <- x
  s <- gsub("\\\\", "\\\\\\\\", s, perl = TRUE)  # '\' -> '\\'
  s <- gsub("\\$",  "\\\\$",   s, perl = TRUE)  # '$' -> '\$'
  s
}


#' Return TRUE if x is a length-1, non-NA character
#' @keywords internal
is_scalar_chr <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x)
}

#' Detect embedded <think> tags in model output
#'
#' This checks if any text fragment contains both <think> and </think>.
#'
#' @param x Character or list of characters.
#' @return logical(1)
#' @export
detect_embedded_think_tag <- function(x) {
  if (is.null(x)) return(FALSE)
  txt <- paste(unlist(x, use.names = FALSE), collapse = " ")
  grepl("<think>", txt, fixed = TRUE) && grepl("</think>", txt, fixed = TRUE)
}


#' Return the system registry path (internal helper)
#'
#' @return Character(1) absolute path to PsyLingLLM system registry file.
#' @keywords internal
get_system_registry_path <- function() {
  system.file("registry/system_registry.yaml", package = "PsyLingLLM")
}

#' Load the system LLM registry
#'
#' This function loads the registry configuration from the internal
#' YAML file shipped with the \pkg{PsyLingLLM} package.
#' The registry contains model entries, interfaces, and defaults
#' used by functions such as \code{llm_register()},
#' \code{get_model_config()}, and \code{trial_experiment()}.
#'
#' @return A named list corresponding to the parsed registry YAML.
#'   Each entry is a model node (see \code{build_registry_entry_from_analysis()}).
#'   Returns \code{NULL} if the file does not exist or cannot be parsed.
#' @export
#' @examples
#' reg <- load_registry()
#' names(reg)
load_registry <- function() {
  path <- get_system_registry_path()
  if (!file.exists(path)) {
    warning("System registry file not found: ", path)
    return(NULL)
  }

  # Load safely via yaml
  tryCatch(
    yaml::read_yaml(path),
    error = function(e) {
      warning("Failed to parse registry YAML: ", conditionMessage(e))
      NULL
    }
  )
}


#' Detect parameter type for registry storage
#' @keywords internal
detect_param_type <- function(x) {
  if (is.logical(x)) return("logical")
  if (is.numeric(x)) return("numeric")
  if (is.character(x)) return("character")
  if (is.list(x)) return("list")
  "unknown"
}

#' Wrap parameters with type info for registry
#' @keywords internal
wrap_typed_defaults <- function(lst) {
  if (is.null(lst) || !length(lst)) return(list())
  out <- list()
  for (nm in names(lst)) {
    val <- lst[[nm]]
    out[[nm]] <- list(value = val, type = detect_param_type(val))
  }
  out
}

#' Unwrap typed optional_defaults (value/type) back to R types
#' @keywords internal
unwrap_typed_defaults <- function(lst) {
  if (!is.list(lst) || !length(lst)) return(list())
  out <- list()
  for (nm in names(lst)) {
    node <- lst[[nm]]
    # Detect structure {value, type}
    if (is.list(node) && !is.null(node$value) && !is.null(node$type)) {
      tp <- tolower(as.character(node$type))
      val <- node$value
      out[[nm]] <- switch(tp,
                          logical   = as.logical(val),
                          numeric   = as.numeric(val),
                          character = as.character(val),
                          list      = as.list(val),
                          val       # fallback
      )
    } else {
      # old untyped scalar
      out[[nm]] <- node
    }
  }
  out
}

#' Null-coalescing helper
#'
#' Returns `b` when `a` is `NULL` or has zero length, otherwise `a`.
#'
#' @param a First object.
#' @param b Fallback object.
#'
#' @return Either `a` or `b`.
#' @keywords internal
#' @name grapes-or-or-grapes
#' @rdname grapes-or-or-grapes
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a



#' Register an LLM endpoint offline (supports reasoning / thinking path)
#'
#' Builds a registry entry offline — no API key or network required.
#' Accepts standard list-style paths and automatically serializes to
#' PsyLingLLM YAML format. Supports reasoning models (thinking_path / thinking_delta_path).
#'
#' @param model Character. Model key, e.g. "deepseek-reasoner".
#' @param provider Character. "official", "proxy", or "local".
#' @param generation_interface Character. Interface type, e.g. "chat", "responses".
#' @param url Character. Endpoint URL.
#' @param headers Named list of HTTP headers.
#' @param body Named list of body fields (with placeholders).
#' @param role_mapping Named list mapping roles; NULL stored as ~.
#' @param optional_defaults Named list (stream, max_tokens, temperature).
#' @param output_spec Named list of output paths (each path may be a list of strings).
#' @param streaming_spec Named list of streaming config.
#' @param thinking_path Optional list specifying reasoning field path in response (e.g. list("choices","message","reasoning_content")).
#' @param thinking_delta_path Optional list specifying reasoning delta path in streaming (e.g. list("choices","delta","reasoning_content")).
#' @param default_system Character or NULL. Default system message; if NULL, YAML shows ~.
#' @param auto_register Logical. TRUE to skip confirmation prompt.
#'
#' @return Invisibly returns the registry entry.
#' @export
register_endpoint_offline <- function(model,
                                      provider = "official",
                                      generation_interface = "chat",
                                      url,
                                      headers,
                                      body,
                                      role_mapping = NULL,
                                      optional_defaults = list(
                                        stream      = list(value = TRUE,  type = "logical"),
                                        max_tokens  = list(value = 1024, type = "numeric"),
                                        temperature = list(value = 0.7,  type = "numeric")
                                      ),
                                      output_spec = NULL,
                                      streaming_spec = NULL,
                                      thinking_path = NULL,
                                      thinking_delta_path = NULL,
                                      default_system = NULL,
                                      auto_register = TRUE) {

  # ---------------- Helper: list("a","b","c") -> "list(\"a..b..c\")" ----------------
  format_path <- function(path_list) {
    if (is.null(path_list)) return(NULL)
    if (is.character(path_list)) return(sprintf("list(\"%s\")", paste(path_list, collapse = "..")))
    if (is.list(path_list)) return(sprintf("list(\"%s\")", paste(unlist(path_list), collapse = "..")))
    stop("Invalid path: must be list or character vector.")
  }

  # ---------------- Default output paths ----------------
  if (is.null(output_spec)) {
    output_spec <- list(
      respond_path = list("choices","message","content"),
      id_path = list("id"),
      object_path = list("object"),
      token_usage_path = list(
        prompt     = list("usage","prompt_tokens"),
        completion = list("usage","completion_tokens")
      )
    )
  }

  # Serialize paths
  for (k in names(output_spec)) {
    if (k == "token_usage_path") {
      output_spec[[k]]$prompt     <- format_path(output_spec[[k]]$prompt)
      output_spec[[k]]$completion <- format_path(output_spec[[k]]$completion)
    } else {
      output_spec[[k]] <- format_path(output_spec[[k]])
    }
  }

  # Add thinking_path if provided
  output_spec$thinking_path <- format_path(thinking_path)

  # ---------------- Default streaming paths ----------------
  if (is.null(streaming_spec)) {
    streaming_spec <- list(
      enabled = TRUE,
      delta_path = list("choices","delta","content"),
      require_accept_header = FALSE
    )
  }

  # Serialize streaming paths
  streaming_spec$delta_path <- format_path(streaming_spec$delta_path)
  streaming_spec$enabled <- isTRUE(streaming_spec$enabled)
  streaming_spec$require_accept_header <- isTRUE(streaming_spec$require_accept_header)
  if (!is.null(thinking_delta_path)) {
    streaming_spec$thinking_delta_path <- format_path(thinking_delta_path)
  }

  # ---------------- Build registry entry ----------------
  entry <- list(
    model = list(
      provider  = provider,
      reasoning = !is.null(thinking_path) || !is.null(thinking_delta_path),
      input = list(
        default_url = url,
        headers = headers,
        body = body,
        optional_defaults = optional_defaults,
        default_system = if (is.null(default_system)) NULL else default_system,
        role_mapping = role_mapping %||%
          list(system = "system", user = "user", assistant = "assistant")
      ),
      output = output_spec,
      streaming = streaming_spec
    )
  )

  entry <- setNames(list(setNames(list(entry$model), generation_interface)), model)

  # ---------------- Preview ----------------
  message("\n[PsyLingLLM] Model Registration Preview\n")
  utils::str(entry, max.level = 4)

  # ---------------- Confirm & write ----------------
  do_register <- if (isTRUE(auto_register)) TRUE else {
    if (interactive()) {
      ans <- readline(sprintf("[PsyLingLLM] Register '%s'? (yes/no): ", model))
      tolower(ans) %in% c("yes","y")
    } else FALSE
  }

  if (do_register) {
    registry_path <- "~/.psylingllm/user_registry.yaml"
    register_endpoint_to_user_registry(entry, registry_path)
    message(sprintf("[PsyLingLLM]  Registered '%s' in %s", model, registry_path))
  } else {
    message("[PsyLingLLM]  Registration skipped.")
  }

  invisible(entry)
}

#' Print lines gradually with delay (console-safe)
#'
#' @param lines Character vector of text lines.
#' @param delay Numeric, seconds to wait between each line (default 0.3).
#' @param final_delay Numeric, optional delay after the last line.
#' @param prefix Optional string printed before each line (e.g. ">>> ").
#' @export
cat_slowly <- function(lines, delay = 0.3, final_delay = 0, prefix = "") {
  if (length(lines) == 0) return(invisible())
  for (ln in lines) {
    cat(prefix, ln, "\n", sep = "")
    flush.console()
    Sys.sleep(delay)
  }
  if (final_delay > 0) Sys.sleep(final_delay)
  invisible()
}

#' Translate HTTP status code to human-readable meaning
#'
#' @param code Integer HTTP status code
#' @return A short character description
#' @noRd
http_status_meaning <- function(code) {
  tbl <- list(
    `400` = "Bad Request (invalid JSON or parameters)",
    `401` = "Unauthorized (check API key)",
    `403` = "Forbidden (no permission to access the endpoint)",
    `404` = "Not Found (wrong URL or endpoint)",
    `408` = "Request Timeout (server did not respond)",
    `429` = "Too Many Requests (rate limited)",
    `500` = "Internal Server Error (provider fault)",
    `502` = "Bad Gateway (proxy or upstream error)",
    `503` = "Service Unavailable (server overloaded)",
    `504` = "Gateway Timeout (network issue)"
  )
  if (is.null(code) || is.na(code)) return("Unknown status (no response)")
  k <- as.character(code)
  if (!is.null(tbl[[k]])) return(tbl[[k]])
  if (code >= 200L && code < 300L) return("Success")
  if (code >= 300L && code < 400L) return("Redirection")
  if (code >= 400L && code < 500L) return("Client error")
  if (code >= 500L) return("Server error")
  "Unknown status"
}
