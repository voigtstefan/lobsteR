#' Log into your LOBSTER account
#'
#' @param login Your unique account user email address
#' @param pwd Your unique account password
#'
#' @export
#' @importFrom httr add_headers
#' @importFrom rvest session html_form html_form_set session_submit
#' @importFrom assertthat are_equal
#' @return An account object which contains the relevant session data.
account_login <- function(login, pwd) {

  session <- session(url = "https://lobsterdata.com/SignIn.php")

  form <- html_form(x = session)[[1]] |>
    html_form_set(login = login,
                         pwd = pwd)

  submission <- session_submit(
    x = session,
    form = form,
    submit = "sign in",
    add_headers('x-requested-with' = 'XMLHttpRequest')
  )

  valid <- are_equal(
    x = submission$url,
    y = "https://lobsterdata.com/requestdata.php"
  )

  if(valid){cat("# Login on lobsterdata.com successful")}
  list(
    valid = valid,
    session = session,
    submission = submission
  )
}

#' Fetch LOBSTER archive data
#'
#' @param account_login output of the [account_login] function
#'
#' @importFrom rvest session_jump_to html_table html_nodes html_attr
#' @export
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
  archive[order(archive$id, decreasing = TRUE), c(ncol(archive), 1:(ncol(archive)-1))]
}
