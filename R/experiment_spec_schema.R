experiment_spec_schema_path <- function(version = 1L) {
  version <- suppressWarnings(as.integer(version))
  if (length(version) != 1L || is.na(version) || version != 1L) {
    experiment_spec_abort(
      "Only Experiment Spec schema version 1 is supported.",
      reason = "unsupported_schema_version"
    )
  }

  filename <- sprintf("experiment-spec-v%d.schema.json", version)
  path <- system.file("schema", filename, package = "PsyLingLLM")
  if (!nzchar(path)) {
    development_path <- file.path("inst", "schema", filename)
    if (file.exists(development_path)) {
      path <- development_path
    }
  }
  if (!nzchar(path) || !file.exists(path)) {
    experiment_spec_abort(
      sprintf("Experiment Spec schema asset is unavailable: %s.", filename),
      reason = "schema_asset_missing"
    )
  }
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

read_experiment_spec_schema <- function(version = 1L) {
  path <- experiment_spec_schema_path(version)
  text <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  tryCatch(
    jsonlite::fromJSON(text, simplifyVector = FALSE),
    error = function(error) {
      experiment_spec_abort(
        paste("Experiment Spec schema asset contains invalid JSON:", conditionMessage(error)),
        reason = "invalid_schema_asset"
      )
    }
  )
}

experiment_spec_schema_json <- function(version = 1L) {
  path <- experiment_spec_schema_path(version)
  paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}
