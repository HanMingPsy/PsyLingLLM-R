# Registry source loading ----------------------------------------------------

#' Return the Bundled System Registry Path
#'
#' @return Character scalar containing the installed system registry path, or
#'   an empty string when it cannot be found.
#' @keywords internal
get_system_registry_path <- function() {
  system.file("registry/system_registry.yaml", package = "PsyLingLLM")
}

# Load system, user, and default registry sources into canonical v2 views.
# This remains internal until the public registry contracts are migrated.
load_registry_bundle <- function(system_path = get_system_registry_path(),
                                 user_path = get_registry_path(),
                                 default_registry = NULL,
                                 legacy_user_path = NULL) {
  if (is.null(legacy_user_path) &&
      registry_paths_equal(user_path, get_registry_path())) {
    legacy_user_path <- get_legacy_registry_path()
  }
  if (registry_paths_equal(user_path, legacy_user_path)) {
    legacy_user_path <- NULL
  }
  raw_system <- registry_read_source(
    system_path, source = "system", missing_ok = FALSE
  )
  raw_user_current <- registry_read_source(
    user_path, source = "user", missing_ok = TRUE
  )
  raw_user_legacy <- registry_read_source(
    legacy_user_path, source = "legacy user", missing_ok = TRUE
  )
  raw_default <- default_registry

  if (is.null(raw_default)) {
    raw_default <- list()
  }
  if (!is.list(raw_default)) {
    registry_load_abort(
      "Default registry must be a list.",
      source = "default",
      reason = "invalid_type"
    )
  }

  system <- registry_normalize_source(raw_system)
  user_current <- registry_normalize_source(raw_user_current)
  user_legacy <- registry_normalize_source(raw_user_legacy)
  user <- registry_merge_sources(
    registry_empty_v2(),
    user_legacy,
    user_current
  )
  default <- registry_normalize_source(raw_default)
  merged <- registry_merge_sources(default, system, user)
  raw_user <- if (length(raw_user_current)) raw_user_current else raw_user_legacy

  list(
    system = system,
    user = user,
    default = default,
    merged = merged,
    raw = list(
      system = raw_system,
      user = raw_user,
      default = raw_default
    ),
    versions = c(
      system = registry_source_version(raw_system),
      user = registry_source_version(raw_user),
      default = registry_source_version(raw_default)
    ),
    paths = list(system = system_path, user = user_path)
  )
}

registry_paths_equal <- function(left, right) {
  scalar_path <- function(value) {
    is.character(value) && length(value) == 1L && !is.na(value) &&
      nzchar(value)
  }
  if (!scalar_path(left) || !scalar_path(right)) {
    return(FALSE)
  }
  left <- normalizePath(left, winslash = "/", mustWork = FALSE)
  right <- normalizePath(right, winslash = "/", mustWork = FALSE)
  if (identical(.Platform$OS.type, "windows")) {
    left <- tolower(left)
    right <- tolower(right)
  }
  identical(left, right)
}

registry_read_source <- function(path, source, missing_ok,
                                 empty_as_list = TRUE) {
  if (is.null(path) || identical(path, "")) {
    if (missing_ok) {
      return(list())
    }
    registry_load_abort(
      "Registry path is empty.", source, path, "missing_file"
    )
  }
  if (!is.character(path) || length(path) != 1L || is.na(path)) {
    registry_load_abort(
      "Registry path must be a character scalar.",
      source, path, "invalid_path"
    )
  }
  if (!file.exists(path)) {
    if (missing_ok) {
      return(list())
    }
    registry_load_abort(
      "Registry file does not exist.", source, path, "missing_file"
    )
  }

  registry <- tryCatch(
    yaml::read_yaml(path),
    error = function(error) {
      registry_load_abort(
        conditionMessage(error), source, path, "parse_error"
      )
    }
  )
  if (is.null(registry)) {
    if (empty_as_list) {
      return(list())
    }
    return(NULL)
  }
  if (!is.list(registry)) {
    registry_load_abort(
      "Registry document must parse to a list.",
      source, path, "invalid_document"
    )
  }

  registry
}

registry_normalize_source <- function(registry) {
  if (length(registry) == 0L) {
    return(registry_empty_v2())
  }
  as_registry_v2(registry)
}

registry_empty_v2 <- function() {
  list(
    schema_version = 2L,
    providers = list(),
    interfaces = list(),
    capabilities = list(),
    models = list()
  )
}

registry_merge_sources <- function(default, system, user) {
  merged <- registry_empty_v2()
  domains <- c("providers", "interfaces", "capabilities", "models")

  for (source in list(default, system, user)) {
    validate_registry_schema(source)
    for (domain in domains) {
      for (id in names(source[[domain]])) {
        merged[[domain]][[id]] <- source[[domain]][[id]]
      }
    }
  }

  validate_registry_schema(merged)
  merged
}

registry_source_version <- function(registry) {
  if (length(registry) == 0L) {
    return(NA_integer_)
  }
  if ("schema_version" %in% names(registry)) {
    return(as.integer(registry$schema_version))
  }
  1L
}

registry_load_abort <- function(message, source, path = NULL, reason = NULL) {
  location <- source
  if (!is.null(path) && length(path) == 1L && !is.na(path) && nzchar(path)) {
    location <- paste0(location, " registry `", path, "`")
  }
  condition <- structure(
    list(
      message = paste0("Failed to load ", location, ": ", message),
      call = NULL,
      source = source,
      path = path,
      reason = reason
    ),
    class = c("registry_load_error", "error", "condition")
  )
  stop(condition)
}
