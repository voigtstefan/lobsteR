#' Clean one LOBSTER day and aggregate it to snapshots
#'
#' Runs [lobster_clean()] and [lobster_snapshots()] for one day, given either
#' the day's message and order book files or a LOBSTER `.7z` archive and a
#' date. Files inside the archive are streamed, never unpacked to disk.
#'
#' @param message_file,orderbook_file character(1) or `NULL` Paths of the
#'   day's files, or member names inside `archive`. When `archive` is given
#'   they can be left out and are then found by `date`.
#' @param archive character(1) or `NULL` Path to a LOBSTER `.7z` archive.
#' @param date Date or character(1) The trading day to process from
#'   `archive`; not needed when the archive holds a single day.
#' @param freq numeric(1) Snapshot interval in seconds.
#' @param split_edges logical(1) Passed to [lobster_snapshots()].
#' @param ... Further arguments for [lobster_clean()], e.g. `trading_hours`,
#'   `depth_bp` or `cut_at_crosses`.
#'
#' @return The snapshots, as returned by [lobster_snapshots()]. Crosses,
#'   halts and the cleaning log are available with [lobster_crosses()],
#'   [lobster_halts()] and [lobster_log()].
#'
#' @examples
#' \dontrun{
#' snaps <- lobster_process(
#'   archive = "SPY_2024-02-27_2024-03-26_50.7z",
#'   date = "2024-03-20"
#' )
#' lobster_crosses(snaps)
#'
#' # all days of an archive
#' days <- lobster_archive_files("SPY_2024-02-27_2024-03-26_50.7z")
#' snaps <- lapply(days$date, function(d) {
#'   lobster_process(archive = "SPY_2024-02-27_2024-03-26_50.7z", date = d)
#' })
#' }
#' @export
lobster_process <- function(
  message_file = NULL,
  orderbook_file = NULL,
  archive = NULL,
  date = NULL,
  freq = 5,
  split_edges = TRUE,
  ...
) {
  if (is.null(message_file) || is.null(orderbook_file)) {
    if (is.null(archive)) {
      stop("Give 'message_file' and 'orderbook_file', or an 'archive'.",
        call. = FALSE
      )
    }
    days <- lobster_archive_files(archive)
    if (!is.null(date)) {
      days <- days[days$date == as.Date(date), , drop = FALSE]
    }
    if (nrow(days) != 1L) {
      stop(
        if (nrow(days) == 0L) "No files for this date in the archive." else
          "The archive holds several days; choose one with 'date'.",
        call. = FALSE
      )
    }
    message_file <- days$message_file
    orderbook_file <- days$orderbook_file
  }
  x <- lobster_clean(
    message_file, orderbook_file,
    archive = archive, date = date, ...
  )
  lobster_snapshots(x, freq = freq, split_edges = split_edges)
}
