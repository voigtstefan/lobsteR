# Submit one or more requests to an authenticated LOBSTER account

Send the prepared request rows to lobsterdata.com using the
authenticated session contained in `account_login`. Each row in
`request` is submitted as a separate HTTP request. The function performs
network side effects and returns invisibly.

## Usage

``` r
request_submit(account_login, request)
```

## Arguments

- account_login:

  list Output from
  [`account_login()`](https://voigtstefan.github.io/lobsteR/reference/account_login.md)
  that contains a successful authenticated session (`valid == TRUE`) and
  the submission response required for navigation.

- request:

  data.frame A tibble as returned by
  [`request_query()`](https://voigtstefan.github.io/lobsteR/reference/request_query.md)
  with columns: symbol, start_date, end_date, level.

## Value

Invisibly returns `NULL`. The primary effect is to queue requests on the
LOBSTER server; processing happens server-side and may take some time.
Use
[`account_archive()`](https://voigtstefan.github.io/lobsteR/reference/account_archive.md)
afterwards to check when files become available.

## See also

[`account_login()`](https://voigtstefan.github.io/lobsteR/reference/account_login.md),
[`request_query()`](https://voigtstefan.github.io/lobsteR/reference/request_query.md),
[`account_archive()`](https://voigtstefan.github.io/lobsteR/reference/account_archive.md)

## Examples

``` r
if (FALSE) { # \dontrun{
acct <- account_login(
  login = Sys.getenv("LOBSTER_USER"),
  pwd   = Sys.getenv("LOBSTER_PWD")
)

# Build a request and submit it
req <- request_query("AAPL", "2023-01-03", "2023-01-05", level = 1)
request_submit(acct, req)

# LOBSTER processes the request server-side; this may take several minutes.
# Once done, the files appear in the account archive.
archive <- account_archive(acct)
} # }
```
