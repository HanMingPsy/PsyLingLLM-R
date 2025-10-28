#' Classify LLM generation interface from URL (robust and version-agnostic)
#'
#' This unified function normalizes an API URL path, strips leading version prefixes
#' (e.g. /api/v1/, /v2beta/), and classifies the interface type for LLM endpoints.
#'
#' Recognized endpoint patterns (case-insensitive, version-insensitive):
#'   - /chat, /chat/completions → "chat"
#'   - /completions → "completion"
#'   - /messages → "messages"
#'   - /conversation → "conversation"
#'   - /responses → "responses"
#'   - /generate or /text-generation → "generate"
#'   - /inference → "inference"
#' Anything else → "unknown".
#'
#' @param url character(1) Full or partial API URL
#' @return character(1) interface type string
#' @export
classify_generation_interface <- function(url) {
  stopifnot(is.character(url), length(url) == 1L)

  # ---- Normalize path ----
  path <- tolower(trimws(url))

  # Extract path component (drop domain if present)
  path <- sub("^[^/]*//[^/]+", "", path)    # remove scheme+host
  path <- sub("^[^/]*", "", path)           # ensure starts with "/"

  # Normalize multiple slashes and remove trailing slash
  path <- gsub("//+", "/", path)
  path <- sub("/$", "", path)

  # ---- Strip version prefix (/api/v1, /v2beta, etc.) ----
  path <- sub("(?i)^(/api)?/v[0-9]+[a-z]*(?=/|$)", "", path, perl = TRUE)

  # ---- Classification (fuzzy matching) ----
  if (grepl("chat(/completions?)?$", path))     return("chat")
  if (grepl("messages?$", path))                return("messages")
  if (grepl("conversation$", path))             return("conversation")
  if (grepl("responses?$", path))               return("responses")
  if (grepl("completions?$", path))             return("completion")
  if (grepl("generate(text)?$", path))          return("generate")
  if (grepl("inference$", path))                return("inference")

  # ---- Default ----
  "unknown"
}


#' Normalize a free-form provider label
#'
#' This utility normalizes a provider label or tag string into a clean,
#' canonical form. It removes a leading `'@'` if present and trims
#' surrounding whitespace.
#'
#' Used internally when constructing registry keys or interface metadata,
#' ensuring that providers like `"@openai"`, `" chutes.ai "`, or
#' `"local"` are standardized to consistent identifiers.
#'
#' @param provider A character string (or coercible value) representing the
#'   provider label. Only the first element is used.
#'
#' @return A character scalar containing the normalized provider label.
#'   Returns `"unknown"` if the input is `NULL` or empty.
#'
#' @seealso [build_registry_entry_from_analysis()]
#' @export
normalize_provider_label <- function(provider) {
  if (is.null(provider) || !length(provider)) return("unknown")
  t <- trimws(as.character(provider[[1]]))
  sub("^@", "", t)
}


#' Normalize a free-form type string (strip a leading '@' if present)
#' @param type character(1), e.g., "chutes.ai" or "@chutes.ai"
#' @return character(1) normalized type, e.g., "chutes.ai"
#' @export
normalize_type_label <- function(type) {
  if (is.null(type) || !length(type)) return("unknown")
  t <- trimws(as.character(type[[1]]))
  sub("^@", "", t)
}
