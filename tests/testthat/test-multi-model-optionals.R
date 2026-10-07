test_that("multi-model experiments preserve explicit NULL optionals", {
  calls <- list()
  local_mocked_bindings(
    trial_experiment = function(...) {
      arguments <- list(...)
      calls[[length(calls) + 1L]] <<- arguments
      data.frame(
        Response = "ok",
        ModelName = arguments$model_key,
        stringsAsFactors = FALSE
      )
    },
    .package = "PsyLingLLM"
  )
  models <- data.frame(model_key = "fixture-model")
  materials <- data.frame(Material = "One trial")

  multi_model_experiment(models = models, data = materials)
  multi_model_experiment(
    models = models,
    data = materials,
    optionals = NULL
  )

  expect_false("optionals" %in% names(calls[[1L]]))
  expect_true("optionals" %in% names(calls[[2L]]))
  expect_null(calls[[2L]]$optionals)
})

test_that("combined multi-model results create their parent directory", {
  output_path <- file.path(
    withr::local_tempdir(),
    "combined",
    "results.csv"
  )

  result <- suppressMessages(multi_model_experiment(
    models = data.frame(model_key = character()),
    data = data.frame(Material = "fixture"),
    combined_output_path = output_path
  ))

  expect_true(file.exists(output_path))
  expect_equal(nrow(result), 0L)
})
