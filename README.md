
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

## Example: Request and download data from lobsterdata.com

``` r
library(lobsteR)
```

With ´lobsteR´ you can connect easily connect with lobsterdata.com using
your own credentials.

``` r
lobster_login <- account_login(
  login = Sys.getenv("user"), # Replace with your own account mail adress
  pwd = Sys.getenv("pwd") # Replace with your own account password
)
```

Next, we request some data from lobsterdata.com, e.g., message-level
data from *META* for the period from May 1st, 2023 until May 3rd, 2023.
´level´ corresponds to the requested number of orderbook snapshot
levels.

``` r
data_request <- request_query(
  symbol = "META",
  start_date = "2023-05-01",
  end_date = "2023-05-03",
  level = 1)

data_request

request_submit(account_login = account_login,
               request = data_request)
```

After submitting the request, lobsterdata.com will work on providing the
order book snapshots. Depending on the number of messages to process,
this may take some time. Once done, the requested data is available in
your account archive - ready to download!

``` r
lobster_archive <- account_archive(account_login = account_login)
```

When downloading, we automatically unzip the data (this can be omitted
using \`unzip = FALSE´)

``` r
data_download(
  requested_data = lobster_archive,
  account_login = lobster_login,
  path = "../tmp_data")
```

``` r
process_collect(path = "../tmp_data", clean_up = TRUE)
```

``` r
clean_orderbook <- lobsteR:::.process_clean(path = "data/333254")
```
