test_that("registration credentials become reusable placeholders", {
  source <- list(
    headers = list(
      "Authorization" = "Bearer registration-secret",
      "Content-Type" = "application/json"
    ),
    body = list(api_key = "registration-secret", input = "hello")
  )

  templated <- template_registration_credential(
    source,
    "registration-secret"
  )

  expect_identical(
    templated$headers$Authorization,
    "Bearer ${API_KEY}"
  )
  expect_identical(templated$body$api_key, "${API_KEY}")
  expect_identical(source$headers$Authorization, "Bearer registration-secret")
  expect_false(grepl(
    "registration-secret",
    paste(capture.output(str(templated)), collapse = "\n"),
    fixed = TRUE
  ))
})

test_that("offline registration uses the unified user Registry path", {
  captured_path <- NULL
  expected_path <- file.path(tempdir(), "model_registry.yaml")

  local_mocked_bindings(
    get_registry_path = function() expected_path,
    register_endpoint_to_user_registry = function(entry, path) {
      captured_path <<- path
      invisible(entry)
    },
    .package = "PsyLingLLM"
  )

  invisible(capture.output(suppressMessages(register_endpoint_offline(
      model = "fixture-model",
      url = "https://example.invalid/v1/chat/completions",
      headers = list(Authorization = "Bearer ${API_KEY}"),
      body = list(model = "fixture-model"),
      auto_register = TRUE
    ))))

  expect_identical(captured_path, expected_path)
})

test_that("registration diagnostics and templates do not expose credentials", {
  captured_lines <- character()
  captured_analysis <- NULL
  captured_headers <- NULL
  secret <- "registration-secret"
  probe_result <- list(
    non_stream = list(
      status_code = 200L,
      parsed = list(message = paste("provider echoed", secret))
    ),
    stream_attempt = list(
      honored_streaming = FALSE,
      reason = "not requested",
      raw_df = NULL,
      raw_json = NULL
    )
  )

  local_mocked_bindings(
    normalize_provider_label = identity,
    probe_llm_streaming = function(...) probe_result,
    score_candidates_ns = function(...) {
      list(
        best = list(
          answer = list(
            path = c("message"),
            text = paste("provider echoed", secret)
          ),
          think = NULL
        ),
        candidates = data.frame()
      )
    },
    extract_usage_fields = function(...) character(),
    build_standardized_input = function(headers, body, ...) {
      list(
        headers_p2 = headers,
        body_p2 = body,
        diagnostics = list(default_system = NULL)
      )
    },
    make_pass2_probe_inputs = function(...) {
      list(
        headers = list(Authorization = paste("Bearer", secret)),
        body = list(model = "fixture-model")
      )
    },
    render_pass2_path_consistency_report = function(...) "consistent",
    probe_extract_error = function(...) NULL,
    infer_role_mapping_from_body = function(...) NULL,
    build_registry_entry_from_analysis = function(analysis, headers_input, ...) {
      captured_analysis <<- analysis
      captured_headers <<- headers_input
      list("fixture-model" = list(chat = list()))
    },
    format_registration_preview = function(...) "preview",
    cat_slowly = function(lines, ...) {
      captured_lines <<- c(captured_lines, lines)
      invisible()
    },
    .package = "PsyLingLLM"
  )

  result <- suppressMessages(llm_register(
    url = "https://example.invalid/v1/chat/completions",
    headers = list(Authorization = paste("Bearer", secret)),
    body = list(model = "fixture-model", input = "${CONTENT}"),
    api_key = secret,
    auto_register = FALSE
  ))

  rendered <- paste(
    c(
      captured_lines,
      capture.output(str(result)),
      capture.output(str(captured_analysis)),
      capture.output(str(captured_headers))
    ),
    collapse = "\n"
  )
  expect_false(grepl(secret, rendered, fixed = TRUE), info = rendered)
  expect_identical(captured_headers$Authorization, "Bearer ${API_KEY}")
  expect_match(rendered, "[REDACTED]", fixed = TRUE)
})

test_that("the default Registry path uses the standard R config directory", {
  expect_identical(
    get_registry_path(),
    file.path(
      tools::R_user_dir("PsyLingLLM", "config"),
      "model_registry.yaml"
    )
  )
  expect_identical(
    PsyLingLLM:::get_legacy_registry_path(),
    file.path(path.expand("~"), ".psylingllm", "model_registry.yaml")
  )
})

test_that("registration preserves malformed Registry files", {
  registry_path <- file.path(withr::local_tempdir(), "model_registry.yaml")
  writeLines(c("broken:", "  - [unclosed"), registry_path, useBytes = TRUE)
  before <- readBin(registry_path, "raw", n = file.info(registry_path)$size)
  entry <- yaml::read_yaml(test_path(
    "fixtures", "registry-v1-minimal.yaml"
  ))

  expect_error(
    register_endpoint_to_user_registry(entry, registry_path),
    class = "registry_load_error"
  )
  after <- readBin(registry_path, "raw", n = file.info(registry_path)$size)
  expect_identical(after, before)
})

test_that("the v1 registration writer rejects native Registry v2 files", {
  registry_path <- file.path(withr::local_tempdir(), "model_registry.yaml")
  file.copy(
    test_path("fixtures", "registry-v2-valid.yaml"),
    registry_path
  )
  before <- readBin(registry_path, "raw", n = file.info(registry_path)$size)
  entry <- yaml::read_yaml(test_path(
    "fixtures", "registry-v1-minimal.yaml"
  ))

  expect_error(
    register_endpoint_to_user_registry(entry, registry_path),
    "Registry v2"
  )
  after <- readBin(registry_path, "raw", n = file.info(registry_path)$size)
  expect_identical(after, before)
})

test_that("registration writes a validated v1 Registry through a temporary file", {
  registry_directory <- withr::local_tempdir()
  registry_path <- file.path(registry_directory, "model_registry.yaml")
  entry <- yaml::read_yaml(test_path(
    "fixtures", "registry-v1-minimal.yaml"
  ))

  result <- register_endpoint_to_user_registry(entry, registry_path)

  expect_true(file.exists(registry_path))
  expect_identical(yaml::read_yaml(registry_path), result)
  expect_false(any(grepl(
    "^\\.registry-",
    list.files(registry_directory, all.files = TRUE)
  )))
})
