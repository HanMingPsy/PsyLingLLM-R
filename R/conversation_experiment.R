#' Run Multi-turn Conversation Experiment (assistant-native, registry-driven)
#'
#' Executes multi-turn conversations where each conversation is identified by
#' `ConversationId` and ordered by `Turn`. Running history is maintained as a
#' list of structured role messages (`list(role=..., content=...)`) and passed
#' to \code{llm_caller()} via `assistant_content`. This mirrors web chat:
#' `(system) + seed messages + history + current user -> assistant reply`.
#'
#' Request assembly (URL, headers, body/messages, defaults) is driven entirely
#' by the registry via \code{llm_caller()} — this function never mutates headers.
#'
#' Required columns in `data`:
#' - `ConversationId` (character/factor)
#' - `Turn` (integer/numeric)
#' - `Material` (character)
#'
#' Optional:
#' - `TrialPrompt` (row-level); used when present, otherwise `trial_prompt`.
#'
#' History policy:
#' - `history_mode = "all" | "last"` (default `"all"`).
#'   If `"all"`, you can cap with `max_history_turns` (number of past turns; each turn adds 2 messages).
#'
#' Errors / timeouts:
#' - Timeout inside \code{llm_caller()} → `status = 599` ⇒ `TrialStatus = "TIMEOUT"` (continues).
#' - HTTP error (`status >= 400`) ⇒ `TrialStatus = "ERROR"` (continues).
#'
#' @param model_key Character(1). Registry key (e.g., "deepseek-chat" or "deepseek-chat@proxy").
#' @param generation_interface Character(1). Interface name; default "chat".
#' @param api_key Character(1). Provider API key.
#' @param api_url Optional character(1). Overrides registry default URL; required for non-official providers.
#' @param data data.frame/tibble with ConversationId, Turn, Material; optional TrialPrompt.
#' @param trial_prompt Optional character(1). Global prompt prefix (if row TrialPrompt is missing).
#' @param system_content Optional character(1) or NULL. If NULL, registry `default_system` is used when available.
#' @param assistant_content Optional static few-shot seed: character vector or a list of message objects
#'   (`list(role=..., content=...)`). These appear before rolling history and are preserved as-is.
#' @param optionals Optional named list. NULL → use registry typed defaults; list → send only user keys; missing → use defaults.
#' @param role_mapping Optional mapping of roles. If absent, we only use registry mapping for **local labeling**,
#'   and we do **not** pass a role map to \code{llm_caller()} (no forcing).
#' @param history_mode One of `"all"`, `"last"`. Default `"all"`.
#' @param max_history_turns Integer(1) or Inf. Only for `history_mode="all"`. Each turn = 2 messages (user+assistant).
#' @param stream Logical(1) or NULL. NULL uses registry default; otherwise force streaming/non-streaming.
#' @param timeout Integer(1). Per-request timeout in seconds.
#' @param random Logical(1). If TRUE, shuffle conversation order while preserving ascending Turn within each conversation.
#' @param repeats Integer(1). Number of repetitions per base conversation. Typically 1 in feedback loops; each run can dynamically add more trials.
#' @param delay Numeric(1). Delay (seconds) between turns.
#' @param output_path Character or NULL. Where to save results/logs.
#' @param overwrite Logical(1). Overwrite existing outputs.
#' @param return_raw Logical(1). Include raw request/response for debugging.
#' @importFrom stats setNames

#'
#' @return A data.frame/tibble with PsyLingLLM schema columns per turn:
#'   Response, Think, ModelName, TotalResponseTime, FirstTokenLatency (if present),
#'   PromptTokens, CompletionTokens, TrialStatus, Streaming, Timestamp, RequestID,
#'   plus HistoryMode and HistoryUsedMsgs.
#' @export
conversation_experiment <- function(
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
    stream = NULL,
    timeout = getOption("psylingllm.llm_timeout_sec", 120L),
    random = FALSE,
    repeats = 1,
    delay = 0,
    output_path = NULL,
    overwrite = TRUE,
    return_raw = FALSE
) {
  history_mode <- match.arg(history_mode)
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
  safe_chr <- function(x) if (is.null(x) || length(x) == 0 || all(is.na(x))) NA_character_ else as.character(x)[1]
  safe_num <- function(x) if (is.null(x) || length(x) == 0 || all(is.na(x))) NA_real_ else as.numeric(x)[1]
  safe_int <- function(x) if (is.null(x) || length(x) == 0 || all(is.na(x))) NA_integer_ else as.integer(x)[1]
  nz_chr   <- function(x) is.character(x) && length(x) == 1 && nzchar(x)

  # ---- Expand trials via unified helper (row standardization; no random here) ----
  data <- generate_llm_experiment_list(
    data         = data,
    trial_prompt = trial_prompt %||% "",
    repeats      = 1L,     # <- do NOT repeat rows here; we'll repeat conversations below
    random       = FALSE
  )

  # ---- Synthesize/validate conversation columns ----
  if (!("ConversationId" %in% names(data))) data$ConversationId <- "C1"
  data$ConversationId <- as.character(data$ConversationId)

  if (!("Turn" %in% names(data))) {
    data <- dplyr::group_by(data, ConversationId)
    data <- dplyr::mutate(data, Turn = dplyr::row_number())
    data <- dplyr::ungroup(data)
  }
  if (!is.numeric(data$Turn)) {
    stop("`Turn` must be numeric/integer for ordering.")
  }

  # ---- Conversation-level repeats: duplicate each ConversationId block ----
  if (isTRUE(repeats > 1L)) {
    base <- data
    reps <- lapply(seq_len(as.integer(repeats)), function(k) {
      df <- base
      df$ConversationId <- paste0(df$ConversationId, "_r", k)
      df <- dplyr::group_by(df, ConversationId)
      df <- dplyr::mutate(df, Turn = dplyr::row_number())  # reindex turns within each replicate
      dplyr::ungroup(df)
    })
    data <- dplyr::bind_rows(reps)
  }

  # ---- Conversation-aware ordering (optional randomization) ----
  if (isTRUE(random)) {
    conv_ids <- unique(data$ConversationId)
    conv_ids <- sample(conv_ids, length(conv_ids))     # shuffle conversation blocks
    data$..block.. <- match(data$ConversationId, conv_ids)
    data <- dplyr::arrange(data, ..block.., Turn)
    data$..block.. <- NULL
  } else {
    data <- dplyr::arrange(data, ConversationId, Turn)
  }
  data <- tibble::as_tibble(data)


  # ---- Resolve roles for LOCAL labeling only (do not force into llm_caller) ----
  reg_entry <- tryCatch(get_registry_entry(model_key, generation_interface),
                        error = function(e) NULL)
  reg_roles <- if (!is.null(reg_entry)) (reg_entry$input$role_mapping %||% list()) else list()
  local_roles <- list(
    system    = (role_mapping$system    %||% reg_roles$system    %||% "system"),
    user      = (role_mapping$user      %||% reg_roles$user      %||% "user"),
    assistant = (role_mapping$assistant %||% reg_roles$assistant %||% "assistant")
  )
  # We pass user-supplied role_mapping through; if NULL, we pass NULL (no forcing).

  # ---- Validate config ----
  validate_experiment_config(
    api_key = api_key,
    api_url = api_url,
    model = model_key,
    data = data,
    required_cols = c("Material"),
    generation_interface = generation_interface
    # if your validate_experiment_config supports registry=..., you can add:
    # , registry = load_registry()
  )

  # ---- Output/log paths ----
  paths <- resolve_output_and_log(output_path, model_key)
  result_file <- paths$result_file
  logfile <- paths$log_file

  # ---- Initialize schema fields ----
  data$Response <- NA_character_
  data$Think <- NA_character_
  data$ModelName <- model_key
  data$AssistantContext <- NA_character_
  data$HistoryMode <- history_mode
  data$TotalResponseTime <- NA_real_
  data$FirstTokenLatency <- NA_real_
  data$PromptTokens <- NA_integer_
  data$CompletionTokens <- NA_integer_
  data$TrialStatus <- NA_character_
  data$Streaming <- NA
  data$Timestamp <- NA_character_
  data$RequestID <- NA_character_
  data$HistoryUsedMsgs <- NA_integer_

  # ---- Log start ----
  write_experiment_log(
    logfile,
    stage = "start",
    model = model_key,
    streaming = isTRUE(stream),
    total_runs = nrow(data),
    output_path = result_file
  )

  # per-conversation rolling message history (structured role+content)
  conv_ids <- unique(as.character(data$ConversationId))
  histories <- setNames(vector("list", length(conv_ids)), conv_ids)
  for (cid in names(histories)) histories[[cid]] <- assistant_content %||% list()

  # ---- Progress bar ----
  start_time <- Sys.time()
  bar_width <- 40
  update_progress_bar(0, nrow(data), start_time, bar_width, model_key)

  # ---- Iterate turns ----
  for (ri in seq_len(nrow(data))) {
    t0 <- Sys.time()
    cid <- as.character(data$ConversationId[ri])

    # Row/global prompt
    row_tp <- if ("TrialPrompt" %in% names(data)) safe_chr(data$TrialPrompt[ri]) else NA_character_
    eff_prompt <- if (nz_chr(row_tp)) row_tp else trial_prompt

    hist_use  <- histories[[cid]]

    # Current user content = (trial_prompt prefix if any) + material
    user_mat <- safe_chr(data$Material[ri])
    sent_user <- paste0(eff_prompt %||% "", if (!is.null(eff_prompt)) "\n\n" else "", user_mat)

    # ---- Call LLM (llm_caller handles ST/NS branching) ----
    call_args <- list(
      model_key = model_key,
      generation_interface = generation_interface,
      api_key = api_key,
      api_url = api_url,
      trial_prompt = NULL,              # already concatenated
      material = sent_user,             # user message for this turn
      system_content = system_content,  # may be NULL -> registry default_system
      assistant_content = hist_use,     # seed + structured history
      role_mapping = role_mapping,      # pass user-provided map only; NULL means no forcing
      stream = stream,                  # tri-state honored by llm_caller
      timeout = timeout,
      return_raw = return_raw
    )
    # preserve tri-state: only pass optionals when user actually supplied it
    if (!missing(optionals)) call_args$optionals <- optionals

    llm_resp <- tryCatch(
      do.call(llm_caller, call_args),
      error = function(e) handle_llm_error(run_id = ri, err = e, category = "network")
    )

    t1 <- Sys.time()
    status_num <- suppressWarnings(as.integer(llm_resp$status %||% NA_integer_))
    err_msg <- safe_chr(llm_resp$error)

    # ---- TIMEOUT (599) ----
    if (!is.na(status_num) && status_num == 599L) {
      data$Response[ri] <- NA_character_
      data$AssistantContext[ri] <- NA_character_
      data$HistoryMode <- history_mode
      data$Think[ri] <- NA_character_
      data$TotalResponseTime[ri] <- as.numeric(difftime(t1, t0, units = "secs"))
      data$FirstTokenLatency[ri] <- NA_real_
      data$PromptTokens[ri] <- NA_integer_
      data$CompletionTokens[ri] <- NA_integer_
      data$TrialStatus[ri] <- "TIMEOUT"
      data$Streaming[ri] <- llm_resp$streaming %||% isTRUE(stream)
      data$Timestamp[ri] <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
      data$RequestID[ri] <- NA_character_

      write_experiment_log(
        logfile, stage = "warning", run_id = ri,
        msg = sprintf("Conversation %s turn %s timeout (status=599): %s",
                      cid, safe_chr(data$Turn[ri]), err_msg)
      )
      if (delay > 0) Sys.sleep(delay)
      update_progress_bar(ri, nrow(data), start_time, bar_width, model_key)
      next
    }

    # ---- HTTP ERROR (>=400) ----
    if (!is.na(status_num) && status_num >= 400L) {
      data$Response[ri] <- NA_character_
      data$AssistantContext[ri] <- NA_character_
      data$HistoryMode <- history_mode
      data$Think[ri] <- NA_character_
      data$TotalResponseTime[ri] <- as.numeric(difftime(t1, t0, units = "secs"))
      data$FirstTokenLatency[ri] <- NA_real_
      data$PromptTokens[ri] <- NA_integer_
      data$CompletionTokens[ri] <- NA_integer_
      data$TrialStatus[ri] <- "ERROR"
      data$Streaming[ri] <- llm_resp$streaming %||% isTRUE(stream)
      data$Timestamp[ri] <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
      data$RequestID[ri] <- NA_character_

      write_experiment_log(
        logfile, stage = "error", run_id = ri,
        msg = sprintf("Conversation %s turn %s HTTP %s: %s",
                      cid, safe_chr(data$Turn[ri]), status_num, err_msg)
      )
      if (delay > 0) Sys.sleep(delay)
      update_progress_bar(ri, nrow(data), start_time, bar_width, model_key)
      next
    }

    # ---- SUCCESS (ST/NS result handling mirrors trial_experiment) ----
    answer <- safe_chr(llm_resp$answer)
    data$Response[ri] <- answer
    data$Think[ri] <- safe_chr(llm_resp$thinking)
    data$AssistantContext[ri] <- safe_chr(as_json(hist_use))
    data$HistoryMode <- history_mode
    data$TotalResponseTime[ri] <- as.numeric(difftime(t1, t0, units = "secs"))

    # Unconditional read (same as trial_experiment); may be NA if not available
    ft <- llm_resp$first_token_latency
    data$FirstTokenLatency[ri] <- safe_num(ft)

    ptoks <- llm_resp$usage$prompt
    ctoks <- llm_resp$usage$completion
    data$PromptTokens[ri] <- safe_int(ptoks)
    data$CompletionTokens[ri] <- safe_int(ctoks)

    data$TrialStatus[ri] <- llm_resp$TrialStatus %||% "SUCCESS"
    data$Streaming[ri] <- llm_resp$streaming %||% isTRUE(stream)
    data$Timestamp[ri] <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")

    # Align with trial_experiment: prefer usage$id
    data$RequestID[ri] <- safe_chr(llm_resp$usage$id)

    # Append current turn to rolling history (using locally resolved labels)
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
        histories[[cid]] <- tail(histories[[cid]], max_history_turns * 2)
      }
    }

    # mid-run logs from caller
    if (!is.null(llm_resp$LogMessage)) {
      if (grepl("ERROR", llm_resp$LogMessage)) {
        write_experiment_log(logfile, stage = "error", run_id = ri, msg = llm_resp$LogMessage)
      } else if (grepl("WARNING", llm_resp$LogMessage)) {
        write_experiment_log(logfile, stage = "warning", run_id = ri, msg = llm_resp$LogMessage)
      }
    }

    if (delay > 0) Sys.sleep(delay)
    update_progress_bar(ri, nrow(data), start_time, bar_width, model_key)
  }

  # ---- Finalize & save ----
  update_progress_bar(nrow(data), nrow(data), start_time, bar_width, model_key)
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
    failed = sum(data$TrialStatus %in% c("ERROR", "TIMEOUT"), na.rm = TRUE),
    elapsed = elapsed,
    output_path = result_file
  )

  invisible(data)
}
