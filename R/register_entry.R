#' Build a registry entry from analysis results
#'
#' This function constructs a structured registry node from
#' the results of an endpoint analysis, typically produced by
#' `analyze_llm_endpoint()`. It merges information from Pass-1
#' and Pass-2 analysis stages, preserving vendor-specific fields,
#' normalizing optional parameters, and ensuring YAML-ready
#' formatting for downstream usage.
#'
#' **Changes vs previous version:**
#' - Omits `method` entirely when not provided (no `method: ~` in YAML).
#' - In Pass-2 body, \code{"\${PARAMETER}"} fields are stored as `NULL` (`~` in YAML) for cleaner output.
#' - Accepts `optional_defaults` as a named list (e.g., `list(stream = TRUE, max_tokens = 512)`)
#'   and stores it under `input.optional_defaults`.
#'
#' @param model Character(1). Model identifier, e.g. `"deepseek-chat"`.
#' @param provider Character(1). Free-form provider tag, e.g. `"official"`, `"chutes.ai"`, or `"local"`.
#' @param generation_interface Character(1). Interface name (defaults to `"chat"`).
#'   If `NULL`, it will be inferred automatically via `classify_generation_interface()`.
#' @param analysis List. The result from `analyze_llm_endpoint()` containing `pass1` and `pass2` nodes.
#' @param url Character(1). Base URL; persisted as `default_url` only if `provider == "official"`.
#' @param headers_input Named list or `NULL`. Custom HTTP headers.
#'   If `NULL`, Pass-1 raw headers are used.
#' @param role_mapping_input List or `NULL`. Custom role mapping.
#'   If `NULL`, the function infers mappings from Pass-1/Pass-2 bodies.
#' @param stream_param Character scalar (optional).
#' @param optional_defaults Named list. Default generation parameters
#'   (e.g. `list(stream = TRUE, max_tokens = 512)`), stored under `input.optional_defaults`.
#'
#' @return A named list representing a single registry node, keyed by `"<model>@<provider>"`.
#' Each entry contains a nested structure describing model I/O, streaming behavior,
#' token usage paths, and reasoning capabilities.
#'
#' @seealso [analyze_llm_endpoint()], [classify_generation_interface()]
#' @export
build_registry_entry_from_analysis <- function(model,
                                               analysis,
                                               provider = "official",
                                               generation_interface = NULL,
                                               url = NULL,
                                               headers_input = NULL,
                                               role_mapping_input = NULL,
                                               stream_param = NULL,
                                               optional_defaults = NULL) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

  # ---- Helpers ----
  path_literal_for_yaml <- function(path) {
    if (is.null(path) || !length(path)) return(NULL)
    if (is.character(path) && length(path) == 1L && grepl('^\\s*list\\(', path)) {
      return(path)
    }
    segs <- unlist(path, use.names = FALSE)
    segs <- vapply(segs, as.character, character(1))
    paste0('list("', paste(segs, collapse = ".."), '")')
  }

  build_token_usage_block <- function(usage_names) {
    if (is.null(usage_names) || !length(usage_names)) return(NULL)
    mk <- function(field) paste0('list("usage","', field, '")')
    out <- list()
    if ("prompt_tokens"     %in% usage_names) out$prompt     <- mk("prompt_tokens")
    if ("completion_tokens" %in% usage_names) out$completion <- mk("completion_tokens")
    if (!length(out)) return(NULL)
    out
  }

  # ---- Extract Pass-2 processed body and Pass-1 original ----
  body_p2 <- tryCatch(analysis$pass2$input_raw$body, error = function(e) NULL)
  if (is.null(body_p2)) body_p2 <- tryCatch(analysis$pass2$details$input$body, error = function(e) NULL)
  if (is.null(body_p2)) stop("Cannot build registry: Pass-2 processed body is missing.")

  body_p1 <- tryCatch(analysis$pass1$input_raw$body, error = function(e) NULL)
  if (is.null(body_p1)) body_p1 <- tryCatch(analysis$input_raw$body, error = function(e) NULL)

  # Ensure model field alignment
  body_p2$model <- model
  if (!is.null(body_p1)) body_p1$model <- model

  # If not set, inject placeholder for optional defaults
  if (is.null(body_p2[["${PARAMETER}"]])) {
    body_p2[["${PARAMETER}"]] <- "${OPTIONAL_DEFAULTS}"
  }

  # Headers: prefer explicit input, else Pass-1 originals
  headers_reg <- headers_input %||%
    tryCatch(analysis$pass1$input_raw$headers, error = function(e) NULL) %||% list()

  # ---- Ports ----
  ports <- analysis$pass1$ports %||% list()
  respond_lit   <- path_literal_for_yaml(ports$respond_path)
  think_lit     <- path_literal_for_yaml(ports$thinking_path)
  delta_lit     <- path_literal_for_yaml(ports$delta_path)
  delta_th_lit  <- path_literal_for_yaml(ports$thinking_delta_path)
  streaming_enabled <- !is.null(delta_lit)

  # ---- Detect embedded <think> pattern in model output ----
  think_tagged <- FALSE
  if (!is.null(analysis$pass1$details$non_stream$parsed)) {
    think_tagged <- detect_embedded_think_tag(analysis$pass1$details$non_stream$parsed)
  }
  if (think_tagged) {
    # When <think>…</think> present, unify respond/thinking paths
    think_lit <- respond_lit
    delta_th_lit <- delta_lit
  }

  # ---- Usage fields ----
  usage_obj <- tryCatch(analysis$pass1$details$non_stream$parsed$usage, error = function(e) NULL)
  if (is.null(usage_obj)) usage_obj <- tryCatch(analysis$pass1$details$usage, error = function(e) NULL)
  token_usage_path <- build_token_usage_block(names(usage_obj))

  # ---- Detected default_system (informational only) ----



  default_system_prompt_auto <- NULL

  # Case 1: infer_role_mapping_from_body (local body)
  role_mapping_auto <- tryCatch(infer_role_mapping_from_body(analysis$pass1$input_raw$body), error = function(e) NULL)
  if (!is.null(role_mapping_auto) && !is.null(role_mapping_auto$system_content)) {
    default_system_prompt_auto <- role_mapping_auto$system_content
  }
  default_system <- analysis$pass1$default_system %||% default_system_prompt_auto

  # ---- Role mapping ----
  resolve_role_mapping <- function() {
    if (!is.null(role_mapping_input) && length(role_mapping_input)) return(role_mapping_input)
    b1 <- tryCatch(analysis$pass1$input_raw$body, error = function(e) NULL)
    rm1 <- tryCatch(infer_role_mapping_from_body(b1), error = function(e) NULL)
    if (!is.null(rm1) && length(rm1)) return(rm1)
    b2 <- tryCatch(analysis$pass2$input_raw$body, error = function(e) NULL)
    rm2 <- tryCatch(infer_role_mapping_from_body(b2), error = function(e) NULL)
    if (!is.null(rm2) && length(rm2)) return(rm2)

    NULL
  }

  role_mapping_final <- resolve_role_mapping()

  typed_defaults <- if (length(optional_defaults)) wrap_typed_defaults(optional_defaults) else NULL

  accept_required <- isTRUE(analysis$pass2$details$stream_attempt$accept_required)

  if (accept_required) {
    headers_reg$Accept <- "text/event-stream"
  }

  # ---- Input node ----
  input_node <- list(
    default_url        = if (identical(tolower(provider), "official") && !is.null(url) && nzchar(url)) url else NULL,
    headers            = headers_reg,
    body               = body_p2,
    fallback_body      = body_p1,
    optional_defaults  = typed_defaults,
    default_system     = default_system
  )
  if (!is.null(role_mapping_final)) input_node$role_mapping <- role_mapping_final

  # ---- Output node ----
  output_node <- {
    make_path <- function(x) if (!is.null(x)) as.character(x) else NULL
    out <- list(
      respond_path  = make_path(respond_lit),
      thinking_path = make_path(think_lit),
      id_path       = 'list("id")',
      object_path   = 'list("object")'
    )
    if (!is.null(token_usage_path)) out$token_usage_path <- token_usage_path
    out
  }

  # ---- Streaming node ----
  streaming_node <- if (isTRUE(streaming_enabled)) {
    lst <- list(enabled = TRUE)
    lst$delta_path <- as.character(delta_lit)
    if (!is.null(delta_th_lit)) lst$thinking_delta_path <- as.character(delta_th_lit)
    lst$require_accept_header <- accept_required
    if (!is.null(stream_param) && nzchar(stream_param)) {
      lst$param_name <- as.character(stream_param)
    }
    lst
  } else {
    list(enabled = FALSE)
  }


  # ---- Iface node ----
  iface_node <- list(
    provider = provider,
    reasoning = isTRUE(think_tagged || !is.null(think_lit) || !is.null(delta_th_lit)),
    input     = input_node,
    output    = output_node,
    streaming = streaming_node
  )

  # ---- Determine generation interface ----
  if (is.null(generation_interface)) {
    generation_interface <- tryCatch(
      classify_generation_interface(url),
      error = function(e) NULL
    )
  }


  # ---- Final entry keyed by "<model>@<type>" ----
  if (identical(tolower(provider), "official")) {
    key <- model
  } else {
    key <- paste0(model, "@", provider)
  }
  entry <- list()

  top <- list()
  top[[generation_interface]] <- iface_node

  # save entry
  entry[[key]] <- top

  entry
}
