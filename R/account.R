#' Log into your LOBSTER account
#'
#' @param login user email address
#' @param pwd user password
#'
#' @return List with session data.
#' \itemize{
#'   \item valid [logical]
#'   \item session [rvest session]
#'   \item submission [rvest session]
#' }
.account_login <- function(login, pwd) {

  session <- rvest::session(url = "https://lobsterdata.com/SignIn.php")

  form <- rvest::html_form(x = session)[[1]] %>%
    rvest::html_form_set(login = login, pwd = pwd)

  submission <- rvest::session_submit(
    x = session,
    form = form,
    submit = "sign in",
    httr::add_headers('x-requested-with' = 'XMLHttpRequest')
  )

  valid <- assertthat::are_equal(
    x = submission$url,
    y = "https://lobsterdata.com/requestdata.php"
  )

  list(
    valid = valid,
    session = session,
    submission = submission
  )
}

#' Fetch LOBSTER archive data
#'
#' @param account_login output of the [.account_login] function
#'
#' @return Tibble with archive data.
#' \itemize{
#'   \item symbol [character]
#'   \item start_date [Date]
#'   \item end_date [Date]
#'   \item level [integer]
#'   \item size [integer]
#'   \item download [character]
#'   \item id [integer]
#' }
.account_archive <- function(account_login) {

  stopifnot(account_login$valid)

  session <- rvest::session_jump_to(
    x = account_login$submission,
    url = "https://lobsterdata.com/data_archive.php"
  )

  archive <- rvest::html_table(session, fill = TRUE)[[1]]

  archive$Name <- archive$Delete <- NULL

  colnames(archive) <- c("symbol", "start_date", "end_date", "level", "size")

  archive$download <- rvest::html_nodes(session, "td:nth-child(2) a") %>%
    rvest::html_attr("href") %>%
    grep("download", ., value = TRUE) %>%
    paste0("https://lobsterdata.com/", .)

  archive$id <- gsub(".*id=", "", archive$download)

  class(archive$id) <- class(archive$level) <- class(archive$size) <- "integer"
  archive$start_date <- as.Date(archive$start_date)
  archive$end_date <- as.Date(archive$end_date)

  archive[order(archive$id, decreasing = TRUE), ]
}
