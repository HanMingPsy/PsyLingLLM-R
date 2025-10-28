#' Extract a value from nested JSON-like objects by path (0-based, wildcard-aware)
#'
#' Traverses a nested list (from `jsonlite::fromJSON(..., simplifyVector = FALSE)`)
#' using a path of keys/indices. Supports wildcards and collapse.
#'
#' Conventions:
#' - **Indices are 0-based** (JSON style). Converted to 1-based for R internally.
#' - The wildcard `"*"` expands over all elements at that level.
#' - Use `collapse=""` to assemble streaming deltas into one string.
#' - Default `trim=FALSE` to preserve leading spaces (important for SSE tokens).
#'
#' @param x A nested list parsed from JSON.
#' @param path Character/numeric vector or a single dotted/bracket string
#'   (e.g., `"choices.0.message.content"` or `c("choices", 0, "message", "content")`).
#' @param simplify Logical, default TRUE. If TRUE, `unlist(use.names=FALSE)`
#'   atomic leaves into a flat vector.
#' @param collapse Optional scalar. If provided, paste results with collapse.
#' @param trim Logical, default FALSE. If TRUE, trims whitespace from final character values.
#' @param strict Logical, default FALSE. If TRUE, missing path raises error.
#'   Otherwise returns NULL.
#'
#' @return Extracted value(s), or NULL.
#'
#' @examples
#' x <- list(choices = list(list(message = list(content = "Hello", reasoning_content = " Think."))))
#' extract_by_path(x, c("choices", 0, "message", "content"))
#' # "Hello"
#' extract_by_path(x, "choices.0.message.reasoning_content", trim=FALSE)
#' # " Think."
#' y <- list(choices = list(list(delta=list(content="Hel")), list(delta=list(content="lo"))))
#' extract_by_path(y, c("choices","*","delta","content"), collapse="")
#' # "Hello"
#' @noRd
extract_by_path <- function(x,
                            path,
                            simplify = TRUE,
                            collapse = NULL,
                            trim = FALSE,
                            strict = FALSE) {
  is_whole_number_string <- function(z) {
    is.character(z) && grepl("^[0-9]+$", z)
  }

  normalize_path <- function(p) {
    if (is.null(p)) return(character())
    if (is.list(p))  p <- unlist(p, use.names = FALSE)
    if (length(p) == 1 && is.character(p)) {
      s <- gsub("\\[", ".", p)
      s <- gsub("\\]", "", s)
      toks <- unlist(strsplit(s, "\\.", fixed = FALSE), use.names = FALSE)
      toks <- toks[nzchar(toks)]
      return(toks)
    }
    as.vector(p)
  }

  step_once <- function(node, k) {
    if (is.null(node)) return(NULL)

    if (identical(k, "*")) return("**WILDCARD**")

    idx <- NULL
    if (is.numeric(k)) idx <- as.integer(k)
    if (is.null(idx) && is_whole_number_string(k)) idx <- as.integer(k)

    if (!is.null(idx)) {
      idx_r <- idx + 1L  # 0-based → 1-based
      return(tryCatch(node[[idx_r]], error = function(e) NULL))
    } else {
      return(tryCatch(node[[k]], error = function(e) NULL))
    }
  }

  walk <- function(node, toks) {
    if (is.null(node)) return(list())
    if (length(toks) == 0) return(list(node))

    k <- toks[[1]]
    rest <- if (length(toks) > 1) toks[-1] else character()

    if (identical(k, "*")) {
      if (!is.list(node)) return(list())
      out <- list()
      for (el in node) out <- c(out, walk(el, rest))
      return(out)
    } else {
      child <- step_once(node, k)
      if (identical(child, "**WILDCARD**")) return(list())
      if (is.null(child)) return(list())
      return(walk(child, rest))
    }
  }

  toks <- normalize_path(path)
  if (length(toks) == 0) return(NULL)

  matches <- walk(x, toks)
  if (length(matches) == 0) {
    if (isTRUE(strict)) stop("Path not found: ", paste(toks, collapse = "."))
    return(NULL)
  }

  out <- matches
  if (isTRUE(simplify)) {
    are_atomic <- vapply(out, function(z) is.atomic(z) && length(z) == 1, logical(1))
    if (all(are_atomic)) out <- unlist(out, use.names = FALSE)
  }

  if (!is.null(collapse) && (is.atomic(out) || is.vector(out))) {
    out <- paste(out, collapse = collapse)
  }

  if (isTRUE(trim) && is.character(out)) {
    if (requireNamespace("stringr", quietly = TRUE)) {
      out <- stringr::str_trim(out)
    } else {
      out <- gsub("^[[:space:]]+|[[:space:]]+$", "", out)
    }
  }

  out
}


as_json <- function(x) {
  if (is.null(x)) return(NA_character_)
  tryCatch(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null"),
           error = function(e) NA_character_)
}

