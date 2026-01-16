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

  character vector One or more ticker symbols (e.g. "AAPL"). Each
  element is paired with the corresponding elements of `start_date`,
  `end_date` and `level`. Recycling follows base R rules; mismatched
  lengths should be avoided.

- start_date:

  Date-like (Date or character) Start date(s) for the requested
  range(s). Each start date is converted with
  [`as.Date()`](https://rdrr.io/r/base/as.Date.html).

- end_date:

  Date-like (Date or character) End date(s) for the requested range(s).
  Each end date is converted with
  [`as.Date()`](https://rdrr.io/r/base/as.Date.html).

- level:

  integer(1) Required order-book snapshot level (e.g. 1, 2).

- validate:

  logical(1) If TRUE (default) remove weekend days and NYSE holidays and
  — when `account_archive` is supplied — remove days already present in
  the account archive.

- account_archive:

  data.frame or tibble, optional Archive table as returned by
  [`account_archive()`](https://voigtstefan.github.io/lobsteR/reference/account_archive.md).
  When provided, rows that match (symbol, start_date, end_date, level,
  size, download, id) are excluded from the returned request.

- frequency:

  character(1), defaults to "1 day". Frequency string passed to request
  data. For large data ranges, it may be beneficial to request data at a
  lower frequency, e.g. "1 month" to reduce the number of requests to
  the lobster server.

## Value

A tibble (data.frame) with one row per trading day and columns:

- symbol: character

- start_date: Date

- end_date: Date (equal to start_date for daily requests)

- level: integer

The function returns only the days that remain after optional
validation.

## Details

The function does not perform network activity. Use
[`request_submit()`](https://voigtstefan.github.io/lobsteR/reference/request_submit.md)
to send the generated requests to the authenticated LOBSTER session.

## Examples

``` r
if (FALSE) { # \dontrun{
# Single symbol, one-month range
req <- request_query("AAPL", "2020-01-01", "2020-01-31", level = 2)

# Multiple symbols / ranges (vectorised inputs)
req <- request_query(
  symbol = c("AAPL", "MSFT"),
  start_date = c("2020-01-01", "2020-02-01"),
  end_date = c("2020-01-03", "2020-02-03"),
  level = c(1, 1)
)
} # }
```
