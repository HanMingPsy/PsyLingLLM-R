new_interface_resolution_error <- function(reason) {
  structure(
    list(message = reason, call = NULL, reason = reason),
    class = c("registry_resolution_error", "error", "condition")
  )
}

test_that("experiment interface selection prefers Registry defaults", {
  requested <- list()
  local_mocked_bindings(
    resolve_registry_entry = function(model_key,
                                      generation_interface = NULL,
                                      ...) {
      requested[length(requested) + 1L] <<- list(generation_interface)
      list(model = list(key = model_key))
    },
    .package = "PsyLingLLM"
  )

  expect_null(resolve_experiment_generation_interface("fixture", NULL))
  expect_identical(length(requested), 1L)
  expect_null(requested[[1L]])

  expect_identical(
    resolve_experiment_generation_interface("fixture", "responses"),
    "responses"
  )
  expect_identical(length(requested), 1L)
})

test_that("legacy ambiguous interfaces retain the historical chat fallback", {
  requested <- list()
  local_mocked_bindings(
    resolve_registry_entry = function(model_key,
                                      generation_interface = NULL,
                                      ...) {
      requested[length(requested) + 1L] <<- list(generation_interface)
      if (is.null(generation_interface)) {
        stop(new_interface_resolution_error("ambiguous_interface"))
      }
      if (!identical(generation_interface, "chat")) {
        stop(new_interface_resolution_error("interface_not_found"))
      }
      list(model = list(key = model_key))
    },
    .package = "PsyLingLLM"
  )

  expect_identical(
    resolve_experiment_generation_interface("legacy-multi", NULL),
    "chat"
  )
  expect_length(requested, 2L)
  expect_null(requested[[1L]])
  expect_identical(requested[[2L]], "chat")
})

test_that("invalid Registry sources are not hidden by interface fallback", {
  load_error <- structure(
    list(message = "invalid user Registry", call = NULL),
    class = c("registry_load_error", "error", "condition")
  )
  local_mocked_bindings(
    resolve_registry_entry = function(...) stop(load_error),
    .package = "PsyLingLLM"
  )

  expect_error(
    resolve_experiment_generation_interface("fixture", NULL),
    class = "registry_load_error"
  )
})

test_that("trial experiments forward automatic and explicit interfaces", {
  seen_validation <- list()
  seen_caller <- list()
  output_directory <- withr::local_tempdir()

  local_mocked_bindings(
    resolve_experiment_generation_interface = function(model_key,
                                                       generation_interface) {
      generation_interface
    },
    load_registry = function() list(),
    validate_experiment_config = function(...) {
      arguments <- list(...)
      seen_validation[length(seen_validation) + 1L] <<-
        list(arguments$generation_interface)
      invisible(TRUE)
    },
    resolve_output_and_log = function(output_path, model) {
      list(
        result_file = file.path(output_directory, paste0(model, ".csv")),
        log_file = file.path(output_directory, paste0(model, ".log"))
      )
    },
    write_experiment_log = function(...) invisible(TRUE),
    update_progress_bar = function(...) invisible(TRUE),
    finish_progress_bar = function(...) invisible(TRUE),
    save_experiment_results = function(...) invisible(TRUE),
    llm_caller = function(...) {
      arguments <- list(...)
      seen_caller[length(seen_caller) + 1L] <<-
        list(arguments$generation_interface)
      list(
        status = 200L,
        answer = "Y",
        thinking = NULL,
        first_token_latency = NA_real_,
        usage = list(prompt = 1L, completion = 1L, id = "request-1"),
        streaming = FALSE,
        error = NULL
      )
    },
    .package = "PsyLingLLM"
  )

  trial_experiment(
    model_key = "auto-model",
    api_key = "fixture-key",
    data = data.frame(Material = "Fixture")
  )
  trial_experiment(
    model_key = "explicit-model",
    generation_interface = "responses",
    api_key = "fixture-key",
    data = data.frame(Material = "Fixture")
  )

  expect_null(seen_validation[[1L]])
  expect_null(seen_caller[[1L]])
  expect_identical(seen_validation[[2L]], "responses")
  expect_identical(seen_caller[[2L]], "responses")
})

test_that("bundled experiment defaults execute Chat and Responses offline", {
  output_directory <- withr::local_tempdir()
  missing_user <- file.path(output_directory, "missing-user.yaml")
  missing_legacy <- file.path(output_directory, "missing-legacy.yaml")
  chat_payload <- jsonlite::fromJSON(
    test_path("fixtures", "openai-chat-nonstream.json"),
    simplifyVector = FALSE
  )
  responses_payload <- jsonlite::fromJSON(
    test_path("fixtures", "openai-responses-nonstream.json"),
    simplifyVector = FALSE
  )
  seen_urls <- character()

  local_mocked_bindings(
    get_registry_path = function() missing_user,
    get_legacy_registry_path = function() missing_legacy,
    do_nonstream_request = function(url, headers, json_payload, timeout, debug) {
      seen_urls <<- c(seen_urls, url)
      parsed <- if (grepl("/responses$", url)) {
        responses_payload
      } else {
        chat_payload
      }
      list(
        status = 200L,
        text = jsonlite::toJSON(parsed, auto_unbox = TRUE, null = "null"),
        parsed = parsed,
        error = NULL
      )
    },
    update_progress_bar = function(...) invisible(TRUE),
    finish_progress_bar = function(...) invisible(TRUE),
    .package = "PsyLingLLM"
  )

  material <- data.frame(Material = "Offline fixture")
  deepseek <- suppressMessages(trial_experiment(
    model_key = "deepseek-flash",
    api_key = "TEST_TOKEN_PLACEHOLDER",
    data = material,
    optionals = NULL,
    output_path = file.path(output_directory, "deepseek.csv")
  ))
  openai <- suppressMessages(trial_experiment(
    model_key = "gpt-5.6-luna",
    api_key = "TEST_TOKEN_PLACEHOLDER",
    data = material,
    optionals = NULL,
    output_path = file.path(output_directory, "openai.csv")
  ))

  expect_identical(deepseek$TrialStatus, "SUCCESS")
  expect_identical(openai$TrialStatus, "SUCCESS")
  expect_true(any(grepl("/chat/completions$", seen_urls)))
  expect_true(any(grepl("/responses$", seen_urls)))
})
