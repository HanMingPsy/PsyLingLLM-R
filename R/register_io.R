#' Upsert endpoint entry into the user registry (safe merge)
#'
#' This function inserts or updates an LLM endpoint entry in a YAML-based
#' user registry. If an entry with the same key (e.g. "deepseek-chat@chutes.ai")
#' already exists, new generation interface nodes (e.g. `chat`, `completion`)
#' are merged instead of overwriting the whole model section.
#'
#' Interface nodes are automatically detected by structure — any list
#' containing fields like `input`, `output`, `streaming`, or `provider`
#' will be treated as an interface definition.
#'
#' The registry file is rewritten with header comments and each model
#' section separated by comment lines for readability.
#'
#' @param entry A named list, typically returned by `build_registry_entry_from_analysis()`.
#' @param path  Optional registry YAML path (defaults to `get_registry_path()`).
#'
#' @importFrom stats setNames
#'
#' @return Invisibly returns the merged registry list.
#' @export
register_endpoint_to_user_registry <- function(entry, path = get_registry_path()) {
  if (!requireNamespace("yaml", quietly = TRUE)) {
    stop("Package 'yaml' is required for register_endpoint_to_user_registry().")
  }

  ensure_registry_header(path)

  # ---- Load existing registry ----
  reg <- if (file.exists(path)) {
    tryCatch(yaml::read_yaml(path), error = function(e) list())
  } else list()

  if (!is.list(reg)) reg <- list()

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

  # ---- Write back to YAML with headers ----
  con <- file(path, open = "wt", encoding = "UTF-8")
  on.exit(close(con), add = TRUE)

  for (k in names(reg)) {
    cat("# =====================\n", file = con)
    cat(sprintf("# Model: %s\n\n", k), file = con)
    yaml::write_yaml(setNames(list(reg[[k]]), k), con, indent = 2)
    cat("\n", file = con)
  }

  invisible(reg)
}

#' Get user registry path (cross-platform, unified)
#'
#' Always use ~/.psylingllm/model_registry.yaml on all systems.
#' @return Path to user registry YAML
#' @export
get_registry_path <- function() {
  file.path(path.expand("~"), ".psylingllm", "model_registry.yaml")
}


#' Ensure registry directory exists and header is present
#'
#' Creates ~/.psylingllm/ and writes a file header if the registry file
#' does not exist yet or is empty.
#' @param path character(1) registry yaml path
#' @export
ensure_registry_header <- function(path = get_registry_path()) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  if (!file.exists(path) || file.size(path) == 0) {
    con <- file(path, open = "wt", encoding = "UTF-8")
    on.exit(close(con), add = TRUE)
    now <- format(Sys.time(), "%Y-%m-%d %H:%M:%S %z")
    cat("# ==============================================================\n", file = con)
    cat("# PsyLingLLM Model Registry\n", file = con)
    cat("# Registry key format: <model>@<type>\n", file = con)
    cat("# - <type> is free-form (e.g., chutes.ai, local, vllm-prod)\n", file = con)
    cat("# - This file should NOT contain API keys or runtime URLs.\n", file = con)
    cat("# Generated: ", now, "\n", sep = "", file = con)
    cat("# ==============================================================\n\n", file = con)
  }
}

