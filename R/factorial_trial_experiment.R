#' Run Factorial Trial Experiment (Carrier Sentence + Critical Word Filling)
#'
#' Supports multiple carrier sentences, factors, and CW mappings.
#' Automatically generates `Carrier_Sentence` from carrier sentence and CW word.
#' Supports trial prompt as a string or a function.
#'
#' @param data data.frame with columns `Item` and `Material`.
#' @param factors list of factors, e.g. `list(Congruity = c("Congruent","Incongruent"))`.
#' @param CW data.frame with `Item` and columns corresponding to factor-level combinations (wide format).
#' @param fill_method function(condition, Material, CW_word) -> Material.
#' @param trial_prompt string or function.
#' @param repeats integer, number of repetitions per trial.
#' @param random logical, whether to randomize trial order.
#' @param role_mapping list of role names for LLM call.
#' @param system_prompt string, global system message for LLM.
#' @param api_key string, API key.
#' @param model string, LLM model name.
#' @param api_url string, API endpoint.
#' @param max_tokens integer, maximum tokens for response.
#' @param temperature numeric, sampling temperature.
#' @param enable_thinking logical, whether to enable model thinking trace.
#' @param delay numeric, delay (in seconds) between trials.
#' @param output_path string, file path to save experiment results.
#'
#' @return data.frame with columns:
#' `Run`, `Item`, `Material`, factor columns, `Word`, `Carrier_Sentence`,
#' `TrialPrompt`, `Response`, `Think`, `ModelName`, `ResponseTime`.
#' @export
#'
#' @examples
#' data <- data.frame(Item = 1:2, Material = c("Sentence A", "Sentence B"))
#' factors <- list(Congruity = c("Congruent", "Incongruent"))
#' CW <- data.frame(Item = 1:2,
#'                  Congruent = c("dog", "cat"),
#'                  Incongruent = c("car", "chair"))
#' fill_method <- function(cond, Material, CW_word) paste(Material, CW_word)
#' factorial_trial_experiment(data, factors, CW, fill_method,
#'                            trial_prompt = "Read carefully.",
#'                            model = "gpt-4", api_key = "YOUR_KEY", api_url = "https://api.openai.com/v1/chat/completions")
#'
factorial_trial_experiment <- function(
    data,
    factors,
    CW = NULL,
    fill_method,
    trial_prompt = "",
    repeats = 1,
    random = FALSE,
    role_mapping = list(user = "user", system = "system", assistant = "assistant"),
    system_prompt = "You are a participant in a psychology experiment.",
    api_key,
    model,
    api_url,
    max_tokens = 512,
    temperature = 0.7,
    enable_thinking = TRUE,
    delay = 1,
    output_path = "experiment_results.csv"
) {
  # --- Input validation ---
  stopifnot(is.data.frame(data), is.list(factors), is.function(fill_method))
  if (missing(api_key) || missing(model) || missing(api_url)) {
    stop("Arguments `api_key`, `model`, and `api_url` are required.")
  }

  # --------------------------
  # 1. Generate trial list (long format)
  # --------------------------
  data <- generate_llm_factorial_experiment_list(
    data = data,
    factors = factors,
    CW = CW,
    trial_prompt = trial_prompt,
    repeats = repeats,
    random = random
  )

  factor_names <- names(factors)

  # --------------------------
  # 2. Fill carrier sentence with CW word
  # --------------------------
  data$Carrier_Sentence <- vapply(seq_len(nrow(data)), function(i) {
    cond <- as.character(data[i, factor_names])
    carrier <- as.character(data$Material[i])
    word <- if ("Word" %in% colnames(data)) as.character(data$Word[i]) else NULL
    fill_method(cond, carrier, word)
  }, FUN.VALUE = character(1))

  # --------------------------
  # 3. Generate TrialPrompt
  # Priority: function > string > existing TrialPrompt
  # --------------------------
  if (is.function(trial_prompt)) {
    if ("TrialPrompt" %in% colnames(data) && any(nzchar(data$TrialPrompt))) {
      warning("Conflicting TrialPrompt detected. Overwriting with trial_prompt function output.")
    }
    data$TrialPrompt <- vapply(seq_len(nrow(data)), function(i) {
      trial_prompt(data[i, , drop = FALSE])
    }, FUN.VALUE = character(1))

  } else if (is.character(trial_prompt) && nzchar(trial_prompt)) {
    if ("TrialPrompt" %in% colnames(data) && any(nzchar(data$TrialPrompt))) {
      warning("Conflicting TrialPrompt detected. Overwriting with trial_prompt string.")
    }
    data$TrialPrompt <- paste0(trial_prompt, "\n")
  }

  # --------------------------
  # 4. Initialize output columns
  # --------------------------
  data$Response <- NA_character_
  data$Think <- NA_character_
  data$ModelName <- paste0(model, ifelse(enable_thinking, "", " (FAST)"))
  data$ResponseTime <- NA_real_

  # --------------------------
  # 5. LLM trial loop
  # --------------------------
  n_trials <- nrow(data)
  bar_width <- 40
  start_time <- Sys.time()
  update_progress_bar(0, n_trials, start_time, bar_width, data$ModelName[1])

  max_retry <- 5
  for (i in seq_len(n_trials)) {
    attempt <- 1
    repeat {
      t_start <- Sys.time()
      parsed_resp <- tryCatch(
        llm_caller(
          model = model,
          trial_prompt = data$TrialPrompt[i],
          material = data$Carrier_Sentence[i],
          api_key = api_key,
          api_url = api_url,
          custom = role_mapping,
          system_prompt = system_prompt,
          max_tokens = max_tokens,
          temperature = temperature,
          enable_thinking = enable_thinking
        ),
        error = function(e) list(response = NA_character_, think = NA_character_)
      )
      t_end <- Sys.time()

      # Retry only on 429 rate-limit errors
      if (!inherits(parsed_resp, "error") || !grepl("429", parsed_resp$message)) break
      if (attempt > max_retry) stop("Repeatedly failed due to 429 Too Many Requests.")
      Sys.sleep(delay * 2 ^ attempt)
      attempt <- attempt + 1
    }

    # Save trial results
    data$ResponseTime[i] <- as.numeric(difftime(t_end, t_start, units = "secs"))
    data$Response[i] <- parsed_resp$response
    data$Think[i] <- parsed_resp$think

    Sys.sleep(delay)
    update_progress_bar(i, n_trials, start_time, bar_width, data$ModelName[i])
  }

  total_elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  cat("\n", data$ModelName[1], "completed! Total elapsed: ",
      round(total_elapsed, 1), " secs\n")

  # --------------------------
  # 6. Save results
  # --------------------------
  save_experiment_results(data, output_path, enable_thinking)

  return(data)
}
