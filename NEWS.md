# lobsteR (development version)

* A trading halt also ends at the first execution after it, if that comes
  before any resumption message: some LOBSTER files (e.g. SPY, 2008-09-05)
  hold halt messages without a resumption on days that trade normally, which
  dropped the whole day. `lobster_halts()` gains `ended_by`.

* New functions to clean LOBSTER data: `lobster_clean()` turns one day's
  message and order book files into a per-message table of continuous trading,
  `lobster_snapshots()` aggregates it to a regular time grid, and
  `lobster_process()` runs both, also straight from a `.7z` archive.
  `lobster_crosses()`, `lobster_halts()` and `lobster_log()` report the
  auctions, trading halts and dropped messages; `lobster_file_info()` and
  `lobster_archive_files()` parse LOBSTER file names.
* The cleaning follows the Tidy Finance blog code, with these corrections:
  hidden trades are signed against the quote just before the trade, in integer
  prices, and those at the midquote stay unsigned (new `midpoint_volume`);
  signed volume is summed per message and is missing only without trades;
  time weights are split at interval edges and empty intervals carry the book
  state; halts are paired by type, found before the time filter and last to
  the close if trading does not resume; opening and closing crosses are
  detected for any trading hours (e.g. early closes) and reported; snapshots
  carry `n_messages`, `n_trades`, `halted` and depth-truncation flags; time
  stamps are in `America/New_York`.
* Crossed books give `NA` book variables. One-sided books give `NA` midquote
  and spread, and depth 0 on the empty side.
* Order books are read in blocks and only as deep as the depth measures need,
  so memory use does not depend on the number of levels.
* A polars translation with the same functions and output is in `python/`.

# lobsteR 1.0.0

* Initial CRAN submission.
