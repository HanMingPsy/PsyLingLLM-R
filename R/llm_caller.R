#' LLM API Caller with integrated prompt preparation
#'
#' Call a large language model (LLM) API and return parsed output,
#' automatically handling model-specific fast/thinking modes.
#' Supports optional conversation history.
#'
#' @param model Model name
#' @param trial_prompt Trial prompt text (used if conversation is NULL)
#' @param material Trial material text (used if conversation is NULL)
#' @param conversation Optional list of messages with roles and content for conversation history
#'        e.g., list(list(role="user", content="Hello"), list(role="assistant", content="Hi"))
#' @param api_key API key
#' @param api_url API endpoint
#' @param custom Optional role mapping (default: user/system/assistant)
#' @param max_tokens Maximum number of tokens to generate
#' @param temperature Sampling temperature
#' @param enable_thinking Boolean, whether to enable CoT reasoning
#' @return List with parsed output: model, think, response
#' @export
llm_caller <- function(model,
                       trial_prompt = NULL,
                       material = NULL,
                       conversation = NULL,
                       api_key,
                       api_url,
                       custom = list(user="user", system="system", assistant="assistant"),
                       system_prompt = "You are a participant in a psychology experiment.",
                       max_tokens = 1024,
                       temperature = 0.7,
                       enable_thinking = TRUE) {

  role_system <- custom$system %||% "system"
  role_user   <- custom$user %||% "user"

  # Prepare messages
  if (!is.null(conversation)) {
    # Use conversation history
    messages <- conversation
  } else {
    # Single trial prompt
    user_content <- prepare_prompt(model, trial_prompt %||% "", material %||% "", enable_thinking)
    messages <- list(
      list(role = role_system, content = system_prompt),
      list(role = role_user, content = user_content)
    )
  }

  # Construct request body
  body_list <- list(
    model = model,
    messages = messages,
    max_tokens = max_tokens,
    temperature = temperature
  )

  body_list <- adapt_model_request(model, body_list, enable_thinking)

  # Send request
  resp <- httr2::request(api_url) |>
    httr2::req_headers(
      "Authorization" = paste("Bearer", api_key),
      "Content-Type" = "application/json"
    ) |>
    httr2::req_body_json(body_list) |>
    httr2::req_perform()

  resp_body <- httr2::resp_body_json(resp)

  # Parse output
  parsed <- parse_output(model, resp_body)

  return(parsed)
}

