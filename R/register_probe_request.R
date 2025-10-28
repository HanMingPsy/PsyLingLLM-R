#' Probe an LLM endpoint (non-stream + streaming, SSE-aware)
#'
#' Sends two probes to a model endpoint using the given \code{url}, \code{headers},
#' and \code{body}:
#' \enumerate{
#'   \item \strong{Non-streaming POST}: captures raw response text, HTTP status,
#'     a parsed JSON object (when parseable), and any usage block.
#'   \item \strong{Streaming attempt (SSE)}: first tries without an \code{Accept}
#'     header; if no SSE markers are detected, retries with
#'     \code{Accept: text/event-stream}. All SSE lines are returned along with a
#'     lightweight frame of deltas and the raw parsed JSON events.
#' }
#'
#' Internally, the function toggles common streaming keys in \code{body} (e.g.,
#' \code{stream}, \code{streaming}) and parses SSE frames that begin with
#' \code{data:}. It does not assume any vendor schema beyond standard SSE.
#'
#' @param url Character(1). Endpoint URL.
#' @param headers Named list of HTTP headers (e.g., \code{Content-Type},
#'   \code{Authorization}). Keys must be unique.
#' @param body Either a list (will be JSON-encoded with \code{auto_unbox = TRUE})
#'   or a character(1) JSON string. Non-stream probe forces \code{stream = FALSE};
#'   streaming probe forces \code{stream = TRUE}.
#' @param stream_param Character scalar (optional).
#'   Name of the request-body field used by the provider to enable stream.
#' @param timeout Integer(1). Per-request timeout in seconds. Applies to both
#'   non-stream and stream attempts.
#'
#' @return A list with three elements:
#' \describe{
#'   \item{non_stream}{List with fields:
#'     \itemize{
#'       \item \code{raw_text}: character, raw HTTP body.
#'       \item \code{status_code}: integer HTTP status.
#'       \item \code{parsed}: parsed JSON object (or \code{NULL} if parsing fails).
#'       \item \code{usage}: best-effort extraction of usage block (or \code{NULL}).
#'     }
#'   }
#'   \item{stream_attempt}{List with fields:
#'     \itemize{
#'       \item \code{requested_streaming}: logical, always \code{TRUE}.
#'       \item \code{honored_streaming}: logical, whether SSE markers were seen.
#'       \item \code{accept_required}: logical, whether SSE appeared only after adding
#'         \code{Accept: text/event-stream}.
#'       \item \code{reason}: short diagnostic message.
#'       \item \code{raw_lines}: character vector of SSE lines as received.
#'       \item \code{raw_df}: data frame of parsed deltas (id, model, index, role,
#'         \code{content}, \code{reasoning_content}, \code{finish_reason}); may be empty.
#'       \item \code{raw_json}: list of parsed SSE \code{data: \{...\}} payloads.
#'     }
#'   }
#'   \item{input}{Echo of inputs: \code{list(url, headers, body)}.}
#' }
#'
#' @details
#' \strong{SSE detection.} Streaming is considered honored if any line matches
#' \code{^data:\\s*\\\{} (i.e., a JSON object after \code{data:}). The function
#' first attempts without an \code{Accept} header and retries with
#' \code{Accept: text/event-stream} only if no SSE markers are observed.
#'
#' \strong{Safety.} This function does not log or redact secrets. Callers are
#' responsible for redacting/omitting API keys in logs.
#'
#' \strong{Errors.} Network issues and HTTP errors are returned via the
#' \code{non_stream$status_code} when possible; SSE parsing is best-effort and
#' yields empty structures if no valid frames are detected.
#'
#' @section Typical fields in \code{raw_df} (when present):
#' \itemize{
#'   \item \code{content}: token text deltas (chat-style).
#'   \item \code{reasoning_content}: reasoning/think deltas (if provider emits them).
#'   \item \code{finish_reason}: stream finish status per choice (if emitted).
#' }
#'
#' @seealso \code{\link{llm_register}}, \code{\link{get_registry_entry}}
#' @importFrom jsonlite fromJSON toJSON
#' @importFrom curl new_handle handle_setheaders handle_setopt curl_fetch_memory curl_fetch_stream
#' @importFrom utils head tail
#' @export
probe_llm_streaming <- function(url,
                                headers,
                                body,
                                stream_param,
                                timeout = 120) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
  parse_json_safely <- function(txt) {
    tryCatch(jsonlite::fromJSON(txt, simplifyVector = FALSE),
             error = function(e) NULL)
  }

  # --- SSE parser into raw_df + raw_json ---
  parse_sse_lines <- function(raw_lines) {
    rows <- list()
    json_list <- list()
    for (ln in raw_lines) {
      if (!startsWith(ln, "data:")) next
      payload <- sub("^data:\\s*", "", ln)
      if (payload == "[DONE]") next
      obj <- parse_json_safely(payload)
      if (is.null(obj)) next
      json_list[[length(json_list) + 1]] <- obj
      ch <- tryCatch(obj$choices[[1]], error = function(e) NULL)
      delta <- tryCatch(ch$delta, error = function(e) NULL)
      rows[[length(rows) + 1]] <- list(
        id = obj$id %||% NA,
        model = obj$model %||% NA,
        index = ch$index %||% NA,
        role = delta$role %||% NA,
        content = delta$content %||% NA,
        reasoning_content = delta$reasoning_content %||% NA,
        finish_reason = ch$finish_reason %||% NA
      )
    }
    raw_df <- if (length(rows) == 0) {
      data.frame(
        id = character(), model = character(), index = integer(),
        role = character(), content = character(),
        reasoning_content = character(), finish_reason = character(),
        stringsAsFactors = FALSE
      )
    } else {
      do.call(rbind.data.frame, c(rows, list(stringsAsFactors = FALSE)))
    }
    list(raw_df = raw_df, raw_json = json_list)
  }

  # --- helpers for HTTP ---
  to_payload <- function(x) {
    if (is.list(x)) {
      jsonlite::toJSON(x, auto_unbox = TRUE, null = "null")
    } else {
      as.character(x)
    }
  }
  http_post_memory <- function(url, headers, payload, timeout) {
    h <- curl::new_handle(); curl::handle_setheaders(h, .list = headers)
    curl::handle_setopt(h, postfields = payload, timeout = timeout)
    curl::curl_fetch_memory(url, handle = h)
  }
  http_post_stream <- function(url, headers, payload, timeout) {
    h <- curl::new_handle(); curl::handle_setheaders(h, .list = headers)
    curl::handle_setopt(h, postfields = payload, timeout = timeout)
    sse_lines <- character(); cache <- ""
    curl::curl_fetch_stream(url, fun = function(dat) {
      chunk <- iconv(rawToChar(dat, multiple = FALSE), from = "UTF-8", to = "UTF-8", sub = "")
      cache <<- paste0(cache, chunk)
      lines <- strsplit(cache, "\n", fixed = TRUE)[[1]]
      if (!endsWith(cache, "\n")) {
        cache <<- utils::tail(lines, 1)
        if (length(lines) > 1) lines <- utils::head(lines, -1) else lines <- character()
      } else cache <<- ""
      if (length(lines)) sse_lines <<- c(sse_lines, lines)
    }, handle = h)
    list(lines = sse_lines, text = paste(sse_lines, collapse = "\n"))
  }
  detect_streaming_observed <- function(sse_lines) {
    any(grepl("^data:\\s*\\{", sse_lines))
  }

  # --- non-stream run ---
  ns_body <- body
  if (is.list(ns_body)) {
    if (!is.null(stream_param) && nzchar(stream_param)) {
      ns_body[[stream_param]] <- FALSE
    } else {
      ns_body$stream <- FALSE
    }
  }
  ns_payload <- to_payload(ns_body)
  ns_resp <- http_post_memory(url, headers, ns_payload, timeout)
  ns_text <- rawToChar(ns_resp$content)
  ns_obj  <- parse_json_safely(ns_text)

  non_stream <- list(
    raw_text = ns_text,
    status_code = ns_resp$status_code,
    parsed = ns_obj,
    usage = ns_obj$usage %||% NULL
  )

  # --- streaming run (auto retry with Accept if needed) ---
  st_headers <- headers
  st_body <- body
  if (is.list(st_body)) {
    if (!is.null(stream_param) && nzchar(stream_param)) {
      st_body[[stream_param]] <- TRUE
    } else {
      st_body$stream <- TRUE
    }
  }
  st_payload <- to_payload(st_body)

  # first attempt: no Accept header
  if (!is.null(st_headers[["Accept"]])) st_headers[["Accept"]] <- NULL
  st_res1 <- http_post_stream(url, st_headers, st_payload, timeout)
  honored1 <- detect_streaming_observed(st_res1$lines)

  if (!honored1) {
    message("[probe] No SSE markers detected. Retrying with Accept: text/event-stream ...")
    st_headers2 <- c(st_headers, list("Accept" = "text/event-stream"))
    st_res2 <- http_post_stream(url, st_headers2, st_payload, timeout)
    honored2 <- detect_streaming_observed(st_res2$lines)

    if (honored2) {
      honored <- TRUE
      accept_required <- TRUE
      parsed <- parse_sse_lines(st_res2$lines)
      raw_lines <- st_res2$lines
      raw_json <- parsed$raw_json
    } else {
      honored <- FALSE
      accept_required <- FALSE
      parsed <- parse_sse_lines(st_res1$lines)
      raw_lines <- st_res1$lines
      raw_json <- parsed$raw_json
    }
  } else {
    honored <- TRUE
    accept_required <- FALSE
    parsed <- parse_sse_lines(st_res1$lines)
    raw_lines <- st_res1$lines
    raw_json <- parsed$raw_json
  }

  stream_attempt <- list(
    requested_streaming = TRUE,
    honored_streaming   = honored,
    accept_required     = accept_required,
    reason = if (honored) {
      if (accept_required) "SSE detected only after adding Accept header"
      else "SSE detected without Accept header"
    } else {
      "No SSE markers seen after both attempts"
    },
    raw_lines = raw_lines,
    raw_df = parsed$raw_df,
    raw_json = raw_json
  )



  list(non_stream = non_stream,
       stream_attempt = stream_attempt,
       input = list(url = url, headers = headers, body = body))
}

#' Detect API error payloads from a probe result
#'
#' Looks into non-streaming text/parsed JSON and streaming raw_lines/raw_json to
#' find a canonical error message (e.g., {"error": {"message": "..."} }).
#'
#' @param probe list as returned by probe_llm_streaming()
#' @return NULL if no error found; otherwise a list(message=chr, where=chr)
#' @noRd
probe_extract_error <- function(probe) {
  # Non-stream (preferred, usually 4xx JSON body)
  ns_parsed <- tryCatch(probe$non_stream$parsed, error = function(e) NULL)
  if (!is.null(ns_parsed)) {
    # Common vendor shape: {"error": {"message": "..."}}
    msg <- tryCatch(ns_parsed$error$message, error = function(e) NULL)
    if (is.character(msg) && length(msg) == 1 && nzchar(msg)) {
      return(list(message = msg, where = "non_stream.parsed"))
    }
    # Some vendors: {"message":"..."} at top-level
    msg2 <- tryCatch(ns_parsed$message, error = function(e) NULL)
    if (is.character(msg2) && length(msg2) == 1 && nzchar(msg2)) {
      return(list(message = msg2, where = "non_stream.parsed"))
    }
  }
  ns_text <- tryCatch(probe$non_stream$text, error = function(e) NULL)
  if (is.character(ns_text) && nzchar(ns_text)) {
    obj <- tryCatch(jsonlite::fromJSON(ns_text, simplifyVector = FALSE), error = function(e) NULL)
    if (!is.null(obj)) {
      msg <- tryCatch(obj$error$message, error = function(e) NULL)
      if (is.character(msg) && length(msg) == 1 && nzchar(msg)) {
        return(list(message = msg, where = "non_stream.text"))
      }
      msg2 <- tryCatch(obj$message, error = function(e) NULL)
      if (is.character(msg2) && length(msg2) == 1 && nzchar(msg2)) {
        return(list(message = msg2, where = "non_stream.text"))
      }
    }
  }

  # Streaming (SSE) – users sometimes see $stream_attempt$raw_lines with JSON error
  raw_lines <- tryCatch(probe$stream_attempt$raw_lines, error = function(e) NULL)
  if (is.character(raw_lines) && length(raw_lines) > 0) {
    joined <- paste(raw_lines, collapse = "")
    obj <- tryCatch(jsonlite::fromJSON(joined, simplifyVector = FALSE), error = function(e) NULL)
    if (!is.null(obj)) {
      msg <- tryCatch(obj$error$message, error = function(e) NULL)
      if (is.character(msg) && length(msg) == 1 && nzchar(msg)) {
        return(list(message = msg, where = "stream_attempt.raw_lines"))
      }
      msg2 <- tryCatch(obj$message, error = function(e) NULL)
      if (is.character(msg2) && length(msg2) == 1 && nzchar(msg2)) {
        return(list(message = msg2, where = "stream_attempt.raw_lines"))
      }
    }
  }

  # Some probe implementations also expose parsed stream JSON chunks
  raw_json <- tryCatch(probe$stream_attempt$raw_json, error = function(e) NULL)
  if (is.list(raw_json) && length(raw_json) >= 1) {
    # Check first chunk for an error envelope
    obj <- raw_json[[1]]
    msg <- tryCatch(obj$error$message, error = function(e) NULL)
    if (is.character(msg) && length(msg) == 1 && nzchar(msg)) {
      return(list(message = msg, where = "stream_attempt.raw_json"))
    }
    msg2 <- tryCatch(obj$message, error = function(e) NULL)
    if (is.character(msg2) && length(msg2) == 1 && nzchar(msg2)) {
      return(list(message = msg2, where = "stream_attempt.raw_json"))
    }
  }

  NULL
}
