#' Run LLM Repeat-Trial Experiment (Multiple Conditions Supported)
#'
#' Execute repeated trials using a large language model.
#' Each \code{Item × Condition(s)} can be repeated multiple times,
#' trials are randomized across repetitions if \code{random=TRUE},
#' or sequential if \code{random=FALSE}. Results include responses and timing.
#'
#' @param data data.frame containing columns: optionally \code{Run}, optionally \code{Item},
#'   one or more \code{Condition*} columns, \code{Material}, optionally \code{TrialPrompt}.
#'   Optional columns: \code{Target}, \code{CorrectResponse}, \code{TrialType}, \code{Metadata}.
#' @param repeats Integer. Number of repetitions per trial (default = 3).
#' @param api_key Character. API key for the LLM.
#' @param model Character. Model name.
#' @param api_url Character. API endpoint URL.
#' @param system_prompt Character. System-level prompt for the model.
#'   Default: "You are a participant in a psychology experiment."
#' @param role_mapping List. Role mapping, default: \code{list(user="user", system="system", assistant="assistant")}.
#' @param random Logical. Whether to randomize trial order (default \code{TRUE}).
#' @param output_path Character. Output file path (CSV or XLSX).
#' @param max_tokens Integer. Maximum tokens to generate.
#' @param temperature Numeric. Temperature for sampling.
#' @param enable_thinking Logical. Whether to enable chain-of-thought reasoning (default \code{TRUE}).
#' @param delay Numeric. Delay in seconds between requests (default = 1).
#'
#' @return A \code{data.frame} including \code{Response}, \code{Think}, \code{ModelName},
#'   \code{ResponseTime}, plus all original marker/condition columns in standard order.
#' @export
trial_experiment <- function(
    data,
    repeats = 1,
    random = FALSE,
    api_key,
    model,
    api_url,
    trial_prompt = "",
    role_mapping = list(user = "user", system = "system", assistant = "assistant"),
    system_prompt = "You are a participant in a psychology experiment.",
    max_tokens = 1024,
    temperature = 0.7,
    enable_thinking = TRUE,
    delay = 0,
    output_path = "experiment_results.csv"
) {

  data <- generate_llm_experiment_list(data,trial_prompt, repeats, random)

  # --------------------------
  # Initialize output columns
  # --------------------------
  n_trials <- nrow(data)
  data$Response <- NA_character_
  data$Think <- NA_character_
  data$ModelName <- paste0(model, ifelse(enable_thinking, "", " (FAST)"))
  # data$Enable_Thinking <- enable_thinking
  data$ResponseTime <- NA_real_

  # --------------------------
  # Progress bar init
  # --------------------------
  bar_width <- 40
  start_time <- Sys.time()
  update_progress_bar(0, n_trials, start_time, bar_width, paste0(model, ifelse(enable_thinking, "", " (FAST)")))

  # --------------------------
  # Trial loop with retry & delay
  # --------------------------
  max_retry <- 5
  for (i in seq_len(n_trials)) {
    attempt <- 1
    repeat {
      t_start <- Sys.time()
      parsed_resp <- tryCatch(
        llm_caller(
          model = model,
          trial_prompt = data$TrialPrompt[i],
          material = data$Material[i],
          api_key = api_key,
          api_url = api_url,
          custom = role_mapping,
          system_prompt = system_prompt,
          max_tokens = max_tokens,
          temperature = temperature,
          enable_thinking = enable_thinking
        ),
        error = function(e) e
      )
      t_end <- Sys.time()
      if (!inherits(parsed_resp, "error") || !grepl("429", parsed_resp$message)) break
      if (attempt > max_retry) stop("Repeatedly failed due to 429 Too Many Requests")
      Sys.sleep(delay * 2 ^ attempt)  # RT not included
      attempt <- attempt + 1
    }

    data$ResponseTime[i] <- as.numeric(difftime(t_end, t_start, units = "secs"))
    data$Response[i] <- parsed_resp$response
    data$Think[i] <- parsed_resp$think

    Sys.sleep(delay)  # RT not included


    update_progress_bar(i, n_trials, start_time, bar_width, data$ModelName[i])
  }

  total_elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  cat("\n", data$ModelName[1], "completed! Total elapsed: ", round(total_elapsed, 1), " secs\n")



  save_experiment_results(data, output_path, enable_thinking)

  return(data)
}
