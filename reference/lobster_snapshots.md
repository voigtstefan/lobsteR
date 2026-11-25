# Aggregate cleaned LOBSTER messages to a regular time grid

Turns the output of
[`lobster_clean()`](https://voigtstefan.github.io/lobsteR/reference/lobster_clean.md)
into snapshots on a regular grid, by default every 5 seconds. Each
snapshot is labelled by the end `t` of its interval `(t - freq, t]`.

## Usage

``` r
lobster_snapshots(x, freq = 5, split_edges = TRUE)
```

## Arguments

- x:

  Output of
  [`lobster_clean()`](https://voigtstefan.github.io/lobsteR/reference/lobster_clean.md).

- freq:

  numeric(1) Interval length in seconds.

- split_edges:

  logical(1) `TRUE` (default) splits time weights at interval edges and
  carries the book state into empty intervals, as described above.
  `FALSE` reproduces the weighting of the Tidy Finance blog code, for
  comparisons only: each state's duration counts in the interval where
  the state starts, and empty intervals repeat the previous interval's
  averages.

## Value

A `data.table` with columns `ts`, `midquote`, `signed_volume`,
`trading_volume`, `midpoint_volume`, `depth{bp}_ask`, `depth{bp}_bid`,
`spread`, `n_messages`, `n_trades`, `halted` and `depth{bp}_truncated`.
The `"lobster"` attribute of `x` is kept.

## Definitions

- `midquote`:

  the midquote in force at `t`: the book state after the last message at
  or before `t`. During halts and after crossed states it keeps the last
  valid midquote.

- `spread`, `depth*`:

  time-weighted averages over the interval. Each book state counts for
  the time it is in force inside the interval; the state inherited from
  the previous interval counts from the interval's start, and a state
  that lasts beyond the interval's end counts only up to it. An interval
  without messages therefore gets the book state in force throughout.
  Time in halts, outside the session and in crossed books does not
  count, nor does time in one-sided books for the spread (depth counts
  it, with 0 on the empty side); an interval without any such time is
  `NA`.

- `signed_volume`:

  net buyer-initiated volume in shares, the sum of `trade_sign * size`
  over all executions. Unsigned trades (hidden trades at the midquote)
  add zero. `NA` only when the interval has no trade.

- `trading_volume`:

  dollar volume of all executions (USD), including unsigned ones.

- `midpoint_volume`:

  dollar volume (USD) of hidden executions exactly at the midquote, the
  part of `trading_volume` without a sign.

- `n_messages`, `n_trades`:

  number of messages (types 1–5) and of executions (types 4 and 5) in
  the interval. `n_messages == 0` marks intervals whose book variables
  are carried over.

- `halted`:

  `TRUE` when the interval overlaps a trading halt.

- `depth{bp}_truncated`:

  `TRUE` when depth within `bp` may be cut short by the number of levels
  in the file at some point of the interval.

Volumes use the time stamp of the message (an execution at exactly `t`
belongs to the interval labelled `t`). Crosses (auctions) are never part
of the snapshots; see
[`lobster_crosses()`](https://voigtstefan.github.io/lobsteR/reference/lobster_metadata.md).

The grid runs from the start of the trading hours to the end of
continuous trading. Time stamps are `POSIXct` in `America/New_York`.

## Examples

``` r
if (FALSE) { # \dontrun{
msgs <- lobster_clean(message_file, orderbook_file)
snaps <- lobster_snapshots(msgs, freq = 5)
} # }
```
