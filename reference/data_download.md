# Download requested archive files

Download one or more files listed in `requested_data` using the
authenticated session in `account_login`. Files are written to `path`.
The file write and optional extraction are performed in a background R
process (via
[`callr::r_bg()`](https://callr.r-lib.org/reference/r_bg.html)). If
`unzip = TRUE` the original `.7z` archive is removed after extraction.

## Usage

``` r
data_download(requested_data, account_login, path = ".", unzip = TRUE)
```

## Arguments

- requested_data:

  data.frame A tibble with archive metadata that must include at minimum
  a `download` column (full download URL) and an `id` column. Typically
  a (filtered) result from
  [`account_archive()`](https://voigtstefan.github.io/lobsteR/reference/account_archive.md).

- account_login:

  list Output from
  [`account_login()`](https://voigtstefan.github.io/lobsteR/reference/account_login.md)
  containing the authenticated session used to fetch file content.

- path:

  character(1) Directory where downloaded files will be written and (if
  `unzip = TRUE`) extracted. The directory must already exist; create it
  first with `dir.create(path, recursive = TRUE)` if needed.

- unzip:

  logical(1) If `TRUE` (default) extract the downloaded `.7z` archive
  using
  [`archive::archive_extract()`](https://archive.r-lib.org/reference/archive_extract.html)
  and delete the archive file afterwards. Set to `FALSE` to keep the raw
  archive.

## Value

Invisibly returns `NULL`. Files are written to `path` by background R
processes launched via
[`callr::r_bg()`](https://callr.r-lib.org/reference/r_bg.html). These
processes are not monitored after launch; verify that the expected files
exist in `path` before proceeding with analysis.

## Details

For each row in `requested_data` the function fetches the file content
via the authenticated session and spawns a background process to write
and optionally extract the file. Because extraction runs in the
background, the function returns before the files are fully written to
disk.

## See also

[`account_login()`](https://voigtstefan.github.io/lobsteR/reference/account_login.md),
[`account_archive()`](https://voigtstefan.github.io/lobsteR/reference/account_archive.md)

## Examples

``` r
if (FALSE) { # \dontrun{
acct    <- account_login(Sys.getenv("LOBSTER_USER"), Sys.getenv("LOBSTER_PWD"))
archive <- account_archive(acct)

# Download all AAPL files to a local directory
dir.create("data-lobster", showWarnings = FALSE)
data_download(
  requested_data = archive[archive$symbol == "AAPL", ],
  account_login  = acct,
  path           = "data-lobster"
)

# Keep the raw .7z archives without extracting
data_download(
  requested_data = archive,
  account_login  = acct,
  path           = "data-lobster",
  unzip          = FALSE
)
} # }
```
