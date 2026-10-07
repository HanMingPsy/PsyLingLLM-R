#' Upsert endpoint entry into the user registry (safe merge)
#'
#' This Registry v1 writer inserts or updates an LLM endpoint entry in a
#' YAML-based user registry. If an entry with the same key (e.g.
#' "deepseek-chat@chutes.ai") already exists, new generation interface nodes
#' (e.g. `chat`, `completion`) are merged instead of overwriting the whole
#' model section. Native Registry v2 bundles are rejected rather than mixed
#' with v1 entries.
#'
#' Interface nodes are automatically detected by structure — any list
#' containing fields like `input`, `output`, `streaming`, or `provider`
#' will be treated as an interface definition.
#'
#' The complete result is validated and written to a temporary file before the
#' original is replaced. Invalid existing YAML is never silently discarded.
#'
#' @param entry A named list, typically returned by `build_registry_entry_from_analysis()`.
#' @param path  Optional Registry v1 YAML path (defaults to
#'   `get_registry_path()`).
#'
#' @importFrom stats setNames
#'
#' @return Invisibly returns the merged registry list.
#' @export
register_endpoint_to_user_registry <- function(entry, path = get_registry_path()) {
  if (!requireNamespace("yaml", quietly = TRUE)) {
    stop("Package 'yaml' is required for register_endpoint_to_user_registry().")
  }

  if (!is.list(entry) || length(entry) != 1L || is.null(names(entry)) ||
      is.na(names(entry)[1L]) || !nzchar(names(entry)[1L]) ||
      !is.list(entry[[1L]])) {
    stop("`entry` must contain exactly one named Registry v1 model entry.",
         call. = FALSE)
  }

  # ---- Load existing registry ----
  reg <- if (file.exists(path)) {
    registry_read_source(
      path,
      source = "user",
      missing_ok = FALSE
    )
  } else list()

  if (length(reg) && "schema_version" %in% names(reg)) {
    stop(
      paste(
        "Registry v2 files are read-only for the v1 registration writer.",
        "Use a separate v1 user Registry path or edit and validate the v2",
        "bundle explicitly."
      ),
      call. = FALSE
    )
  }

  # ---- Extract entry key and data ----
  key <- names(entry)[1]
  new_entry <- entry[[key]]

  # ---- Merge with existing entry (if present) ----
  if (!is.null(reg[[key]])) {
    existing <- reg[[key]]

    for (field in names(new_entry)) {
      value <- new_entry[[field]]

      # Detect if this field is a generation interface node
      is_interface <- is.list(value) && any(names(value) %in% c("input", "output"))

      if (is_interface) {
        # Replace or add interface node
        existing[[field]] <- value
      } else {
        existing[[field]] <- value
      }
    }

    # Keep field order deterministic (alphabetical)
    reg[[key]] <- existing[sort(names(existing))]
  } else {
    # New model entry
    reg[[key]] <- new_entry
  }

  # Validate the complete v1 document before replacing any user file.
  validate_registry_schema(registry_normalize_source(reg))
  write_user_registry_v1(reg, path)

  invisible(reg)
}

#' Get user registry path (cross-platform, unified)
#'
#' Uses the platform-specific user configuration directory returned by
#' \code{tools::R_user_dir("PsyLingLLM", "config")}. The historical
#' \code{~/.psylingllm/model_registry.yaml} location remains readable but is
#' not rewritten automatically.
#' @return Path to user registry YAML
#' @export
get_registry_path <- function() {
  file.path(
    tools::R_user_dir("PsyLingLLM", "config"),
    "model_registry.yaml"
  )
}

get_legacy_registry_path <- function() {
  file.path(path.expand("~"), ".psylingllm", "model_registry.yaml")
}


#' Ensure registry directory exists and header is present
#'
#' Creates the Registry directory and writes a file header if the Registry
#' file does not exist yet or is empty.
#' @param path character(1) registry yaml path
#' @export
ensure_registry_header <- function(path = get_registry_path()) {
  ensure_psylingllm_directory(dirname(path), "Registry directory")
  if (!file.exists(path) || file.size(path) == 0) {
    temporary <- tempfile(
      pattern = ".registry-header-",
      tmpdir = dirname(path),
      fileext = ".yaml"
    )
    on.exit(if (file.exists(temporary)) unlink(temporary, force = TRUE),
            add = TRUE)
    writeLines(registry_header_lines(), temporary, useBytes = TRUE)
    replace_file_safely(temporary, path, overwrite = TRUE)
  }
  invisible(path)
}

registry_header_lines <- function() {
  now <- format(Sys.time(), "%Y-%m-%d %H:%M:%S %z")
  c(
    "# =============================================================",
    "# PsyLingLLM Model Registry",
    "# Registry key format: <model>@<type>",
    "# - <type> is free-form (e.g., chutes.ai, local, vllm-prod)",
    "# - This file should NOT contain API keys or runtime URLs.",
    paste0("# Generated: ", now),
    "# =============================================================",
    ""
  )
}

write_user_registry_v1 <- function(registry, path) {
  ensure_psylingllm_directory(dirname(path), "Registry directory")
  temporary <- tempfile(
    pattern = ".registry-",
    tmpdir = dirname(path),
    fileext = ".yaml"
  )
  on.exit(if (file.exists(temporary)) unlink(temporary, force = TRUE),
          add = TRUE)

  connection <- file(temporary, open = "wt", encoding = "UTF-8")
  tryCatch(
    {
      for (key in names(registry)) {
        cat("# =====================\n", file = connection)
        cat(sprintf("# Model: %s\n\n", key), file = connection)
        yaml::write_yaml(
          setNames(list(registry[[key]]), key),
          connection,
          indent = 2
        )
        cat("\n", file = connection)
      }
    },
    finally = close(connection)
  )

  written <- registry_read_source(
    temporary,
    source = "temporary user",
    missing_ok = FALSE
  )
  validate_registry_schema(registry_normalize_source(written))
  replace_file_safely(temporary, path, overwrite = TRUE)
  invisible(path)
}

