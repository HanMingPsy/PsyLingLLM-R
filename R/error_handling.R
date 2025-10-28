#' PsyLingLLM Error Handling Utilities (Enhanced)
#'
#' Centralized error handling for experiments.
#' Adds detailed error categories and clearer diagnostics.
#'
#' @keywords internal
#' @name error_handling
NULL

.psyll_state <- new.env(parent = emptyenv())

# --- Report warning only once ---
report_once <- function(key, msg) {
  if (!exists(key, envir = .psyll_state)) {
    assign(key, TRUE, envir = .psyll_state)
    warning(msg, call. = FALSE)
  }
}

#' Validate experiment configuration and resolve API URL
#'
#' Applies PsyLingLLM's registry-first rules:
#' - Official providers may omit \code{api_url} if the registry defines
#'   \code{input.default_url}.
#' - Non-official providers (model key contains \code{"@"} or provider != "official")
#'   must supply \code{api_url}.
#'
#' Also checks required data columns and API key presence.
#'
#' @param api_key Character(1). Provider API key.
#' @param api_url Character(1) or NULL. Optional for official providers.
#' @param model Character(1). Registry key (e.g., "deepseek-chat" or "deepseek-chat@proxy").
#' @param data data.frame/tibble. Must contain columns in \code{required_cols}.
#' @param required_cols Character vector. Columns that must be present in \code{data}.
#' @param registry Ignored (kept for backward compatibility).
#' @param generation_interface Character(1). Interface to validate, default "chat".
#'
#' @return Invisibly returns a list with resolved fields:
#'   \code{list(api_key, api_url, model_key, provider, generation_interface)}.
#' @export
validate_experiment_config <- function(api_key,
                                       api_url,
                                       model,
                                       data,
                                       required_cols = c("Material"),
                                       registry = NULL,
                                       generation_interface = "chat") {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
  nz_chr <- function(x) is.character(x) && length(x) == 1 && nzchar(x)

  # --- data columns
  missing_cols <- setdiff(required_cols, names(data))
  if (length(missing_cols)) {
    stop(sprintf("[PsyLingLLM] FATAL - Missing required column(s): %s",
                 paste(missing_cols, collapse = ", ")), call. = FALSE)
  }

  # --- API key
  if (!nz_chr(api_key)) {
    stop("[PsyLingLLM] FATAL - API key is missing or empty.", call. = FALSE)
  }

  # --- registry lookup (user-first, system fallback)
  entry <- tryCatch(
    get_registry_entry(model_key = model,
                       generation_interface = generation_interface),
    error = function(e) NULL
  )

  # model found?
  if (is.null(entry)) {
    # If no registry entry and api_url is missing, we cannot proceed.
    if (!nz_chr(api_url)) {
      stop(sprintf("[PsyLingLLM] FATAL - Model '%s' not found in registry and api_url is missing.", model),
           call. = FALSE)
    }
    provider <- "unknown"
    resolved_url <- api_url
  } else {
    provider <- entry$provider %||% "unknown"
    default_url <- entry$input$default_url %||% NULL

    # resolve per rules
    is_non_official <- grepl("@", model, fixed = TRUE) || !identical(provider, "official")
    if (!nz_chr(api_url)) {
      if (!is_non_official && nz_chr(default_url)) {
        resolved_url <- default_url
      } else {
        stop("[PsyLingLLM] FATAL - API URL is missing or empty for non-official provider (or no default_url in registry).",
             call. = FALSE)
      }
    } else {
      resolved_url <- api_url
    }
  }

  invisible(list(
    api_key = api_key,
    api_url = resolved_url,
    model_key = model,
    provider = provider,
    generation_interface = generation_interface
  ))
}



# --- Error handling ---
handle_llm_error <- function(run_id, err, category = "UNKNOWN") {
  msg <- if (inherits(err, "condition")) conditionMessage(err) else as.character(err)
  log_msg <- sprintf("[PsyLingLLM] Run %d ERROR (%s) - %s", run_id, category, msg)

  # Detailed status mapping
  detail <- switch(toupper(category),
                   "NETWORK" = "NETWORK_ERROR",
                   "HTTP"    = "HTTP_ERROR",
                   "JSON"    = "API_ERROR",
                   "CONFIG"  = "MODEL_NOT_FOUND",
                   "UNKNOWN")

  list(
    Response = NA_character_,
    Think = NA_character_,
    TrialStatus = "ERROR",
    TrialStatusDetail = detail,
    LogMessage = log_msg,
    TotalResponseTime = NA_real_
  )
}

# --- Warning handling ---
handle_llm_warning <- function(run_id, msg, category = "GENERAL") {
  log_msg <- sprintf("[PsyLingLLM] Run %d WARNING (%s) - %s", run_id, category, msg)
  list(
    TrialStatus = "SUCCESS",
    TrialStatusDetail = paste0("WARNING_", toupper(category)),
    LogMessage = log_msg
  )
}

# --- Safe parse response with fallback ---
safe_parse_response <- function(resp, cfg, run_id) {
  tryCatch(
    {
      res <- parse_answer_and_think(cfg, resp = resp)

      # 空返回处理
      if (is.null(res$response) || !nzchar(trimws(res$response))) {
        fb <- tryCatch(
          extract_by_path(resp, c("choices", 0, "message", "content")),
          error = function(e) NULL
        )
        if (!is.null(fb) && nzchar(trimws(fb))) {
          # report_once("respond_path_fallback",
          #             sprintf("[PsyLingLLM] WARNING - respond_path not found for model '%s', fallback to OpenAI standard.",
          #                     cfg$name %||% "unknown"))
          return(list(
            response = fb,
            think = NA_character_,
            TrialStatus = "SUCCESS",
            TrialStatusDetail = "RESPOND_PATH_FALLBACK"
          ))
        } else {
          # ⚠️ 空返回 → 警告
          warning(sprintf(
            "[PsyLingLLM] WARNING - model '%s' returned empty response.",
            cfg$name %||% "unknown"
          ), call. = FALSE)
          return(list(
            response = NA_character_,
            think = NA_character_,
            TrialStatus = "SUCCESS",
            TrialStatusDetail = "EMPTY_RESPONSE"
          ))
        }
      }

      list(response = res$response,
           think = res$think,
           TrialStatus = "SUCCESS",
           TrialStatusDetail = "OK")
    },
    error = function(e) handle_llm_error(run_id, e, "JSON")
  )
}

