#' Render a registry entry preview (verbatim from the registry node)
#'
#' This function renders a human/CI readable preview **directly from the
#' registry entry**, without any heuristics. It mirrors the exact structure that
#' will be serialized into YAML (provider, input/body/fallback_body/optionals,
#' output paths, streaming config).
#'
#' The function supports entries with one or more interfaces
#' (e.g., "chat", "completion"). Each interface is printed in order.
#'
#' @param entry A single-model registry entry (named list) as returned by
#'   `build_registry_entry_from_analysis()`, e.g.:
#'   list("<model_key>" = list(completion = <iface_node>, chat = <iface_node>, ...))
#'
#' @return Character vector of lines suitable for printing to console/CI.
#' @export
format_registration_preview <- function(entry) {
  stopifnot(is.list(entry), length(entry) == 1)
  model_key <- names(entry)[1]
  model_node <- entry[[model_key]]
  stopifnot(is.list(model_node), length(model_node) >= 1)

  yn <- function(x) if (isTRUE(x)) "yes" else "no"
  nz <- function(x, alt = "~") if (is.null(x) || (is.character(x) && !nzchar(x))) alt else x
  as_chr <- function(x) {
    if (is.null(x)) return("~")
    if (is.logical(x) && length(x) == 1) return(yn(x))
    if (is.numeric(x)  && length(x) == 1) return(as.character(x))
    if (is.character(x) && length(x) == 1) return(x)
    # For any non-scalar list/complex value, render a short structural hint
    if (is.list(x)) return("(list)")
    "(value)"
  }

  # Render token_usage_path block (prompt/completion/total) if present
  render_token_usage <- function(tu) {
    lines <- character()
    lines <- c(lines, "- token_usage_path:")
    if (is.null(tu) || !length(tu)) {
      lines <- c(lines, "    - ~")
      return(lines)
    }
    if (!is.null(tu$prompt))     lines <- c(lines, sprintf("  - prompt: %s",     as_chr(tu$prompt)))
    if (!is.null(tu$completion)) lines <- c(lines, sprintf("  - completion: %s", as_chr(tu$completion)))
    if (!is.null(tu$total))      lines <- c(lines, sprintf("  - total: %s",      as_chr(tu$total)))
    if (length(lines) == 1L)     lines <- c(lines, "    - ~")
    lines
  }

  # Begin rendering
  lines <- character()
  lines <- c(lines, sprintf("\U0001F9FE  Registration Preview  \U0001F9FE:  `%s`", model_key), "  ")

  iface_names <- names(model_node)
  for (i in seq_along(iface_names)) {
    iface_name <- iface_names[[i]]
    iface <- model_node[[iface_name]]

    # Header line
    provider  <- nz(iface$provider)
    reasoning <- yn(iface$reasoning)
    lines <- c(
      lines,
      sprintf("[TYPE]   %s   |   [PROVIDER]   %s   |   [REASONING]   %s", iface_name, provider, reasoning),
      ""
    )

    # Input
    input <- iface$input %||% list()
    lines <- c(lines, " \U0001F4E6 Input Configuration")
    lines <- c(lines, "(Defines how the API request body is structured and what optionals are supported)\n")
    lines <- c(lines, sprintf("- default_url: %s", as_chr(input$default_url)))

    # Headers (verbatim)
    lines <- c(lines, "\n- headers:")
    lines <- c(lines, render_named_bullets(input$headers, indent = "  "))

    # Body and fallback_body (verbatim order)
    lines <- c(lines, "\n- body:")
    if (!is.null(input$body)) {
      b <- render_body(input$body, level = 1L)
      if (length(b)) {
        lines <- c(lines, b)
      } else {
        lines <- c(lines, "  - ~")
      }
    } else {
      lines <- c(lines, "  - ~")
    }

    lines <- c(lines, "\n- fallback_body:")
    if (!is.null(input$fallback_body)) {
      fb <- render_body(input$fallback_body, level = 1L)  # <-- pass the right object
      if (length(fb)) {
        lines <- c(lines, fb)
      } else {
        lines <- c(lines, "  - ~")
      }
    } else {
      lines <- c(lines, "  - ~")
    }

    # Optional defaults
    if (!is.null(input$optional_defaults) && length(input$optional_defaults)) {
      lines <- c(lines, "\n- optional_defaults:")
      lines <- c(lines, render_named_bullets(input$optional_defaults, indent = "  "))
    } else {
      lines <- c(lines, "- optional_defaults: ~")
    }

    if (!is.null(input$role_mapping) && length(input$role_mapping)) {
      lines <- c(lines, "\n- role_mapping:")
      lines <- c(lines, render_named_bullets(input$role_mapping, indent = "  "))
    } else {
      lines <- c(lines, "\n- role_mapping: ~")
    }

    lines <- c(lines, sprintf("\n- default_system: %s", as_chr(input$default_system)), "")

    # Output
    out <- iface$output %||% list()
    lines <- c(lines, "\n \U0001F9E0 Output Configuration")
    lines <- c(lines, "(Specifies JSON paths used to extract model responses and metadata)")
    lines <- c(lines, sprintf("\n- respond_path: %s",    as_chr(out$respond_path[[1]] %||% out$respond_path)))
    lines <- c(lines, sprintf("\n- thinking_path: %s",   as_chr(out$thinking_path[[1]] %||% out$thinking_path %||% NULL)))
    lines <- c(lines, sprintf("\n- id_path: %s",         as_chr(out$id_path[[1]] %||% out$id_path)))
    lines <- c(lines, sprintf("\n- object_path: %s",     as_chr(out$object_path[[1]] %||% out$object_path)))
    if (!is.null(out$token_usage_path)) {
      lines <- c(lines, render_token_usage(out$token_usage_path))
    } else {
      lines <- c(lines, "- token_usage_path: ~")
    }
    lines <- c(lines, "")

    # Streaming
    st <- iface$streaming %||% list(enabled = FALSE)
    lines <- c(lines, "\n \U0001F501 Streaming Configuration")
    lines <- c(lines, "(Defines Server-Sent Event (SSE) delta mapping for incremental responses)\n")
    lines <- c(lines, sprintf("- enabled: %s", yn(st$enabled)))
    lines <- c(lines, sprintf("- delta_path: %s",           as_chr(st$delta_path[[1]] %||% st$delta_path %||% NULL)))
    lines <- c(lines, sprintf("- thinking_delta_path: %s",  as_chr(st$thinking_delta_path[[1]] %||% st$thinking_delta_path %||% NULL)))
    lines <- c(lines, "")

    # Separator between interfaces
    if (i < length(iface_names)) {
      lines <- c(lines, "---", "")
    } else {
      lines <- c(lines, "---")
    }
  }

  lines <- c(lines,
  "\n\n\U0001F50E Please review the registry entry carefully before confirming registration.
   If something looks incorrect:
     - You can re-run the llm_register with corrected inputs.
     - Or manually edit the registry YAML file.\n\n")
  lines
}

#' Indent all lines by N indentation levels (2 spaces per level)
#' @param x character vector of lines
#' @param levels integer number of indent levels (each = 2 spaces)
#' @return character vector with indentation applied
#' @keywords internal
#' @noRd
indent_lines <- function(x, levels = 1L) {
  if (length(x) == 0) return(x)
  pad <- paste0(rep("  ", max(0L, as.integer(levels))), collapse = "")
  paste0(pad, x)
}

#' Render a body list in YAML-like preview form, preserving key order
#'
#' - Top-level items are rendered as " - key: value"
#' - Nested lists increase indentation by 1 level (2 spaces)
#' - NULL/empty become "~"
#' - Character values are left verbatim (do not escape placeholders)
#'
#' @param x list or atomic to render
#' @param level integer indentation level (0 at the " - body:" anchor level)
#' @return character vector of lines
#' @keywords internal
#' @noRd
render_body <- function(x, level = 0L) {
  bullet <- function(k, v) paste0("- ", k, ": ", v)

  as_yaml_scalar <- function(v) {
    if (is.null(v) || (is.atomic(v) && length(v) == 0)) return("~")
    if (isTRUE(is.list(v))) return(NULL)  # handled by list branch
    if (length(v) > 1 && is.atomic(v)) {
      # simple inline array representation for preview
      vals <- v
      vals_chr <- if (is.character(vals)) vals else as.character(vals)
      return(paste0("[", paste(vals_chr, collapse = ", "), "]"))
    }
    if (is.logical(v)) return(if (isTRUE(v)) "true" else if (identical(v, FALSE)) "false" else "~")
    if (is.numeric(v)) return(format(v, trim = TRUE, scientific = FALSE))
    if (is.character(v)) return(v)  # keep placeholders verbatim
    "~"
  }

  # NULL or atomic
  if (!is.list(x)) {
    sc <- as_yaml_scalar(x)
    return(indent_lines(bullet("", gsub("^: ", "", paste0(": ", sc))), level)) # "- : value" -> "- value"
  }

  # list branch (preserve order)
  nms <- names(x)
  out <- character()

  for (i in seq_along(x)) {
    key <- nms[i]
    val <- x[[i]]

    if (is.list(val)) {
      # nested object
      line <- paste0("- ", key, ":")
      out <- c(out, indent_lines(line, level))
      # children rendered one level deeper
      child <- render_body(val, level = level + 1L)
      if (length(child) == 0) {
        out <- c(out, indent_lines("~", level + 1L))
      } else {
        out <- c(out, child)
      }
    } else {
      sc <- as_yaml_scalar(val)
      out <- c(out, indent_lines(bullet(key, sc), level))
    }
  }
  out
}

#' Render a named list as YAML-like bullet lines
#'
#' Supports both simple key:value pairs and typed defaults
#' of the form list(value=..., type=...).
#'
#' @param lst Named list to render.
#' @param indent String of spaces used for indentation (default "    ").
#' @return Character vector of lines.
#' @keywords internal
render_named_bullets <- function(lst, indent = "    ") {
  if (is.null(lst) || !length(lst)) return(character())
  out <- character()
  nms <- names(lst)
  if (is.null(nms)) nms <- rep("", length(lst))

  as_chr <- function(x) {
    if (is.null(x)) return("~")
    if (is.logical(x)) return(tolower(as.character(x)))
    if (is.numeric(x)) return(as.character(x))
    if (is.character(x)) return(x)
    if (is.list(x)) return("<list>")
    deparse(x)
  }

  for (i in seq_along(lst)) {
    key <- nms[[i]]
    val <- lst[[i]]

    # case 1: typed default (list(value=..., type=...))
    if (is.list(val) && all(c("value","type") %in% names(val))) {
      out <- c(out, sprintf("%s- %s:", indent, key))
      out <- c(out, sprintf("%s    value: %s", indent, as_chr(val$value)))
      out <- c(out, sprintf("%s    type: %s", indent, as_chr(val$type)))
    }
    # case 2: simple named pair
    else if (nzchar(key)) {
      out <- c(out, sprintf("%s- %s: %s", indent, key, as_chr(val)))
    }
    # case 3: unnamed scalar list item
    else {
      out <- c(out, sprintf("%s- %s", indent, as_chr(val)))
    }
  }
  out
}
