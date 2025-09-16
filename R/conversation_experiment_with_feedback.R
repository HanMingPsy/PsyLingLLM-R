#' Run LLM Conversation Experiment with Feedback
#'
#' Sequentially sends trials to an LLM, keeps conversation history,
#' and applies user-defined feedback to modify subsequent prompts.
#'
#' @param data Data frame or file path with at least `TrialPrompt` and `Material`.
#' @param repeats Number of times to repeat materials.
#' @param random Shuffle trial order.
#' @param api_key API key for the LLM.
#' @param model LLM model name.
#' @param api_url LLM API endpoint.
#' @param trial_prompt Initial prompt prefix for each trial.
#' @param feedback_fn Function(response, row, conversation) returning list(name, next_prompt, meta).
#' @param apply_mode "replace_next" = overwrite next row, "insert_dynamic" = insert new row.
#' @param role_mapping Mapping for roles: user/system/assistant.
#' @param system_prompt Initial system message.
#' @param max_trials Maximum trials to run.
#' @param delay Delay (seconds) between trials.
#' @param output_path File path to save results.
#' @param enable_thinking Logical; enable chain-of-thought.
#' @param ... Extra arguments passed to `llm_caller`.
#' @return Data frame of trial results.
#' @export
conversation_experiment_with_feedback <- function(
    data,
    repeats = 1,
    random = FALSE,
    api_key,
    model,
    api_url,
    trial_prompt = "",
    feedback_fn,
    apply_mode = c("replace_next", "insert_dynamic"),
    role_mapping = list(user = "user", system = "system", assistant = "assistant"),
    system_prompt = "You are a participant in a psychology experiment.",
    max_trials = 50,
    delay = 1,
    output_path = "experiment_results.csv",
    enable_thinking = FALSE,
    ...
) {
  apply_mode <- match.arg(apply_mode)

  # --------------------------
  # Prepare data
  # --------------------------
  data <- generate_llm_experiment_list(data, trial_prompt, repeats, random)
  orig_trials <- nrow(data)
  n_trials <- orig_trials

  data$Response <- NA_character_
  data$Think <- NA_character_
  data$ConversationHistory <- NA_character_
  data$ModelName <- paste0(model, ifelse(enable_thinking, "", " (FAST)"))
  data$ResponseTime <- NA_real_

  results <- list()
  conversation <- list(list(role = role_mapping$system, content = system_prompt))

  # --------------------------
  # Progress bar
  # --------------------------
  bar_width <- 40
  start_time <- Sys.time()
  max_steps <- if (apply_mode == "replace_next") orig_trials else max_trials
  update_progress_bar(0, max_steps, start_time, bar_width, data$ModelName[1])

  trial_count <- 0
  i <- 1
  while (i <= n_trials && trial_count < max_trials) {
    trial_count <- trial_count + 1

    row <- data[i, , drop = FALSE]
    trial_prompt <- as.character(row$TrialPrompt %||% "")
    material <- as.character(row$Material %||% "")

    user_text <- paste(trial_prompt, material)
    conv <- append(conversation, list(list(role = "user", content = user_text)))

    # --------------------------
    # Call LLM
    # --------------------------
    t_start <- Sys.time()
    parsed_resp <- llm_caller(
      model = model,
      conversation = conv,
      api_key = api_key,
      api_url = api_url,
      custom = role_mapping,
      system_prompt = system_prompt,
      enable_thinking = enable_thinking,
      ...
    )
    elapsed_trial <- as.numeric(difftime(Sys.time(), t_start, units = "secs"))

    conversation <- append(conv, list(list(role = "assistant", content = parsed_resp$response)))

    # --------------------------
    # Apply feedback
    # --------------------------
    fb <- NULL
    if (is.function(feedback_fn)) {
      fb <- tryCatch(feedback_fn(parsed_resp$response, row, conversation),
                     error = function(e) { warning("feedback_fn error: ", e$message); NULL })
    }

    if (!is.null(fb) && !is.null(fb$next_prompt) && nzchar(fb$next_prompt)) {
      new_row <- data[1, , drop = FALSE]
      new_row[1, ] <- NA
      new_row$TrialPrompt <- fb$next_prompt
      new_row$Material <- ""

      if (apply_mode == "replace_next") {
        if (i + 1 <= n_trials) {
          data$TrialPrompt[i + 1] <- fb$next_prompt
        } else {
          data <- dplyr::bind_rows(data, new_row)
          n_trials <- nrow(data)
        }
      } else if (apply_mode == "insert_dynamic") {
        if (i < n_trials) {
          top <- data[1:i, , drop = FALSE]
          bottom <- data[(i + 1):n_trials, , drop = FALSE]
          data <- dplyr::bind_rows(top, new_row, bottom)
        } else {
          data <- dplyr::bind_rows(data, new_row)
        }
        n_trials <- nrow(data)
      }
    }

    # --------------------------
    # Record results
    # --------------------------
    row_list <- list(
      Run = trial_count,
      TrialPrompt = trial_prompt,
      Material = material,
      Response = parsed_resp$response %||% "",
      FeedbackDecision = fb$name %||% NA_character_,
      FeedbackMeta = if (!is.null(fb$meta)) {
        as.character(jsonlite::toJSON(fb$meta, auto_unbox = TRUE))
      } else {
        NA_character_
      },
      ConversationHistory = as.character(jsonlite::toJSON(conversation, auto_unbox = TRUE)),
      ResponseTime = elapsed_trial
    )
    if ("Item" %in% names(row)) row_list$Item <- row$Item
    if ("Condition" %in% names(row)) row_list$Condition <- row$Condition

    results[[trial_count]] <- as.data.frame(row_list, stringsAsFactors = FALSE, check.names = FALSE)

    # --------------------------
    # Progress bar update
    # --------------------------
    update_progress_bar(trial_count, max_trials, start_time, bar_width, model)

    # --------------------------
    # Early stop for replace_next
    # --------------------------
    if (apply_mode == "replace_next" && i >= orig_trials) break

    if (delay > 0) Sys.sleep(delay)
    i <- i + 1
  }

  cat("\nExperiment finished.\n")
  out_df <- dplyr::bind_rows(results)

  if (apply_mode == "insert_dynamic"){
  if ("Item" %in% colnames(out_df)) {
    out_df$Item <- NULL
  }}

  save_experiment_results(out_df, output_path, enable_thinking)
  return(out_df)
}
