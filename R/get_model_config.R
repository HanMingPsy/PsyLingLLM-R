#' Resolve a model name (id or alias) to a registry entry (new registry-aware)
#'
#' Works with the new load_registry() bundle (list with $merged).
#' Still supports passing a preloaded flat registry list via `registry`.
#'
#' @param model_name Character. Official model id pasted by user, or an alias.
#' @param registry Optional. Either a flat list of models.
#'
#' @return A list (model config) or NULL if not found.
#' @export
get_model_config <- function(model_name, registry = NULL) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

  registry_resolver_assert_string(model_name, "model_name")
  if (is.null(registry)) {
    registry <- load_registry()
  }
  if (!is.list(registry)) {
    stop("[PsyLingLLM] FATAL - registry must be a list.", call. = FALSE)
  }

  is_bundle <- "merged" %in% names(registry) &&
    is.list(registry$merged) &&
    identical(registry$merged$schema_version, 2L)
  is_v2 <- "schema_version" %in% names(registry)
  if (is_bundle) {
    validate_registry_schema(registry$merged)
    reg <- registry$merged$models
  } else if (is_v2) {
    validate_registry_schema(registry)
    reg <- registry$models
  } else {
    reg <- registry
  }

  lookup_models <- lapply(reg, function(model) {
    aliases <- if (is.list(model)) model$aliases else NULL
    if (!is.character(aliases)) {
      aliases <- character()
    }
    list(aliases = aliases)
  })
  match <- tryCatch(
    registry_resolve_model_key(model_name, lookup_models),
    registry_resolution_error = identity
  )
  if (!inherits(match, "registry_resolution_error")) {
    return(reg[[match$key]])
  }
  if (!identical(match$reason, "model_not_found")) {
    stop(match)
  }

  # 3) bare id
  parts <- unlist(strsplit(model_name, "[/:]", perl = TRUE))
  bare <- parts[length(parts)]
  if (bare %in% names(reg)) {
    warning(sprintf(
      "[PsyLingLLM] WARNING - model '%s' not found, fallback to bare id '%s'.",
      model_name, bare
    ), call. = FALSE)
    return(reg[[bare]])
  }

  # 4) family
  family <- sub("-[0-9]+[a-zA-Z]*$", "", bare)
  if (family %in% names(reg)) {
    warning(sprintf(
      "[PsyLingLLM] WARNING - model '%s' not found, fallback to family '%s'.",
      model_name, family
    ), call. = FALSE)
    return(reg[[family]])
  }

  # 5) vendor default
  vendor <- parts[1]
  vendor_default <- paste0(vendor, ":default")
  if (vendor_default %in% names(reg)) {
    warning(sprintf(
      "[PsyLingLLM] WARNING - model '%s' not found, fallback to vendor template '%s'.",
      model_name, vendor_default
    ), call. = FALSE)
    return(reg[[vendor_default]])
  }

  # 6) heuristic guess → vendor default
  guessed_vendor <- NULL
  if (grepl("^gpt|^o[0-9]", bare)) guessed_vendor <- "openai"
  if (grepl("^claude", bare)) guessed_vendor <- "anthropic"
  if (grepl("^glm", bare)) guessed_vendor <- "zhipu"
  if (grepl("^llama", bare)) guessed_vendor <- "meta"
  if (grepl("^mistral|^mixtral", bare)) guessed_vendor <- "mistral"
  if (grepl("^gemini", bare)) guessed_vendor <- "google"
  if (grepl("^moonshot", bare)) guessed_vendor <- "moonshot"
  if (grepl("^command", bare)) guessed_vendor <- "cohere"

  if (!is.null(guessed_vendor)) {
    vendor_default <- paste0(guessed_vendor, ":default")
    if (vendor_default %in% names(reg)) {
      warning(sprintf(
        "[PsyLingLLM] WARNING - model '%s' not found, guessed vendor '%s', fallback to '%s'.",
        model_name, guessed_vendor, vendor_default
      ), call. = FALSE)
      return(reg[[vendor_default]])
    }
  }

  # 7) final fallback
  if ("openai:default" %in% names(reg)) {
    warning(sprintf(
      "[PsyLingLLM] WARNING - model '%s' not found, fallback to OpenAI default.",
      model_name
    ), call. = FALSE)
    return(reg[["openai:default"]])
  }

  stop(sprintf("[PsyLingLLM] FATAL - model '%s' not found in registry.", model_name))
}



