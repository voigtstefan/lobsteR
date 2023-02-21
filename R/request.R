.request_query <- function(symbol, start_date, end_date, level) {

  stopifnot(is.character(symbol))
  stopifnot(assertthat::is.date(start_date))
  stopifnot(assertthat::is.date(end_date))
  stopifnot(is.integer(level))

  param <- list(symbol, start_date, end_date, level)

  param_length <- sapply(param, length) %>% unique()

  stopifnot(length(param_length) == 1 & all(param_length > 0))

  purrr::pmap_df(
    .l = param,
    ~ {
      date_range <- seq.Date(from = ..2, to = ..3, by = "1 day")

      data.frame(
        symbol = ..1,
        start_date = date_range,
        end_date = date_range,
        level = ..4
      )
    }
  )
}

.request_validate <- function(account_archive, request_query) {

  holiday <- sapply(request_query$start_date, data.table::year) %>%
    unique() %>%
    timeDate::holidayNYSE() %>%
    as.Date()

  res <- subset(
    request_query,
    !(as.integer(format(start_date, "%w")) %in% c(0,6) | start_date %in% holiday)
  )

  dplyr::anti_join(res, account_archive, by = colnames(res))
}

.request_execute <- function(account_login, request_validate) {

  purrr::pmap_lgl(
    request_validate,
    ~ {
      rvest::html_form(x = account_login$submission)[[1]] %>%
        rvest::html_form_set(
          stock1 = ..1,
          startdate1 = ..2,
          enddate1 = ..3,
          level1 = ..4
        ) %>%
        rvest::session_submit(
          x = account_login$session,
          form = .,
          submit = NULL,
          httr::add_headers('x-requested-with' = 'XMLHttpRequest')
        ) %$%
        assertthat::are_equal(response$status_code, 200)
    }
  )

}

.request_download <- function(account_login, path, id) {

  account_archive <- lobsteR:::.account_archive(account_login = account_login)

  download <- account_archive[account_archive$id == id, ]$download

  session <- rvest::jump_to(account_login$submission, download)$response

  proc <- callr::r_bg(
    function(content, filename, save_as) {
      `%>%` <- magrittr::`%>%`

      writeBin(object = content, con = filename)

      dir.create(path = save_as, showWarnings = TRUE)

      archive::archive_extract(archive = filename, dir = save_as)

      unlink(filename, recursive = TRUE)
    },
    args = list(
      content = session$content,
      filename = glue::glue("{path}/{basename(download)}.7z"),
      save_as = glue::glue("{path}/{id}")
    ),
    supervise = TRUE
  )

  list(id = id, proc = proc)

}

