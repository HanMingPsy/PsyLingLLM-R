#' Call an LLM via the registry
#'
#' Builds a request strictly from the model registry entry (no ad-hoc headers/body/messages).
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
#' Optionals (tri-state, injected via \code{"\${PARAMETER}"} if present)
#' \itemize{
#'   \item Missing: use registry \code{input.optional_defaults} if present; otherwise inject nothing;
#'   \item \code{NULL}: inject nothing;
#'   \item Named list: use user keys only (do not merge defaults).
#' }
#'
#' Non-streaming extraction uses flat-key equality and wildcard ("..") regex fallback via
#' \code{flatten_json_paths()} and \code{normalize_path_key_with_regex()}.
#' Streaming reconstruction uses \code{stream_reconstruct_text()} and the registry
#' \code{delta_path} (and optional \code{thinking_delta_path}).
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
#'
#' @return A list with fields: \code{status}, \code{interface}, \code{model_key}, \code{streaming},
#'   \code{usage}, \code{answer}, \code{thinking}, and optionally \code{raw} or \code{error}.
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
                       debug = FALSE) {
  if (!requireNamespace("jsonlite", quietly = TRUE) ||
      !requireNamespace("curl", quietly = TRUE)) {
    stop("Packages 'jsonlite' and 'curl' are required for llm_caller().")
  }

  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

  # --- Load & select registry entry -----------------------------------------
  entry <- get_registry_entry(model_key, generation_interface)
  if (debug) message("[llm_caller] provider: ", entry$provider,
                     " | interface: ", entry$interface)

  # URL: user wins; official -> fallback; non-official -> required
  url <- resolve_api_url(
    api_url     = api_url,
    provider    = entry$provider,
    default_url = entry$input$default_url
  )
  if (debug) message("[llm_caller] url: ", url)

  # --- Template & role gating -----------------------------------------------
  body_tmpl <- entry$input$body %||% list()
  msgs_meta  <- detect_message_keys_from_template(body_tmpl)
  supports_roles <- isTRUE(msgs_meta$supports_roles)

  if (!supports_roles && (!is.null(system_content) || !is.null(assistant_content))) {
    warning("[llm_caller] Template has no ${ROLE}; system/assistant content will be ignored.")
  }

  # role mapping: disabled by default; apply only if user supplied
  use_role_map <- is.list(role_mapping) && length(role_mapping)
  map_role <- function(role) if (use_role_map) (role_mapping[[tolower(role)]] %||% role) else role

  # --- Build user content ----------------------------------------------------
  user_content <- build_user_content(trial_prompt, material)
  if (!nzchar(user_content)) {
    stop("At least one of 'trial_prompt' or 'material' must be provided.")
  }

  # --- Assemble messages -----------------------------------------------------
  body <- body_tmpl
  if (supports_roles) {
    msg_list <- list()

    # 1) system (user-specified > registry default_system)
    sys_text <- system_content
    if (is.null(sys_text)) sys_text <- entry$input$default_system %||% NULL
    if (!is.null(sys_text)) {
      msg_list[[length(msg_list) + 1]] <- list(
        role    = map_role("system"),
        content = sys_text
      )
    }

    # 2) prior history / few-shots (could include user/assistant pairs)
    hist_msgs <- normalize_history_messages(assistant_content, map_role)
    if (length(hist_msgs)) {
      msg_list <- c(msg_list, hist_msgs)
    }

    # 3) current user turn (always last)
    msg_list[[length(msg_list) + 1]] <- list(
      role    = map_role("user"),
      content = user_content
    )

    # inject into template honoring vendor keys
    container <- msgs_meta$container_key
    role_key  <- msgs_meta$role_key
    cont_key  <- msgs_meta$content_key

    body[[container]] <- lapply(msg_list, function(m) {
      lst <- list()
      lst[[role_key]] <- m$role
      lst[[cont_key]] <- m$content
      lst
    })
  } else {
    # ROLE-less template: fill ${CONTENT} via placeholder substitution only.
    # - No role injection; system_content / assistant_content are ignored
    #   (a warning is already emitted above when provided).
    # - user_content was built from trial_prompt/material earlier.
    body <- body_tmpl

    # Substitute ${CONTENT} anywhere in the template body.
    # (headers/API_KEY replacement still happens later, unchanged.)
    body <- replace_placeholders(body, list(CONTENT = user_content))
  }

  # --- Optionals tri-state ---------------------------------------------------
  # Missing -> defaults (if any) else none; NULL -> none; list -> user only
  opt <- resolve_optionals_tristate(
    optionals_missing = missing(optionals),
    optionals_value   = if (missing(optionals)) NULL else optionals,
    defaults          = entry$input$optional_defaults %||% list()
  )
  body <- inject_optionals_anchor(body, opt)

  # stream precedence: param > opt$stream > registry streaming.enabled
  resolved_stream <- if (!is.null(stream)) {
    isTRUE(stream)
  } else if ("stream" %in% names(opt)) {
    isTRUE(opt$stream)
  } else {
    isTRUE(entry$streaming$enabled)
  }
  if (resolved_stream) {
    stream_field <- entry$streaming$param_name
    if (!is.null(stream_field) && is.character(stream_field) && nzchar(stream_field)) {
      body[[stream_field]] <- TRUE
    } else {
      body$stream <- TRUE
    }
  }

  # --- Headers & placeholder substitution -----------------------------------
  headers <- entry$input$headers %||% list()
  if (!is.null(api_key)) {
    headers <- replace_placeholders(headers, list(API_KEY = api_key))
    body    <- replace_placeholders(body,    list(API_KEY = api_key))
  }

  if (!supports_roles) {
    body <- replace_placeholders(body, list(CONTENT = user_content))
  }

  # --- HTTP call -------------------------------------------------------------
  json_payload <- jsonlite::toJSON(body, auto_unbox = TRUE, null = "null", digits = NA)

  usage <- list(prompt = NULL, completion = NULL, id = NULL)

  if (resolved_stream) {
    # ---- Streaming branch ----------------------------------------------------
    st <- do_stream_request(url, headers, json_payload, timeout = timeout, debug = debug)

    answer   <- stream_reconstruct_text(st$raw_json, entry$streaming$delta_path)
    thinking <- if (!is.null(entry$streaming$thinking_delta_path)) {
      stream_reconstruct_text(st$raw_json, entry$streaming$thinking_delta_path)
    } else NULL

    if (is.list(entry$output$token_usage_path)) {
      pu <- entry$output$token_usage_path$prompt
      cu <- entry$output$token_usage_path$completion
      if (!is.null(pu)) usage$prompt <- suppressWarnings(as.integer(stream_reconstruct_text(st$raw_json, entry$output$token_usage_path$prompt)))
      if (!is.null(cu)) usage$completion <- suppressWarnings(as.integer(stream_reconstruct_text(st$raw_json, entry$output$token_usage_path$completion)))
    }

    if (!is.null(entry$output$id_path)) {
      usage$id <- suppressWarnings(stream_reconstruct_text(st$raw_json, entry$output$id_path))
    }

    return(list(
      status    = st$status,
      interface = entry$interface,
      model_key = entry$model_key,
      streaming = TRUE,
      usage     = usage,
      answer    = as.character(answer %||% ""),
      thinking  = if (is.null(thinking)) NULL else as.character(thinking),
      first_token_latency = st$first_token_latency,
      raw       = if (isTRUE(return_raw)) list(
        request = list(url = url, headers = headers, body = jsonlite::fromJSON(json_payload, simplifyVector = FALSE)),
        response = list(stream = st)
      ) else NULL,
      error     = if (st$status >= 400L) list(code = st$status, message = st$error %||% "HTTP error") else NULL
    ))

  } else {
    # ---- Non-streaming branch ------------------------------------------------
    ns <- do_nonstream_request(url, headers, json_payload, timeout = timeout, debug = debug)
    parsed <- ns$parsed

    answer <- if (!is.null(entry$output$respond_path)) {
      extract_text_by_spec(parsed, entry$output$respond_path)
    } else ""
    thinking <- if (!is.null(entry$output$thinking_path)) {
      x <- extract_text_by_spec(parsed, entry$output$thinking_path)
      if (nzchar(x)) x else NULL
    } else NULL

    if (is.list(entry$output$token_usage_path)) {
      pu <- entry$output$token_usage_path$prompt
      cu <- entry$output$token_usage_path$completion
      if (!is.null(pu)) usage$prompt <- suppressWarnings(as.integer(extract_text_by_spec(parsed, pu)))
      if (!is.null(cu)) usage$completion <- suppressWarnings(as.integer(extract_text_by_spec(parsed, cu)))
    }

    if (!is.null(entry$output$id_path)) {
      usage$id <- suppressWarnings(as.character(extract_text_by_spec(parsed, entry$output$id_path)))
    }

    return(list(
      status    = ns$status,
      interface = entry$interface,
      model_key = entry$model_key,
      streaming = FALSE,
      usage     = usage,
      answer    = as.character(answer %||% ""),
      thinking  = thinking,
      raw       = if (isTRUE(return_raw)) list(
        request = list(url = url, headers = headers, body = jsonlite::fromJSON(json_payload, simplifyVector = FALSE)),
        response = list(non_stream = list(status = ns$status, text = ns$text, parsed = parsed))
      ) else NULL,
      error     = if (ns$status >= 400L) list(code = ns$status, message = ns$error %||% "HTTP error") else NULL
    ))
  }
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
#' @return A modified copy of \code{body} with the optional parameters merged in.
#'   If no optionals are provided or the anchor is absent, the input is returned unchanged.
#'
#' @keywords internal
inject_optionals_anchor <- function(body, opt) {
  if (!length(opt)) return(body)
  if (is.list(body) && "${PARAMETER}" %in% names(body)) {
    body[["${PARAMETER}"]] <- NULL
    for (k in names(opt)) body[[k]] <- opt[[k]]
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


#' Extract text by registry path spec (flat-key with optional ".." wildcard)
#' @keywords internal
extract_text_by_spec <- function(obj, path_spec) {
  nr <- normalize_path_key_with_regex(path_spec)  # provided in register_utils.R
  df <- tryCatch(flatten_json_paths(obj, keep_numeric = TRUE), error = function(e) data.frame())
  if (!nrow(df)) return("")
  hit <- df$value[df$path == nr$key]
  if (length(hit)) {
    ch <- suppressWarnings(as.character(hit[[1]])); return(if (length(ch)) ch else "")
  }
  if (!is.na(nr$regex)) {
    hit <- df$value[grepl(nr$regex, df$path)]
    if (length(hit)) {
      ch <- suppressWarnings(as.character(hit[[1]])); return(if (length(ch)) ch else "")
    }
  }
  ""
}

#' Minimal non-streaming POST (registry-strict headers)
#' @keywords internal
do_nonstream_request <- function(url,
                                 headers,
                                 json_payload,
                                 timeout = 120,
                                 debug = FALSE) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
  parse_json_safely <- function(txt) {
    tryCatch(jsonlite::fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL)
  }
  to_payload <- function(x) {
    if (is.list(x)) {
      jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", na = "null")
    } else {
      as.character(x %||% "")
    }
  }

  # --- Strict: use headers exactly as given ---
  payload <- to_payload(json_payload)
  h <- curl::new_handle()
  curl::handle_setheaders(h, .list = headers)

  curl::handle_setopt(
    h,
    customrequest = "POST",
    postfields = payload,
    timeout = as.integer(timeout)
  )

  res <- tryCatch(curl::curl_fetch_memory(url, handle = h), error = function(e) e)
  if (inherits(res, "error")) {
    return(list(
      status = 599L,
      text = NULL,
      parsed = NULL,
      error = as.character(res$message)
    ))
  }

  text <- rawToChar(res$content)
  parsed <- parse_json_safely(text)

  if (isTRUE(debug)) {
    cat("----- [DEBUG non-stream] headers -----\n")
    print(headers)
    cat("----- [DEBUG non-stream] body -----\n")
    cat(payload, "\n")
  }

  list(
    status = res$status_code %||% 200L,
    text = text,
    parsed = parsed,
    error = NULL
  )
}


#' Minimal SSE streaming POST (registry-strict headers)
#' @keywords internal
do_stream_request <- function(url,
                              headers,
                              json_payload,
                              timeout = 120,
                              debug = FALSE) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
  parse_json_safely <- function(txt) {
    tryCatch(jsonlite::fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL)
  }
  to_payload <- function(x) {
    if (is.list(x)) {
      jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", na = "null")
    } else {
      as.character(x %||% "")
    }
  }

  payload <- to_payload(json_payload)
  raw_lines <- character()

  json_events <- list()
  cache <- ""
  first_token_latency <- NA_real_
  t_start <- Sys.time()

  cb <- function(dat) {
    chunk <- iconv(rawToChar(dat, multiple = FALSE), from = "UTF-8", to = "UTF-8", sub = "")
    cache <<- paste0(cache, chunk)
    lines <- strsplit(cache, "\n", fixed = TRUE)[[1]]
    if (!endsWith(cache, "\n")) {
      cache <<- utils::tail(lines, 1)
      if (length(lines) > 1) lines <- utils::head(lines, -1) else lines <- character()
    } else {
      cache <<- ""
    }

    if (!length(lines)) return(TRUE)
    raw_lines <<- c(raw_lines, lines)

    data_lines <- grep("^data:", lines, value = TRUE)
    if (!length(data_lines)) return(TRUE)

    if (is.na(first_token_latency)) {
      first_token_latency <<- as.numeric(difftime(Sys.time(), t_start, units = "secs"))
    }

    for (ln in data_lines) {
      payload_txt <- sub("^data:\\s*", "", ln)
      if (identical(payload_txt, "[DONE]")) next
      obj <- parse_json_safely(payload_txt)
      if (!is.null(obj)) {
        json_events[[length(json_events) + 1]] <<- obj
      }
    }
    TRUE
  }

  # --- Strict: use headers exactly as given ---
  h <- curl::new_handle()
  curl::handle_setheaders(h, .list = headers)

  curl::handle_setopt(
    h,
    customrequest = "POST",
    postfields = payload,
    timeout = as.integer(timeout)
  )

  if (isTRUE(debug)) {
    cat("----- [DEBUG stream] headers -----\n")
    print(headers)
    cat("----- [DEBUG stream] body -----\n")
    cat(payload, "\n")
  }

  res <- tryCatch(curl::curl_fetch_stream(url, cb, handle = h), error = function(e) e)
  if (inherits(res, "error")) {
    return(list(
      status = 599L,
      raw_json = json_events,
      raw_lines = if (isTRUE(debug)) raw_lines else NULL,
      first_token_latency = first_token_latency,
      error = as.character(res$message)
    ))
  }

  list(
    status = res$status_code %||% 200L,
    raw_json = json_events,
    raw_lines = if (isTRUE(debug)) raw_lines else NULL,
    first_token_latency = first_token_latency,
    error = NULL
  )
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
