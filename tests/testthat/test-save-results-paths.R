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
