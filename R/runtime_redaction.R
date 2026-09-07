# Runtime diagnostic redaction ---------------------------------------------

redact_llm_diagnostics <- function(value, field_name = NULL) {
  if (is_sensitive_diagnostic_field(field_name)) {
    return("[REDACTED]")
  }

  if (is.list(value)) {
    result <- value
    value_names <- names(value)
    for (index in seq_along(value)) {
      child_name <- if (is.null(value_names)) NULL else value_names[[index]]
      result[index] <- list(redact_llm_diagnostics(value[[index]], child_name))
    }
    return(result)
  }

  if (is.character(value)) {
    return(vapply(
      value,
      redact_diagnostic_text,
      character(1),
      USE.NAMES = FALSE
    ))
  }

  if (is.raw(value)) {
    return(tryCatch(
      charToRaw(redact_diagnostic_text(rawToChar(value))),
      error = function(error) charToRaw("[REDACTED BINARY]")
    ))
  }

  value
}

is_sensitive_diagnostic_field <- function(field_name) {
  if (is.null(field_name) || length(field_name) != 1L ||
      is.na(field_name)) {
    return(FALSE)
  }
  normalized <- gsub("[^a-z0-9]", "", tolower(field_name))
  normalized %in% c(
    "authorization", "proxyauthorization", "xapikey", "apikey",
    "accesstoken", "refreshtoken", "clientsecret", "password",
    "credential", "credentials"
  )
}

redact_diagnostic_text <- function(value) {
  if (is.na(value) || !nzchar(value)) {
    return(value)
  }
  value <- gsub(
    "(?i)\\bBearer\\s+[^\\s,;]+",
    "Bearer [REDACTED]",
    value,
    perl = TRUE
  )
  value <- gsub(
    "(?im)^((?:authorization|proxy-authorization|x-api-key|api-key|set-cookie)\\s*:\\s*).*$",
    "\\1[REDACTED]",
    value,
    perl = TRUE
  )
  value <- gsub(
    "(?i)(\\\"?(?:api[_-]?key|access[_-]?token|client[_-]?secret|password)\\\"?\\s*[:=]\\s*\\\"?)[^\\\"\\s,;}]+",
    "\\1[REDACTED]",
    value,
    perl = TRUE
  )
  gsub("\\$\\{(?:API_KEY|ACCESS_TOKEN|CLIENT_SECRET)\\}",
       "[REDACTED]", value, perl = TRUE)
}

diagnostic_request_payload <- function(payload) {
  parsed <- if (is.character(payload) && length(payload) == 1L) {
    tryCatch(
      jsonlite::fromJSON(payload, simplifyVector = FALSE),
      error = function(error) NULL
    )
  } else {
    payload
  }
  if (is.null(parsed)) {
    return(redact_llm_diagnostics(as.character(payload %||% "")))
  }
  jsonlite::toJSON(
    redact_llm_diagnostics(parsed),
    auto_unbox = TRUE,
    null = "null",
    digits = NA
  )
}
