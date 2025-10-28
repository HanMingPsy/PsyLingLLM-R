#' Run LLM Conversation Experiment with Feedback (no injected rows in replace_next)
#'
#' Multi-turn conversations identified by `ConversationId` and ordered by `Turn`.
#' Rolling history (seed + past turns) is passed to `llm_caller()` via `assistant_content`.
#'
#' Feedback semantics:
#' - apply_mode = "replace_next": DO NOT insert extra rows; simply overwrite the
#'   next planned row's `TrialPrompt` in the same conversation.
#' - apply_mode = "insert_dynamic": if under per-conversation cap, append a new
#'   executable row (next turn) using `next_prompt`.
#'
#' All request assembly (URL/headers/body/messages/defaults) is registry-driven
#' by `llm_caller()`; this function never mutates headers.
#'
#' @param model_key Character(1).
#' @param generation_interface Character(1). Default "chat".
#' @param api_key Character(1). Provider API key.
#' @param api_url Optional character(1). Overrides registry default URL; required for non-official providers.
#' @param data data.frame/tibble with ConversationId, Turn, Material; optional TrialPrompt.
#' @param trial_prompt Optional character(1). Global prefix when row TrialPrompt is missing.
#' @param system_content Optional character(1) or NULL. If NULL, uses registry `default_system` when available.
#' @param assistant_content Optional static few-shot seed: character vector or a list of message objects
#'   (`list(role=..., content=...)`). These appear before rolling history and are preserved as-is.
#' @param optionals Optional named list. NULL → use registry typed defaults; list → send only user keys; missing → use defaults.
#' @param role_mapping Optional mapping for local labels; not forced into `llm_caller()` unless supplied.
#' @param history_mode "all" or "last". Default "all".
#' @param max_history_turns Integer(1) or Inf. Only for "all". Each turn contributes 2 messages.
#' @param max_turns Integer(1) or NULL. Per-conv cap for insert_dynamic. Ignored for replace_next.
#' @param stream Logical(1) or NULL. NULL uses registry default; otherwise force streaming/non-streaming.
#' @param timeout Integer(1). Per-request timeout seconds.
#' @param repeats Integer(1). Conversation block repetitions before randomization.
#' @param random Logical(1). Shuffle conversation order (Turn order preserved inside).
#' @param apply_mode "replace_next" or "insert_dynamic".
#' @param feedback_fn function(response, row, context) -> list(name, next_prompt, meta).
#' @param delay Numeric(1). Seconds between turns.
#' @param output_path Character or NULL. Where to save results/logs.
#' @param overwrite Logical(1). Overwrite outputs.
#' @param return_raw Logical(1). Include raw request/response.
#' @importFrom stats setNames
#'
#' @return Tibble with PsyLingLLM schema per executed turn.
#' @export
conversation_experiment_with_feedback <- function(
    model_key,
    generation_interface = "chat",
    api_key,
    api_url = NULL,
    data,
    trial_prompt = NULL,
    system_content = NULL,
    assistant_content = NULL,
    optionals = NULL,
    role_mapping = NULL,
    history_mode = c("all", "last"),
    max_history_turns = Inf,
    max_turns = NULL,
    stream = NULL,
    timeout = getOption("psylingllm.llm_timeout_sec", 120L),
    repeats = 1,
    random = FALSE,
    apply_mode = c("replace_next", "insert_dynamic"),
    feedback_fn,
    delay = 0,
    output_path = NULL,
    overwrite = TRUE,
    return_raw = FALSE
) {
  history_mode <- match.arg(history_mode)
  apply_mode <- match.arg(apply_mode)

  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
  safe_chr <- function(x) if (is.null(x) || length(x) == 0 || all(is.na(x))) NA_character_ else as.character(x)[1]
  safe_num <- function(x) if (is.null(x) || length(x) == 0 || all(is.na(x))) NA_real_ else as.numeric(x)[1]
  safe_int <- function(x) if (is.null(x) || length(x) == 0 || all(is.na(x))) NA_integer_ else as.integer(x)[1]
  nz_chr   <- function(x) is.character(x) && length(x) == 1 && nzchar(x)

  # ---- Standardize base rows (no repeats/random yet) ------------------------
  data <- generate_llm_experiment_list(
    data         = data,
    trial_prompt = trial_prompt %||% "",
    repeats      = 1L,
    random       = FALSE
  )

  # Ensure ConversationId / Turn
  if (!("ConversationId" %in% names(data))) data$ConversationId <- "C1"
  data$ConversationId <- as.character(data$ConversationId)

  if (!("Turn" %in% names(data))) {
    data <- dplyr::group_by(data, ConversationId)
    data <- dplyr::mutate(data, Turn = dplyr::row_number())
    data <- dplyr::ungroup(data)
  }
  if (!is.numeric(data$Turn)) stop("`Turn` must be numeric/integer for ordering.")

  # Repeats: duplicate conv blocks
  if (isTRUE(repeats > 1L)) {
    base <- data
    reps <- lapply(seq_len(as.integer(repeats)), function(k) {
      df <- base
      df$ConversationId <- paste0(df$ConversationId, "_r", k)
      df <- dplyr::group_by(df, ConversationId)
      df <- dplyr::mutate(df, Turn = dplyr::row_number())
      dplyr::ungroup(df)
    })
    data <- dplyr::bind_rows(reps)
  }

  # Randomize by conversation (keep Turn order inside)
  if (isTRUE(random)) {
    conv_ids <- unique(data$ConversationId)
    conv_ids <- sample(conv_ids, length(conv_ids))
    data$..block.. <- match(data$ConversationId, conv_ids)
    data <- dplyr::arrange(data, ..block.., Turn)
    data$..block.. <- NULL
  } else {
    data <- dplyr::arrange(data, ConversationId, Turn)
  }
  data <- tibble::as_tibble(data)

  # Local role labels for logging only
  reg_entry <- tryCatch(get_registry_entry(model_key, generation_interface), error = function(e) NULL)
  reg_roles <- if (!is.null(reg_entry)) (reg_entry$input$role_mapping %||% list()) else list()
  local_roles <- list(
    system    = (role_mapping$system    %||% reg_roles$system    %||% "system"),
    user      = (role_mapping$user      %||% reg_roles$user      %||% "user"),
    assistant = (role_mapping$assistant %||% reg_roles$assistant %||% "assistant")
  )

  # Validate config
  validate_experiment_config(
    api_key = api_key,
    api_url = api_url,
    model = model_key,
    data = data,
    required_cols = c("Material"),
    generation_interface = generation_interface
  )

  # Output/log paths
  paths <- resolve_output_and_log(output_path, model_key)
  result_file <- paths$result_file
  logfile <- paths$log_file

  # Ensure result columns exist
  add_if_missing <- function(df, nm, val) { if (!(nm %in% names(df))) df[[nm]] <- val; df }
  data <- add_if_missing(data, "TrialPrompt", NA_character_)
  data$Response <- NA_character_
  data$Think <- NA_character_
  data$ModelName <- model_key
  data$AssistantContext <- NA_character_
  data$HistoryMode <- history_mode
  data$HistoryUsedMsgs <- NA_integer_
  data$TotalResponseTime <- NA_real_
  data$FirstTokenLatency <- NA_real_
  data$PromptTokens <- NA_integer_
  data$CompletionTokens <- NA_integer_
  data$TrialStatus <- NA_character_
  data$Streaming <- NA
  data$Timestamp <- NA_character_
  data$RequestID <- NA_character_
  data$FeedbackDecision <- NA_character_
  data$FeedbackMeta <- NA_character_
  data$RequestMessages <- NA_character_

  # Log start
  write_experiment_log(
    logfile,
    stage = "start",
    model = model_key,
    streaming = isTRUE(stream),
    total_runs = nrow(data),
    output_path = result_file
  )

  # Histories & budgets
  conv_ids <- unique(as.character(data$ConversationId))
  histories <- setNames(vector("list", length(conv_ids)), conv_ids)
  for (cid in names(histories)) histories[[cid]] <- assistant_content %||% list()

  planned_counts <- table(data$ConversationId)

  if (identical(apply_mode, "insert_dynamic")) {
    if (!is.null(max_turns)) {
      per_conv_cap <- setNames(rep(as.integer(max_turns), length(conv_ids)), conv_ids)
      steps_target <- length(conv_ids) * as.integer(max_turns)
    } else {
      per_conv_cap <- setNames(rep(Inf, length(conv_ids)), conv_ids)
      steps_target <- sum(as.integer(planned_counts))  # grows if we insert
    }
  } else { # replace_next
    per_conv_cap <- as.integer(planned_counts)
    names(per_conv_cap) <- names(planned_counts)
    steps_target <- sum(as.integer(planned_counts))
  }

  start_time <- Sys.time()
  bar_width <- 40
  update_progress_bar(0, steps_target, start_time, bar_width, model_key)

  executed <- 0L
  exec_count_by_cid <- setNames(integer(length(conv_ids)), conv_ids)

  # Main loop
  i <- 1L
  while (i <= nrow(data)) {
    cid <- as.character(data$ConversationId[i])

    # Cap: if this conversation met its cap, skip this row
    if (exec_count_by_cid[[cid]] >= per_conv_cap[[cid]]) {
      i <- i + 1L
      next
    }

    t0 <- Sys.time()

    # Row/global prompt
    row_tp <- safe_chr(data$TrialPrompt[i])
    eff_prompt <- if (nz_chr(row_tp)) row_tp else trial_prompt
    hist_use <- histories[[cid]]

    # Current user message (prefix + material)
    user_mat <- safe_chr(data$Material[i])
    sent_user <- paste0(eff_prompt %||% "", if (!is.null(eff_prompt)) "\n\n" else "", user_mat)

    # Audit messages
    req_msgs_local <- c(
      if (length(hist_use)) hist_use else list(),
      list(list(role = local_roles$user, content = sent_user))
    )
    data$RequestMessages[i] <- tryCatch(
      jsonlite::toJSON(req_msgs_local, auto_unbox = TRUE, null = "null"),
      error = function(e) NA_character_
    )

    # Call LLM
    call_args <- list(
      model_key = model_key,
      generation_interface = generation_interface,
      api_key = api_key,
      api_url = api_url,
      trial_prompt = NULL,
      material = sent_user,
      system_content = system_content,
      assistant_content = hist_use,
      role_mapping = role_mapping,
      stream = stream,
      timeout = timeout,
      return_raw = return_raw
    )
    if (!missing(optionals)) call_args$optionals <- optionals

    llm_resp <- tryCatch(
      do.call(llm_caller, call_args),
      error = function(e) handle_llm_error(run_id = i, err = e, category = "network")
    )

    t1 <- Sys.time()
    executed <- executed + 1L
    exec_count_by_cid[[cid]] <- exec_count_by_cid[[cid]] + 1L

    # Dynamic progress growth (only if uncapped insert_dynamic)
    if (identical(apply_mode, "insert_dynamic") && is.infinite(per_conv_cap[[cid]]) && executed > steps_target) {
      steps_target <- executed
    }

    status_num <- suppressWarnings(as.integer(llm_resp$status %||% NA_integer_))
    err_msg <- safe_chr(llm_resp$error)

    # Timeout
    if (!is.na(status_num) && status_num == 599L) {
      data$Response[i] <- NA_character_
      data$AssistantContext[i] <- NA_character_
      data$HistoryMode[i] <- history_mode
      data$HistoryUsedMsgs[i] <- length(hist_use)
      data$Think[i] <- NA_character_
      data$TotalResponseTime[i] <- as.numeric(difftime(t1, t0, units = "secs"))
      data$FirstTokenLatency[i] <- NA_real_
      data$PromptTokens[i] <- NA_integer_
      data$CompletionTokens[i] <- NA_integer_
      data$TrialStatus[i] <- "TIMEOUT"
      data$Streaming[i] <- llm_resp$streaming %||% isTRUE(stream)
      data$Timestamp[i] <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
      data$RequestID[i] <- NA_character_
      data$FeedbackDecision[i] <- NA_character_
      data$FeedbackMeta[i] <- NA_character_

      write_experiment_log(
        logfile, stage = "warning", run_id = i,
        msg = sprintf("Conversation %s turn %s timeout (status=599): %s",
                      cid, safe_chr(data$Turn[i]), err_msg)
      )
      if (delay > 0) Sys.sleep(delay)
      update_progress_bar(min(executed, steps_target), steps_target, start_time, bar_width, model_key)
      i <- i + 1L
      next
    }

    # HTTP error
    if (!is.na(status_num) && status_num >= 400L) {
      data$Response[i] <- NA_character_
      data$AssistantContext[i] <- NA_character_
      data$HistoryMode[i] <- history_mode
      data$HistoryUsedMsgs[i] <- length(hist_use)
      data$Think[i] <- NA_character_
      data$TotalResponseTime[i] <- as.numeric(difftime(t1, t0, units = "secs"))
      data$FirstTokenLatency[i] <- NA_real_
      data$PromptTokens[i] <- NA_integer_
      data$CompletionTokens[i] <- NA_integer_
      data$TrialStatus[i] <- "ERROR"
      data$Streaming[i] <- llm_resp$streaming %||% isTRUE(stream)
      data$Timestamp[i] <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
      data$RequestID[i] <- NA_character_
      data$FeedbackDecision[i] <- NA_character_
      data$FeedbackMeta[i] <- NA_character_

      write_experiment_log(
        logfile, stage = "error", run_id = i,
        msg = sprintf("Conversation %s turn %s HTTP %s: %s",
                      cid, safe_chr(data$Turn[i]), status_num, err_msg)
      )
      if (delay > 0) Sys.sleep(delay)
      update_progress_bar(min(executed, steps_target), steps_target, start_time, bar_width, model_key)
      i <- i + 1L
      next
    }

    # Success
    answer <- safe_chr(llm_resp$answer)
    data$Response[i] <- answer
    data$Think[i] <- safe_chr(llm_resp$thinking)

    hist_json <- tryCatch(
      jsonlite::toJSON(hist_use, auto_unbox = TRUE, null = "null"),
      error = function(e) NA_character_
    )
    data$AssistantContext[i] <- safe_chr(hist_json)
    data$HistoryMode[i] <- history_mode
    data$HistoryUsedMsgs[i] <- length(hist_use)
    data$TotalResponseTime[i] <- as.numeric(difftime(t1, t0, units = "secs"))

    ft <- llm_resp$first_token_latency
    data$FirstTokenLatency[i] <- safe_num(ft)
    ptoks <- llm_resp$usage$prompt
    ctoks <- llm_resp$usage$completion
    data$PromptTokens[i] <- safe_int(ptoks)
    data$CompletionTokens[i] <- safe_int(ctoks)

    data$TrialStatus[i] <- llm_resp$TrialStatus %||% "SUCCESS"
    data$Streaming[i] <- llm_resp$streaming %||% isTRUE(stream)
    data$Timestamp[i] <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    data$RequestID[i] <- safe_chr(llm_resp$usage$id)

    # Update rolling history
    if (identical(history_mode, "last")) {
      histories[[cid]] <- list(
        list(role = local_roles$user,      content = sent_user),
        list(role = local_roles$assistant, content = answer)
      )
    } else {
      histories[[cid]] <- c(
        histories[[cid]],
        list(list(role = local_roles$user,      content = sent_user)),
        list(list(role = local_roles$assistant, content = answer))
      )
      if (!is.null(max_history_turns) && length(histories[[cid]]) > max_history_turns * 2) {
        histories[[cid]] <- utils::tail(histories[[cid]], max_history_turns * 2)
      }
    }

    # Feedback
    fb <- NULL
    if (is.function(feedback_fn)) {
      ctx <- list(
        conversation_id = cid,
        turn            = safe_int(data$Turn[i]),
        history_size    = length(hist_use),
        last_answer     = answer
      )
      fb <- tryCatch(feedback_fn(answer, data[i, , drop = FALSE], ctx),
                     error = function(e) { warning("feedback_fn error: ", e$message); NULL })
    }
    data$FeedbackDecision[i] <- safe_chr(fb$name)
    data$FeedbackMeta[i] <- if (!is.null(fb$meta)) {
      safe_chr(tryCatch(jsonlite::toJSON(fb$meta, auto_unbox = TRUE, null = "null"),
                        error = function(e) NA_character_))
    } else NA_character_

    if (!is.null(fb) && nz_chr(fb$next_prompt)) {
      if (identical(apply_mode, "replace_next")) {
        # Overwrite the next planned row (same conversation, next index) — no row insertion.
        same_conv <- which(as.character(data$ConversationId) == cid)
        next_candidates <- same_conv[same_conv > i]
        if (length(next_candidates)) {
          nxt <- next_candidates[1]
          data$TrialPrompt[nxt] <- fb$next_prompt
        }
      } else { # insert_dynamic
        if (exec_count_by_cid[[cid]] < per_conv_cap[[cid]]) {
          next_turn <- safe_int(data$Turn[i]) + 1L
          new_row <- data[i, , drop = FALSE]
          new_row$Turn <- next_turn
          new_row$Material <- ""
          new_row$TrialPrompt <- fb$next_prompt

          wipe <- c("Response","Think","AssistantContext","HistoryMode","HistoryUsedMsgs",
                    "TotalResponseTime","FirstTokenLatency","PromptTokens","CompletionTokens",
                    "TrialStatus","Streaming","Timestamp","RequestID",
                    "FeedbackDecision","FeedbackMeta","RequestMessages")
          new_row[wipe] <- NA

          top <- data[1:i, , drop = FALSE]
          bottom <- if (i < nrow(data)) data[(i + 1):nrow(data), , drop = FALSE] else data[0, , drop = FALSE]
          data <- rbind(top, new_row, bottom)

          # Reindex subsequent turns in this conversation
          sel <- which(as.character(data$ConversationId) == cid &
                         as.numeric(data$Turn) >= next_turn &
                         seq_len(nrow(data)) != (i + 1L))
          if (length(sel)) data$Turn[sel] <- as.numeric(data$Turn[sel]) + 1

          if (is.infinite(per_conv_cap[[cid]])) steps_target <- steps_target + 1L
        }
      }
    }

    if (delay > 0) Sys.sleep(delay)
    update_progress_bar(min(executed, steps_target), steps_target, start_time, bar_width, model_key)
    i <- i + 1L
  }

  # Finalize & save
  update_progress_bar(steps_target, steps_target, start_time, bar_width, model_key)
  cat("\n")

  save_experiment_results(
    data,
    output_path = result_file,
    model = model_key,
    overwrite = overwrite,
    auto_naming = FALSE
  )

  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  write_experiment_log(
    logfile,
    stage = "end",
    total_runs = nrow(data),
    success = sum(data$TrialStatus == "SUCCESS", na.rm = TRUE),
    failed  = sum(data$TrialStatus %in% c("ERROR","TIMEOUT"), na.rm = TRUE),
    elapsed = elapsed,
    output_path = result_file
  )

  invisible(data)
}
utils::globalVariables(c("Turn", "ConversationId", "..block.."))
