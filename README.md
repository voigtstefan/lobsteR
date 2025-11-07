
<!-- badges: start -->
[![R-CMD-check](https://github.com/voigtstefan/lobsteR/actions/workflows/R-CMD-check.yaml/badge.svghttps://github.com/voigtstefan/lobsteR/actions/workflows/R-CMD-check.yaml/badge.svghttps://github.com/voigtstefan/lobsteR/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/voigtstefan/lobsteR/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

# lobsteR

lobsteR provides a tidy workflow to request, download, extract and
prepare LOBSTER order‑book snapshots from <https://lobsterdata.com>. It
focuses on the common tasks needed to get LOBSTER data ready for
analysis (requesting, retrieving and extracting 7z archives). For
downstream high‑frequency analysis, consider packages such as
`highfrequency`.

## Quick start

1.  Install the package (development version):

``` r
|# eval: false
# install remotes if needed
remotes::install_github("voigtstefan/lobsteR")
```

2.  Set credentials securely (recommended: store in `~/.Renviron`):

``` r
# In ~/.Renviron
# LOBSTER_USER=you@example.com
# LOBSTER_PWD=your_password
```

3.  Use the package (network calls are disabled in this README; run
    these examples interactively):

``` r
library(lobsteR)
library(dplyr)
```

## Typical workflow

- Authenticate to your LOBSTER account using your own credentials.

``` r
lobster_login <- account_login(
  login = Sys.getenv("LOBSTER_USER"),
  pwd   = Sys.getenv("LOBSTER_PWD")
)
```

Next, we request some data from lobsterdata.com, e.g., message-level
data from *Microsoft* stock for the period from May 1st, 2023 until May
3rd, 2023. ´level´ corresponds to the requested number of orderbook
snapshot levels.

``` r
#| eval: true
data_request <- request_query(
  symbol     = "MSFT",
  start_date = "2023-05-01",
  end_date   = "2023-05-03",
  level      = 10
)
data_request
```

Next, submit the requests to LOBSTER (server will process them; this can
take time):

``` r
request_submit(account_login = lobster_login,
               request = data_request)
```

After submitting the request, lobsterdata.com will work on providing the
order book snapshots. Depending on the number of messages to process,
this may take some time. Once done, the requested data is available in
your account archive - ready to download!

``` r
lobster_archive <- account_archive(account_login = lobster_login)
```

When downloading, we automatically unzip the data (this can be omitted
using `unzip = FALSE`)

``` r
data_download(
  requested_data = lobster_archive |> filter(symbol == "MSFT"),
  account_login = lobster_login,
  path = "/data")
```

## Notes and recommendations

- The package performs network activity for authentication, request
  submission and downloads.
- `data_download()` writes files to disk and (optionally) extracts them
  using the `archive` package. Ensure required system libraries for
  libarchive are available on your OS.
- Should you have trouble installing `archive` on Ubuntu, try installing
  the system dependencies first:

``` bash
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install -y libarchive-dev
```
