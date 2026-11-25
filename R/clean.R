#' Clean one day of LOBSTER data
#'
#' Reads one day's message file and order book file, keeps the messages of
#' continuous trading and returns one row per message with the book state
#' after it. The order book is read block by block (or level by level from
#' parquet) and only as deep as the depth measures need, so even a 100-level
#' file of a very active stock never has to fit into memory. Files can be read
#' straight from a LOBSTER `.7z` archive without unpacking it.
#'
#' @section Cleaning steps:
#' \enumerate{
#'   \item **Book state.** Prices stay in LOBSTER's integer units
#'     (USD x 10000) for all comparisons. Dummy prices (ask 9999999999, bid
#'     -9999999999) mark empty levels. A book state is valid when both sides
#'     are non-empty and the best ask is not below the best bid; otherwise all
#'     book variables of that row are `NA`.
#'   \item **Depth.** For each distance in `depth_bp`, the number of shares at
#'     the levels priced within that many basis points of the best price on
#'     each side (not of the midquote). `depth0` is the size at the best
#'     price. `depth{bp}_truncated` flags rows where the deepest level in the
#'     file still lies inside the distance, so that depth may be cut short by
#'     the number of levels requested from LOBSTER.
#'   \item **Trading hours and crosses.** Messages outside `trading_hours`
#'     (New York time) are dropped. With `cut_at_crosses = TRUE`, continuous
#'     trading starts after the opening cross (type 6, order id -1) and ends
#'     before the closing cross (type 6, order id -2) whenever these lie
#'     inside the trading hours. All crosses are reported, with price and
#'     volume, in `lobster_crosses()`, and never enter the cleaned messages.
#'   \item **Halts.** Type 7 messages are paired by their price field: a halt
#'     (price -1) lasts until the next resumption of trading (price 1);
#'     resumption of quoting (price 0) does not end it. Halts are found in the
#'     full message stream before any time filter, so a halt that starts
#'     before the open still ends at its resumption. A halt without resumption
#'     lasts until the close. Messages during halts are dropped; the halts are
#'     listed in `lobster_halts()`.
#'   \item **Trade direction.** `trade_sign` is +1 for buyer-initiated and -1
#'     for seller-initiated trades. Visible executions (type 4) take the
#'     opposite of LOBSTER's direction, which is the side of the resting order.
#'     Hidden executions (type 5) carry no usable direction in the NASDAQ
#'     feed, so they are signed against the midquote just before the trade:
#'     the book state after the previous message of the full stream, compared
#'     in integer units (`2 * price` against `ask + bid`). Hidden trades
#'     exactly at that midquote (typically midpoint-peg orders) get
#'     `trade_sign = 0` and `midpoint = TRUE`; hidden trades without a valid
#'     quote before them also get 0.
#' }
#'
#' @param message_file,orderbook_file character(1) The day's message file and
#'   order book file: paths to CSV files (also `.csv.gz`), or member names
#'   inside `archive`. The order book can also be a parquet file whose columns
#'   follow LOBSTER's order (needs the 'nanoparquet' package).
#' @param archive character(1) or `NULL` Path to a LOBSTER `.7z` archive that
#'   holds the two files. They are streamed from the archive; nothing is
#'   unpacked to disk. The `7z` program is used when it is installed (it is
#'   faster), the 'archive' package otherwise; set
#'   `options(lobsteR.use_7z = FALSE)` to always use 'archive'.
#' @param ticker,date Ticker and trading day. By default parsed from the file
#'   names.
#' @param trading_hours character(2) or numeric(2) Start and end of the
#'   continuous session in New York time, as `"HH:MM"`, `"HH:MM:SS"` or
#'   seconds after midnight. Defaults to 09:30--16:00; use
#'   `c("09:30", "13:00")` on early-close days or a wider window for pre- and
#'   post-market trading (together with `cut_at_crosses = FALSE`).
#' @param depth_bp numeric Distances from the best price, in basis points,
#'   for which depth is computed. `0` gives the size at the best price.
#'   `NULL` reads only the best level.
#' @param cut_at_crosses logical(1) Start continuous trading after the
#'   opening cross and end it before the closing cross when they fall inside
#'   `trading_hours`.
#' @param block_size numeric(1) Bytes of CSV text parsed at a time. Each
#'   block passes through one temporary file in [tempdir()], which is
#'   overwritten block by block and removed at the end. Larger blocks are
#'   slightly faster and use more memory.
#'
#' @return A `data.table` with one row per message of continuous trading
#'   (types 1 to 5) and columns
#'   \describe{
#'     \item{`ts`}{seconds after midnight, New York time, as in LOBSTER.}
#'     \item{`time`}{the same instant as `POSIXct` in `America/New_York`.}
#'     \item{`type`, `order_id`, `size`, `direction`}{as in the message file.}
#'     \item{`price`}{message price in USD.}
#'     \item{`trade_sign`}{+1 buyer-, -1 seller-initiated, 0 unsigned; `NA`
#'       for messages that are not executions.}
#'     \item{`midpoint`}{`TRUE` for hidden executions exactly at the midquote
#'       before the trade.}
#'     \item{`best_ask`, `best_bid`, `midquote`}{in USD, after the message.}
#'     \item{`spread`}{quoted spread in basis points of the midquote.}
#'     \item{`depth{bp}_ask`, `depth{bp}_bid`}{shares within `bp` basis points
#'       of the best price, for each value of `depth_bp`.}
#'     \item{`depth{bp}_truncated`}{for each positive `bp`: depth may be cut
#'       short by the number of levels in the file.}
#'   }
#'   Book variables are `NA` when the book is crossed or one side is empty.
#'   The attribute `"lobster"` holds the day's metadata, the crosses, the
#'   halts, the book states at the session boundaries and a log of dropped
#'   messages; [lobster_snapshots()] needs it, and [lobster_crosses()],
#'   [lobster_halts()] and [lobster_log()] read it.
#'
#' @seealso [lobster_snapshots()] to aggregate to a regular time grid,
#'   [lobster_process()] to do both in one step.
#'
#' @examples
#' \dontrun{
#' msgs <- lobster_clean(
#'   "SPY_2024-03-20_34200000_57600000_message_50.csv",
#'   "SPY_2024-03-20_34200000_57600000_orderbook_50.csv"
#' )
#' lobster_crosses(msgs)
#'
#' # straight from the archive, early close
#' msgs <- lobster_clean(
#'   "AAPL_2024-11-29_34200000_46800000_message_10.csv",
#'   "AAPL_2024-11-29_34200000_46800000_orderbook_10.csv",
#'   archive = "AAPL_2024-11-01_2024-11-29_10.7z",
#'   trading_hours = c("09:30", "13:00")
#' )
#' }
#' @export
lobster_clean <- function(
  message_file,
  orderbook_file,
  archive = NULL,
  ticker = NULL,
  date = NULL,
  trading_hours = c("09:30:00", "16:00:00"),
  depth_bp = c(0, 5),
  cut_at_crosses = TRUE,
  block_size = 2^27
) {
  depth_bp <- sort(unique(as.numeric(depth_bp)))
  if (anyNA(depth_bp) || any(depth_bp < 0)) {
    stop("'depth_bp' must hold non-negative numbers.", call. = FALSE)
  }
  hours <- parse_clock(trading_hours)
  if (length(hours) != 2L || hours[1] >= hours[2]) {
    stop("'trading_hours' must give a start before an end.", call. = FALSE)
  }

  # ---- file metadata
  info_m <- lobster_file_info(message_file)
  info_o <- lobster_file_info(orderbook_file)
  if (is.null(ticker)) ticker <- info_m$ticker
  if (is.null(date)) date <- info_m$date
  if (is.na(ticker)) ticker <- info_o$ticker
  if (is.na(date)) date <- info_o$date
  if (is.null(date) || is.na(date)) {
    stop("Cannot read the date from the file names; pass 'date'.", call. = FALSE)
  }
  date <- as.Date(date)
  is_parquet <- grepl("\\.parquet$", orderbook_file)
  if (is_parquet) {
    if (!is.null(archive)) {
      stop("A parquet order book cannot be read from an archive.", call. = FALSE)
    }
    if (!requireNamespace("nanoparquet", quietly = TRUE)) {
      stop("Reading parquet order books needs the 'nanoparquet' package.",
        call. = FALSE
      )
    }
    n_cols <- nrow(nanoparquet::read_parquet_schema(orderbook_file)) - 1L
  } else {
    n_cols <- count_fields(orderbook_file, archive)
  }
  if (n_cols %% 4L != 0L) {
    stop("The order book has ", n_cols, " columns, not a multiple of 4.",
      call. = FALSE
    )
  }
  n_levels <- n_cols %/% 4L
  if (!is.na(info_o$levels) && info_o$levels != n_levels) {
    warning("The file name says ", info_o$levels, " levels, the file holds ",
      n_levels, ".",
      call. = FALSE
    )
  }

  # ---- messages (small: six columns)
  con <- open_input(message_file, archive)
  msg <- data.table::rbindlist(read_csv_blocks(
    con,
    function(path) fread_block(path, select = 1:6),
    block_size
  ))
  close(con)
  data.table::setnames(
    msg,
    c("ts", "type", "order_id", "size", "price", "direction")
  )

  # ---- order book features, aligned with the messages row by row
  book <- if (is_parquet) {
    read_book_parquet(orderbook_file, n_levels, depth_bp)
  } else {
    read_book_csv(orderbook_file, archive, n_levels, depth_bp, block_size)
  }
  n <- nrow(msg)
  if (length(book$a1) != n) {
    stop("The message file has ", n, " rows but the order book ",
      length(book$a1), ".",
      call. = FALSE
    )
  }

  clean_day(
    msg, book,
    ticker = ticker, date = date, n_levels = n_levels,
    levels_read = attr(book, "levels_read"), hours = hours,
    depth_bp = depth_bp, cut_at_crosses = cut_at_crosses,
    window = c(info_m$window_start, info_m$window_end)
  )
}

depth_names <- function(depth_bp) {
  bp <- format(depth_bp, scientific = FALSE, trim = TRUE, drop0trailing = TRUE)
  list(
    ask = paste0("depth", bp, "_ask"),
    bid = paste0("depth", bp, "_bid"),
    trunc = paste0("depth", bp, "_truncated")
  )
}

# The cleaning itself, on the messages and the per-row book features.
clean_day <- function(msg, book, ticker, date, n_levels, levels_read, hours,
                      depth_bp, cut_at_crosses, window) {
  n <- nrow(msg)
  ts <- as.double(msg$ts)
  ts_ns <- round(ts * 1e9)
  if (is.unsorted(ts_ns)) {
    stop("Message time stamps are not in order.", call. = FALSE)
  }
  type <- as.integer(msg$type)
  order_id <- as.double(msg$order_id)
  size <- as.double(msg$size)
  price <- as.double(msg$price)
  direction <- as.integer(msg$direction)

  a1 <- book$a1
  b1 <- book$b1
  ask_ok <- a1 < ask_empty
  bid_ok <- b1 >= bid_empty
  valid <- ask_ok & bid_ok & a1 >= b1
  crossed <- ask_ok & bid_ok & a1 < b1
  x2 <- a1 + b1

  # ---- hidden trades: quote just before the trade, full message stream
  pre_x2 <- c(NA_real_, x2[-n])
  pre_valid <- c(FALSE, valid[-n])
  trade_sign <- rep(NA_integer_, n)
  vis <- type == 4L
  trade_sign[vis] <- -direction[vis]
  hid <- type == 5L
  trade_sign[hid] <- 0L
  hv <- hid & pre_valid
  p2 <- 2 * price
  trade_sign[hv & p2 < pre_x2] <- -1L
  trade_sign[hv & p2 > pre_x2] <- 1L
  midpoint <- hv & p2 == pre_x2
  midpoint[is.na(midpoint)] <- FALSE

  # ---- trading hours, crosses, halts (all from the full stream)
  open_ns <- hours[1] * 1e9
  close_ns <- hours[2] * 1e9
  i6 <- which(type == 6L)
  crosses <- data.table::data.table(
    ts = ts[i6],
    time = as_ny_time(ts[i6], date),
    kind = data.table::fcase(
      order_id[i6] == -1, "opening",
      order_id[i6] == -2, "closing",
      default = "other"
    ),
    order_id = order_id[i6],
    size = size[i6],
    price = ifelse(size[i6] > 0 & price[i6] > 0, price[i6] / 10000, NA_real_),
    dollar_volume = price[i6] * size[i6] / 10000
  )
  start_ns <- open_ns
  end_ns <- close_ns
  start_after <- FALSE # session starts strictly after a cross
  end_before <- FALSE # session ends strictly before a cross
  in_hours6 <- ts_ns[i6] >= open_ns & ts_ns[i6] <= close_ns
  if (cut_at_crosses) {
    oc <- i6[in_hours6 & order_id[i6] == -1]
    if (length(oc)) {
      start_ns <- ts_ns[oc[1]]
      start_after <- TRUE
    }
    cc <- i6[in_hours6 & order_id[i6] == -2]
    if (length(cc)) {
      end_ns <- ts_ns[cc[1]]
      end_before <- TRUE
      if (end_ns < close_ns) {
        warning(sprintf(
          paste(
            "The closing cross at %s lies inside the trading hours;",
            "continuous trading ends there. Set 'trading_hours' to the",
            "early close (e.g. c(\"09:30\", \"13:00\"))?"
          ),
          format(as_ny_time(ts[cc[1]], date), "%H:%M:%OS3")
        ), call. = FALSE)
      }
    }
  }
  if (end_ns <= start_ns) {
    stop("No continuous trading between the crosses and the trading hours.",
      call. = FALSE
    )
  }
  halts <- pair_halts(ts_ns[type == 7L], price[type == 7L])
  halts <- halts[halts$start_ns < end_ns & halts$end_ns > start_ns, ,
    drop = FALSE
  ]

  in_session <- (if (start_after) ts_ns > start_ns else ts_ns >= start_ns) &
    (if (end_before) ts_ns < end_ns else ts_ns <= end_ns)
  in_halt <- logical(n)
  for (h in seq_len(nrow(halts))) {
    in_halt[ts_ns >= halts$start_ns[h] & ts_ns <= halts$end_ns[h]] <- TRUE
  }
  keep <- in_session & !in_halt & type >= 1L & type <= 5L

  # ---- per-row book variables
  nm <- depth_names(depth_bp)
  book_vars <- function(idx) {
    ok <- valid[idx]
    na_if <- function(v, keep = ok) {
      v[!keep] <- NA_real_
      v
    }
    out <- list(
      best_ask = na_if(a1[idx] / 10000, ask_ok[idx]),
      best_bid = na_if(b1[idx] / 10000, bid_ok[idx]),
      midquote = na_if(x2[idx] / 20000),
      spread = na_if(20000 * (a1[idx] - b1[idx]) / x2[idx])
    )
    for (j in seq_along(depth_bp)) {
      out[[nm$ask[j]]] <- na_if(book[[paste0("da", j)]][idx])
      out[[nm$bid[j]]] <- na_if(book[[paste0("db", j)]][idx])
    }
    for (j in which(depth_bp > 0)) {
      tr <- book[[paste0("tr", j)]][idx]
      tr[!ok] <- NA
      out[[nm$trunc[j]]] <- tr
    }
    out
  }

  k <- which(keep)
  rm(vis, hid, hv, p2, pre_x2, pre_valid)
  x <- data.table::as.data.table(c(
    list(
      ts = ts[k],
      time = as_ny_time(ts[k], date),
      type = type[k],
      order_id = order_id[k],
      size = size[k],
      price = price[k] / 10000,
      direction = direction[k],
      trade_sign = trade_sign[k],
      midpoint = midpoint[k]
    ),
    book_vars(k)
  ))

  # ---- book states at the session boundaries, for the time weights
  state_row <- function(t_ns, strictly_before) {
    findInterval(t_ns, ts_ns, left.open = strictly_before)
  }
  b_ts <- c(start_ns, end_ns)
  b_kind <- c("session_start", "session_end")
  b_row <- c(state_row(start_ns, !start_after), 0L)
  for (h in seq_len(nrow(halts))) {
    b_ts <- c(b_ts, max(halts$start_ns[h], start_ns))
    b_kind <- c(b_kind, "halt_start")
    b_row <- c(b_row, 0L)
    if (halts$end_ns[h] < end_ns) {
      b_ts <- c(b_ts, halts$end_ns[h])
      b_kind <- c(b_kind, "halt_end")
      b_row <- c(b_row, state_row(halts$end_ns[h], FALSE))
    }
  }
  bv <- book_vars(ifelse(b_row > 0L, b_row, NA_integer_))
  boundaries <- data.table::as.data.table(c(
    list(ts_ns = b_ts, kind = b_kind),
    bv[setdiff(names(bv), c("best_ask", "best_bid"))]
  ))
  data.table::setorderv(boundaries, "ts_ns")

  halts_out <- data.table::data.table(
    start = halts$start_ns / 1e9,
    end = pmin(halts$end_ns, close_ns) / 1e9,
    start_time = as_ny_time(halts$start_ns / 1e9, date),
    end_time = as_ny_time(pmin(halts$end_ns, close_ns) / 1e9, date),
    resumed = is.finite(halts$end_ns)
  )

  log <- list(
    n_raw = n,
    first_ts = if (n) ts[1] else NA_real_,
    last_ts = if (n) ts[n] else NA_real_,
    n_outside_session = sum(!in_session & type >= 1L & type <= 5L),
    n_in_halts = sum(in_session & in_halt & type >= 1L & type <= 5L),
    n_cross_messages = length(i6),
    n_halt_messages = sum(type == 7L),
    n_kept = length(k),
    n_invalid_book = sum(!valid[k]),
    n_crossed_book = sum(crossed[k]),
    n_trades = sum(type[k] %in% c(4L, 5L)),
    n_midpoint_trades = sum(midpoint[k])
  )

  data.table::setattr(x, "lobster", list(
    ticker = ticker,
    date = date,
    levels = n_levels,
    levels_read = levels_read,
    window = window,
    trading_hours = hours,
    depth_bp = depth_bp,
    session = list(
      open_ns = open_ns, close_ns = close_ns,
      start_ns = start_ns, end_ns = end_ns,
      start = start_ns / 1e9, end = end_ns / 1e9
    ),
    crosses = crosses,
    halts = halts_out,
    halts_ns = halts,
    boundaries = boundaries,
    log = log
  ))
  x
}

# Pair type-7 messages by their price field: -1 starts a halt, 1 (trading
# resumes) ends it, 0 (quoting resumes) is ignored. A halt that never resumes
# gets end = Inf.
pair_halts <- function(ts_ns, price) {
  starts <- numeric(0)
  ends <- numeric(0)
  open <- NA_real_
  for (i in seq_along(ts_ns)) {
    if (price[i] == -1 && is.na(open)) {
      open <- ts_ns[i]
    } else if (price[i] == 1 && !is.na(open)) {
      starts <- c(starts, open)
      ends <- c(ends, ts_ns[i])
      open <- NA_real_
    }
  }
  if (!is.na(open)) {
    starts <- c(starts, open)
    ends <- c(ends, Inf)
  }
  data.frame(start_ns = starts, end_ns = ends)
}

lobster_meta <- function(x) {
  meta <- attr(x, "lobster")
  if (is.null(meta)) {
    stop("'x' has no LOBSTER metadata. Pass the output of lobster_clean(), ",
      "lobster_snapshots() or lobster_process() unchanged.",
      call. = FALSE
    )
  }
  meta
}

#' Crosses, halts and the cleaning log of a LOBSTER day
#'
#' Accessors for the metadata that [lobster_clean()] stores with its output
#' (and that [lobster_snapshots()] and [lobster_process()] pass on).
#'
#' @param x Output of [lobster_clean()], [lobster_snapshots()] or
#'   [lobster_process()].
#'
#' @return
#' * `lobster_crosses()`: a `data.table` with one row per cross message
#'   (type 6) of the whole file: `ts`, `time`, `kind` (`"opening"` for order id
#'   -1, `"closing"` for -2, `"other"`, e.g. halt or IPO crosses), `order_id`,
#'   `size` (shares), `price` (USD, `NA` for a cross without volume) and
#'   `dollar_volume`. None of them is part of the cleaned messages or the
#'   snapshots.
#' * `lobster_halts()`: a `data.table` with one row per halt that overlaps
#'   continuous trading: `start`, `end` (seconds after midnight), `start_time`,
#'   `end_time` and `resumed` (`FALSE` if trading did not resume before the
#'   close).
#' * `lobster_log()`: a list with message counts: `n_raw` messages in the file
#'   (from `first_ts` to `last_ts`), `n_outside_session`, `n_in_halts`,
#'   `n_cross_messages`, `n_halt_messages`, `n_kept`, `n_invalid_book` (kept
#'   messages after which the book is crossed or one-sided), `n_crossed_book`,
#'   `n_trades` and `n_midpoint_trades`, plus the session boundaries and the
#'   number of book levels in the file and read.
#'
#' @examples
#' \dontrun{
#' msgs <- lobster_clean(message_file, orderbook_file)
#' lobster_crosses(msgs)
#' lobster_halts(msgs)
#' lobster_log(msgs)
#' }
#' @name lobster_metadata
NULL

#' @rdname lobster_metadata
#' @export
lobster_crosses <- function(x) lobster_meta(x)$crosses

#' @rdname lobster_metadata
#' @export
lobster_halts <- function(x) lobster_meta(x)$halts

#' @rdname lobster_metadata
#' @export
lobster_log <- function(x) {
  meta <- lobster_meta(x)
  c(meta$log, list(
    session_start = meta$session$start,
    session_end = meta$session$end,
    levels = meta$levels,
    levels_read = meta$levels_read
  ))
}
