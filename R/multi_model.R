#' Run Trials Across Multiple Models (registry-driven, assistant-native)
#'
#' Executes the same trial table on multiple models. Each row of `models`
#' describes one model configuration. For each row, this function delegates to
#' \code{trial_experiment()} with the appropriate arguments and then row-binds
#' the results into a single data frame.
#'
#' ## `models` table
#' Required column:
#' - `model_key` (character): registry key, e.g. "deepseek-chat" or "deepseek-chat@proxy".
#'
#' Optional columns (all per-model; if absent, corresponding top-level args are used):
#' - `generation_interface` (character, default "chat")
#' - `api_key` (character)
#' - `api_url` (character; required for non-official providers or to override official)
#' - `stream` (logical or NA; `NA`/missing means follow registry default)
#' - `system_content` (character or NA)
#' - `assistant_content` (character vector or list-of-message objects; may be JSON string)
#' - `optionals` (list column or JSON string; tri-state honored if column missing)
#' - `role_mapping` (list column or JSON string; only passed if provided)
#' - `output_path` (character; per-model output path for \code{trial_experiment()})
#'
#' Any JSON-like character column (e.g., `optionals`, `role_mapping`, `assistant_content`)
#' will be JSON-decoded if it validates as JSON; otherwise passed through as-is.
#'
#' ## Optionals tri-state
#' - If `models$optionals` exists for that row → pass it to downstream (user keys only).
#' - Else if top-level `optionals` is missing → do **not** pass the param (use registry defaults).
#' - Else if top-level `optionals` is provided (NULL or list) → pass that top-level value.
#'
#' ## Errors & timeouts
#' - Each model is run independently. Errors/timeouts inside \code{trial_experiment()}
#'   are recorded per-trial; the multi-model loop continues.
#'
#' @param models data.frame/tibble describing models; see "models table".
#' @param data Trial table for \code{trial_experiment()} (must contain `Material`; `TrialPrompt` optional).
#' @param trial_prompt Optional character(1). Global trial prefix; row `TrialPrompt` (if any) overrides.
#' @param repeats Integer(1). Number of repetitions per trial for every model.
#' @param random Logical(1). Randomize trial order for every model.
#' @param delay Numeric(1). Delay (seconds) between trials for every model.
#' @param timeout Integer(1). Per-request timeout in seconds.
#' @param overwrite Logical(1). Overwrite per-model outputs.
#' @param return_raw Logical(1). Include raw request/response in per-call results.
#' @param system_content Optional character(1). Fallback system message if model row lacks one.
#' @param assistant_content Optional static few-shot seed: character vector or a list of message objects
#'   (`list(role=..., content=...)`). These appear before rolling history and are preserved as-is.
#' @param role_mapping Optional mapping of roles if model row lacks one.
#' @param optionals Optional named list (or NULL) if model row lacks `optionals`.
#'        *Omitting this argument* preserves the tri-state (registry defaults).
#' @param stream Logical(1) or NULL. Default streaming policy if model row lacks `stream`.
#' @param output_dir Optional character(1). If given, used as a base directory for per-model outputs
#'        when the model row doesn't provide `output_path`.
#' @param combined_output_path Optional character(1). If provided, write the combined results CSV here.
#'
#' @return A data.frame/tibble concatenating all per-model results. Each chunk retains the
#'         standard PsyLingLLM schema columns and is annotated with `ModelKey` (alias of ModelName).
#' @export
multi_model_experiment <- function(
    models,
    data,
    trial_prompt = NULL,
    repeats = 1,
    random = FALSE,
    delay = 0,
    timeout = getOption("psylingllm.llm_timeout_sec", 120L),
    overwrite = TRUE,
    return_raw = FALSE,
    system_content = NULL,
    assistant_content,
    role_mapping,
    optionals = NULL,
    stream = NULL,
    output_dir = NULL,
    combined_output_path = NULL
) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
  nz_chr <- function(x) is.character(x) && length(x) == 1 && nzchar(x)

  # helpers ------------------------------------------------------------
  try_json <- function(x) {
    if (is.null(x)) return(NULL)
    if (is.list(x)) return(x)
    if (is.character(x) && length(x) == 1 && nzchar(x)) {
      if (inherits(try(jsonlite::fromJSON(x, simplifyVector = TRUE), silent = TRUE), "try-error")) return(x)
      return(jsonlite::fromJSON(x, simplifyVector = TRUE))
    }
    x
  }
  has_col <- function(df, nm) nm %in% names(df)

  if (!has_col(models, "model_key")) {
    stop("`models` must contain column `model_key`.")
  }

  # iterate rows -------------------------------------------------------
  all_results <- list()

  for (i in seq_len(nrow(models))) {
    row <- models[i, , drop = FALSE]
    mk   <- as.character(row$model_key)

    gi   <- if (has_col(row, "generation_interface") && nz_chr(row$generation_interface)) {
      as.character(row$generation_interface)
    } else "chat"

    # per-model keys/URL/flags
    api_key_i <- if (has_col(row, "api_key") && nz_chr(row$api_key)) as.character(row$api_key) else NULL
    api_url_i <- if (has_col(row, "api_url") && nz_chr(row$api_url)) as.character(row$api_url) else NULL

    stream_i <- if (has_col(row, "stream")) {
      v <- row$stream[[1]]
      if (is.null(v) || (is.logical(v) && any(is.na(v)))) NULL else isTRUE(v)
    } else stream  # NULL/TRUE/FALSE (tri-state propagated)

    # per-model role/system/assistant/optionals/mapping
    sys_i <- if (has_col(row, "system_content") && nz_chr(row$system_content)) as.character(row$system_content) else system_content

    # assistant_content: allow list-of-messages / character vector / JSON
    asst_i <- if (has_col(row, "assistant_content")) try_json(row$assistant_content[[1]]) else
      if (!missing(assistant_content)) assistant_content else NULL

    # role_mapping: allow list or JSON; only pass if provided (no forcing)
    rolemap_i <- if (has_col(row, "role_mapping")) try_json(row$role_mapping[[1]]) else
      if (!missing(role_mapping)) role_mapping else NULL

    # optionals tri-state:
    # - if column exists AND value is non-NA/non-empty -> pass that
    # - else if top-level missing(...) -> DO NOT pass (preserve registry defaults)
    # - else pass top-level (NULL or list)
    pass_optionals <- FALSE
    optionals_i <- NULL
    is_naish <- function(v) {
      if (is.null(v)) return(TRUE)
      if (length(v) == 0) return(TRUE)
      if (is.atomic(v) && length(v) == 1 && is.na(v)) return(TRUE)
      if (is.character(v) && length(v) == 1) {
        s <- trimws(v)
        return(identical(s, "") || identical(tolower(s), "null"))
      }
      FALSE
    }
    if (has_col(row, "optionals")) {
      val <- row$optionals[[1]]
      if (!is_naish(val)) {
        optionals_i <- try_json(val)
        pass_optionals <- TRUE
      }
    } else if (!missing(optionals)) {
      optionals_i <- optionals
      pass_optionals <- TRUE
    }


    # output path
    out_path_i <- if (has_col(row, "output_path") && nz_chr(row$output_path)) {
      as.character(row$output_path)
    } else output_dir %||% NULL

    # run one model via trial_experiment --------------------------------
    call_args <- list(
      model_key = mk,
      generation_interface = gi,
      api_key = api_key_i,
      api_url = api_url_i,
      data = data,
      trial_prompt = trial_prompt,
      system_content = sys_i,
      assistant_content = asst_i,
      role_mapping = rolemap_i,
      stream = stream_i,
      timeout = timeout,
      repeats = repeats,
      random = random,
      delay = delay,
      output_path = out_path_i,
      overwrite = overwrite,
      return_raw = return_raw
    )
    # preserve optionals tri-state by adding argument only when decided above
    if (isTRUE(pass_optionals)) call_args$optionals <- optionals_i

    res <- tryCatch(
      do.call(trial_experiment, call_args),
      error = function(e) {
        warning(sprintf("[multi_model_experiment] model '%s' failed: %s", mk, e$message))
        # return empty df with schema-compatible columns
        data.frame(
          Response = character(), Think = character(), ModelName = character(),
          TotalResponseTime = numeric(), FirstTokenLatency = numeric(),
          PromptTokens = integer(), CompletionTokens = integer(),
          TrialStatus = character(), Streaming = logical(),
          Timestamp = character(), RequestID = character(),
          stringsAsFactors = FALSE
        )
      }
    )

    # annotate & collect
    if (nrow(res)) {
      if (!"ModelKey" %in% names(res)) res$ModelKey <- res$ModelName
      all_results[[length(all_results) + 1]] <- res
    }
  }

  combined <- if (length(all_results)) dplyr::bind_rows(all_results) else
    data.frame(
      Response = character(), Think = character(), ModelName = character(),
      TotalResponseTime = numeric(), FirstTokenLatency = numeric(),
      PromptTokens = integer(), CompletionTokens = integer(),
      TrialStatus = character(), Streaming = logical(),
      Timestamp = character(), RequestID = character(),
      ModelKey = character(),
      stringsAsFactors = FALSE
    )

  # optional combined CSV -----------------------------------------------------
  if (nz_chr(combined_output_path)) {
    try({
      readr::write_csv(combined, combined_output_path)
      message("[PsyLingLLM] Combined results saved: ", combined_output_path)
    }, silent = TRUE)
  }

  combined
}
