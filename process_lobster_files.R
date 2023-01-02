# The function process_orderbook performs a number of transformations to a lobster tibble

# 1. Remove data recorded during trading halts
# 2. Remove data recorded before opening or after closing auction
# 3. Replace empty orderbook slots with NA prices
# 4. Remove observations with crossed prices
# 5. Merge transactions with unique timestamps

library(tidyverse)
process_orderbook <- function(orderbook) {

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
