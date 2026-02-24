---
output: github_document
---



# lobsteR <img src="man/figures/logo.png" align="right" height="139" alt="" />

<!-- badges: start -->
[![Codecov test coverage](https://codecov.io/gh/voigtstefan/lobsteR/graph/badge.svg)](https://app.codecov.io/gh/voigtstefan/lobsteR)
[![R-CMD-check](https://github.com/voigtstefan/lobsteR/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/voigtstefan/lobsteR/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

`lobsteR` provides a tidy workflow for requesting, downloading, and reading
[LOBSTER](https://lobsterdata.com) high-frequency order book data directly
from R. LOBSTER reconstructs full limit order books from NASDAQ historical
message data and delivers them as pairs of message files and order book
snapshot files. This package handles the end-to-end pipeline — authentication,
request submission, archive retrieval, and file download — so you can focus on
analysis. For downstream high-frequency econometrics, see the
[`highfrequency`](https://CRAN.R-project.org/package=highfrequency) package.

**Prerequisites:** an active account at
[lobsterdata.com](https://lobsterdata.com) is required to request and download
data.

## Installation

You can install the development version of lobsteR from
[GitHub](https://github.com/voigtstefan/lobsteR) with:


``` r
# install.packages("pak")
pak::pak("voigtstefan/lobsteR")
```

## Workflow


``` r
library(lobsteR)
```

### 1. Authenticate

Store your credentials in `.Renviron` (open it with
`usethis::edit_r_environ()`) to avoid hardcoding them in scripts:

```
LOBSTER_USER=you@example.com
LOBSTER_PWD=your-password
```

Then authenticate:


``` r
lobster_login <- account_login(
  login = Sys.getenv("LOBSTER_USER"),
  pwd   = Sys.getenv("LOBSTER_PWD")
)
```

### 2. Build a request

`request_query()` expands a symbol and date range into one row per trading day,
automatically removing weekends and NYSE holidays. `level` sets the number of
order book price levels included in the snapshot files (e.g. `10` returns the
top 10 bid and ask levels).


``` r
library(lobsteR)

request_query(
  symbol     = "MSFT",
  start_date = "2023-01-02",
  end_date   = "2023-01-13",
  level      = 10
)
#>    symbol start_date   end_date level
#> 2    MSFT 2023-01-03 2023-01-03    10
#> 3    MSFT 2023-01-04 2023-01-04    10
#> 4    MSFT 2023-01-05 2023-01-05    10
#> 5    MSFT 2023-01-06 2023-01-06    10
#> 8    MSFT 2023-01-09 2023-01-09    10
#> 9    MSFT 2023-01-10 2023-01-10    10
#> 10   MSFT 2023-01-11 2023-01-11    10
#> 11   MSFT 2023-01-12 2023-01-12    10
#> 12   MSFT 2023-01-13 2023-01-13    10
```

For large date ranges, use `frequency = "1 month"` to submit one request per
month rather than one per day, which reduces load on the LOBSTER server.

### 3. Submit the request


``` r
request_submit(
  account_login = lobster_login,
  request       = data_request
)
```

LOBSTER processes requests server-side. Depending on the volume of messages,
this can take anywhere from a few minutes to several hours. You can safely
close your R session while waiting — processing continues on the LOBSTER
servers.

### 4. Check the archive

Once processing is complete, the files appear in your account archive:


``` r
lobster_archive <- account_archive(account = lobster_login)
lobster_archive
```

The returned tibble has one row per available dataset with columns `id`,
`symbol`, `start_date`, `end_date`, `level`, `size`, and `download`.

### 5. Download


``` r
dir.create("data-lobster", showWarnings = FALSE)

data_download(
  requested_data = dplyr::filter(lobster_archive, symbol == "MSFT"),
  account_login  = lobster_login,
  path           = "data-lobster"
)
```

Downloaded `.7z` archives are extracted automatically. Pass `unzip = FALSE` to
keep the raw archives. Note that extraction runs in a background process, so
the function returns before the files are fully written to disk — check the
`path` directory before proceeding with analysis.

## System dependencies on Linux

The `archive` package used for `.7z` extraction requires system libraries. On
a Debian/Ubuntu system:


``` bash
sudo apt-get update
sudo apt-get install -y gpgv gnupg libarchive13t64 liblz4-dev libacl1-dev libext2fs-dev nettle-dev
sudo apt-get install -y libarchive-dev
```
