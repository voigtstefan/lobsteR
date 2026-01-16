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

A list containing authentication details:

- valid:

  Logical indicating if login was successful

- session:

  httr session object for the authenticated session

- submission:

  httr response object from the login submission

A named list with components:

- valid:

  logical(1) — TRUE when authentication succeeded.

- session:

  rvest session object used for further navigation.

- submission:

  rvest response returned after the sign-in form was submitted.

## Details

The function performs form-based authentication by:

1.  Creating a session with the LOBSTER sign-in page

2.  Filling and submitting the login form

3.  Validating the response URL to confirm successful authentication

A successful login redirects to the request data page. The returned
object should be passed to other functions like
[`account_archive`](https://voigtstefan.github.io/lobsteR/reference/account_archive.md)
and
[`request_submit`](https://voigtstefan.github.io/lobsteR/reference/request_submit.md).

The function submits the sign-in form using an AJAX header
(x-requested-with: XMLHttpRequest) and confirms success by checking the
redirect URL. Network connectivity and valid credentials are required.

## See also

[`account_archive`](https://voigtstefan.github.io/lobsteR/reference/account_archive.md),
[`request_submit`](https://voigtstefan.github.io/lobsteR/reference/request_submit.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# Login to LOBSTER account
my_account <- account_login("user@example.com", "mypassword")

# Check if login was successful
if (my_account$valid) {
  message("Successfully logged in!")
}
} # }

if (FALSE) { # \dontrun{
acct <- account_login("you@example.com", "your-password")
if (acct$valid) {
  archive <- account_archive(acct)
}
} # }
```
