#' Run LLM Trial Experiment
#'
#' Executes repeated trials using a registry-defined LLM interface. All request
#' assembly (URL, headers, body/messages, defaults) is driven by the registry
#' and calls are delegated to \code{llm_caller()}.
#'
#' Columns in `data`:
#' - Required: `Material`
#' - Optional: `TrialPrompt` (row-level), which overrides the global `trial_prompt` when present.
#'
#' Error/timeout handling:
#' - Network/SSE timeout inside \code{llm_caller()} returns \code{status = 599}
#'   and is marked as \code{"TIMEOUT"} without stopping the loop.
#' - HTTP errors (\code{status >= 400}) are marked as \code{"ERROR"} and also continue.
#'
#' @param model_key Character(1). Registry key (e.g., "deepseek-chat" or "deepseek-chat@proxy").
#' @param generation_interface Character(1). Interface name; defaults to "chat".
#' @param api_key Character(1). Provider API key.
#' @param api_url Optional character(1). Overrides registry default URL; required for non-official providers.
#' @param data data.frame/tibble with `Material`; may contain `TrialPrompt`.
#' @param trial_prompt Optional character(1). Global trial prompt (used when row `TrialPrompt` is missing).
#' @param system_content Optional character(1) or NULL. If NULL, use registry `default_system` when available.
#' @param assistant_content Optional static few-shot seed: character vector or a list of message objects
#'   (`list(role=..., content=...)`). These appear before rolling history and are preserved as-is.
#' @param optionals Optional named list. If NULL, use registry typed defaults; user keys are not merged with defaults.
#' @param role_mapping Optional list. Override registry role names (effective only when the template uses \code{\${ROLE}}).
#' @param stream Logical(1) or NULL. NULL = use registry default; otherwise force streaming/non-streaming.
#' @param timeout Integer(1). Per-request HTTP/SSE timeout in seconds (passed to \code{llm_caller()}).
#' @param repeats Integer(1). Number of repetitions per trial.
#' @param random Logical(1). Randomize trial order.
#' @param delay Numeric(1). Delay (seconds) between trials.
#' @param output_path Character or NULL. Where to save results/logs (compatible with prior schema).
#' @param overwrite Logical(1). Overwrite existing output files.
#' @param return_raw Logical(1). Include raw request/response for debugging.
#'
#' @return A data.frame/tibble with PsyLingLLM schema columns:
#'   Response, Think, ModelName, TotalResponseTime, FirstTokenLatency (if stream),
#'   PromptTokens, CompletionTokens, TrialStatus, Streaming, Timestamp, RequestID.
#' @export
trial_experiment <- function(
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
    stream = FALSE,
    timeout = 120,
    repeats = 1,
    random = FALSE,
    delay = 0,
    output_path = NULL,
    overwrite = TRUE,
    return_raw = FALSE
) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
  safe_chr <- function(x) if (is.null(x) || length(x) == 0 || all(is.na(x))) NA_character_ else as.character(x)[1]
  safe_num <- function(x) if (is.null(x) || length(x) == 0 || all(is.na(x))) NA_real_ else as.numeric(x)[1]
  safe_int <- function(x) if (is.null(x) || length(x) == 0 || all(is.na(x))) NA_integer_ else as.integer(x)[1]

  # ---- Build trial list (repeats/random) -----------------------------------
  if (!("Material" %in% names(data))) stop("`data` must contain column `Material`.")
  data <- generate_llm_experiment_list(data, trial_prompt, repeats, random)
  n_trials <- nrow(data)

  # ---- Validate config ------------------------------------------------------
  validate_experiment_config(
    api_key = api_key,
    api_url = api_url,
    model = model_key,
    data = data,
    required_cols = c("Material"),
    registry = load_registry()
  )

  # ---- Output & log paths ---------------------------------------------------
  paths <- resolve_output_and_log(output_path, model_key)
  result_file <- paths$result_file
  logfile <- paths$log_file

  # ---- Initialize schema columns -------------------------------------------
  data$Response <- NA_character_
  data$Think <- NA_character_
  data$ModelName <- model_key
  data$TotalResponseTime <- NA_real_
  data$FirstTokenLatency <- NA_real_
  data$PromptTokens <- NA_integer_
  data$CompletionTokens <- NA_integer_
  data$TrialStatus <- NA_character_
  data$Streaming <- NA
  data$Timestamp <- NA_character_
  data$RequestID <- NA_character_

  # ---- Log start ------------------------------------------------------------
  write_experiment_log(
    logfile,
    stage = "start",
    model = model_key,
    streaming = isTRUE(stream),
    total_runs = n_trials,
    output_path = result_file
  )

  # ---- Progress bar ---------------------------------------------------------
  start_time <- Sys.time()
  bar_width <- 40
  update_progress_bar(0, n_trials, start_time, bar_width, model_key)

  # ---- Trials loop ----------------------------------------------------------
  for (i in seq_len(n_trials)) {
    t0 <- Sys.time()

    # Row-level prompt: prefer row TrialPrompt, else global trial_prompt
    row_prompt <- if ("TrialPrompt" %in% names(data)) data$TrialPrompt[i] else NA_character_
    eff_prompt <- if (!is.na(row_prompt) && nzchar(safe_chr(row_prompt))) row_prompt else trial_prompt

    llm_resp <- tryCatch(
      llm_caller(
        model_key = model_key,
        generation_interface = generation_interface,
        api_key = api_key,
        api_url = api_url,
        trial_prompt = eff_prompt,
        material = data$Material[i],
        system_content = system_content,
        assistant_content = assistant_content,
        optionals = optionals,
        role_mapping = role_mapping,
        stream = stream,              # tri-state honored by llm_caller
        timeout = timeout,
        return_raw = return_raw
      ),
      error = function(e) handle_llm_error(run_id = i, err = e, category = "network")
    )

    t1 <- Sys.time()
    status_num <- suppressWarnings(as.integer(llm_resp$status %||% NA_integer_))
    err_msg <- safe_chr(llm_resp$error)

    # ---- Timeout handling (599) ---------------------------------------------
    if (!is.na(status_num) && status_num == 599L) {
      data$Response[i] <- NA_character_
      data$Think[i] <- NA_character_
      data$TotalResponseTime[i] <- as.numeric(difftime(t1, t0, units = "secs"))
      data$FirstTokenLatency[i] <- NA_real_
      data$PromptTokens[i] <- NA_integer_
      data$CompletionTokens[i] <- NA_integer_
      data$TrialStatus[i] <- "TIMEOUT"
      data$Streaming[i] <- llm_resp$streaming %||% isTRUE(stream)
      data$Timestamp[i] <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
      data$RequestID[i] <- NA_character_

      write_experiment_log(
        logfile, stage = "warning", run_id = i,
        msg = sprintf("Trial %d timeout (status=599): %s", i, err_msg)
      )
      Sys.sleep(delay)
      update_progress_bar(i, n_trials, start_time, bar_width, model_key)
      next
    }

    # ---- HTTP error handling (>=400) ----------------------------------------
    if (!is.na(status_num) && status_num >= 400L) {
      data$Response[i] <- NA_character_
      data$Think[i] <- NA_character_
      data$TotalResponseTime[i] <- as.numeric(difftime(t1, t0, units = "secs"))
      data$FirstTokenLatency[i] <- NA_real_
      data$PromptTokens[i] <- NA_integer_
      data$CompletionTokens[i] <- NA_integer_
      data$TrialStatus[i] <- "ERROR"
      data$Streaming[i] <- llm_resp$streaming %||% isTRUE(stream)
      data$Timestamp[i] <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
      data$RequestID[i] <- NA_character_

      write_experiment_log(
        logfile, stage = "error", run_id = i,
        msg = sprintf("Trial %d HTTP %s: %s", i, status_num, err_msg)
      )
      Sys.sleep(delay)
      update_progress_bar(i, n_trials, start_time, bar_width, model_key)
      next
    }

    # ---- Success path -------------------------------------------------------
    data$Response[i] <- safe_chr(llm_resp$answer)
    data$Think[i] <- safe_chr(llm_resp$thinking)
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
    data$RequestID[i] <- llm_resp$usage$id

    # Mid-run logs preserved
    if (!is.null(llm_resp$LogMessage)) {
      if (grepl("ERROR", llm_resp$LogMessage)) {
        write_experiment_log(logfile, stage = "error", run_id = i, msg = llm_resp$LogMessage)
      } else if (grepl("WARNING", llm_resp$LogMessage)) {
        write_experiment_log(logfile, stage = "warning", run_id = i, msg = llm_resp$LogMessage)
      }
    }

    Sys.sleep(delay)
    update_progress_bar(i, n_trials, start_time, bar_width, model_key)
  }

  # ---- Finalize & save ------------------------------------------------------
  update_progress_bar(n_trials, n_trials, start_time, bar_width, model_key)
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
    total_runs = n_trials,
    success = sum(data$TrialStatus == "SUCCESS", na.rm = TRUE),
    failed = sum(data$TrialStatus %in% c("ERROR","TIMEOUT"), na.rm = TRUE),
    elapsed = elapsed,
    output_path = result_file
  )

  invisible(data)
}
