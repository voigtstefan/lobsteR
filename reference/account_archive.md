# Retrieve LOBSTER data archive information

Fetches information about available datasets in your LOBSTER account
archive. This includes details about symbols, date ranges, order book
levels, file sizes, and download links for each available dataset.

## Usage

``` r
account_archive(account)
```

## Arguments

- account:

  list Output from
  [`account_login()`](https://voigtstefan.github.io/lobsteR/reference/account_login.md)
  containing a valid authenticated session (`valid == TRUE`).

## Value

A tibble with one row per available dataset and columns:

- id:

  integer. Unique identifier for each dataset.

- symbol:

  character. Stock/ETF ticker symbol (e.g., `"SPY"`, `"AAPL"`).

- start_date:

  Date. First date of data coverage.

- end_date:

  Date. Last date of data coverage.

- level:

  integer. Order book depth (number of price levels).

- size:

  integer. File size in bytes.

- download:

  character. Direct download URL for the dataset.

Rows are ordered by `id` descending (most recently requested first).
Datasets with zero file size (not yet processed by LOBSTER) are
excluded.

## Details

The function navigates to the archive page of the authenticated session,
scrapes the archive table, extracts download links, and returns a
structured tibble. Only datasets with non-zero file sizes are included —
datasets still being processed by LOBSTER will not appear until
processing is complete.

## See also

[`account_login()`](https://voigtstefan.github.io/lobsteR/reference/account_login.md),
[`data_download()`](https://voigtstefan.github.io/lobsteR/reference/data_download.md)

## Examples

``` r
if (FALSE) { # \dontrun{
acct <- account_login(
  login = Sys.getenv("LOBSTER_USER"),
  pwd   = Sys.getenv("LOBSTER_PWD")
)

archive <- account_archive(acct)
archive
#> # A tibble: 3 × 7
#>      id symbol start_date end_date   level    size download
#>   <int> <chr>  <date>     <date>     <int>   <int> <chr>
#> 1   102 AAPL   2023-01-03 2023-01-03     1  204800 https://…
#> 2   101 MSFT   2023-01-03 2023-01-05     2  512000 https://…
#> 3   100 SPY    2022-12-01 2022-12-31    10 1048576 https://…

# Filter to a single symbol before downloading
data_download(
  requested_data = archive[archive$symbol == "AAPL", ],
  account_login  = acct,
  path           = "data-lobster"
)
} # }
```
