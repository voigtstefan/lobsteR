# The following script reads in lobster files (already unzipped), 
# merges orderbook and message files, stores a combined orderbook-message tibble 
# and deletes the individual files.

# Required variables:
# ticker
# date
# level

library(tidyverse)
# Read in Messages
messages_filename <- paste0("data/lobster_raw/", ticker, "_", date, "_34200000_57600000_message_", level, ".csv")
orderbook_filename <- paste0("data/lobster_raw/", ticker, "_", date, "_34200000_57600000_orderbook_", level, ".csv")

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
    ts = as.POSIXct(ts, origin = date, tz = "GMT", format = "%Y-%m-%d %H:%M:%OS6"),
    m_price = m_price / 10000
  )

orderbook_raw <- read_csv(orderbook_filename,
  col_names = paste(rep(c("ask_price", "ask_size", "bid_price", "bid_size"), level),
    rep(1:level, each = 4),
    sep = "_"
  ),
  cols(.default = col_double())
) |>
  mutate_at(vars(contains("price")), ~ . / 10000)

orderbook <- bind_cols(messages_raw, orderbook_raw)

store_output <- paste0("data/lobster_orderbook/", ticker, "_", date, "_orderbook.rds")
write_rds(orderbook, store_output, "gz")

unlink(c(messages_filename, orderbook_filename)) # Remove raw files after processing
