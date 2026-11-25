# Crosses, halts and the cleaning log of a LOBSTER day

Accessors for the metadata that
[`lobster_clean()`](https://voigtstefan.github.io/lobsteR/reference/lobster_clean.md)
stores with its output (and that
[`lobster_snapshots()`](https://voigtstefan.github.io/lobsteR/reference/lobster_snapshots.md)
and
[`lobster_process()`](https://voigtstefan.github.io/lobsteR/reference/lobster_process.md)
pass on).

## Usage

``` r
lobster_crosses(x)

lobster_halts(x)

lobster_log(x)
```

## Arguments

- x:

  Output of
  [`lobster_clean()`](https://voigtstefan.github.io/lobsteR/reference/lobster_clean.md),
  [`lobster_snapshots()`](https://voigtstefan.github.io/lobsteR/reference/lobster_snapshots.md)
  or
  [`lobster_process()`](https://voigtstefan.github.io/lobsteR/reference/lobster_process.md).

## Value

- `lobster_crosses()`: a `data.table` with one row per cross message
  (type 6) of the whole file: `ts`, `time`, `kind` (`"opening"` for
  order id -1, `"closing"` for -2, `"other"`, e.g. halt or IPO crosses),
  `order_id`, `size` (shares), `price` (USD, `NA` for a cross without
  volume) and `dollar_volume`. None of them is part of the cleaned
  messages or the snapshots.

- `lobster_halts()`: a `data.table` with one row per halt that overlaps
  continuous trading: `start`, `end` (seconds after midnight),
  `start_time`, `end_time`, `resumed` (`FALSE` if trading did not resume
  before the close) and `ended_by` (`"resumption"`, `"execution"` when
  the first trade after the halt message came before any resumption
  message, or `"close"`).

- `lobster_log()`: a list with message counts: `n_raw` messages in the
  file (from `first_ts` to `last_ts`), `n_outside_session`,
  `n_in_halts`, `n_cross_messages`, `n_halt_messages`, `n_kept`,
  `n_invalid_book` (kept messages after which the book is crossed or
  one-sided), `n_crossed_book`, `n_trades` and `n_midpoint_trades`, plus
  the session boundaries and the number of book levels in the file and
  read.

## Examples

``` r
if (FALSE) { # \dontrun{
msgs <- lobster_clean(message_file, orderbook_file)
lobster_crosses(msgs)
lobster_halts(msgs)
lobster_log(msgs)
} # }
```
