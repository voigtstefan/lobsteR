#' Log in to a LOBSTER account and start an authenticated session
#'
#' Establishes a web session on lobsterdata.com using rvest and attempts to
#' authenticate with the provided credentials. The returned object contains
#' the rvest session and the form submission response; pass that object to
#' [account_archive()] to list available datasets for the account.
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
account_login <- function(login, pwd) {
  session <- session(url = "https://lobsterdata.com/SignIn.php")

  form <- html_form(x = session)[[1]] |>
    html_form_set(login = login, pwd = pwd)

  submission <- session_submit(
    x = session,
    form = form,
    submit = "sign in",
    add_headers('x-requested-with' = 'XMLHttpRequest')
  )

  valid <- submission$url == "https://lobsterdata.com/requestdata.php"

  if (valid) {
    cat("# Login on lobsterdata.com successful")
  }
  list(
    valid = valid,
    session = session,
    submission = submission
  )
}

#' Fetch LOBSTER account archive index
#'
#' Retrieve the archive index page for an authenticated LOBSTER account and
#' return a tibble describing available data files. Rows with a zero size are
#' removed and the results are returned ordered by id (descending).
#'
#' @param account_login list Output from [account_login()]. Must have `valid == TRUE`.
#' @return A tibble (data.frame) with columns:
#' \describe{
#'   \item{symbol}{character — Ticker symbol or instrument identifier.}
#'   \item{start_date}{Date — Dataset start date.}
#'   \item{end_date}{Date — Dataset end date.}
#'   \item{level}{integer — Data level (e.g. L1, L2).}
#'   \item{size}{integer — File size in bytes. Rows with size == 0 are dropped.}
#'   \item{download}{character — Full URL to download the file.}
#'   \item{id}{integer — Numeric id extracted from the download URL.}
#' }
#' @examples
#' \dontrun{
#' acct <- account_login("you@example.com", "your-password")
#' archive_tbl <- account_archive(acct)
#' }
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
