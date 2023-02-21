#' Title
#'
#' @import data.table
#'
#' @param path
#' @param clean_up
#'
#' @return blablabla
.process_cbind <- function(path, clean_up = TRUE) {

  extracted_files <- list.files(path, full.names = TRUE)

  stopifnot(length(extracted_files) > 0)

  symbol <- gsub("_.*", "", basename(extracted_files))[1]

  origin <- gsub(".*[_](\\d+-\\d+-\\d+)[_].*", "\\1", basename(extracted_files))[1]

  # Modify message file
  message_file <- data.table::fread(
    input = grep(pattern = "message", x = extracted_files, value = TRUE),
    colClasses = c(rep("double", 6), "NULL"),
    showProgress = FALSE
  ) %>%
    data.table::setnames(
      old = paste0("V", seq_len(6)),
      new = c("Time", "EventType", "OrderId", "MarketSize", "MarketPrice", "Direction")
    ) %>%
    .[, Time := as.POSIXct(Time, origin = as.Date(origin), tz = "GMT", format = "%Y-%m-%d %H:%M:%OS6")] %>%
    .[, MarketPrice := MarketPrice / 10000]

  # Modify orderbook file

  orderbook_file <- data.table::fread(
    input = grep(pattern = "orderbook", x = extracted_files, value = TRUE),
    showProgress = FALSE
  ) %>%
    .[, .(.SD[, rep(c(TRUE, FALSE), ncol(.) / 2), with = FALSE] / 10000,
          .SD[, rep(c(FALSE, TRUE), ncol(.) / 2), with = FALSE])] %>%
    data.table::setcolorder(neworder = paste0("V", seq_len(ncol(.)))) %>%
    data.table::setnames(
      old = paste0("V", seq_len(ncol(.))),
      new = paste0(
        c("AskPrice", "AskSize", "BidPrice", "BidSize"),
        rep(seq_len(ncol(.) / 4), each = 4)
      )
    )

  # Merge files

  data.table::fwrite(
    x = cbind(message_file, orderbook_file),
    file = glue::glue("{path}/{symbol}_{origin}_{ncol(orderbook_file)/4}.csv"),
    showProgress = FALSE
  )

  if (isTRUE(clean_up)) unlink(extracted_files, recursive = TRUE)
}

.process_highfrequency <- function(path, clean_up = TRUE) {

  #' convert message to highfrequency::sampleTDataRaw format:
  #' The SYMBOL column contains a string identifying the symbol of the trade;
  #' the DT column  represents date and time and contains a POSIXct timestamp;
  #' the PRICE column contains the prices of the trades;
  #' the SIZE column shows the number of shares traded;
  #' the COND column contains the sales condition of the corresponding trade as defined by the NYSE
  #' the characters F, T, and I in our data example above indicate the trade being an intermarket sweep order, an extended hours trade, and/or an odd lot trade respectively.
  #' the EX column shows the exchange of the trade, and CORR is a correction indicator.

  sampleTDataRaw <- data.table::fread(
    input = grep(pattern = "message", x = extracted_files, value = TRUE),
    colClasses = c(rep("double", 6), "NULL"),
    showProgress = FALSE
  ) %>%
    data.table::setnames(
      old = paste0("V", seq_len(6)),
      new = c("Time", "EventType", "OrderId", "MarketSize", "MarketPrice", "Direction")
    ) %>%
    .[, Time := as.POSIXct(Time, origin = as.Date(origin), tz = "GMT", format = "%Y-%m-%d %H:%M:%OS6")] %>%
    .[, MarketPrice := MarketPrice / 10000]

  #' split the data into:
  #' 1. {symbol}_{date}_trade_{level}_raw - data from message
  #' 2. {symbol}_{date}_quote_{level}_raw - data from orderbook
  #' for each level within the orderbook file
  #'
  #' convert the file structure to:
  #' 1. highfrequency::sampleTDataRaw
  #' 2. highfrequency::sampleQDataRaw
  #' formats.
  #'
  #' think about:
  #' - mapping LOBSTER EventType to NYSE exchange of the trade indicator
  #' - not sure how to read the CORR (correction indicator)
  #'
  #' next step:
  #' - build an R6 wrapper to clean and aggregate all data files within
  #' the corresponding request directory
}
