# Retrieve LOBSTER data archive information

Fetches information about available datasets in your LOBSTER account
archive. This includes details about symbols, date ranges, order book
levels, file sizes, and download links for each available dataset.

## Usage

``` r
account_archive(account_login)
```

## Arguments

- account_login:

  List object returned by
  [`account_login`](https://voigtstefan.github.io/lobsteR/reference/account_login.md).
  Must contain a valid authenticated session.

## Value

A tibble with information about available archive data:

- id:

  Integer. Unique identifier for each dataset

- symbol:

  Character. Stock/ETF ticker symbol (e.g., "SPY", "AAPL")

- start_date:

  Date. First date of data coverage

- end_date:

  Date. Last date of data coverage

- level:

  Integer. Order book depth level (number of price levels)

- size:

  Integer. File size in bytes

- download:

  Character. Direct download URL for the dataset

## Details

The function:

1.  Validates the provided account login is successful

2.  Navigates to the data archive page

3.  Scrapes the archive table and extracts download links

4.  Processes and cleans the data into a structured format

5.  Filters out empty datasets (size = 0)

6.  Orders results by ID in descending order (most recent first)

Only datasets with non-zero file sizes are returned. The download URLs
can be used directly with
[`data_download`](https://voigtstefan.github.io/lobsteR/reference/data_download.md)
or similar functions.

## See also

[`account_login`](https://voigtstefan.github.io/lobsteR/reference/account_login.md),
[`data_download`](https://voigtstefan.github.io/lobsteR/reference/data_download.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# Login and get archive info
my_account <- account_login("user@example.com", "password")
archive_info <- account_archive(my_account)

# View available datasets
print(archive_info)

# Get SPY datasets only
spy_data <- archive_info[archive_info$symbol == "SPY", ]
} # }
```
