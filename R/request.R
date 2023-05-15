#' Create a LOBSTER query
#'
#' @param symbol One ticker symbol for which you request data from lobsterdata.com
#' @param start_date Start date of your request
#' @param end_date End date of your request
#' @param level Required number of order book snapshot levels
#' @param validate TRUE Screens the requested dates for holidays if requested.
#' @param account_archive NULL If provided the request is checked against already existing data in the archive.
#'
#' @return A tibble with an overview of the requested trading days.
#'
#' @export
#' @importFrom assertthat is.date
#' @importFrom purrr pmap_df
request_query <- function(symbol, start_date, end_date, level, validate = TRUE, account_archive = NULL) {

  stopifnot(is.character(symbol))
  stopifnot(is.date(as.Date(start_date)))
  stopifnot(is.date(as.Date(end_date)))
  stopifnot(is.numeric(level))

  param <- list(symbol, as.Date(start_date), as.Date(end_date), level)

  param_length <- sapply(param, length) |> unique()

  request <- pmap_df(
    .l = param,
    ~ {
      date_range <- seq.Date(from = ..2, to = ..3, by = "1 day")

      data.frame(
        symbol = ..1,
        start_date = date_range,
        end_date = date_range,
        level = as.integer(..4)
      )
    }
  )
  if(validate){
    request <- request |> .request_validate(request_query = _, account_archive = account_archive)
  }
  return(request)
}

#' Validate a request
#'
#' @param request_query A tibble which states symbol, start_date, end_date, and level of the required data
#' @param account_archive NULL If provided, the validation filters out data which is already available in the account archive
#'
#' @importFrom lubridate year
#' @importFrom timeDate holidayNYSE
#' @importFrom dplyr anti_join
.request_validate <- function(request_query, account_archive = NULL) {

  holiday <- sapply(request_query$start_date, year) |>
    unique() |>
    holidayNYSE() |>
    as.Date()

  res <- subset(
    request_query,
    !(as.integer(format(start_date, "%w")) %in% c(0,6) | start_date %in% holiday)
  )

  if(!is.null(account_archive)){
    res <- anti_join(res, account_archive, by = colnames(res))
  }
  return(res)

}

#' Submit a request
#'
#' @param account_login An account object which contains the relevant session data.
#' @param request A tibble with the requested trading days.
#'
#' @return A tibble with an overview of the requested trading days.
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

#' Download requested data
#'
#' @param requested_data Tibble with archive data.
#' @param path relative path where the data should be stored
#' @param account_login An account object which contains the relevant session data.
#' @param unzip TRUE If true, the .7z files are automatically unzipped. This can be omitted.
#'
#' @export
#' @importFrom rvest session_jump_to
#' @importFrom callr r_bg
#' @importFrom archive archive_extract

data_download <- function(requested_data, account_login, path = ".", unzip = TRUE) {

  stopifnot("Path does not exist" = file.exists(path))

  download <- requested_data$download

  for(i in 1:length(download)){
    session <- session_jump_to(account_login$submission, download[i])$response
    filename = paste0(path,"/",basename(sub(".7z(.*)", ".7z", download[i])))

    proc <- r_bg(
      function(content, filename, path, unzip) {
        writeBin(object = content, con = filename)
        if(unzip){
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

