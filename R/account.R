#' Authenticate with LOBSTER account
#'
#' Logs into your LOBSTER account and creates a session object for subsequent
#' data requests. This function handles the authentication process with
#' lobsterdata.com and validates the login was successful.
#'
#' @param login Character string. Your registered email address for the LOBSTER account.
#' @param pwd Character string. Your account password.
#'
#' @return A list containing authentication details:
#' \describe{
#'   \item{valid}{Logical indicating if login was successful}
#'   \item{session}{httr session object for the authenticated session}
#'   \item{submission}{httr response object from the login submission}
#' }
#'
#' @details
#' The function performs form-based authentication by:
#' \enumerate{
#'   \item Creating a session with the LOBSTER sign-in page
#'   \item Filling and submitting the login form
#'   \item Validating the response URL to confirm successful authentication
#' }
#'
#' A successful login redirects to the request data page. The returned object
#' should be passed to other functions like \code{\link{account_archive}} and
#' \code{\link{request_submit}}.
#'
#' @examples
#' \dontrun{
#' # Login to LOBSTER account
#' my_account <- account_login("user@example.com", "mypassword")
#'
#' # Check if login was successful
#' if (my_account$valid) {
#'   message("Successfully logged in!")
#' }
#' }
#'
#' @seealso \code{\link{account_archive}}, \code{\link{request_submit}}
#'
#' @param login character(1) Email address associated with the LOBSTER account.
#' @param pwd character(1) Account password.
#' @return A named list with components:
#' \describe{
#'   \item{valid}{logical(1) — TRUE when authentication succeeded.}
#'   \item{session}{rvest session object used for further navigation.}
#'   \item{submission}{rvest response returned after the sign-in form was submitted.}
#' }
#' @details The function submits the sign-in form using an AJAX header
#' (x-requested-with: XMLHttpRequest) and confirms success by checking the
#' redirect URL. Network connectivity and valid credentials are required.
#' @examples
#' \dontrun{
#' acct <- account_login("you@example.com", "your-password")
#' if (acct$valid) {
#'   archive <- account_archive(acct)
#' }
#' }
#' @export
#' @importFrom httr add_headers
#' @importFrom rvest session html_form html_form_set session_submit
#' @importFrom assertthat are_equal
account_login <- function(login, pwd) {
  session <- session(url = "https://lobsterdata.com/SignIn.php")

  form <- rvest::html_form(x = session)[[1]] |>
    rvest::html_form_set(login = login, pwd = pwd)

  submission <- rvest::session_submit(
    x = session,
    form = form,
    submit = "sign in",
    httr::add_headers('x-requested-with' = 'XMLHttpRequest')
  )

  valid <- assertthat::are_equal(
    x = submission$url,
    y = "https://data.lobsterdata.com/requestdata.php"
  )

  if (valid) {
    cat("# Login on lobsterdata.com successful")
  }
  list(
    valid = valid,
    session = session,
    submission = submission
  )
}

#' Retrieve LOBSTER data archive information
#'
#' Fetches information about available datasets in your LOBSTER account archive.
#' This includes details about symbols, date ranges, order book levels, file sizes,
#' and download links for each available dataset.
#'
#' @param account_login List object returned by \code{\link{account_login}}.
#'   Must contain a valid authenticated session.
#'
#' @return A tibble with information about available archive data:
#' \describe{
#'   \item{id}{Integer. Unique identifier for each dataset}
#'   \item{symbol}{Character. Stock/ETF ticker symbol (e.g., "SPY", "AAPL")}
#'   \item{start_date}{Date. First date of data coverage}
#'   \item{end_date}{Date. Last date of data coverage}
#'   \item{level}{Integer. Order book depth level (number of price levels)}
#'   \item{size}{Integer. File size in bytes}
#'   \item{download}{Character. Direct download URL for the dataset}
#' }
#'
#' @details
#' The function:
#' \enumerate{
#'   \item Validates the provided account login is successful
#'   \item Navigates to the data archive page
#'   \item Scrapes the archive table and extracts download links
#'   \item Processes and cleans the data into a structured format
#'   \item Filters out empty datasets (size = 0)
#'   \item Orders results by ID in descending order (most recent first)
#' }
#'
#' Only datasets with non-zero file sizes are returned. The download URLs
#' can be used directly with \code{\link{data_download}} or similar functions.
#'
#' @examples
#' \dontrun{
#' # Login and get archive info
#' my_account <- account_login("user@example.com", "password")
#' archive_info <- account_archive(my_account)
#'
#' # View available datasets
#' print(archive_info)
#'
#' # Get SPY datasets only
#' spy_data <- archive_info[archive_info$symbol == "SPY", ]
#' }
#'
#' @seealso \code{\link{account_login}}, \code{\link{data_download}}
#'
#' @export
#' @importFrom rvest session_jump_to html_table html_nodes html_attr
account_archive <- function(account_login) {
  stopifnot(account_login$valid)

  session <- session_jump_to(
    x = account_login$submission,
    url = "https://lobsterdata.com/data_archive.php"
  )

  archive <- html_table(session, fill = TRUE)[[1]]

  archive$Name <- archive$Delete <- NULL

  colnames(archive) <- c("symbol", "start_date", "end_date", "level", "size")

  archive$download <- html_nodes(session, "td:nth-child(2) a") |>
    html_attr("href") |>
    grep("download", x = _, value = TRUE) |>
    paste0("https://lobsterdata.com/", ... = _)

  archive$id <- gsub(".*id=", "", archive$download)

  class(archive$id) <- class(archive$level) <- class(archive$size) <- "integer"
  archive$start_date <- as.Date(archive$start_date)
  archive$end_date <- as.Date(archive$end_date)
  archive <- archive[archive$size != 0, ]
  archive[
    order(archive$id, decreasing = TRUE),
    c(ncol(archive), 1:(ncol(archive) - 1))
  ]
}
