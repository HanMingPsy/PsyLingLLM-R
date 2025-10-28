#' Build standardized Pass-2 headers & body from Pass-1 raw inputs
#'
#' This function reconstructs a normalized set of request headers and body
#' for Pass-2 processing, based purely on the structural layout of the
#' original Pass-1 input. It uses structural inference around
#' \code{"\${CONTENT}"} placeholders rather than heuristic keyword matching.
#'
#' The goal is to generate a consistent and minimal representation of
#' model input for registry or downstream YAML serialization.
#'
#' @param pass1_headers List (raw). The original request headers captured during Pass-1.
#' @param pass1_body List (raw). The original request body captured during Pass-1.
#' @param optional_keys Character vector or list. Optional field names to be
#'   explicitly retained in Pass-2 inference (e.g. `"stream"`, `"max_tokens"`).
#'   These serve as hints to preserve or normalize optional input elements.
#'
#' @return A named list containing three components:
#'   \describe{
#'     \item{headers_p2}{Standardized headers for Pass-2 processing.}
#'     \item{body_p2}{Normalized body structure, inferred from `pass1_body`.}
#'     \item{diagnostics}{List of structural inference metadata, including
#'       style, container keys, message index, content keys, role mappings,
#'       default system prompt, and detected model ID.}
#'   }
#'
#' @seealso [build_body_pass2_structural()], [complete_headers_for_pass2()]
#' @export
build_standardized_input <- function(pass1_headers, pass1_body, optional_keys) {
  # streaming flag only as a light hint (optional)
  sflag <- if (!is.null(pass1_body$stream)) {
    isTRUE(pass1_body$stream)
  } else NA

  body_p2 <- build_body_pass2_structural(pass1_body = pass1_body, optional_keys)
  headers_p2 <- complete_headers_for_pass2(pass1_headers, want_streaming = sflag)

  info <- attr(body_p2, "structural_info")
  attr(body_p2, "structural_info") <- NULL

  list(
    headers_p2 = headers_p2,
    body_p2    = body_p2,
    diagnostics = list(
      style            = info$style,
      container_key    = info$container_key,
      message_index    = info$message_index,
      content_key      = info$content_key,
      role_key         = info$role_key,
      default_system   = info$default_system,
      model_detected   = body_p2$model
    )
  )
}



#' Build Pass-2 body
#'
#' Normalize and simplify a raw Pass-1 request body into a structured Pass-2 form,
#' retaining vendor fields and removing runtime-tunable optionals.
#' The resulting body is schema-clean and suitable for registry serialization.
#'
#' **Rules**
#' \itemize{
#'   \item \strong{Messages style}: rebuild the messages *container* into a single message using
#'     the same field names inferred from the placeholder \code{"\${CONTENT}"} (no guessing);
#'     keep all other top-level fields from Pass-1 except optionals.
#'   \item \strong{Single-prompt style}: keep the original key (e.g., \code{prompt}, \code{input});
#'     remove optionals and retain other top-level fields.
#'   \item Always ensure \code{model} is present (prefer Pass-1; else use \code{model_guess};
#'     otherwise \code{NA}).
#'   \item Append a clean merge point \code{"\${PARAMETER}: \${VALUE}"} at the top level
#'     to mark where optional parameters are injected.
#' }
#'
#' @param pass1_body list (raw). The raw Pass-1 input body from endpoint analysis.
#' @param optional_keys Character vector of explicit optional parameter keys to remove.
#'   If \code{NULL}, defaults to \code{default_optional_keys()}.
#'
#' @return A list representing the normalized Pass-2 body, ready for YAML registry serialization.
#'
#' @export
#'
#' @seealso \link{strip_optionals_from_body}, \link{infer_structure_from_placeholder}
build_body_pass2_structural <- function(pass1_body,
                                        optional_keys = NULL) {
  # ---- 0. Infer structure ----
  info <- infer_structure_from_placeholder(pass1_body, placeholder = "${CONTENT}")

  # ---- 1. Initialize ----
  body_p2 <- pass1_body
  body_p2$model <- pass1_body$model %||% NA_character_

  # ---- 2. Handle single-prompt style ----
  if (identical(info$style, "single")) {
    body_p2 <- strip_optionals_from_body(body_p2, optional_keys)
    if (is.null(body_p2[["${PARAMETER}"]])) {
      body_p2[["${PARAMETER}"]] <- "${VALUE}"
    }
    attr(body_p2, "structural_info") <- info
    return(body_p2)
  }

  # ---- 3. Handle messages style ----
  container <- info$container_key
  if (is.null(container) || !nzchar(container)) {
    stop("Inconsistent messages structure inferred: missing container key.")
  }

  # rebuild messages container to a single entry with ${ROLE}/${CONTENT}
  new_msg <- list()
  if (!is.null(info$role_key) && nzchar(info$role_key)) {
    new_msg[[info$role_key]] <- "${ROLE}"
  }
  new_msg[[info$content_key]] <- "${CONTENT}"

  # replace original container
  body_p2[[container]] <- list(new_msg)

  # ---- 4. Drop optional keys ----
  body_p2 <- strip_optionals_from_body(body_p2, optional_keys)

  # ---- 5. Add ${PARAMETER}: "${VALUE}" merge point ----
  if (is.null(body_p2[["${PARAMETER}"]])) {
    body_p2[["${PARAMETER}"]] <- "${VALUE}"
  }

  attr(body_p2, "structural_info") <- info
  body_p2
}



#' Build Pass-2 EFFECTIVE probe inputs (no forced system; structural role inference)
#'
#' Behavior:
#' - Never add HTTP headers automatically (no implicit Accept).
#' - If `role_mapping` is NULL, infer roles structurally via `infer_role_mapping_from_body()`
#'   (preferred when `pass1_body_for_roles` is provided); otherwise fall back to
#'   `std$diagnostics$role_mapping_inferred` when available. If still absent, only
#'   user role defaults to "user".
#' - `include_system = TRUE` only injects a system message when BOTH:
#'     (a) diagnostics has a non-empty `default_system`, and
#'     (b) a system role label exists (from `role_mapping` or inference).
#'   Otherwise system is skipped (no fallback/forcing).
#' - For messages style, rebuild messages strictly by schema keys from diagnostics:
#'     [ optional system ], then [ required user ].
#' - For single-prompt, keep the prompt key shape; only merge probe defaults.
#' - Probe defaults are merged into the body top-level and placeholders are substituted.
#'
#' @param std list from build_standardized_input()
#' @param api_key character(1)
#' @param content character(1) value for \code{"\${CONTENT}"}
#' @param role_mapping NULL or list(user=..., system=...)
#' @param defaults named list of probe-only params (e.g., list(stream=TRUE, max_tokens=512, temperature=0.7))
#' @param include_system logical(1), default FALSE; add system only when role exists and default_system present
#' @param pass1_body_for_roles optional list; when provided and role_mapping is NULL, roles are inferred from this body
#' @return list(headers=list, body=list, role_used=list(user=..., system=...|NULL))
#' @export
make_pass2_probe_inputs <- function(std,
                                    api_key,
                                    content = "Hello!",
                                    role_mapping = NULL,
                                    defaults = list(stream = TRUE,
                                                    max_tokens = 512,
                                                    temperature = 0.7),
                                    include_system = FALSE,
                                    pass1_body_for_roles = NULL) {
  tm <- extract_pass2_templates(std)
  headers_tmpl <- tm$headers_tmpl
  body_tmpl    <- tm$body_tmpl
  diag         <- tm$diag %||% list()
  if (is.null(headers_tmpl) || is.null(body_tmpl)) {
    stop("Pass-2 templates are incomplete: headers/body template missing.")
  }

  # ---- role labels (only infer when user did not supply) ----
  inferred <- NULL
  if (is.null(role_mapping)) {
    inferred <- infer_role_mapping_from_body(pass1_body_for_roles)
  }
  rm_final <- role_mapping %||% inferred %||% list()
  user_label   <- rm_final$user %||% NULL
  system_label <- rm_final$system %||% NULL

  # ---- build effective body: merge probe defaults ----
  eff_body <- merge_defaults_for_probe(body_tmpl, defaults = defaults)

  # ---- messages style: rebuild messages strictly by diagnostics ----
  if (identical(diag$style, "messages")) {
    container   <- diag$container_key
    role_key    <- diag$role_key
    content_key <- diag$content_key
    if (is.null(container) || !nzchar(container) ||
        is.null(content_key) || !nzchar(content_key)) {
      stop("Diagnostics missing container/content keys for messages structure.")
    }

    msgs <- list()

    # (optional) system message: only when default_system exists AND system_label available
    if (isTRUE(include_system) &&
        !is.null(diag$default_system) && nzchar(as.character(diag$default_system)) &&
        !is.null(system_label) && nzchar(system_label)) {
      sys_msg <- list()
      if (!is.null(role_key) && nzchar(role_key)) sys_msg[[role_key]] <- system_label
      sys_msg[[content_key]] <- as.character(diag$default_system)
      msgs <- append(msgs, list(sys_msg))
    }

    # required user message
    usr_msg <- list()
    if (!is.null(role_key) && nzchar(role_key)) usr_msg[[role_key]] <- user_label
    usr_msg[[content_key]] <- "${CONTENT}"
    msgs <- append(msgs, list(usr_msg))

    eff_body[[container]] <- msgs
  }

  # ---- placeholders → effective ----
  mapping     <- list(API_KEY = api_key, CONTENT = content, ROLE = user_label)
  headers_eff <- sub_placeholders(headers_tmpl, mapping)
  body_eff    <- sub_placeholders(eff_body,    mapping)

  list(
    headers   = headers_eff,
    body      = body_eff,
    role_used = list(user = user_label,
                     system = if (isTRUE(include_system)) system_label else NULL)
  )
}



# ==============================================================
#
#                      Utility Functions
#
# ==============================================================


#' Substitute placeholders \code{"\${API_KEY}"}, \code{"\${CONTENT}"}, \code{"\${ROLE}"} robustly
#'
#' This function performs recursive placeholder substitution within nested R
#' structures (lists or atomic vectors). Each placeholder string of the form
#' \code{"\${VARNAME}"} is replaced by its corresponding value from the provided
#' mapping list.
#'
#' **Features**
#' \itemize{
#'   \item Works on nested lists and atomic vectors.
#'   \item Replacement values are coerced to length-1 character strings and
#'         escaped for Perl regular expressions.
#'   \item \code{NULL}, \code{NA}, or non-scalar replacements are converted to
#'         empty strings (\code{""}).
#' }
#'
#' @param x A list or atomic vector containing placeholder strings.
#' @param mapping A named list providing substitution values, e.g.,
#'   \code{list(API_KEY = "...", CONTENT = "...", ROLE = "user")}.
#'
#' @return The transformed object, with all placeholders replaced by their
#'   corresponding mapped values.
#'
#' @export
sub_placeholders <- function(x, mapping) {
  if (is.list(x)) {
    return(lapply(x, sub_placeholders, mapping))
  }
  if (is.character(x)) {
    out <- x
    for (nm in names(mapping)) {
      # only attempt substitution when pattern actually appears
      pat <- paste0("\\$\\{", nm, "\\}")
      if (any(grepl(pat, out, perl = TRUE))) {
        repl <- escape_replacement(mapping[[nm]])
        out  <- gsub(pat, repl, out, perl = TRUE)
      }
    }
    return(out)
  }
  x
}

#' Strip optional runtime parameters from a request body
#'
#' This function removes optional (runtime-tunable) parameters from a raw
#' request body to yield a clean, structural Pass-2 body. It first removes
#' fields listed in \code{optional_keys} (highest priority), then applies a
#' heuristic to detect and drop non-standard but optional-like fields
#' (e.g., vendor variants of temperature/top_p/max_tokens etc.).
#'
#' Core structural fields (e.g., \code{model}, \code{prompt}, \code{messages},
#' \code{"${PARAMETER}"}) are preserved. Optionally, vendor extension fields
#' (e.g., prefixed by \code{vendor_} or \code{x_}) can be preserved via
#' \code{preserve_vendor_fields = TRUE}.
#'
#' @param body list. Raw Pass-1-like request body.
#' @param optional_keys character(). Explicit optional keys to remove first
#'   (highest priority). If \code{NULL}, \code{default_optional_keys()} is used.
#' @param preserve_vendor_fields logical(1). If \code{TRUE}, keep fields that look
#'   like vendor-specific extensions (e.g., names starting with \code{vendor_} or \code{x_}).
#' @param warn logical(1). If \code{TRUE}, emit a message summarizing removed keys.
#'
#' @return list. The cleaned body.
#' @export
strip_optionals_from_body <- function(body,
                                      optional_keys = NULL,
                                      preserve_vendor_fields = TRUE,
                                      warn = TRUE) {
  if (is.null(body) || !is.list(body)) return(body)

  # --- 0) Setup ---------------------------------------------------------------
  optional_keys <- optional_keys %||% default_optional_keys()

  # "Core" structural keys that must be preserved if present
  core_keys <- c(
    "model", "prompt", "messages", "inputs", "input", "instruction",
    # common message fields or containers
    "role", "content", "system",
    # reserved Pass-2 merge anchor
    "${PARAMETER}"
  )

  is_core_key <- function(nm) {
    nm %in% core_keys
  }

  looks_like_vendor_ext <- function(nm) {
    startsWith(nm, "vendor_") || startsWith(nm, "x_")
  }

  # --- 1) Remove explicit optionals (highest priority) -----------------------
  removed_explicit <- intersect(names(body), optional_keys)
  if (length(removed_explicit)) {
    body[removed_explicit] <- NULL
  }

  # --- 2) Heuristic pass for non-standard optionals --------------------------
  # Heuristic patterns drawn from common LLM providers (OpenAI/Anthropic/Gemini/Cohere/Mistral/HF)
  # Capture variants of: tokens, temperature, sampling, penalties, stops, seeds, beams, logprobs, logits, etc.
  optional_like_patterns <- c(
    # streaming & decoding
    "(^|_)stream(ing)?$", "sse$", "use_streaming$",
    # token limits
    "max_?tokens?$", "max_output_tokens$", "max_new_tokens$", "token_limit$", "n_?predict$",
    # sampling & nucleus/top-k
    "temperature$", "sampling_?temperature$", "temp(erature)?_?[0-9]*$",
    "top_?p$", "top_?k$", "min_?p$", "typical_?p$",
    # penalties
    "presence_?penalty$", "frequency_?penalty$", "repetition_?penalty$", "length_?penalty$", "penalty_?(alpha)?$",
    # stochasticity / seeds
    "^seed$", "random_?seed$",
    # beams / search
    "beam(_?width|_?size)?$", "use_?beam_?search$", "best_?of$",
    # stops
    "^stop$", "stop_?(sequences|words)?$",
    # response shaping / formats
    "response_?format$", "guided_(json|regex|choice|decoding)$", "grammar$", "json_?schema(_def)?$",
    # logprobs / logit bias
    "logprobs?$", "top_?logprobs?$", "logit_?bias(es|_map)?$",
    # choice count
    "^(n|num)_?(choices|candidates)?$|^candidate_?count$",
    # tool calling & function calling (runtime toggles)
    "^tools?$", "tool_?choice$", "parallel_?tool_?calls$", "function_?call(_name)?$", "^functions$",
    # reasoning toggles (runtime)
    "^reasoning$", "reasoning_?effort$", "thinking$", "enable_?reasoning$", "thinking_(budget|tokens)$",
    # safety / moderation / metadata (often runtime policy knobs)
    "^safety_?settings$", "^safety_?spec$", "^metadata$",
    # search / retrieval toggles
    "disable_?search$", "^websearch$", "search_?domain_?filter$",
    # retry / request control
    "max_?retries$", "^user$", "^echo$", "^suffix$",
    # vendor-generic placeholders
    "^sampling_?params$"
  )

  optional_like_regex <- paste0("(", paste(optional_like_patterns, collapse = "|"), ")")

  removed_heuristic <- character(0)
  for (nm in names(body)) {
    # already removed
    if (is.null(body[[nm]])) next

    # never remove core keys
    if (is_core_key(nm)) next

    # optionally preserve vendor extensions
    if (preserve_vendor_fields && looks_like_vendor_ext(nm)) next

    # if explicitly marked optional, it was removed in step 1
    if (nm %in% optional_keys) next

    # heuristic removal
    if (grepl(optional_like_regex, nm, ignore.case = TRUE, perl = TRUE)) {
      removed_heuristic <- c(removed_heuristic, nm)
      body[[nm]] <- NULL
    }
  }

  body
}


#' Inject optional params into a body using a whitelist
#' @param body list
#' @param optional_params named list of candidates to inject
#' @param whitelist character vector of allowed keys
#' @export
inject_optional_params <- function(body, optional_params = NULL, whitelist = NULL) {
  if (is.null(optional_params) || !length(optional_params)) return(body)
  if (is.null(whitelist) || !length(whitelist)) whitelist <- names(optional_params)
  for (k in intersect(names(optional_params), whitelist)) {
    v <- optional_params[[k]]
    if (!is.null(v)) body[[k]] <- v
  }
  body
}


#' Infer role mapping from a chat-style LLM request body
#'
#' This helper inspects a JSON-like request body used by chat-based LLM APIs
#' and infers how conversational roles (e.g., *user*, *assistant*, *system*)
#' are represented in provider-specific message structures.
#'
#' The function analyzes structural metadata (as produced by
#' [infer_structure_from_placeholder()]) to identify the message container,
#' role keys, and message indices. It returns a mapping that can later be
#' used in the registry under `input$role_mapping` to ensure consistent
#' message composition across providers.
#'
#' @param pass1_body A list representing the request body (usually as captured
#'   during Pass-1 analysis). Typically this is the same structure passed to
#'   [build_standardized_input()] or [llm_register()].
#'
#' @return A named list with up to three fields describing provider-specific
#'   role labels:
#'   \describe{
#'     \item{user}{Label for the user role (e.g. `"user"` or `"human"`).}
#'     \item{assistant}{Label for the assistant role
#'       (e.g. `"assistant"`, `"bot"`, or `"model"`).}
#'     \item{system}{Label for the system/instruction role
#'       (e.g. `"system"` or `"context"`). May include a companion field
#'       `system_content` with the detected instruction text.}
#'   }
#'
#'   Returns `NULL` if no mapping can be inferred.
#'
#'
#' @seealso [build_standardized_input()], [infer_structure_from_placeholder()]
#' @export
infer_role_mapping_from_body <- function(pass1_body) {
  info <- infer_structure_from_placeholder(pass1_body, placeholder = "${CONTENT}")

  # single-prompt → no roles to infer
  if (!identical(info$style, "messages") || is.null(info$role_key) || !nzchar(info$role_key)) {
    return(NULL)
  }

  container <- info$container_key
  idx       <- info$message_index
  if (is.null(container) || is.na(idx)) return(NULL)

  node <- pass1_body[[container]]
  if (!is.list(node) || length(node) < idx) return(NULL)

  out <- list()

  # helper: is a scalar, non-empty, non-placeholder string
  is_clean_scalar <- function(v) {
    is.character(v) && length(v) == 1 && nzchar(v) && !grepl("\\$\\{.+\\}", v)
  }

  # USER mapping: role value of the message with ${CONTENT}
  msg <- node[[idx]]
  rv  <- tryCatch(msg[[info$role_key]], error = function(e) NULL)
  if (is_clean_scalar(rv)) out$user <- as.character(rv)

  # SYSTEM mapping: scan earlier siblings with non-placeholder content
  if (idx > 1) {
    for (j in seq.int(idx - 1, 1)) {
      m <- tryCatch(node[[j]], error = function(e) NULL)
      if (is.list(m)) {
        cv  <- tryCatch(m[[info$content_key]], error = function(e) NULL)
        rv2 <- tryCatch(m[[info$role_key]], error = function(e) NULL)
        if (is_clean_scalar(cv) && is_clean_scalar(rv2)) {
          out$system          <- as.character(rv2)
          out$system_content  <- as.character(cv)
          break
        }
      }
    }
  }

  if (!length(out)) return(NULL)
  out
}


#' Merge default generation parameters into a request body (probe only)
#'
#' This helper function inserts a set of default parameters into a model
#' request body for *probing* or lightweight inspection, without altering
#' persistent templates.
#'
#' It removes the placeholder \code{"\${PARAMETER}"} if present and merges
#' predefined defaults (e.g., \code{stream}, \code{max_tokens}, \code{temperature})
#' into the top-level body structure.
#'
#' Commonly used during test or probe calls to ensure a minimal,
#' fully specified request payload before sending to an API endpoint.
#'
#' @param body A list representing the request body (e.g., a Pass-2 body structure).
#' @param defaults A named list of default parameter values to inject into
#'   \code{body}. Defaults to:
#'   \preformatted{
#'   list(stream = TRUE, max_tokens = 512, temperature = 0.7)
#'   }
#'
#' @return A modified list identical to \code{body} but with:
#' \itemize{
#'   \item the placeholder field \code{"\${PARAMETER}"} removed (if present);
#'   \item each entry in \code{defaults} merged into the top level.
#' }
#' @export
merge_defaults_for_probe <- function(body,
                                     defaults = list(stream = TRUE,
                                                     max_tokens = 512,
                                                     temperature = 0.7)) {
  out <- body
  if (!is.null(out[["${PARAMETER}"]])) out[["${PARAMETER}"]] <- NULL
  if (length(defaults)) for (k in names(defaults)) out[[k]] <- defaults[[k]]
  out
}



#' Complete headers minimally for Pass-2 (keeps user values)
#' @param pass1_headers list
#' @param want_streaming logical or NA
#' @return list headers_p2
#' @export
complete_headers_for_pass2 <- function(pass1_headers, want_streaming = NA) {
  h <- pass1_headers %||% list()
  if (!any(tolower(names(h)) == "content-type")) {
    h[["Content-Type"]] <- "application/json"
  }
  if (isTRUE(want_streaming) && !any(tolower(names(h)) == "accept")) {
    h[["Accept"]] <- "text/event-stream"
  }
  h
}


#' Tolerant extraction of Pass-2 templates (headers and body)
#'
#' This helper function extracts the standardized Pass-2 templates
#' (headers and body) from a structured input object produced by
#' [build_standardized_input()] or a compatible analysis result.
#'
#' It is **tolerant** to missing or partial components — if `headers_p2`
#' or `body_p2` are unavailable, the function gracefully falls back to
#' their raw equivalents (`headers` or `body`).
#' Diagnostics are returned if present.
#'
#' @param std List. A standardized object containing Pass-2 fields such as
#'   `headers_p2`, `body_p2`, and optionally `diagnostics`. Typically, this
#'   is the output of [build_standardized_input()].
#'
#' @return A named list with the following components:
#'   \describe{
#'     \item{headers_tmpl}{Standardized Pass-2 headers, or raw headers if missing.}
#'     \item{body_tmpl}{Standardized Pass-2 body, or raw body if missing.}
#'     \item{diag}{Diagnostics information if available, otherwise `NULL`.}
#'   }
#' @seealso [build_standardized_input()]
#' @export
extract_pass2_templates <- function(std) {
  list(
    headers_tmpl = std$headers_p2 %||% std$headers %||% NULL,
    body_tmpl    = std$body_p2    %||% std$body    %||% NULL,
    diag         = std$diagnostics %||% NULL
  )
}


#' Default optional keys for common LLM providers (explicit removal first)
#'
#' This list aggregates widely-seen optional (runtime-tunable) fields across
#' OpenAI, Anthropic, Google Gemini, Cohere, Mistral and Hugging Face style APIs.
#' It is intentionally broad; tailor at call-site if needed.
#'
#' @return character vector of key names
#' @export
default_optional_keys <- function() {
  c(
    # Streaming
    "stream", "streaming", "use_streaming", "sse",

    # Token limits
    "max_tokens", "max_output_tokens", "max_new_tokens", "token_limit", "n_predict",

    # Sampling & nucleus/top-k
    "temperature", "sampling_temperature", "top_p", "top_k", "min_p", "typical_p",

    # Penalties
    "presence_penalty", "frequency_penalty", "repetition_penalty", "length_penalty", "penalty_alpha",

    # Beams / best-of
    "beam_width", "beam_size", "use_beam_search", "best_of",

    # Stops
    "stop", "stop_sequences", "stop_words",

    # Logprobs / logit bias
    "logprobs", "top_logprobs", "logit_bias", "logit_biases", "logit_bias_map",

    # Seeds / randomness
    "seed", "random_seed",

    # Response shaping / formats
    "response_format", "guided_json", "guided_regex", "guided_choice", "guided_decoding",
    "grammar", "json_schema", "json_schema_def",

    # Tool & function calling (runtime toggles)
    "tools", "tool_choice", "parallel_tool_calls", "function_call", "function_call_name", "functions",

    # Reasoning toggles (runtime)
    "reasoning", "reasoning_effort", "thinking", "enable_reasoning", "thinking_budget", "thinking_tokens",

    # Safety / moderation / metadata (often runtime)
    "safety_settings", "safety_spec", "metadata",

    # Search / retrieval toggles
    "disable_search", "websearch", "search_domain_filter",

    # Retry / request control / misc
    "max_retries", "user", "echo", "suffix", "sampling_params"
  )
}
