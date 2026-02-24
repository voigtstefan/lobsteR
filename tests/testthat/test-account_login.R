library(testthat)

test_that("account_login returns expected structure with mocked rvest", {
  # mock network / rvest calls used inside account_login
  testthat::local_mocked_bindings(
    session = function(url) list(url = url),
    html_form = function(x) list(list()),
    html_form_set = function(form, ...) list(login = list(...)),
    session_submit = function(x, form, submit, add_headers) {
      list(url = "https://data.lobsterdata.com/requestdata.php")
    },
    are_equal = function(x, y) identical(x, y),
    .env = asNamespace("lobsteR")
  )

  res <- account_login("user@example.com", "pwd")

  expect_type(res, "list")
  expect_named(res, c("valid", "session", "submission"))
  expect_true(is.logical(res$valid))
  expect_true(res$valid)
})
