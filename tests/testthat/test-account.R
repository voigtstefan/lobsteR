test_that("account_login returns expected structure when rvest calls succeed (stubbed)", {
  testthat::with_mocked_bindings(
    session = function(url) structure(list(url = url), class = "session"),
    html_form = function(x) list(list()), # one empty form
    html_form_set = function(form, login, pwd) form, # return the form unchanged
    session_submit = function(x, form, submit, add_headers) {
      list(url = "https://data.lobsterdata.com/requestdata.php")
    },
    add_headers = function(...) NULL,
    .env = asNamespace("lobsteR"),
    {
      acct <- account_login("fake@example.com", "pw")
      expect_type(acct, "list")
      expect_true(is.logical(acct$valid))
      expect_true(acct$valid)
      expect_named(acct, c("valid", "session", "submission"))
    }
  )
})

test_that("account_archive parses archive table and filters zero-size rows", {
  html_fixture <- '
  <html>
    <body>
      <table>
        <thead>
          <tr>
            <th>Name</th>
            <th>Download</th>
            <th>Start Date</th>
            <th>End Date</th>
            <th>Level</th>
            <th>Size</th>
            <th>Delete</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td>file0</td>
            <td><a href="download.php?id=1">SYM0</a></td>
            <td>2020-01-01</td>
            <td>2020-01-01</td>
            <td>1</td>
            <td>0</td>
            <td>del</td>
          </tr>
          <tr>
            <td>file1</td>
            <td><a href="download.php?id=2">AAPL</a></td>
            <td>2020-01-02</td>
            <td>2020-01-02</td>
            <td>1</td>
            <td>100</td>
            <td>del</td>
          </tr>
        </tbody>
      </table>
    </body>
  </html>
  '

  # stub the package's session_jump_to to return an xml document built from html_fixture
  testthat::with_mocked_bindings(
    session_jump_to = function(x, url) xml2::read_html(html_fixture),
    .env = asNamespace("lobsteR"),
    {
      fake_login <- list(valid = TRUE, submission = NULL)
      res <- account_archive(fake_login)

      # expected: zero-size row removed, single row remaining
      expect_s3_class(res, "data.frame")
      expect_equal(nrow(res), 1L)

      # columns: id first then symbol, start_date, end_date, level, size, download
      expect_equal(names(res)[1], "id")
      expect_true("symbol" %in% names(res))
      expect_true("download" %in% names(res))

      # types and values
      expect_true(inherits(res$start_date, "Date"))
      expect_true(inherits(res$end_date, "Date"))
      expect_true(is.integer(res$id) || is.numeric(res$id))
      expect_equal(as.integer(res$id[1]), 2L)
      expect_equal(res$symbol[1], "AAPL")
      expect_equal(as.integer(res$size[1]), 100L)
      expect_true(grepl("^https?://lobsterdata\\.com/", res$download[1]))
    }
  )
})
