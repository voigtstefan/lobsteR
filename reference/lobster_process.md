# Clean one LOBSTER day and aggregate it to snapshots

Runs
[`lobster_clean()`](https://voigtstefan.github.io/lobsteR/reference/lobster_clean.md)
and
[`lobster_snapshots()`](https://voigtstefan.github.io/lobsteR/reference/lobster_snapshots.md)
for one day, given either the day's message and order book files or a
LOBSTER `.7z` archive and a date. Files inside the archive are streamed,
never unpacked to disk.

## Usage

``` r
lobster_process(
  message_file = NULL,
  orderbook_file = NULL,
  archive = NULL,
  date = NULL,
  freq = 5,
  split_edges = TRUE,
  ...
)
```

## Arguments

- message_file, orderbook_file:

  character(1) or `NULL` Paths of the day's files, or member names
  inside `archive`. When `archive` is given they can be left out and are
  then found by `date`.

- archive:

  character(1) or `NULL` Path to a LOBSTER `.7z` archive.

- date:

  Date or character(1) The trading day to process from `archive`; not
  needed when the archive holds a single day.

- freq:

  numeric(1) Snapshot interval in seconds.

- split_edges:

  logical(1) Passed to
  [`lobster_snapshots()`](https://voigtstefan.github.io/lobsteR/reference/lobster_snapshots.md).

- ...:

  Further arguments for
  [`lobster_clean()`](https://voigtstefan.github.io/lobsteR/reference/lobster_clean.md),
  e.g. `trading_hours`, `depth_bp` or `cut_at_crosses`.

## Value

The snapshots, as returned by
[`lobster_snapshots()`](https://voigtstefan.github.io/lobsteR/reference/lobster_snapshots.md).
Crosses, halts and the cleaning log are available with
[`lobster_crosses()`](https://voigtstefan.github.io/lobsteR/reference/lobster_metadata.md),
[`lobster_halts()`](https://voigtstefan.github.io/lobsteR/reference/lobster_metadata.md)
and
[`lobster_log()`](https://voigtstefan.github.io/lobsteR/reference/lobster_metadata.md).

## Examples

``` r
if (FALSE) { # \dontrun{
snaps <- lobster_process(
  archive = "SPY_2024-02-27_2024-03-26_50.7z",
  date = "2024-03-20"
)
lobster_crosses(snaps)

# all days of an archive
days <- lobster_archive_files("SPY_2024-02-27_2024-03-26_50.7z")
snaps <- lapply(days$date, function(d) {
  lobster_process(archive = "SPY_2024-02-27_2024-03-26_50.7z", date = d)
})
} # }
```
