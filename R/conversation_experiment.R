#' Run LLM Conversation-style Experiment
#'
#' Multiple-trials-per-run experiment. Each trial is sent sequentially to the LLM,
#' previous trials' user/assistant pairs are preserved in conversation context.
#'
#' @param data data.frame with columns: TrialPrompt, Material.
#'   Optional columns: Run, Item, Condition*, Target, CorrectResponse, TrialType, Metadata
#' @param api_key API key
#' @param model Model name
#' @param api_url API endpoint
#' @param system_prompt Character. Initial system message. Default: "You are a participant in a psychology experiment."
#' @param role_mapping List. Default: list(user="user", system="system", assistant="assistant")
#' @param random Logical. Whether to randomize trial order. Default: FALSE
#' @param output_path Character. CSV/XLSX path
#' @param max_tokens Integer. Maximum tokens per trial (can adjust per trial)
#' @param temperature Numeric. Sampling temperature
#' @param enable_thinking Logical. Default TRUE
#' @return data.frame with trial results and conversation history
#' @export
conversation_experiment <- function(
    data,
    repeats = 1,
    random = FALSE,
    api_key,
    model,
    api_url,
    trial_prompt = "",
    role_mapping = list(user="user", system="system", assistant="assistant"),
    system_prompt = "You are a participant in a psychology experiment.",
    max_tokens = 1024,
    temperature = 0.7,
    enable_thinking = TRUE,
    output_path = "experiment_results.csv"
) {
  # # --------------------------
  # # Load data if path is provided
  # # --------------------------
  # if (is.character(data) && length(data) == 1 && file.exists(data)) {
  #   message("Loading experiment list from file: ", data)
  #   data <- generate_llm_experiment_list(file_path = data, trial_prompt=trial_prompt, experiment_type="conversation_experiment")
  # } else if (!is.data.frame(data)) {
  #   stop("'data' must be either a data.frame or a valid file path (CSV/XLSX).")
  # }
  # # --------------------------
  # # Validate required columns
  # # --------------------------
  # required_cols <- c("TrialPrompt", "Material")
  # missing_cols <- setdiff(required_cols, colnames(data))
  # if (length(missing_cols) > 0) {
  #   stop(paste("Missing required columns:", paste(missing_cols, collapse = ", ")))
  # }
  #
  # # Optional columns
  # run_col <- if ("Run" %in% colnames(data)) "Run" else NULL
  # item_col <- if ("Item" %in% colnames(data)) "Item" else NULL
  # cond_cols <- grep("^Condition", colnames(data), value = TRUE)
  #
  # # Randomize trial order if requested
  # if (isTRUE(random)) {
  #   data <- data[sample(nrow(data)), , drop = FALSE]
  # }

  data <- generate_llm_experiment_list(data,trial_prompt, repeats, random)

  # Initialize output columns
  n_trials <- nrow(data)
  data$Response <- NA_character_
  data$Think <- NA_character_
  data$ConversationHistory <- NA_character_
  data$ModelName <- paste0(model, ifelse(enable_thinking, "", " (FAST)"))
  data$ResponseTime <- NA_real_

  conversation <- list(
    list(role = role_mapping$system %||% "system", content = system_prompt)
  )

  # --------------------------
  # Progress bar init
  # --------------------------
  bar_width <- 40
  start_time <- Sys.time()
  update_progress_bar(0, n_trials, start_time, bar_width, paste0(model, ifelse(enable_thinking, "", " (FAST)")))

  # --------------------------
  # Trial loop
  # --------------------------
  for (i in seq_len(n_trials)) {
    t_start <- Sys.time()

    # Prepare conversation for this trial
    trial_prompt <- data$TrialPrompt[i] %||% ""
    material <- data$Material[i] %||% ""
    user_content <- prepare_prompt(model, trial_prompt, material, enable_thinking)

    # Append current trial as user message
    messages <- append(conversation, list(
      list(role = role_mapping$user %||% "user", content = user_content)
    ))

    # Call LLM
    parsed <- llm_caller(
      model = model,
      conversation = messages,
      api_key = api_key,
      api_url = api_url,
      custom = role_mapping,
      system_prompt = system_prompt,
      max_tokens = max_tokens,
      temperature = temperature,
      enable_thinking = enable_thinking
    )

    t_end <- Sys.time()
    data$ResponseTime[i] <- as.numeric(difftime(t_end, t_start, units = "secs"))

    # Save outputs
    data$Response[i] <- parsed$response
    data$Think[i] <- parsed$think
    data$ModelName[i] <- paste0(model, ifelse(enable_thinking, "", " (FAST)"))

    # Update conversation (add assistant response)
    conversation <- append(messages, list(
      list(role = role_mapping$assistant %||% "assistant", content = parsed$response)
    ))

    # Record conversation history as JSON
    data$ConversationHistory[i] <- jsonlite::toJSON(conversation, auto_unbox = TRUE)


    update_progress_bar(i, n_trials, start_time, bar_width, data$ModelName[i])
  }

  cat("\n", data$ModelName[1], "completed! Total elapsed:",
      round(as.numeric(difftime(Sys.time(), start_time, units="secs")), 1), "secs\n")

  save_experiment_results(data, output_path, enable_thinking)

  return(data)
}
