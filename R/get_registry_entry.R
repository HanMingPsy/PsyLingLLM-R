#' Retrieve a registry interface entry (inputs / outputs / streaming)
#'
#' Look up a model first in the **user registry** (by default at
#' `get_registry_path()`), and if not found, fall back to the **system
#' registry** located at `inst/registry/model_registry.yaml`. Select an interface
#' (e.g., `"chat"`, `"completion"`) and return a **normalized** node ready for
#' request assembly.
#'
#' Normalization rules:
#' - `input.role_mapping` may be partially specified or absent; we keep it as is
#'   (possibly `NULL` per key). Downstream callers decide whether to apply it.
#' - Boolean-like values such as `"yes"/"no"`, `"true"/"false"`, `0/1` are
#'   coerced to logicals for `reasoning` and `streaming.enabled`.
#' - `optional_defaults` scalars are lightly normalized (numeric-like strings →
#'   numeric; boolean-like strings → logical) while preserving unknown vendor
#'   fields.
#' - Output path fields (e.g., `respond_path`, `delta_path`) are **left as-is**
#'   (e.g., `list("choices..message.content")`).
#'
#' Model key conventions:
#' - Official providers typically use keys **without** `@` (e.g., `"deepseek-chat"`).
#' - Non-official providers should use keys **with** `@provider`
#'   (e.g., `"deepseek-chat@proxy"`).
#'
#' @param model_key Character(1). Either `"<model>"` or `"<model>@<provider>"`.
#' @param generation_interface Character(1) or NULL. One of `"chat"`, `"completion"`,
#'   `"messages"`, `"conversation"`, `"responses"`, `"generate"`, `"inference"`.
#'   If `NULL` and the model has exactly one interface, that interface is selected.
#' @param path Character(1). User registry path. Defaults to `get_registry_path()`.
#'
#' @return A list with fields:
#' \describe{
#'   \item{model_key}{Resolved key (may include `@provider`).}
#'   \item{interface}{Selected interface name.}
#'   \item{provider}{Provider label from the registry node (normalized to lower).}
#'   \item{reasoning}{Logical. Whether the provider exposes reasoning fields.}
#'   \item{input}{List with `default_url`, `headers`, `body`, `fallback_body`,
#'   `optional_defaults`, `default_system`, and `role_mapping` (kept as provided).}
#'   \item{output}{List with `respond_path`, `thinking_path`, `id_path`,
#'   `object_path`, and optional `token_usage_path`.}
#'   \item{streaming}{List with `enabled`, `delta_path`, `thinking_delta_path`.}
#'   \item{interfaces}{Character vector of available interfaces for this model.}
#' }
#' @examples
#' \dontrun{
#'   ent <- get_registry_entry("deepseek-chat", generation_interface = "chat")
#'   ent$input$role_mapping$user
#'   ent$output$respond_path
#' }
#' @export
get_registry_entry <- function(model_key,
                               generation_interface = NULL,
                               path = get_registry_path()) {
  if (!requireNamespace("yaml", quietly = TRUE)) {
    stop("Package 'yaml' is required for get_registry_entry().")
  }

  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

  # --- helpers (local) ------------------------------------------------------
  normalize_bool <- function(x) {
    if (is.logical(x)) return(x)
    if (is.numeric(x) && length(x) == 1) return(!is.na(x) && x != 0)
    if (is.character(x) && length(x) == 1) {
      s <- tolower(trimws(x))
      if (s %in% c("true","t","yes","y","on","1"))  return(TRUE)
      if (s %in% c("false","f","no","n","off","0","~","null","na","none","")) return(FALSE)
    }
    isTRUE(x)
  }

  normalize_scalar <- function(v) {
    if (is.null(v) || length(v) != 1) return(v)
    if (is.logical(v) || is.numeric(v)) return(v)
    if (is.character(v)) {
      s <- trimws(v)
      if (tolower(s) %in% c("true","t","yes","y","on","1"))  return(TRUE)
      if (tolower(s) %in% c("false","f","no","n","off","0")) return(FALSE)
      if (grepl("^[-+]?[0-9]+(\\.[0-9]+)?$", s)) return(as.numeric(s))
      return(s)
    }
    v
  }

  normalize_role_mapping <- function(mp) {
    # Keep as provided, but only accept known keys; allow NULLs (caller decides to apply).
    out <- list(system = NULL, user = NULL, assistant = NULL, tool = NULL)
    if (!is.list(mp)) return(out)
    nm <- tolower(names(mp))
    for (k in names(out)) {
      i <- which(nm == k)[1]
      if (length(i) && !is.na(i)) {
        val <- mp[[i]]
        if (is.character(val) && length(val) == 1 && nzchar(val)) out[[k]] <- val
      }
    }
    out
  }

  read_yaml_safe <- function(p) {
    if (!is.character(p) || !length(p) || is.na(p) || !file.exists(p)) return(NULL)
    tryCatch(yaml::read_yaml(p), error = function(e) NULL)
  }

  select_interface <- function(node, iface) {
    if (!is.list(node) || !length(node)) stop("Registry node is empty or invalid.")
    iface_names <- names(node)
    if (is.null(iface_names) || !length(iface_names)) stop("No interfaces found for this model.")
    if (!is.null(iface)) {
      if (is.null(node[[iface]])) {
        stop(sprintf("Interface '%s' not found. Available: %s",
                     iface, paste(iface_names, collapse = ", ")))
      }
      return(list(iface_name = iface, iface_node = node[[iface]], iface_names = iface_names))
    }
    if (length(iface_names) == 1) {
      nm <- iface_names[[1]]
      return(list(iface_name = nm, iface_node = node[[nm]], iface_names = iface_names))
    }
    stop(sprintf("Multiple interfaces available: %s. Please specify `generation_interface`.",
                 paste(iface_names, collapse = ", ")))
  }


  # --- 1) user registry first ----------------------------------------------
  user_reg <- read_yaml_safe(path)
  if (!is.null(user_reg) && is.list(user_reg) && !is.null(user_reg[[model_key]])) {
    sel <- select_interface(user_reg[[model_key]], generation_interface)
    return(normalize_registry_entry(sel$iface_node, model_key, sel$iface_name))
  }

  # --- 2) system registry fallback ------------------------------------------
  sys_path <- get_system_registry_path()
  sys_reg  <- read_yaml_safe(sys_path)
  if (!is.null(sys_reg) && is.list(sys_reg) && !is.null(sys_reg[[model_key]])) {
    sel <- select_interface(sys_reg[[model_key]], generation_interface)
    return(normalize_registry_entry(sel$iface_node, model_key, sel$iface_name))
  }

  stop(sprintf("Model '%s' not found in user or system registry.", model_key), call. = FALSE)
}

# ---- internal helpers -------------------------------------------------------

#' Return the system registry path (internal helper)
#'
#' Default location: `inst/registry/model_registry.yaml` inside the installed package.
#' Separated for safe test-time overriding without touching base::system.file().
#' @return Character(1) absolute path, or "" if missing.
#' @keywords internal
get_system_registry_path <- function() {
  # NOTE: If your package name is actually 'psylingllm', change below accordingly.
  system.file("registry/model_registry.yaml", package = "PsyLingLLM")
}



#' Normalize a raw registry entry (internal, legacy/export-free)
#'
#' Backward-compatible alias kept for older tests/fixtures that call this directly.
#' Prefer the closure `normalize_registry_entry()` inside `get_registry_entry()`.
#' @keywords internal
normalize_registry_entry <- function(entry, model_key, generation_interface) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
  boolify <- function(x) {
    if (is.logical(x)) return(x)
    if (is.character(x)) {
      lx <- tolower(trimws(x))
      if (lx %in% c("yes","true","y","1"))  return(TRUE)
      if (lx %in% c("no","false","n","0"))  return(FALSE)
    }
    if (is.numeric(x) && length(x) == 1) return(!is.na(x) && x != 0)
    isTRUE(x)
  }

  provider   <- tolower(as.character(entry$provider %||% "unknown"))
  reasoning  <- boolify(entry$reasoning %||% FALSE)

  inp <- entry$input %||% list()

  optional_defaults_raw <- inp$optional_defaults %||% list()
  opt <- unwrap_typed_defaults(optional_defaults_raw)


  role_mapping_raw <- inp$role_mapping %||% inp$role_map %||% NULL
  role_mapping <- {
    out <- list(system = NULL, user = NULL, assistant = NULL, tool = NULL)
    if (is.list(role_mapping_raw)) {
      nm <- tolower(names(role_mapping_raw))
      for (k in names(out)) {
        i <- which(nm == k)[1]
        if (length(i) && !is.na(i)) {
          val <- role_mapping_raw[[i]]
          if (is.character(val) && length(val) == 1 && nzchar(val)) out[[k]] <- val
        }
      }
    }
    out
  }

  list(
    model_key  = model_key,
    interface  = generation_interface,
    provider   = provider,
    reasoning  = reasoning,
    input      = list(
      default_url       = inp$default_url %||% NULL,
      headers           = inp$headers %||% list(),
      body              = inp$body %||% list(),
      fallback_body     = inp$fallback_body %||% NULL,
      optional_defaults = opt,
      default_system    = inp$default_system %||% NULL,
      role_mapping      = role_mapping
    ),
    output     = {
      out <- entry$output %||% list()
      list(
        respond_path     = out$respond_path %||% NULL,
        thinking_path    = out$thinking_path %||% NULL,
        id_path          = out$id_path %||% NULL,
        object_path      = out$object_path %||% NULL,
        token_usage_path = out$token_usage_path %||% NULL
      )
    },
    streaming  = {
      st <- entry$streaming %||% list()
      list(
        enabled             = boolify(st$enabled %||% FALSE),
        delta_path          = st$delta_path %||% NULL,
        thinking_delta_path = st$thinking_delta_path %||% NULL,
        param_name          = st$param_name %||% NULL
      )
    },
    interfaces = names(entry %||% list())
  )
}
