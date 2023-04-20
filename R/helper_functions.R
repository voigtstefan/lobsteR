#' compute_depth
#'
#'
#' @param orderbook The orderbook file
#' @param side The side for which depth should be computed
#' @param bp Basis points from best quote
#'
#' @return blablabla
compute_depth <- function(orderbook,
                          side = "bid",
                          bp = 0) {

  # Computes depth (in contract) based on orderbook snapshots
  if (side == "bid") {
    value_bid <- (1 - bp / 10000) * orderbook |> select("bid_price_1")
    index_bid <- orderbook |>
      select(contains("bid_price")) |>
      mutate_all(function(x) {
        if_else(is.na(x),
                FALSE,
                x >= value_bid
        )
      })

    sum_vector <- (orderbook |> select(contains("bid_size")) * index_bid) |> rowSums(na.rm = TRUE)
  } else {
    value_ask <- (1 + bp / 10000) * orderbook |> select("ask_price_1")
    index_ask <- orderbook |>
      select(contains("ask_price")) |>
      mutate_all(function(x) {
        if_else(is.na(x),
                FALSE,
                x <= value_ask
        )
      })
    sum_vector <- (orderbook |> select(contains("ask_size")) * index_ask) |> rowSums(na.rm = TRUE)
  }
  return(sum_vector)
}
