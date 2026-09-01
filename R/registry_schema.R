#' Validate Registry v2 Schema
#'
#' Validates whether a registry entry follows PsyLingLLM
#' Registry v2 structure.
#'
#' Registry v2 requires:
#' - schema_version
#' - provider
#' - capabilities
#' - interfaces
#'
#' @param entry A registry entry as a named list.
#'
#' @return Logical value. Returns TRUE when valid.
#'
#' @export
validate_registry_schema <- function(entry) {

  required_fields <- c(
    "schema_version",
    "provider",
    "capabilities",
    "interfaces"
  )

  missing_fields <- setdiff(
    required_fields,
    names(entry)
  )

  if (length(missing_fields) > 0) {
    stop(
      sprintf(
        "Missing registry fields: %s",
        paste(missing_fields, collapse = ", ")
      )
    )
  }

  if (!identical(
    as.integer(entry$schema_version),
    2L
  )) {
    stop(
      "Registry schema_version must be 2."
    )
  }

  if (!is.list(entry$capabilities)) {
    stop(
      "`capabilities` must be a list."
    )
  }

  if (!is.list(entry$interfaces)) {
    stop(
      "`interfaces` must be a list."
    )
  }

  TRUE
}
