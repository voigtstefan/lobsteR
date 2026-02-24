#' Create a LOBSTER data request (one row per trading day)
#'
#' Construct a request describing which trading-day files to ask LOBSTER for.
#' For each symbol and date range the function expands the range to one row per
#' calendar day, converts the level to integer, and (optionally) validates the
#' requested days by removing weekends, NYSE holidays and any days already
#' present in the provided account archive.
#'
#' @param symbol character vector One or more ticker symbols (e.g. `"AAPL"`).
#'   Each element is paired with the corresponding elements of `start_date`,
#'   `end_date` and `level`. Recycling follows base R rules; mismatched lengths
#'   should be avoided.
#' @param start_date Date-like (Date or character) Start date(s) for the
#'   requested range(s). Converted with `as.Date()`.
#' @param end_date Date-like (Date or character) End date(s) for the
#'   requested range(s). Converted with `as.Date()`.
#' @param level integer(1) Required order-book snapshot level (e.g. `1`, `2`,
#'   `10`).
#' @param validate logical(1) If `TRUE` (default) remove weekend days and NYSE
#'   holidays. When `account_archive` is also supplied, days already present in
#'   the archive are additionally removed to avoid duplicate requests.
#' @param account_archive data.frame or tibble, optional Archive table as
#'   returned by [account_archive()]. When provided, rows already present in
#'   the archive (matched on symbol, start_date, end_date, and level) are
#'   excluded.
#' @param frequency character(1) Frequency string passed to `seq.Date()`.
#'   Defaults to `"1 day"` (one row per trading day). Use `"1 month"` for
#'   large date ranges to reduce the number of individual requests sent to the
#'   LOBSTER server. Validation (`validate = TRUE`) is only applied when
#'   `frequency == "1 day"`.
#'
#' @return A data.frame with one row per period and columns:
#'   * `symbol`: character
#'   * `start_date`: Date — start of the period (equal to `end_date` for daily
#'     requests)
#'   * `end_date`: Date — end of the period
#'   * `level`: integer
#'
#'   When `validate = TRUE` and `frequency = "1 day"`, weekend days and NYSE
#'   holidays are silently removed, so the output typically contains fewer rows
#'   than the full calendar span of the requested date range.
#'
#' @details This function performs no network activity. Use [request_submit()]
#'   to send the generated request to an authenticated LOBSTER session.
#'
#' @examples
#' # Single symbol, one-week range (weekends and holidays removed automatically)
#' request_query("AAPL", "2023-01-02", "2023-01-06", level = 1)
#'
#' # Multiple symbols with paired date ranges
#' request_query(
#'   symbol     = c("AAPL", "MSFT"),
#'   start_date = c("2023-01-03", "2023-02-01"),
#'   end_date   = c("2023-01-05", "2023-02-03"),
#'   level      = 1
#' )
#'
#' # Monthly frequency for a large date range (no per-day expansion)
#' request_query(
#'   symbol     = "SPY",
#'   start_date = "2022-01-01",
#'   end_date   = "2022-12-31",
#'   level      = 10,
#'   frequency  = "1 month"
#' )
#'
#' \dontrun{
#' # Exclude days already in the archive to avoid duplicate requests
#' acct    <- account_login(Sys.getenv("LOBSTER_USER"), Sys.getenv("LOBSTER_PWD"))
#' archive <- account_archive(acct)
#'
#' req <- request_query(
#'   symbol          = "AAPL",
#'   start_date      = "2023-01-02",
#'   end_date        = "2023-01-31",
#'   level           = 1,
#'   account_archive = archive
#' )
#' }
#'
#' @seealso [request_submit()], [account_archive()], [account_login()]
#'
#' @export
#' @importFrom assertthat is.date
#' @importFrom purrr pmap_df
request_query <- function(
  symbol,
  start_date,
  end_date,
  level,
  validate = TRUE,
  account_archive = NULL,
  frequency = "1 day"
) {
  stopifnot(is.character(symbol))
  stopifnot(!anyNA(symbol))
  stopifnot(is.date(as.Date(start_date)))
  stopifnot(is.date(as.Date(end_date)))
  stopifnot(is.numeric(level))

  param <- list(symbol, as.Date(start_date), as.Date(end_date), level)

  request <- pmap_df(
    .l = param,
    ~ {
      date_range <- seq.Date(from = ..2, to = ..3, by = frequency)

      if (frequency == "1 day") {
        ends <- date_range # each day is its own period
      } else {
        ends <- c(date_range[-1] - 1L, end_date)
      }

      data.frame(
        symbol = ..1,
        start_date = date_range,
        end_date = ends,
        level = as.integer(..4)
      )
    }
  )
  if (validate & frequency == "1 day") {
    request <- request |>
      .request_validate(request_query = _, account_archive = account_archive)
  }
  return(request)
}

#' Validate a generated request (remove weekends, holidays, existing files)
#'
#' Internal helper used by [request_query()]. Removes weekend days (Saturday
#' and Sunday) and NYSE holidays for the years present in `request_query`.
#' When `account_archive` is supplied, rows that are already available in the
#' archive are removed using a row-wise anti-join.
#'
#' @param request_query data.frame A tibble produced by [request_query()]
#'   containing columns: symbol, start_date, end_date, level.
#' @param account_archive data.frame or tibble, optional When provided, rows
#'   present in the archive (matching all columns of `request_query`) are
#'   excluded from the validation result.
#'
#' @return A filtered tibble containing only valid trading days that are not
#'   weekends, NYSE holidays, or already present in `account_archive`.
#'
#' @noRd
#' @importFrom lubridate year
#' @importFrom timeDate holidayNYSE
#' @importFrom dplyr anti_join
.request_validate <- function(request_query, account_archive = NULL) {
  years    <- unique(year(request_query$start_date))
  holidays <- as.Date(holidayNYSE(years))

  is_weekend <- as.integer(format(request_query$start_date, "%u")) >= 6L
  is_holiday <- request_query$start_date %in% holidays

  res <- request_query[!is_weekend & !is_holiday, ]
  if (!is.null(account_archive)) {
    res <- anti_join(res, account_archive, by = colnames(res))
  }
  return(res)
}

#' Submit one or more requests to an authenticated LOBSTER account
#'
#' Send the prepared request rows to lobsterdata.com using the authenticated
#' session contained in `account_login`. Each row in `request` is submitted
#' as a separate HTTP request. The function performs network side effects and
#' returns invisibly.
#'
#' @param account_login list Output from [account_login()] that contains a
#'   successful authenticated session (`valid == TRUE`) and the submission
#'   response required for navigation.
#' @param request data.frame A tibble as returned by [request_query()] with
#'   columns: symbol, start_date, end_date, level.
#'
#' @return Invisibly returns `NULL`. The primary effect is to queue requests on
#'   the LOBSTER server; processing happens server-side and may take some time.
#'   Use [account_archive()] afterwards to check when files become available.
#'
#' @examples
#' \dontrun{
#' acct <- account_login(
#'   login = Sys.getenv("LOBSTER_USER"),
#'   pwd   = Sys.getenv("LOBSTER_PWD")
#' )
#'
#' # Build a request and submit it
#' req <- request_query("AAPL", "2023-01-03", "2023-01-05", level = 1)
#' request_submit(acct, req)
#'
#' # LOBSTER processes the request server-side; this may take several minutes.
#' # Once done, the files appear in the account archive.
#' archive <- account_archive(acct)
#' }
#'
#' @seealso [account_login()], [request_query()], [account_archive()]
#'
#' @export
#' @importFrom rvest html_form html_form_set session_submit
#' @importFrom httr add_headers
#' @importFrom purrr pwalk
request_submit <- function(account_login, request) {
  suppressMessages(
    pwalk(
      request,
      ~ {
        html_form(x = account_login$submission)[[1]] |>
          html_form_set(
            stock1 = ..1,
            startdate1 = ..2,
            enddate1 = ..3,
            level1 = ..4
          ) |>
          session_submit(
            x = account_login$session,
            form = _,
            submit = NULL,
            add_headers('x-requested-with' = 'XMLHttpRequest')
          )
      }
    )
  )
  invisible(NULL)
}

#' Download requested archive files
#'
#' Download one or more files listed in `requested_data` using the
#' authenticated session in `account_login`. Files are written to `path`.
#' The file write and optional extraction are performed in a background R
#' process (via `callr::r_bg()`). If `unzip = TRUE` the original `.7z` archive
#' is removed after extraction.
#'
#' @param requested_data data.frame A tibble with archive metadata that must
#'   include at minimum a `download` column (full download URL) and an `id`
#'   column. Typically a (filtered) result from [account_archive()].
#' @param account_login list Output from [account_login()] containing the
#'   authenticated session used to fetch file content.
#' @param path character(1) Directory where downloaded files will be written
#'   and (if `unzip = TRUE`) extracted. The directory must already exist;
#'   create it first with `dir.create(path, recursive = TRUE)` if needed.
#' @param unzip logical(1) If `TRUE` (default) extract the downloaded `.7z`
#'   archive using `archive::archive_extract()` and delete the archive file
#'   afterwards. Set to `FALSE` to keep the raw archive.
#'
#' @return Invisibly returns `NULL`. Files are written to `path` by background
#'   R processes launched via `callr::r_bg()`. These processes are not
#'   monitored after launch; verify that the expected files exist in `path`
#'   before proceeding with analysis.
#'
#' @details
#' For each row in `requested_data` the function fetches the file content via
#' the authenticated session and spawns a background process to write and
#' optionally extract the file. Because extraction runs in the background, the
#' function returns before the files are fully written to disk.
#'
#' @examples
#' \dontrun{
#' acct    <- account_login(Sys.getenv("LOBSTER_USER"), Sys.getenv("LOBSTER_PWD"))
#' archive <- account_archive(acct)
#'
#' # Download all AAPL files to a local directory
#' dir.create("data-lobster", showWarnings = FALSE)
#' data_download(
#'   requested_data = archive[archive$symbol == "AAPL", ],
#'   account_login  = acct,
#'   path           = "data-lobster"
#' )
#'
#' # Keep the raw .7z archives without extracting
#' data_download(
#'   requested_data = archive,
#'   account_login  = acct,
#'   path           = "data-lobster",
#'   unzip          = FALSE
#' )
#' }
#'
#' @seealso [account_login()], [account_archive()]
#'
#' @export
#' @importFrom rvest session_jump_to
#' @importFrom callr r_bg
#' @importFrom archive archive_extract
data_download <- function(
  requested_data,
  account_login,
  path = ".",
  unzip = TRUE
) {
  stopifnot("Path does not exist" = file.exists(path))

  download <- requested_data$download

  for (i in seq_along(download)) {
    session <- session_jump_to(account_login$submission, download[i])$response
    filename = paste0(path, "/", basename(sub(".7z(.*)", ".7z", download[i])))

    proc <- r_bg(
      function(content, filename, path, unzip) {
        writeBin(object = content, con = filename)
        if (unzip) {
          archive::archive_extract(archive = filename, dir = path)
          unlink(filename, recursive = TRUE)
        }
      },
      args = list(
        content = session$content,
        filename = filename,
        path = path,
        unzip = unzip
      ),
      supervise = TRUE
    )

    list(id = requested_data$id[i], proc = proc)
  }
  invisible(NULL)
}
