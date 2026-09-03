make_request_builder_entry <- function(provider = "official",
                                       streaming = FALSE,
                                       role_template = TRUE) {
  if (role_template) {
    body <- list(
      model = "fixture-model",
      messages = list(
        list(role = "${ROLE}", content = "${CONTENT}")
      )
    )
  } else {
    body <- list(model = "fixture-model", input = "${CONTENT}")
  }
  body[["${PARAMETER}"]] <- "${VALUE}"

  list(
    model_key = "fixture-model",
    interface = "chat",
    provider = provider,
    input = list(
      default_url = "https://example.invalid/v1/chat/completions",
      headers = list(
        `Content-Type` = "application/json",
        Authorization = "Bearer ${API_KEY}"
      ),
      body = body,
      optional_defaults = list(temperature = 0.2, stream = FALSE),
      default_system = "Default system message."
    ),
    streaming = list(
      enabled = streaming,
      param_name = "stream"
    )
  )
}

make_request_context <- function(optionals_missing = TRUE,
                                 optionals_value = NULL,
                                 stream = NULL,
                                 role_mapping = NULL,
                                 api_key = NULL,
                                 api_url = NULL,
                                 system_content = NULL,
                                 assistant_content = NULL) {
  new_llm_call_context(
    trial_prompt = "Instruction",
    material = "Material",
    system_content = system_content,
    assistant_content = assistant_content,
    api_key = api_key,
    optionals_missing = optionals_missing,
    optionals_value = optionals_value,
    stream = stream,
    role_mapping = role_mapping,
    api_url = api_url,
    timeout = 45
  )
}

test_that("legacy builder returns a transport-neutral request", {
  request <- build_llm_request(
    "legacy_template_v1",
    make_request_builder_entry(),
    make_request_context()
  )

  expect_s3_class(request, "psylingllm_request")
  expect_named(
    request,
    c(
      "method", "url", "headers", "body", "encoding", "stream",
      "transport_id", "timeout"
    )
  )
  expect_identical(request$method, "POST")
  expect_identical(request$encoding, "json")
  expect_identical(request$transport_id, "http_json")
  expect_identical(request$timeout, 45)
  expect_false(request$stream)
})

test_that("legacy builder preserves message ordering and role mapping", {
  context <- make_request_context(
    role_mapping = list(
      system = "developer",
      user = "human",
      assistant = "model"
    ),
    assistant_content = list(
      list(role = "user", content = "Earlier question"),
      list(role = "assistant", content = "Earlier answer")
    )
  )
  request <- build_llm_request(
    "legacy_template_v1",
    make_request_builder_entry(),
    context
  )

  expect_identical(
    vapply(request$body$messages, `[[`, character(1), "role"),
    c("developer", "human", "model", "human")
  )
  expect_identical(
    vapply(request$body$messages, `[[`, character(1), "content"),
    c(
      "Default system message.",
      "Earlier question",
      "Earlier answer",
      "Instruction\n\nMaterial"
    )
  )
})

test_that("legacy builder preserves all three optionals states", {
  entry <- make_request_builder_entry()
  missing_request <- build_llm_request(
    "legacy_template_v1",
    entry,
    make_request_context(optionals_missing = TRUE)
  )
  null_request <- build_llm_request(
    "legacy_template_v1",
    entry,
    make_request_context(optionals_missing = FALSE)
  )
  named_request <- build_llm_request(
    "legacy_template_v1",
    entry,
    make_request_context(
      optionals_missing = FALSE,
      optionals_value = list(top_p = 0.9)
    )
  )

  expect_identical(missing_request$body$temperature, 0.2)
  expect_identical(missing_request$body$stream, FALSE)
  expect_true("${PARAMETER}" %in% names(null_request$body))
  expect_false("temperature" %in% names(null_request$body))
  expect_identical(named_request$body$top_p, 0.9)
  expect_false("temperature" %in% names(named_request$body))
  expect_false("${PARAMETER}" %in% names(named_request$body))
})

test_that("legacy builder preserves stream precedence", {
  entry <- make_request_builder_entry(streaming = TRUE)
  explicit_false <- build_llm_request(
    "legacy_template_v1",
    entry,
    make_request_context(
      optionals_missing = FALSE,
      optionals_value = list(stream = TRUE),
      stream = FALSE
    )
  )
  optional_true <- build_llm_request(
    "legacy_template_v1",
    entry,
    make_request_context(
      optionals_missing = FALSE,
      optionals_value = list(stream = TRUE)
    )
  )

  expect_false(explicit_false$stream)
  expect_identical(explicit_false$transport_id, "http_json")
  expect_true(optional_true$stream)
  expect_identical(optional_true$body$stream, TRUE)
  expect_identical(optional_true$transport_id, "sse_json")
})

test_that("role-less templates retain content substitution and warning", {
  entry <- make_request_builder_entry(role_template = FALSE)

  expect_warning(
    request <- build_llm_request(
      "legacy_template_v1",
      entry,
      make_request_context(system_content = "Ignored system")
    ),
    "Template has no ${ROLE}",
    fixed = TRUE
  )
  expect_identical(request$body$input, "Instruction\n\nMaterial")
})

test_that("placeholder substitution does not modify the registry entry", {
  entry <- make_request_builder_entry()
  original <- entry
  request <- build_llm_request(
    "legacy_template_v1",
    entry,
    make_request_context(api_key = "TEST_TOKEN_PLACEHOLDER")
  )

  expect_identical(entry, original)
  expect_identical(
    request$headers$Authorization,
    "Bearer TEST_TOKEN_PLACEHOLDER"
  )
})

test_that("legacy builder preserves explicit URL override requirements", {
  entry <- make_request_builder_entry(provider = "fixture-proxy")

  expect_error(
    build_llm_request(
      "legacy_template_v1",
      entry,
      make_request_context()
    ),
    "Non-official provider requires api_url"
  )
  request <- build_llm_request(
    "legacy_template_v1",
    entry,
    make_request_context(api_url = "https://proxy.invalid/chat")
  )
  expect_identical(request$url, "https://proxy.invalid/chat")
})

test_that("builder dispatcher rejects unknown component IDs", {
  condition <- tryCatch(
    build_llm_request(
      "unregistered_builder",
      make_request_builder_entry(),
      make_request_context()
    ),
    llm_request_builder_error = identity
  )

  expect_s3_class(condition, "llm_request_builder_error")
  expect_identical(condition$reason, "unknown_builder")
  expect_identical(condition$builder_id, "unregistered_builder")
  expect_match(condition$message, "legacy_template_v1", fixed = TRUE)
})

test_that("request validation rejects invalid builder output", {
  request <- build_llm_request(
    "legacy_template_v1",
    make_request_builder_entry(),
    make_request_context()
  )
  request$timeout <- -1

  expect_error(
    validate_llm_request(request, "legacy_template_v1"),
    class = "llm_request_builder_error"
  )
})
