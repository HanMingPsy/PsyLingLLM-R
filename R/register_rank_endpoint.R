#' Default keyword lexicon for ns/st scoring
#'
#' @return A named list with strong_signal, ns, st, and blacklist entries.
#' @export
default_keyword_lexicon <- function() {
  list(
    # Streaming "strong signals" — used as a separate feature; never mixed into keyword counts.
    strong_signal = c("delta", "fragment", "chunk", "partial", "continue", "increment", "prefix"),
    # Non-streaming keyword banks
    ns = list(
      answer = c("content", "text", "message", "output", "choice", "answer", "response", "result", "reply", "body"),
      think  = c("reasoning", "thought", "rationale", "explanation", "chain", "inference", "analysis",
                 "trace", "justification", "thinking", "why", "because", "solve", "deduce")
    ),
    # Streaming keyword banks (same semantics; delta handled separately as strong_signal)
    st = list(
      answer = c("content", "text", "message", "output", "choice", "answer", "response", "result", "reply", "body"),
      think  = c("reasoning", "thought", "rationale", "explanation", "chain", "inference", "analysis",
                 "trace", "justification", "thinking", "why", "because", "solve", "deduce")
    ),
    # Hard blacklist tokens that indicate metadata/system fields
    blacklist = unique(c(
      # existing metadata/system
      "id", "created", "timestamp", "time", "usage", "model", "object",
      "finish_reason", "role", "index", "meta", "status", "system_fingerprint",
      # provider error & diagnostics
      common_error_blacklist(),
      # diagnostics/debug fields
      "exception", "debug", "stack", "stacktrace", "trace", "context", "diagnostic",
      # transport-ish
      "http", "url", "headers"
    ))
  )
}

#' Common provider error-field blacklist (path segments only)
#'
#' Curated from OpenAI, Anthropic, Google/Vertex, Azure OpenAI, AWS Bedrock,
#' Mistral, and Cohere docs. These are *field names* that typically occur in
#' error/diagnostic payloads and should be excluded from answer/think scoring.
#'
#' Important: We intentionally DO NOT include "message" because many providers
#' use `...message.content` for valid assistant responses.
#'
#' @return character vector of lowercase tokens (segments)
#' @export
common_error_blacklist <- function() {
  c(
    # generic
    "error", "errors", "type", "code", "status", "status_code", "detail", "details",
    "inner_error", "innererror", "request_id", "request-id", "requestid",
    # google rpc / vertex
    "status", "details", "fieldviolations", "google.rpc", "badrequest",
    # azure openai content filter
    "content_filter_results", "responsibleaipolicyviolation", "content_policy_violation",
    # aws bedrock exceptions (streaming & runtime)
    "throttlingexception", "validationexception", "internalserverexception",
    "serviceunavailableexception", "modeltimeoutexception", "modelstreamerrorexception",
    "modelerrorexception", "originalstatuscode", "originalmessage",
    # anthropic types
    "invalid_request_error", "authentication_error", "permission_error",
    "not_found_error", "request_too_large", "rate_limit_error",
    "api_error", "overloaded_error",
    # openai common codes (values often appear as fields)
    "invalid_request_error", "rate_limit_error", "context_length_exceeded",
    # mistral / fastapi
    "detail", "loc", "msg"
  )
}


#' Flatten a JSON-like object into (path, key, value) rows
#'
#' @param x list parsed from JSON
#' @param keep_numeric logical; keep numeric leaves as strings
#' @return data.frame(path, key, value, type)
#' @export
flatten_json_paths <- function(x, keep_numeric = FALSE) {
  rows <- list()
  walk <- function(node, path = character()) {
    if (is.list(node)) {
      nms <- names(node)
      if (is.null(nms)) nms <- rep("", length(node))
      for (i in seq_along(node)) walk(node[[i]], c(path, nms[[i]]))
    } else {
      if (is.character(node) && length(node) == 1) {
        rows[[length(rows) + 1]] <<- list(
          path = paste(path, collapse = "."),
          key = if (length(path)) tail(path, 1) else "",
          value = node,
          type = "character"
        )
      } else if (keep_numeric && (is.numeric(node) || is.integer(node)) && length(node) == 1) {
        rows[[length(rows) + 1]] <<- list(
          path = paste(path, collapse = "."),
          key = if (length(path)) tail(path, 1) else "",
          value = as.character(node),
          type = "numeric"
        )
      }
    }
  }
  walk(x, character())
  if (!length(rows)) {
    return(data.frame(path = character(), key = character(), value = character(), type = character(),
                      stringsAsFactors = FALSE))
  }
  as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE)
}

#' Rank non-streaming JSON paths for answer/think (segment-aware, conflict-guarded)
#'
#' Given a parsed **non-streaming** LLM JSON response, this function scores every
#' leaf node and returns the most probable **answer** and **think** fields.
#' The scorer:
#' \itemize{
#'   \item flattens the JSON into \code{(path, key, value)} rows;
#'   \item counts \emph{segment-exact} matches against \code{lexicon$ns$answer}
#'         and \code{lexicon$ns$think};
#'   \item applies path boosts (e.g., \code{choices/message/content/text} → answer;
#'         \code{reasoning/thinking/analysis} → think);
#'   \item penalizes answer picks found under reasoning-like segments;
#'   \item length-normalizes and clipped-length scores;
#'   \item softmax-normalizes to probabilities and selects tops above thresholds.
#' }
#'
#' @param obj A parsed JSON object (list) representing a non-streaming response.
#' @param lexicon A keyword lexicon list (see \code{default_keyword_lexicon()}),
#'   containing \code{$ns$answer}, \code{$ns$think}, and a global \code{$blacklist}.
#' @param prob_thresh Named list with numeric thresholds in \code{[0, 1]} for
#'   selection: \code{list(answer = 0.60, think = 0.55)} by default. If the top
#'   probability for a side is below its threshold, that side is returned as \code{NULL}.
#' @param top_k Integer. Number of top ranked candidate rows to keep in the
#'   \code{candidates} data frame (after sorting by the max of the two scores).
#'
#' @return A list with:
#' \describe{
#'   \item{\code{best}}{A list with two entries \code{answer} and \code{think},
#'     each either \code{NULL} or a list: \code{list(path, key, text, prob, score)}.
#'     If both winners point to the same path, the \code{think} winner is suppressed
#'     (set to \code{NULL}) to avoid duplication.}
#'   \item{\code{candidates}}{A data frame of up to \code{top_k} rows with columns:
#'     \code{path}, \code{key}, \code{value}, \code{hits_answer}, \code{hits_think},
#'     \code{len_norm}, \code{len_clip}, \code{path_boost_ans}, \code{path_boost_think},
#'     \code{conflict_reason}, \code{score_ns_answer}, \code{score_ns_think},
#'     \code{prob_ns_answer}, \code{prob_ns_think}, \code{excerpt}, \code{rank_key}.}
#' }
#'
#' @details
#' The scoring uses segment-level token hits (no substring matching) plus path-based
#' boosts and conflict penalties. Probabilities are produced via a softmax over
#' the respective score vectors (\code{answer} and \code{think}) independently.
#' Thresholds gate the final picks. See also \code{score_candidates_st()} for
#' streaming (SSE) candidates ranking.
#'
#' @section Conflicts & thresholds:
#' If both best indices resolve to the same \code{path}, \code{think} is suppressed.
#' Any side whose top probability is below its threshold is returned as \code{NULL}.
#'
#' @seealso \code{\link{score_candidates_st}}, \code{\link{flatten_json_paths}},
#'   \code{\link{default_keyword_lexicon}}
#'
#' @export
score_candidates_ns <- function(obj,
                                lexicon = default_keyword_lexicon(),
                                prob_thresh = list(answer = 0.60, think = 0.55),
                                top_k = 10) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
  if (is.null(obj) || length(obj) == 0) {
    return(list(best = list(answer = NULL, think = NULL),
                candidates = data.frame()))
  }
  df <- flatten_json_paths(obj, keep_numeric = TRUE)
  if (!nrow(df)) {
    return(list(best = list(answer = NULL, think = NULL),
                candidates = data.frame()))
  }

  max_len <- max(nchar(df$value %||% ""), na.rm = TRUE)
  max_len <- ifelse(is.finite(max_len) && max_len > 0, max_len, 1)

  ans_tokens <- lexicon$ns$answer
  thk_tokens <- lexicon$ns$think
  blacklist  <- lexicon$blacklist

  compute_row <- function(i) {
    path <- df$path[i]; key <- df$key[i]; val <- df$value[i]
    segs <- extract_segments(path, key)

    hits_answer <- segment_hit_count(segs, ans_tokens)
    hits_think  <- segment_hit_count(segs, thk_tokens)

    len_norm    <- nchar(val) / max_len
    len_clip    <- f_len_clip(len_norm)

    # Segment-aware boosts (no substring)
    ans_boost_segs <- c("choices", "message", "output", "content", "text", "choice",
                        "answer", "reply", "result")
    thk_boost_segs <- c("reasoning", "reasoning_content", "thinking", "explanation",
                        "rationale", "trace", "analysis", "justification")

    path_boost_ans   <- as.integer(any(ans_boost_segs %in% segs))
    path_boost_think <- as.integer(any(thk_boost_segs %in% segs))

    conflict_reason  <- has_reasoning_segment(segs)

    invalid <- is_invalid_candidate(path, key, val, blacklist)

    score_ns_answer <- if (invalid) -9999 else (
      7*hits_answer + 2*len_clip + 2*path_boost_ans
      - 5*as.integer(conflict_reason)   # ⬅ depress answer if reasoning segment present
    )
    score_ns_think  <- if (invalid) -9999 else (
      6*hits_think  + 4*len_clip + 2*path_boost_think
      + 2*as.integer(conflict_reason)   # ⬅ boost think if reasoning segment present
    )

    list(
      path = path, key = key, value = val,
      hits_answer = hits_answer, hits_think = hits_think,
      len_norm = len_norm, len_clip = len_clip,
      path_boost_ans = path_boost_ans, path_boost_think = path_boost_think,
      conflict_reason = as.integer(conflict_reason),
      score_ns_answer = score_ns_answer, score_ns_think = score_ns_think
    )
  }

  rows <- lapply(seq_len(nrow(df)), compute_row)
  cand <- as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE)

  # numeric coercion
  as_num <- function(x, default = NA_real_) { y <- suppressWarnings(as.numeric(x)); y[!is.finite(y)] <- default; y }
  num_cols <- c("hits_answer","hits_think","len_norm","len_clip",
                "path_boost_ans","path_boost_think","conflict_reason",
                "score_ns_answer","score_ns_think")
  for (cn in num_cols) cand[[cn]] <- as_num(cand[[cn]], if (grepl("^score", cn)) -9999 else 0)

  cand$prob_ns_answer <- softmax_safe(cand$score_ns_answer)
  cand$prob_ns_think  <- softmax_safe(cand$score_ns_think)
  cand$excerpt <- vapply(cand$value, trim_excerpt, character(1), n = 160)

  pick_idx <- function(probs, thr) { i <- suppressWarnings(which.max(probs)); if (!length(i) || is.na(i) || probs[i] < thr) NA_integer_ else i }
  i_ans <- pick_idx(cand$prob_ns_answer, prob_thresh$answer)
  i_thk <- pick_idx(cand$prob_ns_think,  prob_thresh$think)

  if (!is.na(i_ans) && !is.na(i_thk) && identical(cand$path[i_ans], cand$path[i_thk])) i_thk <- NA_integer_

  best <- list(
    answer = if (!is.na(i_ans)) list(path = cand$path[i_ans], key = cand$key[i_ans],
                                     text = cand$value[i_ans], prob = cand$prob_ns_answer[i_ans],
                                     score = cand$score_ns_answer[i_ans]) else NULL,
    think  = if (!is.na(i_thk)) list(path = cand$path[i_thk], key = cand$key[i_thk],
                                     text = cand$value[i_thk], prob = cand$prob_ns_think[i_thk],
                                     score = cand$score_ns_think[i_thk]) else NULL
  )

  cand$rank_key <- pmax(cand$score_ns_answer, cand$score_ns_think, na.rm = TRUE)
  cand <- cand[order(-cand$rank_key), ]
  if (nrow(cand) > top_k) cand <- cand[seq_len(top_k), ]

  list(best = best, candidates = cand)
}



#' Rank streaming (SSE) candidates for answer/think
#'   (temporal aggregation, delta-aware, conflict-guarded)
#'
#' Given a sequence of **streaming** SSE payloads (parsed JSON objects or a
#' pre-flattened table), this function aggregates token deltas across events and
#' scores candidate JSON paths for the most probable **answer** and **think**
#' fields.
#'
#' @param raw_df A pre-flattened \code{data.frame} of event-level paths and values,
#'   typically containing columns such as \code{event_index}, \code{path}, \code{key},
#'   and \code{value}. May be \code{NULL} if only \code{raw_json} is supplied.
#' @param raw_json A list of parsed SSE JSON payloads, where each element corresponds
#'   to one event. Each should be a JSON-like list structure.
#' @param lexicon A keyword lexicon list (see \code{\link{default_keyword_lexicon}}),
#'   containing entries \code{$st$answer}, \code{$st$think}, and a global
#'   \code{$blacklist}.
#' @param prob_thresh Named list of acceptance thresholds in \code{[0,1]}, controlling
#'   when top candidates for each side are accepted (defaults to
#'   \code{list(answer = 0.70, think = 0.55)}).
#' @param top_k Integer. Keep at most this many top-ranked candidates in the returned
#'   \code{candidates} table.
#'
#' @return A list with two elements:
#'   \describe{
#'     \item{\code{best}}{List containing \code{answer} and \code{think} entries.
#'       Each entry is either \code{NULL} or a list with fields
#'       \code{path}, \code{key}, \code{text}, \code{prob}, and \code{score}.}
#'     \item{\code{candidates}}{A data frame of up to \code{top_k} rows containing
#'       event-level metrics, normalized scores, and probabilities for each
#'       candidate path.}
#'   }
#'
#' @details
#' The algorithm aggregates streaming delta events, rewarding stable token updates
#' across time and penalizing conflicts (e.g., answer-like text inside reasoning
#' segments). It uses early/late-event cues, lexical matching, and conflict guards.
#' See \code{\link{score_candidates_ns}} for the non-streaming variant.
#'
#' @seealso \code{\link{score_candidates_ns}}, \code{\link{flatten_json_paths}},
#'   \code{\link{default_keyword_lexicon}}
#'
#' @export

score_candidates_st <- function(raw_df,
                                raw_json,
                                lexicon = default_keyword_lexicon(),
                                prob_thresh = list(answer = 0.70, think = 0.55),
                                top_k = 10) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
  if (is.null(raw_df) || !nrow(raw_df) || is.null(raw_json) || !length(raw_json)) {
    return(list(best = list(answer = NULL, think = NULL),
                candidates = data.frame()))
  }

  max_event <- length(raw_json)
  buckets <- new.env(parent = emptyenv())
  for (ev in seq_along(raw_json)) {
    flat <- flatten_json_paths(raw_json[[ev]], keep_numeric = TRUE)
    if (!nrow(flat)) next
    for (i in seq_len(nrow(flat))) {
      path <- flat$path[i]; key <- flat$key[i]; val <- flat$value[i]
      fk <- paste(path, key, sep = "|")
      if (is.null(buckets[[fk]])) buckets[[fk]] <- list(path = path, key = key, values = character(), events = integer())
      if (!is.null(val) && nzchar(val)) {
        buckets[[fk]]$values <- c(buckets[[fk]]$values, val)
        buckets[[fk]]$events <- c(buckets[[fk]]$events, ev)
      }
    }
  }

  keys <- ls(buckets, all.names = FALSE)
  if (!length(keys)) return(list(best = list(answer = NULL, think = NULL), candidates = data.frame()))

  assemble <- function(k) {
    b <- buckets[[k]]
    if (!length(b$values)) return(NULL)
    text <- paste(b$values, collapse = "")
    list(
      path = b$path, key = b$key, text = text,
      first_event = min(b$events), last_event = max(b$events),
      nonempty_count = length(unique(b$events)), len = nchar(text)
    )
  }
  rows <- Filter(Negate(is.null), lapply(keys, assemble))
  cand <- as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE)
  if (!nrow(cand)) return(list(best = list(answer = NULL, think = NULL), candidates = data.frame()))

  # numeric coercion
  as_num <- function(x, default = NA_real_) { y <- suppressWarnings(as.numeric(x)); y[!is.finite(y)] <- default; y }
  cand$first_event    <- as_num(cand$first_event, 0)
  cand$last_event     <- as_num(cand$last_event, 0)
  cand$nonempty_count <- as_num(cand$nonempty_count, 0)
  cand$len            <- as_num(cand$len, 0)

  strong    <- lexicon$strong_signal
  ans_tok   <- lexicon$st$answer
  thk_tok   <- lexicon$st$think
  blacklist <- lexicon$blacklist

  max_len <- max(cand$len %||% 1)
  cand$len_norm <- ifelse(max_len > 0, cand$len / max_len, 0)
  cand$len_clip <- vapply(cand$len_norm, f_len_clip, numeric(1))
  cand$last_event_norm   <- pmin(1, pmax(0, cand$last_event / max_event))
  cand$first_event_early <- as.integer(cand$first_event == 1)
  cand$stop_early        <- as.integer(cand$last_event <  max_event)
  cand$freq_norm         <- pmin(1, pmax(0, cand$nonempty_count / max_event))

  # segment-exact features
  cand$segs_list <- mapply(extract_segments, cand$path, cand$key, SIMPLIFY = FALSE)
  cand$hits_answer <- vapply(cand$segs_list, segment_hit_count, integer(1), vocab = ans_tok)
  cand$hits_think  <- vapply(cand$segs_list, segment_hit_count, integer(1), vocab = thk_tok)
  cand$has_ans_kw   <- as.integer(cand$hits_answer > 0)
  cand$has_think_kw <- as.integer(cand$hits_think  > 0)

  cand$hit_delta <- mapply(function(path, key) {
    hit_delta_flag(path, key, strong_tokens = strong)
  }, cand$path, cand$key)

  cand$conflict_reason <- vapply(cand$segs_list, has_reasoning_segment, logical(1))

  # segment-aware boosts
  ans_boost_segs <- c("choices", "message", "output", "content", "text", "choice",
                      "answer", "reply", "result")
  thk_boost_segs <- c("reasoning", "reasoning_content", "thinking", "explanation",
                      "rationale", "trace", "analysis", "justification")
  cand$path_boost_ans   <- as.integer(vapply(cand$segs_list, function(s) any(ans_boost_segs %in% s), logical(1)))
  cand$path_boost_think <- as.integer(vapply(cand$segs_list, function(s) any(thk_boost_segs %in% s), logical(1)))

  # invalids
  cand$invalid <- mapply(is_invalid_candidate, cand$path, cand$key, cand$text,
                         MoreArgs = list(blacklist_tokens = blacklist))

  # ensure numeric
  num_cols <- c("hits_answer","hits_think","len_norm","len_clip","last_event_norm",
                "first_event_early","stop_early","freq_norm","has_ans_kw","has_think_kw",
                "hit_delta","path_boost_ans","path_boost_think")
  for (cn in num_cols) cand[[cn]] <- as_num(cand[[cn]], 0)
  cand$conflict_reason <- as.integer(cand$conflict_reason)

  # scores (delta is conditional, and reasoning conflict penalizes answer)
  cand$score_st_answer <- ifelse(
    cand$invalid, -9999,
    6*cand$last_event_norm +
      4*cand$hits_answer +
      3*cand$freq_norm +
      2*cand$len_clip +
      2*cand$path_boost_ans +
      4*(cand$hit_delta * cand$has_ans_kw) -
      5*cand$conflict_reason         # ⬅ depress answer if reasoning segment present
  )
  cand$score_st_think <- ifelse(
    cand$invalid, -9999,
    5*cand$first_event_early +
      5*cand$stop_early +
      4*cand$hits_think +
      3*cand$len_clip +
      2*(1 - cand$freq_norm) +
      1*cand$path_boost_think +
      3*(cand$hit_delta * cand$has_think_kw) +
      2*cand$conflict_reason         # ⬅ boost think if reasoning segment present
  )

  # absolute guards (unchanged)
  ok_ans <- (cand$last_event_norm >= 0.80) | ((cand$last_event_norm >= 0.67) & (cand$hits_answer >= 2))
  ok_thk <- (cand$first_event_early == 1 & cand$stop_early == 1) |
    ((cand$hits_think >= 2) & xor(cand$first_event_early == 1, cand$stop_early == 1))
  cand$score_st_answer[!ok_ans & cand$score_st_answer > -9999] <- cand$score_st_answer[!ok_ans & cand$score_st_answer > -9999] - 5
  cand$score_st_think[!ok_thk  & cand$score_st_think  > -9999] <- cand$score_st_think[!ok_thk  & cand$score_st_think  > -9999] - 5

  # probs & picks
  cand$prob_st_answer <- softmax_safe(cand$score_st_answer)
  cand$prob_st_think  <- softmax_safe(cand$score_st_think)
  cand$excerpt <- vapply(cand$text, trim_excerpt, character(1), n = 160)

  pick_idx <- function(probs, thr) { i <- suppressWarnings(which.max(probs)); if (!length(i) || is.na(i) || probs[i] < thr) NA_integer_ else i }
  i_ans <- pick_idx(cand$prob_st_answer, prob_thresh$answer)
  i_thk <- pick_idx(cand$prob_st_think,  prob_thresh$think)
  if (!is.na(i_ans) && !is.na(i_thk) && identical(cand$path[i_ans], cand$path[i_thk])) i_thk <- NA_integer_

  best <- list(
    answer = if (!is.na(i_ans)) list(path = cand$path[i_ans], key = cand$key[i_ans],
                                     text = cand$text[i_ans], prob = cand$prob_st_answer[i_ans],
                                     score = cand$score_st_answer[i_ans]) else NULL,
    think  = if (!is.na(i_thk)) list(path = cand$path[i_thk], key = cand$key[i_thk],
                                     text = cand$text[i_thk], prob = cand$prob_st_think[i_thk],
                                     score = cand$score_st_think[i_thk]) else NULL
  )

  cand$rank_key <- pmax(cand$score_st_answer, cand$score_st_think, na.rm = TRUE)
  cand <- cand[order(-cand$rank_key), ]
  if (nrow(cand) > top_k) cand <- cand[seq_len(top_k), ]

  list(best = best, candidates = cand)
}


# ==============================================================
#
#                     Utility Functions
#
# ==============================================================


#' Count keyword hits by exact segment match (no substrings)
#' @keywords internal
segment_hit_count <- function(segs, vocab) {
  if (!length(segs) || !length(vocab)) return(0L)
  sum(tolower(vocab) %in% segs)
}


#' Extract lowercase dot-level segments from a path/key
#' @keywords internal
extract_segments <- function(path, key) {
  p <- tolower(as.character(path %||% ""))
  k <- tolower(as.character(key  %||% ""))
  segs <- unlist(strsplit(p, "\\.", perl = TRUE), use.names = FALSE)
  segs <- c(segs[nzchar(segs)], if (nzchar(k)) k else NULL)
  unique(segs)
}


#' Reasoning segment flag (any think-ish segment present)
#' @keywords internal
has_reasoning_segment <- function(segs) {
  reason_segs <- c("reasoning", "reasoning_content", "thinking", "thought",
                   "rationale", "explanation", "trace", "analysis", "justification",
                   "cot", "chain_of_thought", "chain-of-thought")
  any(reason_segs %in% segs)
}

#' Hard filter: blacklist, nullish, booleans, numeric-only, too-short
#' Segment-exact blacklist (compares path segments, not substrings).
#'
#' @param path,key,value character scalars
#' @param blacklist_tokens character vector
#' @return logical
#' @export
is_invalid_candidate <- function(path, key, value,
                                 blacklist_tokens = default_keyword_lexicon()$blacklist) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
  segs <- extract_segments(path %||% "", key %||% "")
  # segment-exact intersection (lowercase)
  blk <- tolower(unique(blacklist_tokens))
  if (length(intersect(segs, blk)) > 0) return(TRUE)

  if (is.null(value) || is.na(value)) return(TRUE)
  val <- as.character(value)
  if (!nzchar(val)) return(TRUE)
  if (tolower(val) %in% c("null", "none", "n/a", "undefined", "true", "false")) return(TRUE)
  if (grepl("^[0-9]+$", val)) return(TRUE)
  if (grepl("^[0-9\\.]+$", val)) return(TRUE)
  if (nchar(val) < 3) return(TRUE)
  FALSE
}

#' Strong-signal (delta-like) hit for streaming
#' @param path character
#' @param key character
#' @param strong_tokens character vector
#' @return 0/1 integer
#' @keywords internal
hit_delta_flag <- function(path, key, strong_tokens) {
  hay <- tolower(paste(path, key, sep = " "))
  as.integer(any(vapply(strong_tokens, function(tok) grepl(tok, hay, fixed = TRUE), logical(1))))
}

#' Length clipping function for robust length scoring
#'
#' Maps len_norm into [0,1] with a dead-zone for tiny strings and a cap for very long ones.
#' @param len_norm numeric in [0,1]
#' @return numeric in [0,1]
#' @keywords internal
f_len_clip <- function(len_norm) {
  x <- max(0, min(1, as.numeric(len_norm)))
  if (x < 0.2) return(0)
  if (x > 0.6) return(1)
  (x - 0.2) / 0.4
}

#' Safe softmax
#' @param x numeric vector
#' @return numeric probabilities summing to 1 (or zero vector if all -Inf-like)
#' @keywords internal
softmax_safe <- function(x) {
  if (length(x) == 0) return(numeric())
  x[is.na(x)] <- -9999
  m <- max(x)
  z <- exp(x - m)
  if (!is.finite(sum(z)) || sum(z) == 0) return(rep(0, length(x)))
  z / sum(z)
}
