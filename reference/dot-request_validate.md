# Validate a generated request (remove weekends, holidays, existing files)

Internal helper used by
[`request_query()`](https://voigtstefan.github.io/lobsteR/reference/request_query.md).
Removes weekend days (Saturday and Sunday) and NYSE holidays for the
years present in `request_query`. When `account_archive` is supplied,
rows that are already available in the archive are removed using a
row-wise anti-join.

## Usage

``` r
.request_validate(request_query, account_archive = NULL)
```

## Arguments

- request_query:

  data.frame A tibble produced by
  [`request_query()`](https://voigtstefan.github.io/lobsteR/reference/request_query.md)
  containing columns: symbol, start_date, end_date, level.

- account_archive:

  data.frame or tibble, optional When provided, rows present in the
  archive (matching all columns of `request_query`) are excluded from
  the validation result.

## Value

A filtered tibble containing only valid trading days that are not
weekends, NYSE holidays, or already present in `account_archive`.
