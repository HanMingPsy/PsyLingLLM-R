#' Recursively find the first path to a placeholder string
#'
#' This utility function traverses a nested R object (typically a list)
#' to locate the first scalar string that exactly matches a given placeholder
#' value (by default, \code{"\${CONTENT}"}). It performs a depth-first search
#' and returns the traversal path as a list of keys and/or indices.
#'
#' Path segments are expressed as character keys or integer indices,
#' for example:
#' ```
#' list("messages", 2, "content")
#' ```
#' indicating that the placeholder was found at
#' `x[["messages"]][[2]][["content"]]`.
#'
#' @param x A nested R object (usually a list or list-like structure) to be searched.
#' @param placeholder Character(1). The exact scalar string value to look for.
#'   Defaults to \code{"\${CONTENT}"}.
#'
#' @return A list of path segments (keys or indices) leading to the first
#'   occurrence of the placeholder, or `NULL` if not found.
#'
#' @seealso [build_body_pass2_structural()]
#' @export
find_placeholder_path <- function(x, placeholder = "${CONTENT}") {
  stack <- list(list(obj = x, path = list()))
  while (length(stack)) {
    cur <- stack[[length(stack)]]
    stack <- stack[-length(stack)]
    obj <- cur$obj; path <- cur$path
    if (is.list(obj)) {
      nm <- names(obj)
      for (i in seq_along(obj)) {
        seg <- if (length(nm) && nzchar(nm[i])) nm[i] else i
        stack[[length(stack) + 1]] <- list(obj = obj[[i]], path = c(path, seg))
      }
    } else if (is.character(obj) && length(obj) == 1) {
      if (identical(obj, placeholder)) return(path)
    }
  }
  NULL
}


#' Get a nested value by a mixed path (character keys and integer indices)
#'
#' This helper function retrieves a nested value from a list-like object
#' by following a *mixed path* consisting of character keys (for named lists)
#' and/or integer indices (for unnamed elements).
#'
#' It is tolerant to structural inconsistencies: if any intermediate
#' component is missing, `NULL`, or not a list, the function returns `NULL`
#' rather than throwing an error.
#'
#' @param x A list or list-like R object from which to retrieve a nested value.
#' @param path A vector or list of path segments. Each segment may be either:
#'   \itemize{
#'     \item A **character key**, e.g. `"messages"`;
#'     \item An **integer index**, e.g. `2L`.
#'   }
#'   The function follows these segments in order to descend into nested structures.
#'
#' @return The nested value located at the specified path, or `NULL`
#'   if the path does not exist or cannot be traversed.
#'
#' @seealso [find_placeholder_path()]
#' @export
list_get_by_path <- function(x, path) {
  cur <- x
  if (is.null(path) || !length(path)) return(cur)
  for (seg in path) {
    if (is.null(cur)) return(NULL)
    if (!is.list(cur)) return(NULL)
    if (is.character(seg)) {
      if (!seg %in% names(cur)) return(NULL)
      cur <- cur[[seg]]
    } else if (is.numeric(seg)) {
      idx <- as.integer(seg)
      if (idx < 1 || idx > length(cur)) return(NULL)
      cur <- cur[[idx]]
    } else return(NULL)
  }
  cur
}


#' Infer structure from where \code{"\${CONTENT}"} lives
#'
#' - If \code{"\${CONTENT}"} sits inside a small list which is inside a larger list,
#'   treat it as messages-style.
#'   * content_key = name of the element holding \code{"\${CONTENT}"}
#'   * role_key    = the *immediately previous* element name in that small list
#'   * container_key = the named key that holds the sequence of messages
#'   * message_index = the numeric position in that sequence
#' - If \code{"\${CONTENT}"} is directly under a top-level key, treat as single-prompt.
#'
#' @param body A list or character vector representing the raw input structure
#'   in which the placeholder is to be searched.
#' @param placeholder Character(1). The placeholder string to search for,
#'   typically \code{"\${CONTENT}"}.
#'
#' @return list(style, container_key, message_index, content_key, role_key, default_system)
#' @export
infer_structure_from_placeholder <- function(body, placeholder = "${CONTENT}") {
  p <- find_placeholder_path(body, placeholder = placeholder)
  if (is.null(p)) stop("Could not locate ${CONTENT} in Pass-1 body.")

  content_key <- as.character(p[[length(p)]])
  if (!is_key(content_key)) {
    return(list(style = "single",
                container_key = NULL,
                message_index = NULL,
                content_key = as.character(p[[length(p)]]),
                role_key = NULL,
                default_system = NULL))
  }

  msg_path <- p[seq_len(length(p) - 1)]
  msg_node <- list_get_by_path(body, msg_path)
  if (!is.list(msg_node)) {
    return(list(style = "single",
                container_key = NULL,
                message_index = NULL,
                content_key = content_key,
                role_key = NULL,
                default_system = NULL))
  }

  nm <- names(msg_node)
  idx <- which(nm == content_key)[1]
  role_key <- if (!is.na(idx) && idx > 1) nm[idx - 1] else NULL
  if (!is.null(role_key) && !nzchar(role_key)) role_key <- NULL

  container_key <- NULL
  message_index <- NULL
  if (length(msg_path) >= 2) {
    last_seg <- msg_path[[length(msg_path)]]
    prev_seg <- msg_path[[length(msg_path) - 1]]
    if (is.numeric(last_seg) && is_key(prev_seg)) {
      container_key <- as.character(prev_seg)
      message_index <- as.integer(last_seg)
    }
  }

  if (is.null(container_key) || is.na(message_index)) {
    return(list(style = "single",
                container_key = NULL,
                message_index = NULL,
                content_key = content_key,
                role_key = role_key,
                default_system = NULL))
  }

  # Heuristic system (purely structural): prior sibling message's same content field
  default_system <- NULL
  container_path <- msg_path[seq_len(length(msg_path) - 1)]
  container_node <- list_get_by_path(body, container_path)
  if (is.list(container_node) && length(container_node) >= 1 && message_index > 1) {
    for (j in seq.int(message_index - 1, 1)) {
      m <- tryCatch(container_node[[j]], error = function(e) NULL)
      if (is.list(m) && !is.null(m[[content_key]]) &&
          is.character(m[[content_key]]) && length(m[[content_key]]) == 1 &&
          nzchar(m[[content_key]])) {
        default_system <- as.character(m[[content_key]])
        break
      }
    }
  }

  list(
    style = "messages",
    container_key = container_key,
    message_index = message_index,
    content_key = content_key,
    role_key = role_key,
    default_system = default_system
  )
}


#' Extract a value by path from a parsed JSON-like list
#' Numeric segments are treated as zero-based JSON indices
#' @param obj list
#' @param path mixed path spec
#' @keywords internal
#' @export
json_get_by_path <- function(obj, path) {
  segs <- coerce_path_segments(path)
  cur <- obj
  for (sg in segs) {
    if (is.null(cur)) return(NULL)
    if (is.numeric(sg)) {
      idx <- as.integer(sg)
      if (is.na(idx)) return(NULL)
      cur <- cur[[idx + 1L]]  # zero-based -> 1-based
    } else {
      cur <- cur[[as.character(sg)]]
    }
  }
  cur
}



#' Safely coerce various path specs to segment vector
#' Accepts: list("a","b"), c("a","b"), "a.b", 'list("a","b")'
#' @param p mixed
#' @keywords internal
#' @export
coerce_path_segments <- function(p) {
  # already vector
  if (is.list(p) && all(vapply(p, function(x) is.character(x) || is.numeric(x), logical(1)))) {
    return(unlist(p, use.names = FALSE))
  }
  if (is.character(p) && length(p) == 1) {
    s <- trimws(p)
    # R list("a","b") literal
    if (grepl('^list\\s*\\(.*\\)\\s*$', s)) {
      ok <- grepl('^list\\s*\\((".*?"(\\s*,\\s*".*?")*)\\)\\s*$', s)
      if (ok) {
        segs <- tryCatch(eval(parse(text = s), envir = baseenv()), error = function(e) NULL)
        if (is.null(segs)) return(character())
        return(unlist(segs, use.names = FALSE))
      }
    }
    # dot path
    if (grepl("\\.", s)) {
      out <- unlist(strsplit(s, "\\.", perl = TRUE), use.names = FALSE)
      return(out[nzchar(out)])
    }
    # single token
    return(s)
  }
  if (is.atomic(p)) return(as.character(p))
  character()
}


#' Utility: check if a path segment is a named key
#'
#' Determines whether a given path segment represents a valid named key
#' (i.e., a non-empty single-length character string).
#' Used internally by list/path traversal helpers such as
#' [list_get_by_path()] and [find_placeholder_path()].
#'
#' @param seg A single path segment to test (may be character, numeric, or other type).
#'
#' @return Logical scalar. `TRUE` if the segment is a non-empty character key,
#'   otherwise `FALSE`.
is_key <- function(seg) is.character(seg) && length(seg) == 1 && nzchar(seg)
