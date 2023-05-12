utils::globalVariables(c("type", "direction", "m_price", "ts", "order_id", "seconds", "ask_price_1", "bid_price_1", "midquote", "m_size", "ts", "m_price","level","start_date"))

#' process_collect
#' @export
#' @importFrom glue glue
#'
#' @param path The path of the files
#' @param clean_up Remove the raw files after collecting lobsterdata
#'
#' @return blablabla
process_collect <- function(path, clean_up = TRUE) {

  extracted_files <- list.files(path, full.names = TRUE)

  stopifnot(length(extracted_files) > 0)
  symbol <- gsub("_.*", "", basename(extracted_files))[1]
  date <- gsub(".*[_](\\d+-\\d+-\\d+)[_].*", "\\1", basename(extracted_files))[1]

  # Modify message file
  messages_filename <- grep(pattern = "message", x = extracted_files, value = TRUE)
  messages_raw <- read_csv(messages_filename,
                           col_names = c("ts", "type", "order_id", "m_size", "m_price", "direction", "null"),
                           col_types = cols(
                             ts = col_double(),
                             type = col_integer(),
                             order_id = col_integer(),
                             m_size = col_double(),
                             m_price = col_double(),
                             direction = col_integer(),
                             null = col_skip()
                           )
  ) |>
    mutate(
      ts = as.POSIXct(ts, origin = as.Date(date), tz = "GMT",
                      format = "%Y-%m-%d %H:%M:%OS6"),
      m_price = m_price / 10000
    )

  # Modify orderbook file
  orderbook_filename <- grep(pattern = "orderbook", x = extracted_files, value = TRUE)
  orderbook_raw <- read_csv(orderbook_filename,
                            col_names = paste(rep(c("ask_price", "ask_size", "bid_price", "bid_size"), level),
                                              rep(1:level, each = 4),
                                              sep = "_"
                            ),
                            cols(.default = col_double())
  ) |>
    mutate_at(vars(contains("price")), ~ . / 10000)
  # Merge files
  orderbook <- bind_cols(messages_raw, orderbook_raw)

  store_output <- glue::glue("{path}/{symbol}_{date}_{ncol(orderbook_raw)/4}.csv.gz")
  write_csv(orderbook, store_output, "gz")

  if (isTRUE(clean_up)) unlink(extracted_files, recursive = TRUE)
}

#' process_clean
#'
#' @import readr
#' @import dplyr
#' @importFrom utils head tail
#'
#' @param path The path of the file
#'
#' @return blablabla

process_clean <- function(path) {
  orderbook <- read_csv(list.files(path = path, full.names = TRUE),
                        col_types = cols(
                          ts = col_datetime(format = ""),
                          type = col_double(),
                          order_id = col_double(),
                          m_size = col_double(),
                          m_price = col_double(),
                          direction = col_double(),
                          ask_price_1 = col_double(),
                          ask_size_1 = col_double(),
                          bid_price_1 = col_double(),
                          bid_size_1 = col_double()
                        ))

  # Did a trading halt happen? ----
  halt_index <- orderbook |>
    filter(type == 7 & direction == -1 & m_price == -1 / 10000 | type == 7 & direction == -1 & m_price == 1 / 10000)

  while (nrow(halt_index) > 1) {
    # Filter out messages that occurred in between trading halts
    cat("Trading halt detected")
    orderbook <- orderbook |>
      filter(ts < halt_index$ts[1] | ts > halt_index$ts[2])
    halt_index <- halt_index |> filter(row_number() > 2)
  }

  # Opening and closing auction ----
  # Discard everything before type 6 & ID -1 and everything after type 6 & ID -2

  opening_auction <- orderbook |>
    filter(
      type == 6,
      order_id == -1
    ) |>
    pull(ts)

  closing_auction <- orderbook |>
    filter(
      type == 6,
      order_id == -2
    ) |>
    pull(ts)

  if (length(opening_auction) != 1) {
    opening_auction <- orderbook |>
      select(ts) |>
      head(1) |>
      pull(ts) - seconds(0.1)
  }
  if (length(closing_auction) != 1) {
    closing_auction <- orderbook |>
      select(ts) |>
      tail(1) |>
      pull(ts) + seconds(0.1)
  }

  orderbook <- orderbook |> filter(ts > opening_auction & ts < closing_auction)
  orderbook <- orderbook |> filter(type != 6 & type != 7)

  # Replace "empty" slots in orderbook (0 volume) with NA prices ----
  orderbook <- orderbook |>
    mutate(
      across(contains("bid_price"), ~ replace(., . < 0, NA)),
      across(contains("ask_price"), ~ replace(., . >= 999999, NA))
    )

  # Remove crossed orderbook observations ----
  orderbook <- orderbook |>
    filter(ask_price_1 > bid_price_1)

  # Merge transactions with unique time stamp ----
  trades <- orderbook |>
    filter(type == 4 | type == 5) |>
    select(ts:direction)

  trades <- inner_join(trades,
                       orderbook |>
                         group_by(ts) |>
                         filter(row_number() == 1) |>
                         ungroup() |>
                         transmute(ts,
                                   ask_price_1,
                                   bid_price_1,
                                   midquote = ask_price_1 / 2 + bid_price_1 / 2,
                                   lag_midquote = lag(midquote)
                         ),
                       by = "ts"
  )

  trades <- trades |>
    mutate(direction = case_when(
      type == 5 & m_price < lag_midquote ~ 1, # lobster convention: direction = 1 if executed against a limit buy order
      type == 5 & m_price > lag_midquote ~ -1,
      type == 4 ~ as.double(direction),
      TRUE ~ as.double(NA)
    ))

  # Aggregate transactions with size and volume weighted price
  trade_aggregated <- trades |>
    group_by(ts) |>
    summarise(
      type = last(type),
      order_id = NA,
      m_price = sum(m_price * m_size) / sum(m_size),
      m_size = sum(m_size),
      direction = last(direction)
    )

  # Merge trades with last observed orderbook snapshot
  trade_aggregated <- inner_join(trade_aggregated,
                                 orderbook |>
                                   select(ts,
                                          ask_price_1:last_col()) |>
                                   group_by(ts) |>
                                   filter(row_number() == n()),
                                 by = "ts"
  )

  orderbook <- orderbook |>
    filter(
      type != 4,
      type != 5
    ) |>
    bind_rows(trade_aggregated) |>
    arrange(ts) |>
    mutate(direction = if_else(type == 4 | type == 5,
                               direction,
                               as.double(NA)))

  return(orderbook)
}
