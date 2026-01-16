# Download requested archive files

Download one or more files listed in `requested_data` using the
authenticated session in `account_login`. Files are written to `path`.
Downloads occur in the calling R process but the file write and optional
extraction are performed in a background R process (via callr::r_bg). If
`unzip = TRUE` the original archive is removed after extraction.

## Usage

``` r
data_download(requested_data, account_login, path = ".", unzip = TRUE)
```

## Arguments

- requested_data:

  data.frame A tibble with archive metadata that must include at minimum
  a `download` column (full download URL) and an `id` column used for
  tracking.

- account_login:

  list Output from
  [`account_login()`](https://voigtstefan.github.io/lobsteR/reference/account_login.md)
  containing the authenticated session used to fetch file content.

- path:

  character(1) Filesystem path where downloaded files will be written
  and (if `unzip = TRUE`) extracted. The path must already exist.

- unzip:

  logical(1) If TRUE (default) extract the downloaded .7z archive using
  archive::archive_extract and delete the archive file afterwards.

## Value

Invisibly returns NULL. Side effects: files written to `path` and
background processes spawned to perform file writes / extraction.

## Details

The function uses rvest::session_jump_to() to request each download URL
and then launches a background R process to write the binary content and
optionally extract it. The function is silent about progress and returns
invisibly; background processes are left running under callr.
