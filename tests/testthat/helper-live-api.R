live_api_enabled <- function() {
  identical(tolower(Sys.getenv("PSYLINGLLM_LIVE_API_TESTS")), "true")
}

live_api_load_environment <- function() {
  if (!live_api_enabled()) {
    return(invisible(FALSE))
  }
  env_file <- testthat::test_path("..", "..", "API.Renviron")
  if (file.exists(env_file)) {
    readRenviron(env_file)
  }
  invisible(TRUE)
}

live_api_require <- function(variables) {
  testthat::skip_on_cran()
  testthat::skip_if_not(
    live_api_enabled(),
    "Set PSYLINGLLM_LIVE_API_TESTS=true to run live API tests."
  )
  live_api_load_environment()
  missing <- variables[!nzchar(Sys.getenv(variables))]
  testthat::skip_if(
    length(missing) > 0L,
    paste("Missing live-test setting(s):", paste(missing, collapse = ", "))
  )
}

live_api_registry <- function() {
  qwen_openai_url <- Sys.getenv(
    "QWEN_OPENAI_BASE_URL",
    unset = "https://qwen-openai.example.invalid/v1"
  )
  qwen_anthropic_url <- Sys.getenv(
    "QWEN_ANTHROPIC_BASE_URL",
    unset = "https://qwen-anthropic.example.invalid"
  )

  list(
    schema_version = 2L,
    providers = list(
      live_openai = list(
        type = "official",
        base_url = "https://api.openai.com/v1",
        auth = list(scheme = "bearer", env_var = "OPENAI_API_KEY"),
        headers = list(`Content-Type` = "application/json")
      ),
      live_deepseek = list(
        type = "official",
        base_url = "https://api.deepseek.com",
        auth = list(scheme = "bearer", env_var = "DEEPSEEK_API_KEY"),
        headers = list(`Content-Type` = "application/json")
      ),
      live_qwen_openai = list(
        type = "official",
        base_url = qwen_openai_url,
        auth = list(scheme = "bearer", env_var = "QWEN_API_KEY"),
        headers = list(`Content-Type` = "application/json")
      ),
      live_qwen_anthropic = list(
        type = "official",
        base_url = qwen_anthropic_url,
        auth = list(
          scheme = "header",
          header = "x-api-key",
          env_var = "QWEN_API_KEY"
        ),
        headers = list(
          `Content-Type` = "application/json",
          `anthropic-version` = "2023-06-01"
        )
      )
    ),
    interfaces = list(
      live_openai_responses = list(
        protocol = "openai_responses",
        request = list(
          builder = "openai_responses",
          method = "POST",
          encoding = "json",
          path = "/responses",
          parameters = list(
            max_output_tokens = list(description = "Native output limit."),
            reasoning = list(description = "Native reasoning configuration.")
          )
        ),
        transport = list(non_stream = "http_json", stream = "sse_json"),
        response = list(parser = "openai_responses"),
        streaming = list(
          supported = TRUE,
          request_parameter = "stream",
          request_value = TRUE
        ),
        metadata = list(legacy_interface = "responses")
      ),
      live_openai_chat = list(
        protocol = "openai_chat",
        request = list(
          builder = "openai_chat",
          method = "POST",
          encoding = "json",
          path = "/chat/completions",
          parameters = list(
            max_tokens = list(description = "Native output limit."),
            enable_thinking = list(description = "Qwen thinking switch.")
          )
        ),
        transport = list(non_stream = "http_json", stream = "sse_json"),
        response = list(parser = "openai_chat"),
        streaming = list(
          supported = TRUE,
          request_parameter = "stream",
          request_value = TRUE
        ),
        capabilities = list(
          reasoning = list(response_channel = "reasoning")
        ),
        metadata = list(legacy_interface = "chat")
      ),
      live_anthropic_messages = list(
        protocol = "anthropic_messages",
        request = list(
          builder = "anthropic_messages",
          method = "POST",
          encoding = "json",
          path = "/v1/messages",
          parameters = list(
            max_tokens = list(description = "Native output limit."),
            thinking = list(description = "Native thinking configuration.")
          )
        ),
        transport = list(non_stream = "http_json", stream = "sse_json"),
        response = list(parser = "anthropic_messages"),
        streaming = list(
          supported = TRUE,
          request_parameter = "stream",
          request_value = TRUE
        ),
        metadata = list(legacy_interface = "chat")
      )
    ),
    capabilities = list(
      reasoning = list(value_type = "logical", default = FALSE),
      streaming = list(value_type = "logical", default = FALSE)
    ),
    models = list(
      live_openai = list(
        provider = "live_openai",
        model_id = Sys.getenv("OPENAI_TEST_MODEL", unset = "gpt-5.6-luna"),
        interfaces = list("live_openai_responses"),
        default_interface = "live_openai_responses",
        capabilities = list(reasoning = TRUE, streaming = TRUE)
      ),
      live_deepseek = list(
        provider = "live_deepseek",
        model_id = Sys.getenv("DEEPSEEK_TEST_MODEL", unset = "deepseek-flash"),
        interfaces = list("live_openai_chat"),
        default_interface = "live_openai_chat",
        capabilities = list(reasoning = TRUE, streaming = TRUE)
      ),
      live_qwen_openai = list(
        provider = "live_qwen_openai",
        model_id = Sys.getenv("QWEN_TEST_MODEL", unset = "qwen3.8-flash"),
        interfaces = list("live_openai_chat"),
        default_interface = "live_openai_chat",
        capabilities = list(reasoning = TRUE, streaming = TRUE)
      ),
      live_qwen_anthropic = list(
        provider = "live_qwen_anthropic",
        model_id = Sys.getenv("QWEN_TEST_MODEL", unset = "qwen3.8-flash"),
        interfaces = list("live_anthropic_messages"),
        default_interface = "live_anthropic_messages",
        capabilities = list(reasoning = TRUE, streaming = TRUE)
      )
    )
  )
}

live_api_registry_path <- function(.local_envir = parent.frame()) {
  directory <- withr::local_tempdir(.local_envir = .local_envir)
  path <- file.path(directory, "live-registry.yaml")
  yaml::write_yaml(live_api_registry(), path)
  path
}

live_api_use_registry <- function() {
  local_envir <- parent.frame()
  registry_path <- live_api_registry_path(.local_envir = local_envir)
  testthat::local_mocked_bindings(
    get_registry_path = function() registry_path,
    .package = "PsyLingLLM",
    .env = local_envir
  )
  invisible(registry_path)
}

live_api_use_openai_proxy <- function() {
  proxy <- Sys.getenv("OPENAI_HTTPS_PROXY")
  if (nzchar(proxy)) {
    withr::local_envvar(
      c(https_proxy = proxy, HTTPS_PROXY = proxy),
      .local_envir = parent.frame()
    )
  }
  invisible(proxy)
}

expect_live_success <- function(result, api_key, streaming) {
  testthat::expect_identical(result$status, 200L)
  testthat::expect_identical(result$streaming, streaming)
  testthat::expect_true(is.character(result$answer) && nzchar(result$answer))
  testthat::expect_true(is.list(result$usage))
  serialized <- jsonlite::toJSON(result, auto_unbox = TRUE, null = "null")
  testthat::expect_false(grepl(api_key, serialized, fixed = TRUE))
}
