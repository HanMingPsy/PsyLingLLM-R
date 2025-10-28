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

  norm_key <- function(x) {
    x |>
      tolower() |>
      gsub("[/:_\\s]+", "-", x = _) |>
      gsub("-{2,}", "-", x = _) |>
      sub("^-", "", x = _) |>
      sub("-$", "", x = _)
  }

  # Load new-style registry bundle and pick $merged, or accept a flat list.
  reg_in <- registry
  reg <- if (!is.null(reg_in$merged)) reg_in$merged else reg_in

  # 1) exact
  if (model_name %in% names(reg)) return(reg[[model_name]])

  # 2) normalized / alias
  keys_norm <- vapply(names(reg), norm_key, character(1))
  name_norm <- norm_key(model_name)
  hit <- which(keys_norm == name_norm)
  if (length(hit) == 1) return(reg[[ names(reg)[hit] ]])

  for (k in names(reg)) {
    aliases <- reg[[k]]$aliases %||% character()
    if (tolower(model_name) %in% tolower(aliases)) return(reg[[k]])
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



