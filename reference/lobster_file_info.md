# Parse LOBSTER file and archive names

LOBSTER names its files
`{ticker}_{date}_{start}_{end}_{type}_{levels}.csv`, where `start` and
`end` are the requested time window in milliseconds after midnight and
`type` is `message` or `orderbook`. Monthly or daily archives are named
`{ticker}_{first date}_{last date}_{levels}.7z`. This function extracts
these fields from file names or full paths.

## Usage

``` r
lobster_file_info(path)
```

## Arguments

- path:

  character Paths or file names. Compressed CSV files (`.csv.gz`,
  `.csv.bz2`, `.csv.xz`) and `.parquet` files that keep the LOBSTER name
  are recognised as well.

## Value

A data.frame with one row per path and columns `path`, `file`
(`"message"`, `"orderbook"` or `"archive"`, `NA` if the name does not
follow the LOBSTER convention), `ticker`, `date` (first trading day),
`last_date` (last trading day; equal to `date` for message and order
book files), `window_start` and `window_end` (requested window in
seconds after midnight; `NA` for archives) and `levels`.

## Details

The time window in a file name is the window that was requested from
LOBSTER. It does not mark the trading session: files often contain
messages from long before the open to long after the close.

## Examples

``` r
lobster_file_info(c(
  "SPY_2024-03-20_34200000_57600000_message_10.csv",
  "data/SPY_2024-03-20_34200000_57600000_orderbook_10.csv",
  "SPY_2024-02-27_2024-03-26_50.7z",
  "notes.txt"
))
#>                                                     path      file ticker
#> 1        SPY_2024-03-20_34200000_57600000_message_10.csv   message    SPY
#> 2 data/SPY_2024-03-20_34200000_57600000_orderbook_10.csv orderbook    SPY
#> 3                        SPY_2024-02-27_2024-03-26_50.7z   archive    SPY
#> 4                                              notes.txt      <NA>   <NA>
#>         date  last_date window_start window_end levels
#> 1 2024-03-20 2024-03-20        34200      57600     10
#> 2 2024-03-20 2024-03-20        34200      57600     10
#> 3 2024-02-27 2024-03-26           NA         NA     50
#> 4       <NA>       <NA>           NA         NA     NA
```
