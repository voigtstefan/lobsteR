# Submit one or more requests to an authenticated LOBSTER account

Send the prepared request rows to lobsterdata.com using the
authenticated session contained in `account_login`. Each row in
`request` is submitted as a separate request. This function performs
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

Invisibly returns NULL. The primary effect is to submit requests to the
remote service; any responses are not returned by this function.
