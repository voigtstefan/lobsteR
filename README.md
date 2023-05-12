
# lobsteR

<!-- badges: start -->
<!-- badges: end -->

The goal of lobsteR is to provide a tidy framework to request data from
lobsterdata.com, to download, unzip, and clean the data. The package
focuses on the core functionalities required to get LOBSTER data ready
fast, for subsequent typical high-frequency econometrics applications,
we refer to the `highfrequency` package.

## Installation

You can install the development version of lobsteR from
[GitHub](https://github.com/) with:

``` r
# install.packages("devtools")
devtools::install_github("voigtstefan/lobsteR")
```

## Example

This is a basic example which shows you how to solve a common problem:

``` r
library(lobsteR)
```

Connect to Lobster using your credentials.

``` r
account_login <- account_login(
  login = Sys.getenv("user"),
  pwd = Sys.getenv("pwd")
)
```

Create a request for data from lobster

``` r
data_request <- request_query(
  symbol = c("META"),
  start_date = Sys.Date() - 100,
  end_date = Sys.Date() - 98,
  level = 1
) |>
  request_validate()

request_submit(account_login = account_login,
               request_validate = data_request)
```

Inspect your archive: Once lobsterdata.com provides your data, you can
download

``` r
account_archive <- account_archive(account_login = account_login)

request_download(
  account_login = account_login,
  path = "data",
  id = 333308
)
lobsteR:::.process_collect(path = "data/333254", clean_up = FALSE)

clean_orderbook <- lobsteR:::.process_clean(path = "data/333254")
```
