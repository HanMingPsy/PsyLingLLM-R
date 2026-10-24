test_that("explicit output paths do not initialize the default result directory", {
  fake_default <- file.path(withr::local_tempdir(), "default-results")
  output_directory <- withr::local_tempdir()
  local_mocked_bindings(
    default_results_directory = function() fake_default,
    .package = "PsyLingLLM"
  )

  paths <- PsyLingLLM:::resolve_output_and_log(
    output_path = output_directory,
    model = "fixture-model"
  )
  saved <- suppressMessages(save_experiment_results(
    data = data.frame(Response = "ok"),
    output_path = file.path(output_directory, "explicit.csv")
  ))

  expect_false(dir.exists(fake_default))
  expect_true(startsWith(paths$result_file, output_directory))
  expect_true(file.exists(saved))
})

test_that("default results use the standard R user-data directory", {
  expect_identical(
    PsyLingLLM:::default_results_directory(),
    file.path(tools::R_user_dir("PsyLingLLM", "data"), "results")
  )
})

test_that("saving to a new directory creates it and returns an existing file", {
  output_directory <- file.path(withr::local_tempdir(), "new-results")

  saved <- suppressMessages(save_experiment_results(
    data = data.frame(Response = "ok"),
    output_path = output_directory,
    model = "fixture-model"
  ))

  expect_true(dir.exists(output_directory))
  expect_true(file.exists(saved))
  expect_true(startsWith(saved, normalizePath(output_directory)))
})

test_that("result write failures are errors and do not report a false path", {
  blocker <- tempfile()
  writeLines("not a directory", blocker)
  output_path <- file.path(blocker, "results.csv")

  expect_error(
    suppressWarnings(save_experiment_results(
      data = data.frame(Response = "ok"),
      output_path = output_path
    )),
    "directory|write|file",
    ignore.case = TRUE
  )
  expect_false(file.exists(output_path))
})

test_that("flat result files retain standard columns and exclude RAW", {
  output_directory <- withr::local_tempdir()
  result <- data.frame(
    Response = "Y",
    FirstTokenLatency = NA_real_,
    RequestID = "request-1",
    stringsAsFactors = FALSE
  )
  result$raw <- list(list(
    request = list(headers = list(Authorization = "Bearer secret-value")),
    response = list(parsed = list(answer = "Y"))
  ))
  output_path <- file.path(output_directory, "results.csv")

  suppressMessages(save_experiment_results(result, output_path))
  restored <- readr::read_csv(output_path, show_col_types = FALSE)

  expect_true("FirstTokenLatency" %in% names(restored))
  expect_false("raw" %in% names(restored))
})

test_that("Excel output adds a redacted path-based RAW sheet", {
  skip_if_not_installed("readxl")
  output_directory <- withr::local_tempdir()
  result <- data.frame(
    Response = c("Y", "N"),
    FirstTokenLatency = c(NA_real_, NA_real_),
    RequestID = c("request-1", NA_character_),
    stringsAsFactors = FALSE
  )
  original_raw <- list(
    list(
      request = list(headers = list(Authorization = "Bearer secret-value")),
      response = list(parsed = list(
        usage = list(reasoning_tokens = 4L),
        logprobs = list(content = list(list(token = "Y", logprob = -0.1)))
      ))
    ),
    NULL
  )
  result$raw <- original_raw
  output_path <- file.path(output_directory, "results.xlsx")

  suppressMessages(save_experiment_results(result, output_path))

  expect_identical(readxl::excel_sheets(output_path), c("Results", "Raw"))
  flat <- readxl::read_xlsx(output_path, sheet = "Results")
  raw <- readxl::read_xlsx(output_path, sheet = "Raw")
  expect_true("FirstTokenLatency" %in% names(flat))
  expect_false("raw" %in% names(flat))
  expect_true(all(c(
    "ResultRow", "RequestID", "FieldPath", "ValueType",
    "ValueEncoding", "ValueChunk", "ValueChunks", "Value"
  ) %in% names(raw)))
  expect_true(any(raw$FieldPath == "$response$parsed$usage$reasoning_tokens"))
  expect_true(any(raw$FieldPath == "$response$parsed$logprobs$content[1]$token"))
  expect_true(any(raw$Value == '"[REDACTED]"', na.rm = TRUE))
  expect_false(any(grepl("secret-value", raw$Value, fixed = TRUE), na.rm = TRUE))
  expect_identical(result$raw, original_raw)
})

test_that("large RAW projections continue onto numbered sheets", {
  raw <- data.frame(
    ResultRow = 1:5,
    RequestID = NA_character_,
    FieldPath = paste0("$value[", 1:5, "]"),
    ValueType = "integer",
    ValueEncoding = "scalar",
    ValueChunk = 1L,
    ValueChunks = 1L,
    Value = as.character(1:5),
    stringsAsFactors = FALSE
  )

  sheets <- PsyLingLLM:::split_raw_sheets(raw, max_excel_rows = 3L)

  expect_identical(names(sheets), c("Raw", "Raw_2", "Raw_3"))
  expect_identical(unname(vapply(sheets, nrow, integer(1))), c(2L, 2L, 1L))
  expect_identical(do.call(rbind, unname(sheets))$Value, raw$Value)
})
