#' Aggregate cleaned LOBSTER messages to a regular time grid
#'
#' Turns the output of [lobster_clean()] into snapshots on a regular grid,
#' by default every 5 seconds. Each snapshot is labelled by the end `t` of its
#' interval `(t - freq, t]`.
#'
#' @section Definitions:
#' \describe{
#'   \item{`midquote`}{the midquote in force at `t`: the book state after the
#'     last message at or before `t`. During halts and after crossed states it
#'     keeps the last valid midquote.}
#'   \item{`spread`, `depth*`}{time-weighted averages over the interval. Each
#'     book state counts for the time it is in force inside the interval; the
#'     state inherited from the previous interval counts from the interval's
#'     start, and a state that lasts beyond the interval's end counts only up
#'     to it. An interval without messages therefore gets the book state in
#'     force throughout. Time in halts, outside the session and in crossed
#'     books does not count, nor does time in one-sided books for the spread
#'     (depth counts it, with 0 on the empty side); an interval without any
#'     such time is `NA`.}
#'   \item{`signed_volume`}{net buyer-initiated volume in shares, the sum of
#'     `trade_sign * size` over all executions. Unsigned trades (hidden trades
#'     at the midquote) add zero. `NA` only when the interval has no trade.}
#'   \item{`trading_volume`}{dollar volume of all executions (USD), including
#'     unsigned ones.}
#'   \item{`midpoint_volume`}{dollar volume (USD) of hidden executions
#'     exactly at the midquote, the part of `trading_volume` without a sign.}
#'   \item{`n_messages`, `n_trades`}{number of messages (types 1--5) and of
#'     executions (types 4 and 5) in the interval. `n_messages == 0` marks
#'     intervals whose book variables are carried over.}
#'   \item{`halted`}{`TRUE` when the interval overlaps a trading halt.}
#'   \item{`depth{bp}_truncated`}{`TRUE` when depth within `bp` may be cut
#'     short by the number of levels in the file at some point of the
#'     interval.}
#' }
#'
#' Volumes use the time stamp of the message (an execution at exactly `t`
#' belongs to the interval labelled `t`). Crosses (auctions) are never part of
#' the snapshots; see [lobster_crosses()].
#'
#' The grid runs from the start of the trading hours to the end of continuous
#' trading. Time stamps are `POSIXct` in `America/New_York`.
#'
#' @param x Output of [lobster_clean()].
#' @param freq numeric(1) Interval length in seconds.
#' @param split_edges logical(1) `TRUE` (default) splits time weights at
#'   interval edges and carries the book state into empty intervals, as
#'   described above. `FALSE` reproduces the weighting of the Tidy Finance
#'   blog code, for comparisons only: each state's duration counts in the
#'   interval where the state starts, and empty intervals repeat the previous
#'   interval's averages.
#'
#' @return A `data.table` with columns `ts`, `midquote`, `signed_volume`,
#'   `trading_volume`, `midpoint_volume`, `depth{bp}_ask`, `depth{bp}_bid`,
#'   `spread`, `n_messages`, `n_trades`, `halted` and `depth{bp}_truncated`.
#'   The `"lobster"` attribute of `x` is kept.
#'
#' @examples
#' \dontrun{
#' msgs <- lobster_clean(message_file, orderbook_file)
#' snaps <- lobster_snapshots(msgs, freq = 5)
#' }
#' @export
lobster_snapshots <- function(x, freq = 5, split_edges = TRUE) {
  meta <- lobster_meta(x)
  f <- round(freq * 1e9)
  if (length(f) != 1L || is.na(f) || f <= 0) {
    stop("'freq' must be a positive number of seconds.", call. = FALSE)
  }
  ses <- meta$session
  nm <- depth_names(meta$depth_bp)
  pos <- meta$depth_bp > 0
  avg_cols <- c(
    "spread",
    as.vector(rbind(nm$ask, nm$bid))
  )
  tr_cols <- nm$trunc[pos]
  state_cols <- c("midquote", avg_cols, tr_cols)

  first_edge <- floor(ses$open_ns / f) * f
  labels <- seq(first_edge + f, ceiling(ses$end_ns / f) * f, by = f)
  n_lab <- length(labels)
  lab_index <- function(b) {
    i <- (b - labels[1]) / f + 1
    i[i < 1 | i > n_lab] <- NA_real_
    i
  }

  ts_ns <- round(x$ts * 1e9)

  # ---- volumes and counts: by message time stamp, interval (t - f, t]
  bucket <- lab_index(ceiling(ts_ns / f) * f)
  trade <- x$type %in% c(4L, 5L)
  dollars <- round(x$price * 10000) * x$size
  n_messages <- tabulate_na(bucket, n_lab)
  n_trades <- tabulate_na(bucket[trade], n_lab)
  trading_volume <- sum_by(bucket[trade], dollars[trade], n_lab) / 10000
  signed_volume <- sum_by(
    bucket[trade], (x$trade_sign * x$size)[trade], n_lab
  )
  signed_volume[n_trades == 0L] <- NA_real_
  mp <- trade & x$midpoint
  midpoint_volume <- sum_by(bucket[mp], dollars[mp], n_lab) / 10000

  # ---- book states: last state per time stamp, plus session boundaries
  last <- !duplicated(ts_ns, fromLast = TRUE)
  st <- data.table::as.data.table(c(
    list(ts_ns = ts_ns[last], prio = rep(1L, sum(last))),
    lapply(state_cols, function(cc) x[[cc]][last])
  ))
  data.table::setnames(st, c("ts_ns", "prio", state_cols))
  bd <- meta$boundaries
  bd <- data.table::as.data.table(c(
    list(
      ts_ns = bd$ts_ns,
      prio = data.table::fcase(
        bd$kind == "session_start", 0L,
        bd$kind == "halt_end", 1L,
        default = 2L
      )
    ),
    lapply(state_cols, function(cc) bd[[cc]])
  ))
  data.table::setnames(bd, c("ts_ns", "prio", state_cols))

  # midquote in force at each label: last valid midquote at or before it
  mq_cols <- c("ts_ns", "prio", "midquote")
  mq <- data.table::rbindlist(list(st[, mq_cols, with = FALSE], bd[, mq_cols, with = FALSE]))
  mq <- mq[!is.na(mq$midquote)]
  data.table::setorderv(mq, c("ts_ns", "prio"))
  hit <- findInterval(labels, mq$ts_ns)
  midquote <- ifelse(hit > 0L, mq$midquote[pmax(hit, 1L)], NA_real_)

  if (split_edges) {
    edges <- data.table::data.table(
      ts_ns = c(first_edge, labels),
      prio = 3L
    )
    tl <- data.table::rbindlist(list(st, bd, edges), fill = TRUE)
    data.table::setorderv(tl, c("ts_ns", "prio"))
    # each edge carries the state in force at that instant
    src <- ifelse(tl$prio == 3L, NA_integer_, seq_len(nrow(tl)))
    src <- data.table::nafill(src, type = "locf")
    for (cc in state_cols) {
      data.table::set(tl, j = cc, value = tl[[cc]][src])
    }
    halts <- meta$halts_ns
    for (h in seq_len(nrow(halts))) {
      in_h <- which(tl$ts_ns >= halts$start_ns[h] & tl$ts_ns < halts$end_ns[h])
      for (cc in state_cols) {
        data.table::set(tl, i = in_h, j = cc, value = NA)
      }
    }
    w <- c(diff(tl$ts_ns), 0)
    wb <- lab_index(floor(tl$ts_ns / f) * f + f)
  } else {
    tl <- st
    w <- c(diff(tl$ts_ns), 0)
    wb <- lab_index(ceiling(tl$ts_ns / f) * f)
  }

  avg <- lapply(avg_cols, function(cc) {
    v <- tl[[cc]]
    ok <- !is.na(v) & !is.na(wb) & w > 0
    num <- sum_by(wb[ok], w[ok] * v[ok], n_lab)
    den <- sum_by(wb[ok], w[ok], n_lab)
    ifelse(den > 0, num / den, NA_real_)
  })
  names(avg) <- avg_cols
  trunc <- lapply(tr_cols, function(cc) {
    v <- tl[[cc]]
    ok <- !is.na(v) & !is.na(wb) & w > 0
    out <- sum_by(wb[ok], as.double(v[ok]), n_lab) > 0
    out[sum_by(wb[ok], rep(1, sum(ok)), n_lab) == 0] <- NA # no book state
    out
  })
  names(trunc) <- tr_cols
  if (!split_edges) {
    # blog code: empty intervals repeat the previous interval's averages
    for (cc in avg_cols) {
      avg[[cc]] <- data.table::nafill(avg[[cc]], type = "locf")
    }
  }

  halted <- logical(n_lab)
  halts <- meta$halts_ns
  for (h in seq_len(nrow(halts))) {
    halted <- halted |
      (halts$start_ns[h] < labels & halts$end_ns[h] > labels - f)
  }

  out <- data.table::as.data.table(c(
    list(
      ts = as_ny_time(labels / 1e9, meta$date),
      midquote = midquote,
      signed_volume = signed_volume,
      trading_volume = trading_volume,
      midpoint_volume = midpoint_volume
    ),
    avg[setdiff(avg_cols, "spread")],
    list(
      spread = avg$spread,
      n_messages = n_messages,
      n_trades = n_trades,
      halted = halted
    ),
    trunc
  ))
  data.table::setattr(out, "lobster", meta)
  out
}

tabulate_na <- function(b, n) {
  tabulate(b[!is.na(b)], nbins = n)
}

sum_by <- function(b, v, n) {
  ok <- !is.na(b)
  out <- numeric(n)
  if (any(ok)) {
    s <- rowsum(as.double(v[ok]), b[ok], reorder = TRUE)
    out[as.integer(rownames(s))] <- s[, 1]
  }
  out
}
