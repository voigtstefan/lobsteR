# List the message and order book files in a LOBSTER archive

Reads the table of contents of a LOBSTER `.7z` archive (without
unpacking it) and pairs each day's message file with its order book
file.

## Usage

``` r
lobster_archive_files(archive)
```

## Arguments

- archive:

  character(1) Path to a `.7z` archive as downloaded from LOBSTER.

## Value

A data.frame with one row per trading day and columns `ticker`, `date`,
`levels`, `message_file`, `orderbook_file` (member names inside the
archive), `window_start` and `window_end`.

## Examples

``` r
if (FALSE) { # \dontrun{
lobster_archive_files("SPY_2024-02-27_2024-03-26_50.7z")
} # }
```
