test_that("request_query expands ranges and respects validate = FALSE", {
  res <- request_query(
    "AAPL",
    "2021-01-01",
    "2021-01-03",
    level = 2,
    validate = FALSE
  )
  expect_s3_class(res, "data.frame")
  expect_equal(nrow(res), 3L)
  expect_equal(
    as.character(res$start_date),
    c("2021-01-01", "2021-01-02", "2021-01-03")
  )
  expect_true(all(res$level == 2L))
})

test_that("request_query with validate = TRUE removes weekends", {
  # 2021-01-01..2021-01-05 includes Sat(2) and Sun(3) which should be removed
  # stub holidayNYSE to return no holidays so we only remove weekends in this test
  testthat::with_mocked_bindings(
    holidayNYSE = function(years) as.Date(character(0)),
    .env = asNamespace("lobsteR"),
    {
      res <- request_query(
        "SYM",
        "2021-01-01",
        "2021-01-05",
        level = 1,
        validate = TRUE
      )
      expect_true(all(lubridate::wday(res$start_date, week_start = 1) %in% 1:5))
      expect_equal(nrow(res), 3L) # Fri, Mon, Tue
    }
  )
})

test_that("request_query removes rows present in account_archive", {
  req <- request_query(
    "X",
    "2021-01-04",
    "2021-01-04",
    level = 1,
    validate = FALSE
  )
  # Build an archive that matches the single requested row (same cols)
  archive <- data.frame(
    symbol = req$symbol,
    start_date = req$start_date,
    end_date = req$end_date,
    level = req$level,
    size = 100L,
    download = "https://lobsterdata.com/download.php?id=1",
    id = 1L,
    stringsAsFactors = FALSE
  )
  res <- request_query(
    "X",
    "2021-01-04",
    "2021-01-04",
    level = 1,
    validate = TRUE,
    account_archive = archive
  )
  expect_equal(nrow(res), 0L)
})

test_that(".request_validate removes holidays (stubbed) and weekends", {
  # prepare input spanning a holiday
  df <- data.frame(
    symbol = "H",
    start_date = as.Date(c("2021-01-04", "2021-01-05")), # 2021-01-04 will be treated as holiday by stub
    end_date = as.Date(c("2021-01-04", "2021-01-05")),
    level = 1L,
    stringsAsFactors = FALSE
  )

  # stub holidayNYSE to return 2021-01-04 for the year 2021
  testthat::with_mocked_bindings(
    holidayNYSE = function(years) as.Date("2021-01-04"),
    .env = asNamespace("lobsteR"),
    {
      out <- .request_validate(df, account_archive = NULL)
      expect_false(any(out$start_date == as.Date("2021-01-04")))
      expect_true(any(out$start_date == as.Date("2021-01-05")))
    }
  )
})

test_that("request_submit calls session_submit once per row", {
  calls <- list(count = 0L)
  fake_submission <- structure(list(foo = "bar"), class = "submission")
  fake_session <- structure(list(foo = "sess"), class = "session")
  acct <- list(
    valid = TRUE,
    submission = fake_submission,
    session = fake_session
  )

  # stubs
  testthat::with_mocked_bindings(
    html_form = function(x) list(list()), # one empty form per call
    html_form_set = function(form, ...) form, # noop
    session_submit = function(x, form, submit, add_headers) {
      calls$count <<- calls$count + 1L
      structure(list(ok = TRUE), class = "response")
    },
    add_headers = function(...) NULL,
    .env = asNamespace("lobsteR"),
    {
      req <- data.frame(
        symbol = c("A", "B"),
        start_date = as.Date(c("2021-01-06", "2021-01-07")),
        end_date = as.Date(c("2021-01-06", "2021-01-07")),
        level = c(1L, 1L),
        stringsAsFactors = FALSE
      )
      # call and ensure no error; real function returns invisibly
      invisible(request_submit(acct, req))
      expect_equal(calls$count, 2L)
    }
  )
})

test_that("data_download requests content and invokes callr::r_bg for each download", {
  captured <- list(calls = list())
  # stubbed response content (raw)
  fake_content <- as.raw(c(1L, 2L, 3L))

  testthat::with_mocked_bindings(
    session_jump_to = function(x, url) {
      list(response = list(content = fake_content))
    },
    r_bg = function(fun, args, supervise) {
      # capture the args passed to the background function
      captured$calls[[length(captured$calls) + 1L]] <<- list(
        fun = fun,
        args = args,
        supervise = supervise
      )
      structure(list(proc = "fakeproc"), class = "r_bg")
    },
    .env = asNamespace("lobsteR"),
    {
      tmp <- tempdir()
      requested_data <- data.frame(
        download = c(
          "https://lobsterdata.com/download.php?id=10",
          "https://lobsterdata.com/download.php?id=11"
        ),
        id = c(10L, 11L),
        stringsAsFactors = FALSE
      )
      acct <- list(valid = TRUE, submission = NULL)
      invisible(data_download(requested_data, acct, path = tmp, unzip = FALSE))
      expect_equal(length(captured$calls), 2L)
      # check filename arg was constructed and content passed through
      expect_true(all(vapply(
        captured$calls,
        function(x) is.raw(x$args$content),
        logical(1)
      )))
      filenames <- vapply(
        captured$calls,
        function(x) x$args$filename,
        character(1)
      )
      expect_true(all(
        grepl("download.php", filenames) | grepl("\\.7z", filenames)
      ))
    }
  )
})
