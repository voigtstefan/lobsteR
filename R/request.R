#' Create a LOBSTER data request (one row per trading day)
#'
#' Construct a request describing which trading-day files to ask LOBSTER for.
#' For each symbol and date range the function expands the range to one row per
#' calendar day, converts the level to integer, and (optionally) validates the
#' requested days by removing weekends, NYSE holidays and any days already
#' present in the provided account archive.
#'
#' @param symbol character vector One or more ticker symbols (e.g. "AAPL").
#'   Each element is paired with the corresponding elements of `start_date`,
#'   `end_date` and `level`. Recycling follows base R rules; mismatched lengths
#'   should be avoided.
#' @param start_date Date-like (Date or character) Start date(s) for the
#'   requested range(s). Each start date is converted with `as.Date()`.
#' @param end_date Date-like (Date or character) End date(s) for the
#'   requested range(s). Each end date is converted with `as.Date()`.
#' @param level integer(1) Required order-book snapshot level (e.g. 1, 2).
#' @param validate logical(1) If TRUE (default) remove weekend days and NYSE
#'   holidays and — when `account_archive` is supplied — remove days already
#'   present in the account archive.
#' @param account_archive data.frame or tibble, optional Archive table as
#'   returned by [account_archive()]. When provided, rows that match
#'   (symbol, start_date, end_date, level, size, download, id) are excluded
#'   from the returned request.
#' @param frequency character(1), defaults to "1 day". Frequency string passed to request data.
#'   For large data ranges, it may be beneficial to request data at a lower frequency,
#'   e.g. "1 month" to reduce the number of requests to the lobster server.
#'
#' @return A tibble (data.frame) with one row per trading day and columns:
#'   * symbol: character
#'   * start_date: Date
#'   * end_date: Date (equal to start_date for daily requests)
#'   * level: integer
#'
#'   The function returns only the days that remain after optional validation.
#'
#' @details The function does not perform network activity. Use
#'   [request_submit()] to send the generated requests to the authenticated
#'   LOBSTER session.
#'
#' @examples
#' \dontrun{
#' # Single symbol, one-month range
#' req <- request_query("AAPL", "2020-01-01", "2020-01-31", level = 2)
#'
#' # Multiple symbols / ranges (vectorised inputs)
#' req <- request_query(
#'   symbol = c("AAPL", "MSFT"),
#'   start_date = c("2020-01-01", "2020-02-01"),
#'   end_date = c("2020-01-03", "2020-02-03"),
#'   level = c(1, 1)
#' )
#' }
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

  param_length <- sapply(param, length) |> unique()

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
#' @keywords internal
#' @importFrom lubridate year
#' @importFrom timeDate timeDate
#' @importFrom timeDate isHoliday
#' @importFrom dplyr anti_join
.request_validate <- function(request_query, account_archive = NULL) {
  res <- request_query[
    !timeDate::isHoliday(timeDate::timeDate(request_query$start_date)),
  ]
  if (!is.null(account_archive)) {
    res <- anti_join(res, account_archive, by = colnames(res))
  }
  return(res)
}

#' Submit one or more requests to an authenticated LOBSTER account
#'
#' Send the prepared request rows to lobsterdata.com using the authenticated
#' session contained in `account_login`. Each row in `request` is submitted
#' as a separate request. This function performs network side effects and
#' returns invisibly.
#'
#' @param account_login list Output from [account_login()] that contains a
#'   successful authenticated session (`valid == TRUE`) and the submission
#'   response required for navigation.
#' @param request data.frame A tibble as returned by [request_query()] with
#'   columns: symbol, start_date, end_date, level.
#'
#' @return Invisibly returns NULL. The primary effect is to submit requests to
#'   the remote service; any responses are not returned by this function.
#'
#' @details
#' The function iterates through each row of the `request` data frame and
#' submits a separate AJAX request to the LOBSTER server. The processing
#' happens asynchronously on the server side, so the function returns
#' immediately after submission. Use \code{\link{account_archive}} to check
#' when the data becomes available for download.
#'
#' @examples
#' \dontrun{
#' # Login to your account
#' my_account <- account_login("user@example.com", "password")
#'
#' # Create a data request
#' req <- request_query(
#'   symbol = "AAPL",
#'   start_date = "2024-01-02",
#'   end_date = "2024-01-05",
#'   level = 10
#' )
#'
#' # Submit the request
#' request_submit(account_login = my_account, request = req)
#'
#' # Wait for processing (may take several minutes)
#' # Then check your archive
#' archive <- account_archive(my_account)
#' }
#'
#' @seealso \code{\link{account_login}}, \code{\link{request_query}}, \code{\link{account_archive}}
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
}

#' Download requested archive files
#'
#' Download one or more files listed in `requested_data` using the authenticated
#' session in `account_login`. Files are written to `path`. Downloads occur in
#' the calling R process but the file write and optional extraction are
#' performed in a background R process (via callr::r_bg). If `unzip = TRUE`
#' the original archive is removed after extraction.
#'
#' @param requested_data data.frame A tibble with archive metadata that must
#'   include at minimum a `download` column (full download URL) and an `id`
#'   column used for tracking.
#' @param account_login list Output from [account_login()] containing the
#'   authenticated session used to fetch file content.
#' @param path character(1) Filesystem path where downloaded files will be
#'   written and (if `unzip = TRUE`) extracted. The path must already exist.
#' @param unzip logical(1) If TRUE (default) extract the downloaded .7z archive
#'   using archive::archive_extract and delete the archive file afterwards.
#'
#' @details The function uses rvest::session_jump_to() to request each download
#'   URL and then launches a background R process to write the binary content
#'   and optionally extract it. The function is silent about progress and
#'   returns invisibly; background processes are left running under callr.
#'
#'   Downloaded files are LOBSTER format message and order book files with
#'   naming convention: `SYMBOL_YYYY-MM-DD_LEVEL_messageXXX.csv` and
#'   `SYMBOL_YYYY-MM-DD_LEVEL_orderbookXXX.csv`.
#'
#' @return Invisibly returns NULL. Side effects: files written to `path` and
#'   background processes spawned to perform file writes / extraction.
#'
#' @examples
#' \dontrun{
#' # Login and get archive
#' my_account <- account_login("user@example.com", "password")
#' archive <- account_archive(my_account)
#'
#' # Download all AAPL data
#' data_download(
#'   requested_data = archive[archive$symbol == "AAPL", ],
#'   account_login = my_account,
#'   path = "data/lobster"
#' )
#'
#' # Download without extracting (keep .7z files)
#' data_download(
#'   requested_data = archive[1:3, ],
#'   account_login = my_account,
#'   path = "data/lobster",
#'   unzip = FALSE
#' )
#'
#' # Using dplyr to filter specific data
#' library(dplyr)
#' data_download(
#'   requested_data = archive |>
#'     filter(symbol == "MSFT", start_date >= as.Date("2024-01-01")),
#'   account_login = my_account,
#'   path = "data/lobster"
#' )
#' }
#'
#' @seealso \code{\link{account_archive}}, \code{\link{account_login}}
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

  for (i in 1:length(download)) {
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
}
