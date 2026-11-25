# Clean one day of LOBSTER data

Reads one day's message file and order book file, keeps the messages of
continuous trading and returns one row per message with the book state
after it. The order book is read block by block (or level by level from
parquet) and only as deep as the depth measures need, so even a
100-level file of a very active stock never has to fit into memory.
Files can be read straight from a LOBSTER `.7z` archive without
unpacking it.

## Usage

``` r
lobster_clean(
  message_file,
  orderbook_file,
  archive = NULL,
  ticker = NULL,
  date = NULL,
  trading_hours = c("09:30:00", "16:00:00"),
  depth_bp = c(0, 5),
  cut_at_crosses = TRUE,
  block_size = 2^27
)
```

## Arguments

- message_file, orderbook_file:

  character(1) The day's message file and order book file: paths to CSV
  files (also `.csv.gz`), or member names inside `archive`. The order
  book can also be a parquet file whose columns follow LOBSTER's order
  (needs the 'nanoparquet' package).

- archive:

  character(1) or `NULL` Path to a LOBSTER `.7z` archive that holds the
  two files. They are streamed from the archive; nothing is unpacked to
  disk. The `7z` program is used when it is installed (it is faster),
  the 'archive' package otherwise; set `options(lobsteR.use_7z = FALSE)`
  to always use 'archive'.

- ticker, date:

  Ticker and trading day. By default parsed from the file names.

- trading_hours:

  character(2) or numeric(2) Start and end of the continuous session in
  New York time, as `"HH:MM"`, `"HH:MM:SS"` or seconds after midnight.
  Defaults to 09:30–16:00; use `c("09:30", "13:00")` on early-close days
  or a wider window for pre- and post-market trading (together with
  `cut_at_crosses = FALSE`).

- depth_bp:

  numeric Distances from the best price, in basis points, for which
  depth is computed. `0` gives the size at the best price. `NULL` reads
  only the best level.

- cut_at_crosses:

  logical(1) Start continuous trading after the opening cross and end it
  before the closing cross when they fall inside `trading_hours`.

- block_size:

  numeric(1) Bytes of CSV text parsed at a time. Each block passes
  through one temporary file in
  [`tempdir()`](https://rdrr.io/r/base/tempfile.html), which is
  overwritten block by block and removed at the end. Larger blocks are
  slightly faster and use more memory.

## Value

A `data.table` with one row per message of continuous trading (types 1
to 5) and columns

- `ts`:

  seconds after midnight, New York time, as in LOBSTER.

- `time`:

  the same instant as `POSIXct` in `America/New_York`.

- `type`, `order_id`, `size`, `direction`:

  as in the message file.

- `price`:

  message price in USD.

- `trade_sign`:

  +1 buyer-, -1 seller-initiated, 0 unsigned; `NA` for messages that are
  not executions.

- `midpoint`:

  `TRUE` for hidden executions exactly at the midquote before the trade.

- `best_ask`, `best_bid`, `midquote`:

  in USD, after the message.

- `spread`:

  quoted spread in basis points of the midquote.

- `depth{bp}_ask`, `depth{bp}_bid`:

  shares within `bp` basis points of the best price, for each value of
  `depth_bp`.

- `depth{bp}_truncated`:

  for each positive `bp`: depth may be cut short by the number of levels
  in the file.

Midquote and spread are `NA` when the book is crossed or one side is
empty. Depth is `NA` only in crossed books; an empty side has depth 0.
The attribute `"lobster"` holds the day's metadata, the crosses, the
halts, the book states at the session boundaries and a log of dropped
messages;
[`lobster_snapshots()`](https://voigtstefan.github.io/lobsteR/reference/lobster_snapshots.md)
needs it, and
[`lobster_crosses()`](https://voigtstefan.github.io/lobsteR/reference/lobster_metadata.md),
[`lobster_halts()`](https://voigtstefan.github.io/lobsteR/reference/lobster_metadata.md)
and
[`lobster_log()`](https://voigtstefan.github.io/lobsteR/reference/lobster_metadata.md)
read it.

## Cleaning steps

1.  **Book state.** Prices stay in LOBSTER's integer units (USD x 10000)
    for all comparisons. Dummy prices (ask 9999999999, bid -9999999999)
    mark empty levels. A book state is valid when both sides are
    non-empty and the best ask is not below the best bid; otherwise
    midquote and spread are `NA`. In a one-sided book the empty side has
    depth 0; in a crossed book all book variables are `NA`.

2.  **Depth.** For each distance in `depth_bp`, the number of shares at
    the levels priced within that many basis points of the best price on
    each side (not of the midquote). `depth0` is the size at the best
    price. `depth{bp}_truncated` flags rows where the deepest level in
    the file still lies inside the distance, so that depth may be cut
    short by the number of levels requested from LOBSTER.

3.  **Trading hours and crosses.** Messages outside `trading_hours` (New
    York time) are dropped. With `cut_at_crosses = TRUE`, continuous
    trading starts after the opening cross (type 6, order id -1) and
    ends before the closing cross (type 6, order id -2) whenever these
    lie inside the trading hours. All crosses are reported, with price
    and volume, in
    [`lobster_crosses()`](https://voigtstefan.github.io/lobsteR/reference/lobster_metadata.md),
    and never enter the cleaned messages.

4.  **Halts.** Type 7 messages are paired by their price field: a halt
    (price -1) lasts until the next resumption of trading (price 1) or
    the next execution, whichever comes first (some files hold halt
    messages without a resumption on days that trade normally);
    resumption of quoting (price 0) does not end it. Halts are found in
    the full message stream before any time filter, so a halt that
    starts before the open still ends at its resumption. A halt without
    resumption lasts until the close. Messages during halts are dropped;
    the halts are listed in
    [`lobster_halts()`](https://voigtstefan.github.io/lobsteR/reference/lobster_metadata.md).

5.  **Trade direction.** `trade_sign` is +1 for buyer-initiated and -1
    for seller-initiated trades. Visible executions (type 4) take the
    opposite of LOBSTER's direction, which is the side of the resting
    order. Hidden executions (type 5) carry no usable direction in the
    NASDAQ feed, so they are signed against the midquote just before the
    trade: the book state after the previous message of the full stream,
    compared in integer units (`2 * price` against `ask + bid`). Hidden
    trades exactly at that midquote (typically midpoint-peg orders) get
    `trade_sign = 0` and `midpoint = TRUE`; hidden trades without a
    valid quote before them also get 0.

## See also

[`lobster_snapshots()`](https://voigtstefan.github.io/lobsteR/reference/lobster_snapshots.md)
to aggregate to a regular time grid,
[`lobster_process()`](https://voigtstefan.github.io/lobsteR/reference/lobster_process.md)
to do both in one step.

## Examples

``` r
if (FALSE) { # \dontrun{
msgs <- lobster_clean(
  "SPY_2024-03-20_34200000_57600000_message_50.csv",
  "SPY_2024-03-20_34200000_57600000_orderbook_50.csv"
)
lobster_crosses(msgs)

# straight from the archive, early close
msgs <- lobster_clean(
  "AAPL_2024-11-29_34200000_46800000_message_10.csv",
  "AAPL_2024-11-29_34200000_46800000_orderbook_10.csv",
  archive = "AAPL_2024-11-01_2024-11-29_10.7z",
  trading_hours = c("09:30", "13:00")
)
} # }
```
