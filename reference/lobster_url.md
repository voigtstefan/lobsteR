# Address of the LOBSTER website

LOBSTER moved its PHP site, which handles sign-in, requests, the data
archive and downloads, to `https://php.lobsterdata.com` in 2026, when
`lobsterdata.com` became a new web app. All functions of lobsteR build
their addresses with this helper, so a future move needs only the option
`lobsteR.base_url`.

## Usage

``` r
lobster_url(path = "")
```

## Arguments

- path:

  character(1) Path of a page on the LOBSTER site, e.g. `"SignIn.php"`.
  Empty for the base address.

## Value

character(1) The full address.

## Examples

``` r
lobster_url("SignIn.php")
#> [1] "https://php.lobsterdata.com/SignIn.php"
```
