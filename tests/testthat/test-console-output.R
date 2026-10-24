test_that("progress output can be suppressed", {
  expect_silent(suppressMessages({
    value <- update_progress_bar(
      current = 1,
      total = 1,
      start_time = Sys.time(),
      model_name = "test-model"
    )
  }))

  expect_null(value)
})

test_that("slow console messages can be suppressed", {
  expect_silent(
    suppressMessages(cat_slowly("Preview", delay = 0, final_delay = 0))
  )
})
