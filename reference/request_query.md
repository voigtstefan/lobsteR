# Create a LOBSTER data request (one row per trading day)

Construct a request describing which trading-day files to ask LOBSTER
for. For each symbol and date range the function expands the range to
one row per calendar day, converts the level to integer, and
(optionally) validates the requested days by removing weekends, NYSE
holidays and any days already present in the provided account archive.

## Usage

``` r
request_query(
  symbol,
  start_date,
  end_date,
  level,
  validate = TRUE,
  account_archive = NULL,
  frequency = "1 day"
)
```

## Arguments

- symbol:

  character vector One or more ticker symbols (e.g. `"AAPL"`). Each
  element is paired with the corresponding elements of `start_date`,
  `end_date` and `level`. Recycling follows base R rules; mismatched
  lengths should be avoided.

- start_date:

  Date-like (Date or character) Start date(s) for the requested
  range(s). Converted with
  [`as.Date()`](https://rdrr.io/r/base/as.Date.html).

- end_date:

  Date-like (Date or character) End date(s) for the requested range(s).
  Converted with [`as.Date()`](https://rdrr.io/r/base/as.Date.html).

- level:

  integer(1) Required order-book snapshot level (e.g. `1`, `2`, `10`).

- validate:

  logical(1) If `TRUE` (default) remove weekend days and NYSE holidays.
  When `account_archive` is also supplied, days already present in the
  archive are additionally removed to avoid duplicate requests.

- account_archive:

  data.frame or tibble, optional Archive table as returned by
  [`account_archive()`](https://voigtstefan.github.io/lobsteR/reference/account_archive.md).
  When provided, rows already present in the archive (matched on symbol,
  start_date, end_date, and level) are excluded.

- frequency:

  character(1) Frequency string passed to
  [`seq.Date()`](https://rdrr.io/r/base/seq.Date.html). Defaults to
  `"1 day"` (one row per trading day). Use `"1 month"` for large date
  ranges to reduce the number of individual requests sent to the LOBSTER
  server. Validation (`validate = TRUE`) is only applied when
  `frequency == "1 day"`.

## Value

A data.frame with one row per period and columns:

- `symbol`: character

- `start_date`: Date — start of the period (equal to `end_date` for
  daily requests)

- `end_date`: Date — end of the period

- `level`: integer

When `validate = TRUE` and `frequency = "1 day"`, weekend days and NYSE
holidays are silently removed, so the output typically contains fewer
rows than the full calendar span of the requested date range.

## Details

This function performs no network activity. Use
[`request_submit()`](https://voigtstefan.github.io/lobsteR/reference/request_submit.md)
to send the generated request to an authenticated LOBSTER session.

## See also

[`request_submit()`](https://voigtstefan.github.io/lobsteR/reference/request_submit.md),
[`account_archive()`](https://voigtstefan.github.io/lobsteR/reference/account_archive.md),
[`account_login()`](https://voigtstefan.github.io/lobsteR/reference/account_login.md)

## Examples

``` r
# Single symbol, one-week range (weekends and holidays removed automatically)
request_query("AAPL", "2023-01-02", "2023-01-06", level = 1)
#>   symbol start_date   end_date level
#> 2   AAPL 2023-01-03 2023-01-03     1
#> 3   AAPL 2023-01-04 2023-01-04     1
#> 4   AAPL 2023-01-05 2023-01-05     1
#> 5   AAPL 2023-01-06 2023-01-06     1

# Multiple symbols with paired date ranges
request_query(
  symbol     = c("AAPL", "MSFT"),
  start_date = c("2023-01-03", "2023-02-01"),
  end_date   = c("2023-01-05", "2023-02-03"),
  level      = 1
)
#>   symbol start_date   end_date level
#> 1   AAPL 2023-01-03 2023-01-03     1
#> 2   AAPL 2023-01-04 2023-01-04     1
#> 3   AAPL 2023-01-05 2023-01-05     1
#> 4   MSFT 2023-02-01 2023-02-01     1
#> 5   MSFT 2023-02-02 2023-02-02     1
#> 6   MSFT 2023-02-03 2023-02-03     1

# Monthly frequency for a large date range (no per-day expansion)
request_query(
  symbol     = "SPY",
  start_date = "2022-01-01",
  end_date   = "2022-12-31",
  level      = 10,
  frequency  = "1 month"
)
#>    symbol start_date   end_date level
#> 1     SPY 2022-01-01 2022-01-31    10
#> 2     SPY 2022-02-01 2022-02-28    10
#> 3     SPY 2022-03-01 2022-03-31    10
#> 4     SPY 2022-04-01 2022-04-30    10
#> 5     SPY 2022-05-01 2022-05-31    10
#> 6     SPY 2022-06-01 2022-06-30    10
#> 7     SPY 2022-07-01 2022-07-31    10
#> 8     SPY 2022-08-01 2022-08-31    10
#> 9     SPY 2022-09-01 2022-09-30    10
#> 10    SPY 2022-10-01 2022-10-31    10
#> 11    SPY 2022-11-01 2022-11-30    10
#> 12    SPY 2022-12-01 2022-12-31    10

if (FALSE) { # \dontrun{
# Exclude days already in the archive to avoid duplicate requests
acct    <- account_login(Sys.getenv("LOBSTER_USER"), Sys.getenv("LOBSTER_PWD"))
archive <- account_archive(acct)

req <- request_query(
  symbol          = "AAPL",
  start_date      = "2023-01-02",
  end_date        = "2023-01-31",
  level           = 1,
  account_archive = archive
)
} # }
```
