#' Parse LOBSTER file and archive names
#'
#' LOBSTER names its files `{ticker}_{date}_{start}_{end}_{type}_{levels}.csv`,
#' where `start` and `end` are the requested time window in milliseconds after
#' midnight and `type` is `message` or `orderbook`. Monthly or daily archives
#' are named `{ticker}_{first date}_{last date}_{levels}.7z`. This function
#' extracts these fields from file names or full paths.
#'
#' The time window in a file name is the window that was requested from
#' LOBSTER. It does not mark the trading session: files often contain
#' messages from long before the open to long after the close.
#'
#' @param path character Paths or file names. Compressed CSV files
#'   (`.csv.gz`, `.csv.bz2`, `.csv.xz`) and `.parquet` files that keep the
#'   LOBSTER name are recognised as well.
#'
#' @return A data.frame with one row per path and columns `path`, `file`
#'   (`"message"`, `"orderbook"` or `"archive"`, `NA` if the name does not
#'   follow the LOBSTER convention), `ticker`, `date` (first trading day),
#'   `last_date` (last trading day; equal to `date` for message and order book
#'   files), `window_start` and `window_end` (requested window in seconds after
#'   midnight; `NA` for archives) and `levels`.
#'
#' @examples
#' lobster_file_info(c(
#'   "SPY_2024-03-20_34200000_57600000_message_10.csv",
#'   "data/SPY_2024-03-20_34200000_57600000_orderbook_10.csv",
#'   "SPY_2024-02-27_2024-03-26_50.7z",
#'   "notes.txt"
#' ))
#' @export
lobster_file_info <- function(path) {
  path <- as.character(path)
  name <- basename(path)
  re_file <- paste0(
    "^([^_]+)_([0-9]{4}-[0-9]{2}-[0-9]{2})_([0-9]+)_([0-9]+)_",
    "(message|orderbook)_([0-9]+)\\.(csv(\\.(gz|bz2|xz))?|parquet)$"
  )
  re_archive <- paste0(
    "^([^_]+)_([0-9]{4}-[0-9]{2}-[0-9]{2})_([0-9]{4}-[0-9]{2}-[0-9]{2})_",
    "([0-9]+)\\.(7z|zip)$"
  )
  n <- length(path)
  out <- data.frame(
    path = path,
    file = rep(NA_character_, n),
    ticker = rep(NA_character_, n),
    date = as.Date(rep(NA_character_, n)),
    last_date = as.Date(rep(NA_character_, n)),
    window_start = rep(NA_real_, n),
    window_end = rep(NA_real_, n),
    levels = rep(NA_integer_, n),
    stringsAsFactors = FALSE
  )
  is_file <- grepl(re_file, name)
  if (any(is_file)) {
    m <- regmatches(name[is_file], regexec(re_file, name[is_file]))
    m <- do.call(rbind, m)
    out$file[is_file] <- m[, 6]
    out$ticker[is_file] <- m[, 2]
    out$date[is_file] <- as.Date(m[, 3])
    out$last_date[is_file] <- as.Date(m[, 3])
    out$window_start[is_file] <- as.numeric(m[, 4]) / 1000
    out$window_end[is_file] <- as.numeric(m[, 5]) / 1000
    out$levels[is_file] <- as.integer(m[, 7])
  }
  is_archive <- !is_file & grepl(re_archive, name)
  if (any(is_archive)) {
    m <- regmatches(name[is_archive], regexec(re_archive, name[is_archive]))
    m <- do.call(rbind, m)
    out$file[is_archive] <- "archive"
    out$ticker[is_archive] <- m[, 2]
    out$date[is_archive] <- as.Date(m[, 3])
    out$last_date[is_archive] <- as.Date(m[, 4])
    out$levels[is_archive] <- as.integer(m[, 5])
  }
  out
}

#' List the message and order book files in a LOBSTER archive
#'
#' Reads the table of contents of a LOBSTER `.7z` archive (without unpacking
#' it) and pairs each day's message file with its order book file.
#'
#' @param archive character(1) Path to a `.7z` archive as downloaded from
#'   LOBSTER.
#'
#' @return A data.frame with one row per trading day and columns `ticker`,
#'   `date`, `levels`, `message_file`, `orderbook_file` (member names inside
#'   the archive), `window_start` and `window_end`.
#'
#' @examples
#' \dontrun{
#' lobster_archive_files("SPY_2024-02-27_2024-03-26_50.7z")
#' }
#' @export
lobster_archive_files <- function(archive) {
  members <- archive::archive(archive)$path
  info <- lobster_file_info(members)
  info <- info[!is.na(info$file) & info$file != "archive", , drop = FALSE]
  key <- paste(info$ticker, info$date, info$levels)
  msg <- info[info$file == "message", , drop = FALSE]
  ob <- info[info$file == "orderbook", , drop = FALSE]
  ob_key <- paste(ob$ticker, ob$date, ob$levels)
  msg_key <- paste(msg$ticker, msg$date, msg$levels)
  out <- data.frame(
    ticker = msg$ticker,
    date = msg$date,
    levels = msg$levels,
    message_file = msg$path,
    orderbook_file = ob$path[match(msg_key, ob_key)],
    window_start = msg$window_start,
    window_end = msg$window_end,
    stringsAsFactors = FALSE
  )
  out[order(out$ticker, out$date), , drop = FALSE]
}

# ---------------------------------------------------------------- internals

# Open a file, a compressed file or a member of an archive as a binary
# connection. Nothing is unpacked to disk. Archive members are streamed by the
# `7z` program when it is installed (multi-threaded, faster) and by libarchive
# (package 'archive') otherwise.
open_input <- function(file, archive = NULL) {
  if (is.null(archive)) {
    if (!file.exists(file)) {
      stop("File not found: ", file, call. = FALSE)
    }
    return(file(file, open = "rb"))
  }
  if (!file.exists(archive)) {
    stop("Archive not found: ", archive, call. = FALSE)
  }
  sevenzip <- Sys.which("7z")
  if (nzchar(sevenzip) && isTRUE(getOption("lobsteR.use_7z", TRUE))) {
    cmd <- paste(
      shQuote(sevenzip), "e -so -bso0 -bsp0",
      shQuote(normalizePath(archive)), shQuote(file)
    )
    return(pipe(cmd, open = "rb"))
  }
  con <- archive::archive_read(archive, file, mode = "rb")
  open(con, "rb")
  con
}

# Read a headerless CSV stream in blocks of about `block_size` bytes that end
# at a line break and call `parse(path)` on each block. Each block is written
# to one temporary file in tempdir() (overwritten block by block, removed at
# the end), which data.table::fread() parses much faster than text held in R.
# The block is completed up to the next line break with a few more bytes from
# the stream, so the large block itself is never copied. Memory stays bounded
# by the block size, whatever the size of the file.
read_csv_blocks <- function(con, parse, block_size = 2^27) {
  tmp <- tempfile("lobster-block-", fileext = ".csv")
  on.exit(unlink(tmp))
  nl <- as.raw(10L)
  left <- raw(0)
  out <- list()
  repeat {
    b <- readBin(con, "raw", block_size)
    if (length(b) == 0L && length(left) == 0L) {
      break
    }
    f <- file(tmp, open = "wb")
    writeBin(left, f)
    writeBin(b, f)
    left <- raw(0)
    last <- if (length(b)) b[length(b)] else as.raw(0L)
    if (last != nl) {
      repeat {
        s <- readBin(con, "raw", 65536L)
        if (length(s) == 0L) {
          writeBin(nl, f)
          break
        }
        j <- match(nl, s)
        if (is.na(j)) {
          writeBin(s, f)
          next
        }
        writeBin(s[seq_len(j)], f)
        if (j < length(s)) left <- s[(j + 1L):length(s)]
        break
      }
    }
    close(f)
    rm(b)
    out[[length(out) + 1L]] <- parse(tmp)
  }
  out
}

# Number of fields in the first line of a CSV input.
count_fields <- function(file, archive = NULL) {
  con <- open_input(file, archive)
  on.exit(close(con))
  b <- readBin(con, "raw", 65536L)
  nl <- which(b == as.raw(10L))
  first <- if (length(nl)) b[seq_len(nl[1] - 1L)] else b
  sum(first == as.raw(44L)) + 1L
}

fread_block <- function(path, select = NULL) {
  data.table::fread(
    file = path,
    sep = ",",
    header = FALSE,
    select = select,
    integer64 = "double",
    showProgress = FALSE
  )
}

# Seconds after midnight from "HH:MM", "HH:MM:SS(.sss)" or numbers.
parse_clock <- function(x) {
  if (is.numeric(x)) {
    return(as.numeric(x))
  }
  x <- as.character(x)
  vapply(
    strsplit(x, ":", fixed = TRUE),
    function(p) {
      p <- as.numeric(p)
      if (length(p) < 2L || length(p) > 3L || anyNA(p)) {
        stop("Cannot read trading hours '", paste(p, collapse = ":"),
          "'; use 'HH:MM' or 'HH:MM:SS'.",
          call. = FALSE
        )
      }
      if (length(p) == 2L) p <- c(p, 0)
      sum(p * c(3600, 60, 1))
    },
    numeric(1)
  )
}

ny_midnight <- function(date) {
  as.numeric(as.POSIXct(format(as.Date(date)), tz = "America/New_York"))
}

as_ny_time <- function(seconds, date) {
  .POSIXct(ny_midnight(date) + seconds, tz = "America/New_York")
}
