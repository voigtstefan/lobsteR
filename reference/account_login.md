# Authenticate with LOBSTER account

Logs into your LOBSTER account and creates a session object for
subsequent data requests. This function handles the authentication
process with lobsterdata.com and validates the login was successful.

## Usage

``` r
account_login(login, pwd)
```

## Arguments

- login:

  character(1) Email address associated with the LOBSTER account.

- pwd:

  character(1) Account password.

## Value

A named list with components:

- valid:

  logical(1) — `TRUE` when authentication succeeded.

- session:

  rvest session object used for further navigation.

- submission:

  rvest response returned after the sign-in form was submitted.

## Details

The function submits the sign-in form using an AJAX header
(`x-requested-with: XMLHttpRequest`) and confirms success by checking
the redirect URL. Network connectivity and valid credentials are
required.

Store credentials in your `.Renviron` file (`usethis::edit_r_environ()`)
to avoid hardcoding them in scripts:

    LOBSTER_USER=you@example.com
    LOBSTER_PWD=your-password

## See also

[`account_archive()`](https://voigtstefan.github.io/lobsteR/reference/account_archive.md),
[`request_submit()`](https://voigtstefan.github.io/lobsteR/reference/request_submit.md)

## Examples

``` r
if (FALSE) { # \dontrun{
acct <- account_login(
  login = Sys.getenv("LOBSTER_USER"),
  pwd   = Sys.getenv("LOBSTER_PWD")
)

if (acct$valid) {
  # Retrieve available datasets in the archive
  archive <- account_archive(acct)

  # Build and submit a new data request
  req <- request_query("AAPL", "2023-01-03", "2023-01-05", level = 1)
  request_submit(acct, req)
}
} # }
```
