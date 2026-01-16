library(testthat)

test_that("data_download errors when path does not exist", {
  fake_requested <- data.frame(download = character(0), id = integer(0))
  expect_error(
    data_download(
      requested_data = fake_requested,
      account_login = list(),
      path = "this_path_does_not_exist_12345"
    ),
    "Path does not exist"
  )
})
