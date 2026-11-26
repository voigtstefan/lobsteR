library(testthat)

# The tests mock only session_jump_to() and parse real HTML: mocks of the
# rvest functions that lobsteR imports (html_table(), html_nodes(),
# html_attr()) are not undone after a test under pkgload and leak into later
# test files.

test_that("account_archive errors for invalid login", {
  expect_error(account_archive(list(valid = FALSE)), regexp = "TRUE")
})

test_that("account_archive parses an archive page", {
  testthat::skip_if_not_installed("xml2")
  page <- '
  <html><body>
    <table>
      <thead><tr>
        <th>Name</th><th>Download</th><th>Start Date</th><th>End Date</th>
        <th>Level</th><th>Size</th><th>Delete</th>
      </tr></thead>
      <tbody><tr>
        <td>file</td><td><a href="download.php?id=42">SPY</a></td>
        <td>2023-01-03</td><td>2023-01-03</td><td>1</td><td>12345</td><td>del</td>
      </tr></tbody>
    </table>
  </body></html>'
  testthat::local_mocked_bindings(
    session_jump_to = function(x, url) xml2::read_html(page),
    .env = asNamespace("lobsteR")
  )

  res <- account_archive(list(valid = TRUE, submission = list()))

  expect_s3_class(res, "data.frame")
  expect_equal(res$id[1], 42L)
  expect_equal(res$symbol[1], "SPY")
  expect_equal(res$start_date[1], as.Date("2023-01-03"))
})

test_that("account_archive returns no rows for an empty archive", {
  testthat::skip_if_not_installed("xml2")
  # The page of an empty archive holds only the site's layout tables
  page <- '
  <html><body>
    <p>an empty archive.</p>
    <table><tr><td>main.</td><td>resources.</td><td>help.</td><td>partner.</td></tr>
      <tr><td></td></tr></table>
    <table><tr><td></td></tr></table>
  </body></html>'
  testthat::local_mocked_bindings(
    session_jump_to = function(x, url) xml2::read_html(page),
    .env = asNamespace("lobsteR")
  )

  res <- account_archive(list(valid = TRUE, submission = list()))

  expect_s3_class(res, "data.frame")
  expect_equal(nrow(res), 0)
  expect_equal(
    colnames(res),
    c("id", "symbol", "start_date", "end_date", "level", "size", "download")
  )
  expect_s3_class(res$start_date, "Date")
})
