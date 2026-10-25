#' Inspect One Archived RAW Trial Record
#'
#' Returns the RAW record associated with one result row. The input may be the
#' in-memory result returned with \code{return_raw = TRUE} or the object loaded
#' from a \code{raw_output_path} RDS archive.
#'
#' @param result A data frame containing a one-record-per-row \code{raw}
#'   list-column.
#' @param trial Positive integer selecting the result row.
#'
#' @return The selected RAW record. The value may contain nested lists, data
#'   frames, character strings, numeric or logical vectors, raw bytes, or
#'   \code{NULL}, as preserved by RDS.
#' @export
get_trial_raw <- function(result, trial = 1L) {
  validate_raw_result_object(result)
  trial <- validate_raw_trial_selection(trial, nrow(result))
  result$raw[[trial]]
}

#' Extract Standard Process Metrics from RAW Trial Results
#'
#' Creates one provider-independent summary row per trial from the preserved
#' RAW records. The extractor searches protocol data by field meaning rather
#' than model name. Missing or unsupported values remain \code{NA}; they are
#' never inferred.
#'
#' @param result A data frame containing a one-record-per-row \code{raw}
#'   list-column, including an object returned by \code{readRDS()}.
#'
#' @return A data frame with one row per trial and standardized availability
#'   fields. Provider-specific evidence remains available in \code{result$raw}.
#' @export
extract_process_metrics <- function(result) {
  validate_raw_result_object(result)
  if (!nrow(result)) return(empty_process_metrics_table())

  rows <- lapply(seq_len(nrow(result)), function(index) {
    raw_record <- result$raw[[index]]
    source <- raw_response_metric_source(raw_record)
    logprob_summary <- raw_logprob_summary(source)
    answer_entry <- logprob_summary$first_entry

    parse_error <- raw_find_transport_metadata(raw_record, "parse_error")
    recovery <- raw_find_transport_metadata(raw_record, "parse_recovery")
    usage <- raw_find_first_named(source, "usage")
    reasoning <- raw_find_first_named(usage, "reasoning_tokens")
    input_tokens <- raw_find_first_named(usage, c("prompt_tokens", "input_tokens"))
    output_tokens <- raw_find_first_named(
      usage,
      c("completion_tokens", "output_tokens")
    )
    cached_tokens <- raw_find_first_named(
      usage,
      c("cached_tokens", "cache_read_input_tokens")
    )

    data.frame(
      ResultRow = index,
      TrialKey = raw_result_scalar(result, index, "TrialKey"),
      RequestID = raw_result_scalar(result, index, "RequestID"),
      InputTokens = raw_as_integer(input_tokens),
      OutputTokens = raw_as_integer(output_tokens),
      ReasoningTokens = raw_as_integer(reasoning),
      ReasoningTokensAvailable = !is.na(raw_as_integer(reasoning)),
      CachedTokens = raw_as_integer(cached_tokens),
      FinishReason = raw_as_character(
        raw_find_first_named(source, c("finish_reason", "stop_reason"))
      ),
      AnswerToken = if (is.null(answer_entry)) {
        NA_character_
      } else {
        raw_as_character(answer_entry$token)
      },
      AnswerLogProb = if (is.null(answer_entry) ||
                          is.null(answer_entry$logprob)) {
        NA_real_
      } else {
        as.numeric(answer_entry$logprob[[1L]])
      },
      LogprobsAvailable = logprob_summary$available,
      ReturnedTokenCount = logprob_summary$token_count,
      ParseRecovery = raw_recovery_description(recovery),
      ProcessMetricsStatus = raw_process_metrics_status(
        raw_record,
        parse_error,
        reasoning,
        logprob_summary$available
      ),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

#' Extract Token Probabilities from RAW Trial Results
#'
#' Converts supported token-logprob structures into a long, provider-neutral
#' table. Each returned candidate retains its original log probability;
#' probabilities are computed with \code{exp(logprob)} and are not renormalized
#' over the returned top-k candidates.
#'
#' @param result A data frame containing a one-record-per-row \code{raw}
#'   list-column, including an object returned by \code{readRDS()}.
#' @param trials Optional positive integer vector selecting result rows.
#'
#' @return A long data frame with selected and alternative token candidates.
#'   Unsupported or unrequested log probabilities produce an empty table.
#' @export
extract_token_probabilities <- function(result, trials = NULL) {
  validate_raw_result_object(result)
  if (is.null(trials)) {
    trials <- seq_len(nrow(result))
  } else {
    trials <- validate_raw_trial_selection(trials, nrow(result), multiple = TRUE)
  }

  records <- unlist(lapply(trials, function(index) {
    source <- raw_response_metric_source(result$raw[[index]])
    entries <- collect_token_logprob_entries(source)
    if (!length(entries)) return(list())
    Map(function(entry, position) {
      token_logprob_entry_rows(
        entry = entry,
        result_row = index,
        request_id = raw_result_scalar(result, index, "RequestID"),
        token_position = position
      )
    }, entries, seq_along(entries))
  }), recursive = FALSE)

  if (!length(records)) return(empty_token_probability_table())
  do.call(rbind, records)
}

validate_raw_result_object <- function(result) {
  if (!is.data.frame(result)) {
    stop("`result` must be a data frame returned by a PsyLingLLM experiment.",
         call. = FALSE)
  }
  if (!("raw" %in% names(result)) || !is.list(result$raw)) {
    stop("`result` must contain a `raw` list-column.", call. = FALSE)
  }
  if (length(result$raw) != nrow(result)) {
    stop("RAW records must correspond one-to-one with result rows.",
         call. = FALSE)
  }
  invisible(TRUE)
}

validate_raw_trial_selection <- function(trial, row_count, multiple = FALSE) {
  valid <- is.numeric(trial) && length(trial) >= 1L &&
    !anyNA(trial) && all(is.finite(trial)) &&
    all(trial == as.integer(trial)) &&
    all(trial >= 1L & trial <= row_count)
  if (!valid || (!isTRUE(multiple) && length(trial) != 1L)) {
    stop("`trial` must select valid positive result-row indices.", call. = FALSE)
  }
  as.integer(trial)
}

raw_result_scalar <- function(result, index, name) {
  if (!(name %in% names(result))) return(NA_character_)
  value <- result[[name]][[index]]
  if (!length(value) || is.na(value[[1L]])) NA_character_ else as.character(value[[1L]])
}

raw_find_first_named <- function(value, names_to_find) {
  if (!is.list(value)) return(NULL)
  value_names <- names(value)
  if (!is.null(value_names)) {
    for (name in names_to_find) {
      matched <- which(value_names == name)
      if (length(matched)) {
        matched_value <- value[[matched[[1L]]]]
        if (!is.null(matched_value)) return(matched_value)
      }
    }
  }
  for (child in value) {
    found <- raw_find_first_named(child, names_to_find)
    if (!is.null(found)) return(found)
  }
  NULL
}

raw_response_metric_source <- function(raw_record) {
  if (is.null(raw_record)) return(NULL)
  response <- if (is.list(raw_record) && !is.null(raw_record$response)) {
    raw_record$response
  } else {
    raw_record
  }
  parsed <- raw_find_first_named(response, "parsed")
  if (is.null(parsed)) response else parsed
}

raw_find_transport_metadata <- function(raw_record, name) {
  if (is.null(raw_record)) return(NULL)
  response <- if (is.list(raw_record) && !is.null(raw_record$response)) {
    raw_record$response
  } else {
    raw_record
  }
  raw_find_first_named_pruned(
    response,
    name,
    skip_names = c(
      "parsed", "raw_body", "text", "frames", "events",
      "request_payload", "legacy"
    )
  )
}

raw_find_first_named_pruned <- function(value, names_to_find, skip_names) {
  if (!is.list(value)) return(NULL)
  value_names <- names(value)
  if (!is.null(value_names)) {
    for (name in names_to_find) {
      matched <- which(value_names == name)
      if (length(matched)) {
        matched_value <- value[[matched[[1L]]]]
        if (!is.null(matched_value)) return(matched_value)
      }
    }
  }
  for (index in seq_along(value)) {
    child_name <- if (is.null(value_names)) NA_character_ else value_names[[index]]
    if (!is.na(child_name) && child_name %in% skip_names) next
    found <- raw_find_first_named_pruned(
      value[[index]],
      names_to_find,
      skip_names
    )
    if (!is.null(found)) return(found)
  }
  NULL
}

raw_logprob_summary <- function(source) {
  logprobs <- raw_find_first_named(source, "logprobs")
  empty <- list(
    available = FALSE,
    token_count = 0L,
    first_entry = NULL
  )
  if (is.null(logprobs) || !is.list(logprobs)) return(empty)

  is_entry <- function(value) {
    is.list(value) && !is.null(value$token) && !is.null(value$logprob)
  }
  if (is_entry(logprobs)) {
    return(list(available = TRUE, token_count = 1L, first_entry = logprobs))
  }

  for (container_name in c("content", "tokens")) {
    container <- logprobs[[container_name]]
    if (!is.list(container) || !length(container)) next
    valid <- vapply(container, is_entry, logical(1))
    if (any(valid)) {
      first <- which(valid)[[1L]]
      return(list(
        available = TRUE,
        token_count = sum(valid),
        first_entry = container[[first]]
      ))
    }
  }

  fallback <- raw_find_first_token_logprob(logprobs)
  if (is.null(fallback)) empty else list(
    available = TRUE,
    token_count = NA_integer_,
    first_entry = fallback
  )
}

raw_find_first_token_logprob <- function(value) {
  if (!is.list(value)) return(NULL)
  if (!is.null(value$token) && !is.null(value$logprob)) return(value)
  for (child in value) {
    found <- raw_find_first_token_logprob(child)
    if (!is.null(found)) return(found)
  }
  NULL
}

raw_as_integer <- function(value) {
  if (is.null(value) || !length(value)) return(NA_integer_)
  converted <- suppressWarnings(as.integer(value[[1L]]))
  if (!length(converted) || is.na(converted)) NA_integer_ else converted
}

raw_as_character <- function(value) {
  if (is.null(value) || !length(value) || is.na(value[[1L]])) {
    return(NA_character_)
  }
  as.character(value[[1L]])
}

raw_recovery_description <- function(recovery) {
  if (is.null(recovery)) return(NA_character_)
  if (is.list(recovery) && !is.null(recovery$method)) {
    return(as.character(recovery$method[[1L]]))
  }
  if (is.character(recovery) && length(recovery)) return(recovery[[1L]])
  "recorded"
}

raw_process_metrics_status <- function(raw_record, parse_error, reasoning,
                                       token_rows) {
  if (is.null(raw_record)) return("RAW_UNAVAILABLE")
  if (!is.null(parse_error)) return("PARSE_ERROR")
  if (!is.null(reasoning) || any(token_rows)) return("OK")
  "METRICS_UNAVAILABLE"
}

collect_token_logprob_entries <- function(value, path = "$", in_logprobs = FALSE) {
  if (!is.list(value)) return(list())
  value_names <- names(value)
  current_is_entry <- in_logprobs &&
    !is.null(value$token) && !is.null(value$logprob)
  if (current_is_entry) return(list(list(value = value, path = path)))

  children <- lapply(seq_along(value), function(index) {
    name <- if (!is.null(value_names) &&
                !is.na(value_names[[index]]) &&
                nzchar(value_names[[index]])) {
      value_names[[index]]
    } else {
      paste0("[", index, "]")
    }
    child_path <- if (startsWith(name, "[")) {
      paste0(path, name)
    } else {
      paste0(path, "$", name)
    }
    child_in_logprobs <- in_logprobs || name %in% c("logprobs", "top_logprobs")
    collect_token_logprob_entries(
      value[[index]],
      child_path,
      child_in_logprobs
    )
  })
  unlist(children, recursive = FALSE)
}

token_logprob_entry_rows <- function(entry, result_row, request_id,
                                     token_position) {
  selected <- entry$value
  alternatives <- selected$top_logprobs
  selected$top_logprobs <- NULL
  if (is.null(alternatives) || !is.list(alternatives)) alternatives <- list()

  selected_token <- raw_as_character(selected$token)
  candidate_tokens <- vapply(alternatives, function(candidate) {
    raw_as_character(candidate$token)
  }, character(1))
  selected_matches <- which(!is.na(candidate_tokens) & candidate_tokens == selected_token)
  selected_flags <- rep(FALSE, length(alternatives))
  if (length(selected_matches)) selected_flags[selected_matches[[1L]]] <- TRUE

  candidates <- alternatives
  ranks <- seq_along(alternatives)
  if (!length(selected_matches)) {
    candidates <- c(list(selected), candidates)
    selected_flags <- c(TRUE, selected_flags)
    ranks <- c(0L, ranks)
  }
  if (!length(candidates)) return(empty_token_probability_table())

  channel <- if (grepl("reasoning", entry$path, ignore.case = TRUE)) {
    "reasoning"
  } else {
    "answer"
  }
  data.frame(
    ResultRow = rep(result_row, length(candidates)),
    RequestID = rep(request_id, length(candidates)),
    Channel = rep(channel, length(candidates)),
    TokenPosition = rep(token_position, length(candidates)),
    CandidateRank = as.integer(ranks),
    Selected = selected_flags,
    Token = vapply(candidates, function(candidate) {
      raw_as_character(candidate$token)
    }, character(1)),
    TokenBytes = vapply(candidates, function(candidate) {
      raw_token_bytes(candidate$bytes)
    }, character(1)),
    LogProb = vapply(candidates, function(candidate) {
      value <- candidate$logprob
      if (is.null(value) || !length(value)) NA_real_ else as.numeric(value[[1L]])
    }, numeric(1)),
    Probability = vapply(candidates, function(candidate) {
      value <- candidate$logprob
      if (is.null(value) || !length(value)) return(NA_real_)
      exp(as.numeric(value[[1L]]))
    }, numeric(1)),
    SourcePath = rep(entry$path, length(candidates)),
    stringsAsFactors = FALSE
  )
}

raw_token_bytes <- function(value) {
  if (is.null(value) || !length(value)) return(NA_character_)
  if (is.raw(value)) return(paste(as.integer(value), collapse = " "))
  converted <- suppressWarnings(as.integer(unlist(value, use.names = FALSE)))
  if (!length(converted) || anyNA(converted)) return(NA_character_)
  paste(converted, collapse = " ")
}

empty_process_metrics_table <- function() {
  data.frame(
    ResultRow = integer(),
    TrialKey = character(),
    RequestID = character(),
    InputTokens = integer(),
    OutputTokens = integer(),
    ReasoningTokens = integer(),
    ReasoningTokensAvailable = logical(),
    CachedTokens = integer(),
    FinishReason = character(),
    AnswerToken = character(),
    AnswerLogProb = numeric(),
    LogprobsAvailable = logical(),
    ReturnedTokenCount = integer(),
    ParseRecovery = character(),
    ProcessMetricsStatus = character(),
    stringsAsFactors = FALSE
  )
}

empty_token_probability_table <- function() {
  data.frame(
    ResultRow = integer(),
    RequestID = character(),
    Channel = character(),
    TokenPosition = integer(),
    CandidateRank = integer(),
    Selected = logical(),
    Token = character(),
    TokenBytes = character(),
    LogProb = numeric(),
    Probability = numeric(),
    SourcePath = character(),
    stringsAsFactors = FALSE
  )
}
