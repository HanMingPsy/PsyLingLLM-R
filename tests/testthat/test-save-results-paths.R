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

test_that("Excel output stays flat unless an RDS archive is requested", {
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

  expect_identical(readxl::excel_sheets(output_path), "Results")
  flat <- readxl::read_xlsx(output_path, sheet = "Results")
  expect_true("FirstTokenLatency" %in% names(flat))
  expect_false("raw" %in% names(flat))
  expect_identical(result$raw, original_raw)
})

test_that("RDS archives use compact row indexes and one metadata table", {
  skip_if_not_installed("readxl")
  output_directory <- withr::local_tempdir()
  result <- data.frame(
    TrialKey = c("trial-1", "trial-2"),
    Response = c("Y", "N"),
    RequestID = c("request-1", NA_character_),
    stringsAsFactors = FALSE
  )
  result$raw <- list(
    list(
      request = list(headers = list(Authorization = "Bearer secret-value")),
      response = list(non_stream = list(parsed = list(
        usage = list(reasoning_tokens = 4L),
        choices = list(list(logprobs = list(content = list(list(
          token = "Y",
          logprob = -0.1,
          top_logprobs = list(list(token = "Y", logprob = -0.1))
        )))))
      )))
    ),
    NULL
  )
  output_path <- file.path(output_directory, "results.xlsx")
  raw_output_path <- file.path(output_directory, "results_with_raw.rds")

  suppressMessages(save_experiment_results(
    result,
    output_path,
    raw_output_path = raw_output_path
  ))

  expect_identical(
    readxl::excel_sheets(output_path),
    c("Results", "RawIndex", "RawMetadata")
  )
  index <- readxl::read_xlsx(output_path, sheet = "RawIndex")
  expect_identical(
    names(index),
    c("ResultRow", "RawRecordIndex", "RawAvailable", "RawPath")
  )
  expect_identical(index$ResultRow, c(1, 2))
  expect_identical(index$RawRecordIndex, c(1, 2))
  expect_identical(index$RawAvailable, c(TRUE, FALSE))
  expect_identical(index$RawPath, c("raw[[1]]", "raw[[2]]"))
  metadata <- readxl::read_xlsx(output_path, sheet = "RawMetadata")
  expect_identical(names(metadata), c("Field", "Value"))
  metadata_values <- stats::setNames(metadata$Value, metadata$Field)
  expect_identical(
    metadata_values[["RawArtifact"]],
    basename(raw_output_path)
  )
  expect_identical(metadata_values[["ArchiveFormat"]], "RDS")
  expect_identical(
    metadata_values[["RawSchemaVersion"]],
    "psylingllm.raw.v1"
  )
  expect_match(metadata_values[["ArchiveObject"]], "list-column")
  expect_match(metadata_values[["SupportedValueTypes"]], "raw")
  expect_match(metadata_values[["SupportedValueTypes"]], "POSIXct")
  expect_match(metadata_values[["AnalysisFunctions"]], "get_trial_raw")

  archive <- readRDS(raw_output_path)
  expect_identical(nrow(archive), 2L)
  expect_length(archive$raw, 2L)
  rendered <- jsonlite::toJSON(archive$raw, auto_unbox = TRUE, null = "null")
  expect_false(grepl("secret-value", rendered, fixed = TRUE))
  expect_true(grepl("[REDACTED]", rendered, fixed = TRUE))
  expect_identical(
    attr(archive, "psylingllm_raw_schema_version"),
    "psylingllm.raw.v1"
  )
  expect_identical(attr(archive, "psylingllm_archive_format"), "RDS")
  expect_true(
    "raw" %in% attr(archive, "psylingllm_supported_value_types")
  )
  expect_identical(result$raw[[1L]]$request$headers$Authorization,
                   "Bearer secret-value")
})

test_that("RAW archive validation fails before writing invalid artifacts", {
  output_directory <- withr::local_tempdir()
  result <- data.frame(Response = "Y")

  expect_error(
    save_experiment_results(
      result,
      file.path(output_directory, "results.csv"),
      raw_output_path = file.path(output_directory, "raw.rds")
    ),
    "return_raw = TRUE"
  )
  result$raw <- list(list(response = list(parsed = list())))
  expect_error(
    save_experiment_results(
      result,
      file.path(output_directory, "results.csv"),
      raw_output_path = file.path(output_directory, "raw.csv")
    ),
    "rds",
    ignore.case = TRUE
  )
})
