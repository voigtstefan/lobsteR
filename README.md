
<!-- README.md is generated from README.Rmd. Please edit that file -->

\# lobsteR
<img src="man/figures/logo.png" align="right" height="139" alt="" />

<!-- badges: start -->

[![Codecov test
coverage](https://codecov.io/gh/voigtstefan/lobsteR/graph/badge.svg)](https://app.codecov.io/gh/voigtstefan/lobsteR)
[![R-CMD-check](https://github.com/voigtstefan/lobsteR/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/voigtstefan/lobsteR/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

## Quick start

1.  Install the package (development version):

``` r
# install.packages("pak")
pak::pak("voigtstefan/lobsteR")
```

## Request and download data from lobsterdata.com

## Typical workflow

- Authenticate to your LOBSTER account using your own credentials.

``` r
library(lobsteR)
```

``` r
lobster_login <- account_login(
  login = Sys.getenv("LOBSTER_USER"),
  pwd   = Sys.getenv("LOBSTER_PWD")
)
#> # Login on lobsterdata.com successful
```

I recommend to store your credentials in the `.Renviron` file to avoid
hardcoding them in your scripts.

Next, we request some data from lobsterdata.com, e.g., message-level
data from *Microsoft* stock for the period from May 1st, 2023 until May
3rd, 2023. ´level´ corresponds to the requested number of orderbook
snapshot levels.

``` r
#| eval: true
data_request <- request_query(
  symbol = "MSFT",
  start_date = "2025-05-01",
  end_date = "2025-05-15",
  level = 10)

data_request
#>    symbol start_date   end_date level
#> 1    MSFT 2025-05-01 2025-05-01    10
#> 2    MSFT 2025-05-02 2025-05-02    10
#> 5    MSFT 2025-05-05 2025-05-05    10
#> 6    MSFT 2025-05-06 2025-05-06    10
#> 7    MSFT 2025-05-07 2025-05-07    10
#> 8    MSFT 2025-05-08 2025-05-08    10
#> 9    MSFT 2025-05-09 2025-05-09    10
#> 12   MSFT 2025-05-12 2025-05-12    10
#> 13   MSFT 2025-05-13 2025-05-13    10
#> 14   MSFT 2025-05-14 2025-05-14    10
#> 15   MSFT 2025-05-15 2025-05-15    10
```

Next, submit the requests to LOBSTER (server will process them; this can
take time):

``` r
request_submit(account_login = lobster_login,
               request = data_request)
```

After submitting the request, lobsterdata.com will work on providing the
order book snapshots. Depending on the number of messages to process,
this may take some time. You can close the session during the time, the
processing will be done in the background on the servers of Lobster.
Once done, the requested data is available in your account archive -
ready to download!

``` r
lobster_archive <- account_archive(account_login = lobster_login)
```

When downloading, the data is unzipped automatically (this can be
omitted using `unzip = FALSE`)

``` r
data_download(
  requested_data = lobster_archive |> filter(symbol == "MSFT"),
  account_login = lobster_login,
  path = "data-lobster")
```

## Data processing on an Unix system

To unzip data, `lobsteR` relies on the `archive` package which, in turn,
requires a couple of system dependencies to be installed. On a
Debian-based linux system, you can install the required dependencies
using the following commands:

``` bash
sudo apt-get update
sudo apt-get install -y gpgv gnupg libarchive13t64 liblz4-dev libacl1-dev libext2fs-dev nettle-dev
sudo apt-get install -y libarchive-dev
```
