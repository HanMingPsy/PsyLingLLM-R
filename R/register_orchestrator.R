#' Register an LLM Endpoint with Pass-2 Validation
#'
#' Orchestrates a two-pass analysis to register an arbitrary LLM endpoint into
#' the PsyLingLLM registry. **Pass-1** probes the raw endpoint (non-stream and
#' streaming/SSE) and scores likely extraction paths for `answer` and `thinking`
#' fields. **Pass-2** builds a *standardized* request template (using the
#' provider's own field names), re-probes the endpoint, and verifies that the
#' selected ports are still retrievable. Finally, it composes a registry entry
#' and, if requested, writes/merges it into the user registry.
#'
#' This function prints a human-readable report (status, candidate paths,
#' stream capability, usage fields, and Pass-1 vs Pass-2 consistency). It
#' returns a structured object for programmatic inspection.
#'
#' @section Workflow:
#' 1. **Pass-1 probe**: send non-streaming POST; attempt SSE streaming; parse and
#'    score candidate JSON paths for `answer`/`thinking` (and streaming deltas).
#' 2. **Standardize**: construct Pass-2 headers/body that preserve vendor keys,
#'    with placeholders \code{\${ROLE}}, \code{\${CONTENT}}, and a parameter
#'    merge anchor \code{\${PARAMETER}}; apply typed defaults.
#' 3. **Pass-2 probe**: re-issue the request; verify that the chosen ports are
#'    still discoverable (retrievability only; not a semantic equivalence test).
#' 4. **Registry preview & upsert**: compose a registry entry (input/output/
#'    streaming blocks) and optionally write it into the user registry.
#'
#' @param url Character(1). Endpoint URL.
#' @param provider Character(1). Provider label stored in the registry. One of
#'   \code{"official"}, \code{"vllm"}, \code{"proxy"}, \code{"custom"}.
#' @param headers Named list of HTTP headers. May include placeholders such as
#'   \code{\${API_KEY}}; \code{Accept: text/event-stream} is added automatically
#'   during probing if streaming requires it.
#' @param body List template for the request payload. May include placeholders
#'   \code{\${ROLE}}, \code{\${CONTENT}}, and a parameter merge anchor
#'   \code{\${PARAMETER}}. The raw Pass-1 body is preserved as a fallback in the
#'   resulting registry entry.
#' @param api_key Character(1). API/Bearer key used to substitute
#'   \code{\${API_KEY}} in headers/body during probes.
#' @param content_value Character(1). Test content for the user message during
#'   probing (e.g., \code{"Hello!"}).
#' @param generation_interface Optional character(1). Interface name to record
#'   in the entry (e.g., \code{"chat"}, \code{"messages"}, \code{"responses"}).
#'   If \code{NULL}, it may be auto-classified from \code{url}.
#' @param default_system_prompt Optional character(1). Structural default system
#'   message to include in the entry (if applicable). Not forced at runtime.
#' @param optional_defaults Named list of typed defaults (e.g.,
#'   \code{list(stream = TRUE, max_tokens = 512)}). These are recorded in the
#'   entry and used by callers unless explicitly overridden.
#' @param role_mapping Optional named list mapping roles (e.g.,
#'   \code{list(system = "system", user = "user", assistant = "assistant")}).
#'   If \code{NULL}, the function may infer mapping from \code{body} structure
#'   for recording purposes; mapping is never *forced* unless a caller supplies it.
#' @param timeout Numeric(1). Per-probe timeout in seconds.
#' @param top_k Integer(1). Number of near-miss candidates to keep in the
#'   printed ranking tables.
#' @param ns_prob_thresh Named list with probability thresholds for Pass-1/2
#'   non-stream selection, e.g. \code{list(answer = 0.60, think = 0.55)}.
#' @param st_prob_thresh Named list with probability thresholds for Pass-1/2
#'   streaming selection, e.g. \code{list(answer = 0.70, think = 0.55)}.
#' @param lexicon Keyword lexicon (list) for candidate scoring.
#' @param stream_param Character scalar (optional).
#'   Name of the request-body field used by the provider to enable streaming.
#'   For most OpenAI-compatible APIs this is `"stream"`, but some endpoints
#'   use alternative keys such as `"streaming"`, `"enable_sse"`, or `"use_stream"`.
#'   If `NULL`, the function falls back to `"stream".
#' @param auto_register Logical(1). If \code{TRUE}, the composed entry is
#'   immediately written/merged into the user registry; otherwise only a preview
#'   is printed.
#'
#' @details
#' **What “ports retrievability” means**: the Pass-2 check verifies that the
#' JSON paths chosen in Pass-1 (for answer/thinking and streaming deltas) can be
#' rediscovered from the standardized request. It does not guarantee semantic
#' equivalence of outputs, nor does it attempt to reconcile vendor-specific
#' streaming event semantics beyond path retrievability.
#'
#' **Safety & side-effects**: this function makes live requests to the given
#' endpoint. Avoid running in examples/tests against production APIs unless
#' guarded with \code{\\dontrun{}} or environment checks.
#'
#' @return
#' Invisibly returns a list with components:
#' \itemize{
#'   \item \code{report}: Character vector of human-readable log lines.
#'   \item \code{pass1}: List with raw/effective inputs, HTTP details, ranked
#'         candidates, and selected ports (\code{respond_path}, \code{thinking_path},
#'         \code{delta_path}, \code{thinking_delta_path}).
#'   \item \code{pass2}: List with HTTP details and any Pass-2 warnings.
#' }
#'
#' @seealso
#' \code{\link{probe_llm_streaming}},
#' \code{\link{score_candidates_ns}},
#' \code{\link{score_candidates_st}},
#' \code{\link{build_standardized_input}},
#' \code{\link{make_pass2_probe_inputs}},
#' \code{\link{render_pass2_path_consistency_report}},
#' \code{\link{build_registry_entry_from_analysis}},
#' \code{\link{register_endpoint_to_user_registry}},
#' \code{\link{get_registry_entry}},
#' \code{\link{llm_caller}}
#'
#' # Example: OpenAI-compatible chat endpoint
#' \code{
#' llm_register(
#'   url      = "https://api.openai.com/v1/chat/completions",
#'   provider = "official",
#'   headers  = list(
#'     "Content-Type" = "application/json",
#'     "Authorization" = "Bearer \\${API_KEY}"
#'   ),
#'   body     = list(
#'     model    = "gpt-4o-mini",
#'     messages = list(list(role = "user", content = "\\${CONTENT}")),
#'     stream   = TRUE
#'   ),
#'   api_key  = Sys.getenv("OPENAI_API_KEY"),
#'   content_value = "Hello from PsyLingLLM!",
#'   generation_interface = "chat",
#'   optional_defaults   = list(stream = TRUE, max_tokens = 512),
#'   auto_register = FALSE   # preview only
#' )
#' }
#'
#' # Example: DeepSeek-style endpoint (adjust URL/model to your provider)
#' \code{
#' llm_register(
#'   url      = "https://api.deepseek.com/v1/chat/completions",
#'   provider = "proxy",
#'   headers  = list(
#'     "Content-Type" = "application/json",
#'     "Authorization" = "Bearer \\${API_KEY}"
#'   ),
#'   body     = list(
#'     model    = "deepseek-chat",
#'     messages = list(list(role = "user", content = "\\${CONTENT}")),
#'     stream   = TRUE
#'   ),
#'   api_key  = Sys.getenv("DEEPSEEK_API_KEY"),
#'   generation_interface = "chat",
#'   auto_register = TRUE
#' )
#' }
#'
#' @importFrom utils capture.output
#'
#' @keywords registry streaming sse llm
#' @export

llm_register <- function(url,
                         provider = "official",
                         headers,
                         body,
                         api_key,
                         content_value = "Hello!",
                         generation_interface = NULL,
                         default_system_prompt = NULL,
                         optional_defaults = NULL,
                         role_mapping = NULL,
                         timeout = 120,
                         top_k = 5,
                         ns_prob_thresh = list(answer = 0.60, think = 0.55),
                         st_prob_thresh = list(answer = 0.70, think = 0.55),
                         lexicon = default_keyword_lexicon(),
                         stream_param = NULL,
                         auto_register = FALSE
) {
  provider <- normalize_provider_label(provider)

  # ---- Pass 1: ORIGINAL INPUTS (as user provided) ----
  input_raw_p1 <- list(url = url, headers = headers, body = body)

  # calls use substituted "effective" inputs
  mapping <- list(API_KEY = api_key, CONTENT = content_value)
  headers_eff_p1 <- sub_placeholders(headers, mapping)
  body_eff_p1    <- sub_placeholders(body,    mapping)

  # Probe with Pass-1 effective
  res1 <- probe_llm_streaming(url = url, headers = headers_eff_p1, body = body_eff_p1, stream_param = stream_param, timeout = timeout)
  # --- Score NS/ST (Pass 1) → ports
  ns_best <- list(answer = NULL, think = NULL); st_best <- list(answer = NULL, think = NULL)
  ns_cand <- data.frame(); st_cand <- data.frame()
  uf <- character()

  L <- character()
  L <- c(L, "\n--- \U0001F9E9 PsyLingLLM LLM Schema Automatic Analysis --- \n",
         "[Endpoint]",
         sprintf("provider: %s", provider),
         sprintf("URL: %s", url))

  # Input echo
  L <- c(L, "\n[Input]")
  hdr_lines <- if (length(headers_eff_p1)) paste(sprintf("\"%s\" = \"%s\"", names(headers_eff_p1), headers_eff_p1), collapse = ",\n                ") else ""
  L <- c(L, if (nzchar(hdr_lines)) sprintf("headers <- list(%s)", hdr_lines) else "headers <- list()")
  body_p1_dump <- capture.output(dput(body_eff_p1))
  L <- c(L, paste("\nbody <-", paste(body_p1_dump, collapse = "\n        ")))

  # Non-streaming (Pass 1)
  L <- c(L, "\n[Non-Streaming]")
  L <- c(L, sprintf("HTTP status: %s", res1$non_stream$status_code %||% NA))
  if (!is.null(res1$non_stream$parsed)) {
    ns <- score_candidates_ns(obj = res1$non_stream$parsed, lexicon = lexicon,
                              prob_thresh = ns_prob_thresh, top_k = max(10, top_k))
    ns_best <- ns$best; ns_cand <- ns$candidates
    if (!is.null(ns_best$answer)) L <- c(L, paste("\nMost Probable NS answer:\n -", trim_excerpt(ns_best$answer$text)))
    if (!is.null(ns_best$think))  L <- c(L, paste("\nMost Probable NS thinking:\n -", trim_excerpt(ns_best$think$text)))
    uf <- extract_usage_fields(res1$non_stream$parsed)
    if (length(uf)) L <- c(L, paste("\nUsage fields:", paste(uf, collapse = ", ")))
  }

  # Streaming (Pass 1)
  L <- c(L, "\n[Streaming]")
  L <- c(L, paste("Honored streaming:", res1$stream_attempt$honored_streaming %||% FALSE))
  L <- c(L, paste("Reason:", res1$stream_attempt$reason %||% ""))

  if (!is.null(res1$stream_attempt$raw_df) && nrow(res1$stream_attempt$raw_df) &&
      !is.null(res1$stream_attempt$raw_json) && length(res1$stream_attempt$raw_json)) {
    st <- score_candidates_st(raw_df = res1$stream_attempt$raw_df,
                              raw_json = res1$stream_attempt$raw_json,
                              lexicon = lexicon, prob_thresh = st_prob_thresh,
                              top_k = max(10, top_k))
    st_best <- st$best; st_cand <- st$candidates
    if (!is.null(st_best$answer)) L <- c(L, paste("\nMost Probable ST Answer:\n -", trim_excerpt(st_best$answer$text)))
    if (!is.null(st_best$think))  L <- c(L, paste("\nMost Probable ST thinking:\n -", trim_excerpt(st_best$think$text)))
  }

  # Summary (Pass 1 ports)
  ns_answer_path <- ns_best$answer$path %||% NULL
  ns_think_path  <- ns_best$think$path  %||% NULL
  st_answer_path <- st_best$answer$path %||% NULL
  st_think_path  <- st_best$think$path  %||% NULL

  L <- c(L, "\n\n[\U0001F4CA Summary of Extraction Paths]")
  L <- c(L, paste(" Non-stream:\n -respond_path =", ns_answer_path %||% "<none>"))
  L <- c(L, paste(" Non-stream:\n -thinking_path =", ns_think_path %||% "<none>"))
  L <- c(L, paste(" Stream:\n -delta_path =", st_answer_path %||% "<none>"))
  L <- c(L, paste(" Stream:\n -thinking_delta_path =", st_think_path %||% "<none>"))


  # --- Pass 2: standardized self-test (ports retrievability only)

  # pick model from the effective body
  std <- build_standardized_input(headers, body, optional_keys = optional_defaults)
  # templates for record (as "raw" of pass2)
  headers_p2_tmpl <- std$headers_p2 %||% std$headers
  body_p2_tmpl    <- std$body_p2    %||% std$body

  eff2 <- make_pass2_probe_inputs(
    std,
    api_key  = api_key,
    content  = content_value,
    role_mapping = role_mapping,
    defaults = optional_defaults,
    include_system = FALSE,                 # per our latest rule
    pass1_body_for_roles = body
  )

  res2 <- probe_llm_streaming(url, eff2$headers, eff2$body, stream_param = stream_param, timeout = timeout)

  # Pass 2: detailed port verification (aligned with Pass 1 scoring)
  L <- c(L, "\n\n--- \U0001F517 Automatic Reform Consistency Verification ---\n")

  # Extract Pass-2 paths via same scoring logic as Pass-1
  ns2 <- list(best = NULL, candidates = NULL)
  st2 <- list(best = NULL, candidates = NULL)

  if (!is.null(res2$non_stream$parsed)) {
    ns2 <- score_candidates_ns(
      obj = res2$non_stream$parsed,
      lexicon = lexicon,
      prob_thresh = ns_prob_thresh,
      top_k = max(5, top_k)
    )
  }

  if (isTRUE(res2$stream_attempt$honored_streaming)) {
    st2 <- score_candidates_st(
      raw_df = res2$stream_attempt$raw_df,
      raw_json = res2$stream_attempt$raw_json,
      lexicon = lexicon,
      prob_thresh = st_prob_thresh,
      top_k = max(5, top_k)
    )
  }

  # Build comparison structures for Pass-1 vs Pass-2
  pass1_paths <- list(
    ns_answer = ns_answer_path,
    ns_think  = ns_think_path,
    st_answer = st_answer_path,
    st_think  = st_think_path
  )
  pass2_paths <- list(
    ns_answer = ns2$best$answer$path %||% NULL,
    ns_think  = ns2$best$think$path  %||% NULL,
    st_answer = st2$best$answer$path %||% NULL,
    st_think  = st2$best$think$path  %||% NULL
  )

  # Generate the structured report (uses the helper you defined)
  L <- c(L, render_pass2_path_consistency_report(pass1_paths, pass2_paths))

  # Final print
  cat_slowly(L, delay = 0.025, final_delay = 2)

  # Decide model id (prefer Pass-1 body$model; else best-guess)
  model_eff <- body$model %||% "unnamed-model"

  # error detection and early return
  e1 <- e2 <- NULL

  if (res1$non_stream$status_code >= 400L) {
    msg <- sprintf("[llm_register] Network or HTTP error (status=%s: %s)", res1$non_stream$status_code, http_status_meaning(res1$non_stream$status_code))
    warning(msg, call. = FALSE)
    return()
  }

  if (!is.null(res1)) e1 <- probe_extract_error(res1)
  if (!is.null(res2)) e2 <- probe_extract_error(res2)

  if (!is.null(e1) || !is.null(e2)) {
    msg <- paste(
      na.omit(c(
        if (!is.null(e1)) sprintf("Pass-1: %s", e1$message),
        if (!is.null(e2)) sprintf("Pass-2: %s", e2$message)
      )),
      collapse = " \n "
    )
    warning(sprintf("[llm_register] Probe error(s):\n    %s", msg), call. = FALSE)
    return()
  }

  # ---- Record method / role_mapping exactly as provided by the caller (no inference here) ----
  role_mapping_auto <- tryCatch(infer_role_mapping_from_body(body), error = function(e) NULL)
  role_mapping_final <- role_mapping %||% role_mapping_auto %||%
    tryCatch(std$diagnostics$role_mapping_inferred, error = function(e) NULL)

  # Build the Phase-0 analysis object fragments needed by the builder
  analysis_for_registry <- list(
    report = L,  # your assembled report lines (character vector)

    pass1 = list(
      details = res1,
      input_raw = list(url = url, headers = headers, body = body),  # EXACT originals
      input_effective = list(url = url, headers = headers_eff_p1, body = body_eff_p1),
      ports = list(
        respond_path        = ns_answer_path,       # from your scoring/selection
        thinking_path       = ns_think_path,        # may be NULL
        delta_path          = st_answer_path,       # may be NULL
        thinking_delta_path = st_think_path         # may be NULL
      ),
      default_system = default_system_prompt
    ),
    pass2 = list(
      # Pass-2 processed template we standardized (with ${PARAMETER}: {})
      input_raw = list(url = url, headers = headers, body = std$body_p2),
      # Effective inputs actually used for Pass-2 probe (placeholders substituted, defaults merged)
      input_effective = list(url = url, headers = headers_p2_tmpl, body = body_p2_tmpl),
      details = res2
    )
  )

  # --- Optional registration step (prompt) ---
  if (!is.na(model_eff) && nzchar(model_eff)) {
    do_register <- FALSE

    # Build a preview entry before asking user confirmation
    entry <- build_registry_entry_from_analysis(
      model                = model_eff,
      analysis             = analysis_for_registry,
      provider             = provider,                 # e.g., "official","chutes.ai","local"
      generation_interface = generation_interface,
      url                  = url,                      # persisted as default_url only when provider == "official"
      headers_input        = headers,                  # EXACT user headers (placeholders intact)
      role_mapping_input   = role_mapping_final,            # NULL -> stored as ~ (no inference)
      stream_param         = stream_param,
      optional_defaults    = optional_defaults
    )

    # Print CI-style preview *before* asking for registration confirmation
    message("\n\n[PsyLingLLM] Model Registration Preview\n\n")
    preview_lines <- format_registration_preview(entry)
    # cat(paste(preview_lines, collapse = "\n"), "\n")
    cat_slowly(preview_lines, delay = 0.025, final_delay = 1)

    # Ask user for confirmation
    if (isTRUE(auto_register)) {
      do_register <- TRUE
    } else if (interactive()) {
      type_norm  <- normalize_type_label(provider)
      key_preview <- if (identical(tolower(type_norm), "official")) {
        model_eff
      } else {
        paste0(model_eff, "@", type_norm)
      }
      ans <- readline(prompt = sprintf("[PsyLingLLM] Register this model as '%s'? (yes/no): ", key_preview))
      if (tolower(ans) %in% c("yes", "y")) do_register <- TRUE
    }

    # Perform actual registration if confirmed
    if (do_register) {
      register_endpoint_to_user_registry(entry)
      message(sprintf("[PsyLingLLM] \U00002705 Registered as '%s' in %s",
                      names(entry)[1], get_registry_path()))
    } else {
      message("[PsyLingLLM] \U000026A0 Registration skipped by user.")
    }
  }

  # Return object invisibly for pipeline use
  invisible(list(
    report = L,
    pass1 = list(
      details = res1,
      ns = list(best = ns_best, candidates = ns_cand),
      st = list(best = st_best, candidates = st_cand),
      ports = list(
        respond_path = ns_answer_path,
        thinking_path = ns_think_path,
        delta_path = st_answer_path,
        thinking_delta_path = st_think_path
      ),
      detected_system = std$diagnostics$default_system %||% NULL
    ),
    pass2 = if (exists("res2")) list(details = res2, warnings = warnings) else NULL
  ))

}


