# Synthetic LOBSTER days written by fixtures/make-fixtures.R (no real data).
# Day A (2024-03-20): opening cross 09:30:00.5, halt 11:00-11:05 with quoting
# resuming at 11:04, a crossed book at 12:00, closing cross at 16:00:00,
# pre- and post-market messages, dummy prices.
# Day B (2024-11-29): early close at 13:00, halt at 12:30 without resumption,
# one-sided book at 10:00, closing cross without volume.

fixture <- function(day, type) {
  stem <- c(
    a = "TEST_2024-03-20_28800000_61200000",
    b = "TEST_2024-11-29_32400000_50400000"
  )[[day]]
  test_path("fixtures", paste0(stem, "_", type, "_3.csv"))
}
clean_a <- function(...) {
  lobster_clean(fixture("a", "message"), fixture("a", "orderbook"),
    depth_bp = c(0, 1, 5), ...
  )
}
clean_b <- function(...) {
  lobster_clean(fixture("b", "message"), fixture("b", "orderbook"),
    trading_hours = c("09:30", "13:00"), ...
  )
}
at <- function(s, hms) {
  s[format(s$ts, "%H:%M:%S") == hms]
}

test_that("file names are parsed", {
  info <- lobster_file_info(c(
    "dir/SPY_2024-03-20_34200000_57600000_message_50.csv",
    "BRK.B_2024-03-20_34200000_57600000_orderbook_10.csv.gz",
    "SPY_2024-02-27_2024-03-26_50.7z",
    "notes.txt"
  ))
  expect_equal(info$file, c("message", "orderbook", "archive", NA))
  expect_equal(info$ticker, c("SPY", "BRK.B", "SPY", NA))
  expect_equal(info$date, as.Date(c("2024-03-20", "2024-03-20", "2024-02-27", NA)))
  expect_equal(info$last_date[3], as.Date("2024-03-26"))
  expect_equal(info$window_start[1:2], c(34200, 34200))
  expect_equal(info$window_end[1], 57600)
  expect_equal(info$levels, c(50L, 10L, 50L, NA))
})

test_that("ticker, date and levels come from the files", {
  x <- clean_a()
  meta <- attr(x, "lobster")
  expect_equal(meta$ticker, "TEST")
  expect_equal(meta$date, as.Date("2024-03-20"))
  expect_equal(meta$levels, 3L)
  expect_equal(meta$window, c(28800, 61200))
  expect_equal(attr(x$time, "tzone"), "America/New_York")
  expect_equal(format(x$time[1], "%Y-%m-%d %H:%M:%S"), "2024-03-20 09:30:01")
})

test_that("crosses are reported and cut continuous trading", {
  x <- clean_a()
  cr <- lobster_crosses(x)
  expect_equal(cr$kind, c("opening", "other", "closing"))
  expect_equal(cr$ts, c(34200.5, 39900, 57600))
  expect_equal(cr$size, c(5000, 700, 8000))
  expect_equal(cr$price, c(100.01, 100.02, 100.02))
  expect_equal(cr$dollar_volume, c(500050, 70014, 800160))
  # session: strictly after the opening cross, strictly before the close cross
  expect_equal(lobster_log(x)$session_start, 34200.5)
  expect_equal(lobster_log(x)$session_end, 57600)
  expect_true(all(x$ts > 34200.5 & x$ts < 57600))
  expect_false(any(x$type %in% c(6L, 7L)))
  # the pre-cross execution at 09:30:00.2 is not continuous trading
  expect_false(34200.2 %in% x$ts)
  # without the cut, the session runs over the whole trading hours
  y <- clean_a(cut_at_crosses = FALSE)
  expect_true(34200.2 %in% y$ts)
  expect_true(all(y$ts >= 34200 & y$ts <= 57600))
  expect_equal(sum(y$ts == 57600), 1L) # the deletion after the closing cross
})

test_that("halts are paired by type and their messages dropped", {
  x <- clean_a()
  h <- lobster_halts(x)
  expect_equal(nrow(h), 1L)
  expect_equal(c(h$start, h$end), c(39600, 39900)) # quoting resumption ignored
  expect_true(h$resumed)
  expect_false(any(x$ts >= 39600 & x$ts <= 39900))
  expect_equal(lobster_log(x)$n_in_halts, 2L)

  # a halt without resumption lasts to the close (day B)
  b <- clean_b()
  hb <- lobster_halts(b)
  expect_equal(hb$start, 45000)
  expect_equal(hb$end, 46800)
  expect_false(hb$resumed)
  expect_false(any(b$ts >= 45000))
})

test_that("pair_halts handles unmatched resumptions and repeated halts", {
  h <- pair_halts(c(1, 2, 3, 4, 5, 6), c(1, -1, -1, 0, 1, -1))
  expect_equal(h$start_ns, c(2, 6))
  expect_equal(h$end_ns, c(5, Inf))
})

test_that("trades are signed; midpoint trades are unsigned", {
  x <- clean_a()
  tr <- x[x$type %in% c(4L, 5L)]
  # visible: opposite of the resting side
  expect_equal(tr$trade_sign[tr$ts == 34202], 1L)
  expect_equal(tr$trade_sign[tr$ts == 34206], c(-1L, 1L))
  # hidden, against the midquote before the trade (100.01)
  expect_equal(tr$trade_sign[tr$ts == 34203], c(0L, 1L))
  expect_equal(tr$midpoint[tr$ts == 34203], c(TRUE, FALSE))
  expect_equal(tr$trade_sign[tr$ts == 34204], -1L)
  # hidden trade in a crossed book: no valid quote before it
  expect_equal(tr$trade_sign[tr$ts == 43200.5], 0L)
  expect_false(tr$midpoint[tr$ts == 43200.5])
  expect_equal(lobster_log(x)$n_midpoint_trades, 1L)
})

test_that("book variables, dummies, depth and truncation", {
  x <- clean_a()
  r <- x[x$ts == 34201]
  expect_equal(c(r$best_ask, r$best_bid, r$midquote), c(100.02, 100, 100.01))
  expect_equal(r$spread, 10000 * 0.02 / 100.01)
  expect_equal(c(r$depth0_ask, r$depth1_ask, r$depth5_ask), c(400, 600, 700))
  expect_equal(c(r$depth0_bid, r$depth1_bid, r$depth5_bid), c(400, 600, 700))
  # 1 bp: the third level lies outside, so depth is complete
  expect_false(r$depth1_truncated)
  # 5 bp: all three levels lie inside, more may exist beyond the file
  expect_true(r$depth5_truncated)
  # after the sweep the bid side has two levels and a dummy
  s <- x[x$ts == 34206][2]
  expect_equal(c(s$depth5_bid, s$depth1_bid, s$depth0_bid), c(300, 200, 200))
  # crossed book: all book variables NA
  cr <- x[x$ts == 43200]
  expect_true(is.na(cr$midquote) && is.na(cr$spread) && is.na(cr$depth5_ask))
  expect_equal(lobster_log(x)$n_crossed_book, 2L)
  # one-sided book (day B, bid side empty): no midquote or spread, but depth,
  # with 0 on the empty side
  b <- clean_b()
  ob <- b[b$ts == 36000]
  expect_true(is.na(ob$midquote) && is.na(ob$spread) && is.na(ob$best_bid))
  expect_equal(ob$best_ask, 20.02)
  expect_equal(c(ob$depth0_ask, ob$depth5_ask), c(200, 400))
  expect_equal(c(ob$depth0_bid, ob$depth5_bid), c(0, 0))
  expect_false(ob$depth5_truncated)
  expect_equal(lobster_log(b)$n_invalid_book, 1L)
})

test_that("only the levels needed are read", {
  x <- lobster_clean(fixture("a", "message"), fixture("a", "orderbook"),
    depth_bp = 0
  )
  expect_equal(attr(x, "lobster")$levels_read, 1L)
  y <- lobster_clean(fixture("a", "message"), fixture("a", "orderbook"),
    depth_bp = 1
  )
  # same depth whether the file is parsed in one block or in tiny blocks
  z <- lobster_clean(fixture("a", "message"), fixture("a", "orderbook"),
    depth_bp = 1, block_size = 200
  )
  expect_equal(y$depth1_ask, z$depth1_ask)
  expect_equal(y$depth1_bid, z$depth1_bid)
  expect_equal(y$depth1_truncated, z$depth1_truncated)
  expect_equal(y$ts, z$ts)
})

test_that("snapshots: volumes, signs, edges and empty intervals", {
  s <- lobster_snapshots(clean_a(), freq = 5)
  expect_equal(attr(s$ts, "tzone"), "America/New_York")
  expect_equal(nrow(s), 4680L)
  expect_equal(format(range(s$ts), "%H:%M:%S"), c("09:30:05", "16:00:00"))

  a <- at(s, "09:30:05")
  expect_equal(a$signed_volume, 100 + 20 - 30)
  expect_equal(a$trading_volume, 100 * 100.02 + 50 * 100.01 + 20 * 100.015 + 30 * 100.005)
  expect_equal(a$midpoint_volume, 50 * 100.01)
  expect_equal(c(a$n_messages, a$n_trades), c(5L, 4L))
  # time weights from the opening cross (09:30:00.5): 0.5 s at 300, 1 s at
  # 400, 3 s at 300
  expect_equal(a$depth0_ask, (0.5 * 300 + 1 * 400 + 3 * 300) / 4.5)

  # a sweep with both signs at one time stamp: exact net volume
  b <- at(s, "09:30:10")
  expect_equal(b$signed_volume, -400 + 100)
  expect_equal(b$depth0_ask, (1 * 300 + 4 * 200) / 5)

  # an empty interval carries the book state in force, not the last average
  e <- at(s, "09:30:15")
  expect_equal(e$n_messages, 0L)
  expect_true(is.na(e$signed_volume))
  expect_equal(e$trading_volume, 0)
  expect_equal(c(e$depth0_ask, e$depth0_bid), c(200, 200))
  expect_equal(e$midquote, 100.005)

  # state split at an edge: 2 s at 200, 1 s at 200, 2 s at 300
  f <- at(s, "09:30:20")
  expect_equal(f$depth0_ask, (2 * 200 + 1 * 200 + 2 * 300) / 5)
  expect_true(is.na(f$signed_volume)) # messages but no trade
  expect_equal(f$n_messages, 2L)
})

test_that("snapshots: halts, crossed books and the close", {
  s <- lobster_snapshots(clean_a(), freq = 5)
  expect_false(at(s, "11:00:00")$halted)
  expect_true(all(s$halted[format(s$ts, "%H:%M:%S") > "11:00:00" &
    format(s$ts, "%H:%M:%S") <= "11:05:00"]))
  expect_equal(sum(s$halted), 60L)
  h <- at(s, "11:02:00")
  expect_true(is.na(h$spread))
  expect_equal(h$midquote, 100.01) # last midquote before the halt
  expect_equal(h$trading_volume, 0)
  expect_equal(at(s, "11:05:00")$midquote, 100.02) # book at the resumption
  r <- at(s, "11:05:05")
  expect_false(r$halted)
  expect_equal(r$depth0_ask, (1 * 100 + 4 * 300) / 5)
  # crossed for one second: those states carry no weight
  cr <- at(s, "12:00:00")
  expect_equal(cr$depth0_ask, 300)
  expect_equal(at(s, "12:00:05")$depth0_ask, 300)
  # the last snapshot ends at 16:00:00; the cross is not part of it
  l <- s[nrow(s)]
  expect_equal(l$trading_volume, 100 * 100.02)
  expect_equal(l$depth0_ask, (4 * 300 + 1 * 200) / 5)
})

test_that("early close at 13:00 and a halt until the close", {
  b <- clean_b()
  expect_equal(lobster_log(b)$session_start, 34200.1)
  expect_equal(lobster_log(b)$session_end, 46800)
  cr <- lobster_crosses(b)
  expect_equal(cr$kind, c("opening", "closing"))
  expect_true(is.na(cr$price[2])) # cross without volume
  s <- lobster_snapshots(b, freq = 60)
  expect_equal(format(range(s$ts), "%H:%M"), c("09:31", "13:00"))
  expect_true(all(s$halted[format(s$ts, "%H:%M") > "12:30"]))
  expect_true(all(is.na(s$spread[format(s$ts, "%H:%M") > "12:30"])))
  # one-sided book from 10:00:00 to 10:00:02: depth 0 on the empty side,
  # no spread
  m <- format(s$ts, "%H:%M") == "10:01"
  expect_equal(s$depth0_bid[m], (2 * 0 + 58 * 400) / 60)
  expect_equal(s$depth0_ask[m], 200)
  expect_equal(s$spread[m], 10000 * 0.02 / 20.01)
  # with the default 16:00 close, the closing cross ends the session
  expect_warning(
    b16 <- lobster_clean(fixture("b", "message"), fixture("b", "orderbook")),
    "closing cross"
  )
  expect_equal(lobster_log(b16)$session_end, 46800.1)
  expect_false(any(b16$ts > 46800.1))
})

test_that("legacy weighting reproduces the blog code's rule", {
  x <- clean_a()
  s <- lobster_snapshots(x, split_edges = FALSE)
  # the first interval: states weighted to the next message, from 09:30:01
  a <- at(s, "09:30:05")
  expect_equal(a$depth0_ask, (1 * 400 + 1 * 300 + 1 * 300 + 2 * 300) / 5)
  # empty interval repeats the previous interval's average
  expect_equal(at(s, "09:30:15")$depth0_ask, at(s, "09:30:10")$depth0_ask)
  # unchanged parts
  s2 <- lobster_snapshots(x)
  expect_equal(s$midquote, s2$midquote)
  expect_equal(s$trading_volume, s2$trading_volume)
})

test_that("archives are streamed without unpacking", {
  skip_on_cran()
  dir <- withr::local_tempdir()
  arch <- file.path(dir, "TEST_2024-03-20_2024-03-20_3.7z")
  ok <- tryCatch(
    {
      archive::archive_write_files(
        arch,
        c(fixture("a", "message"), fixture("a", "orderbook")),
        format = "7zip"
      )
      TRUE
    },
    error = function(e) FALSE
  )
  skip_if_not(ok, "libarchive cannot write 7z here")
  files <- lobster_archive_files(arch)
  expect_equal(nrow(files), 1L)
  expect_equal(files$date, as.Date("2024-03-20"))
  s1 <- lobster_process(archive = arch, depth_bp = c(0, 1, 5))
  s2 <- lobster_snapshots(clean_a())
  expect_equal(s1, s2, ignore_attr = TRUE)
  expect_equal(nrow(lobster_crosses(s1)), 3L)
  # libarchive instead of the 7z program
  s3 <- withr::with_options(
    list(lobsteR.use_7z = FALSE),
    lobster_process(archive = arch, depth_bp = c(0, 1, 5))
  )
  expect_equal(s3, s2, ignore_attr = TRUE)
})

test_that("input errors are clear", {
  expect_error(
    lobster_clean("x_message.csv", fixture("a", "orderbook"), date = "2024-03-20"),
    "not found"
  )
  expect_error(clean_a(trading_hours = c("16:00", "09:30")), "start before")
  expect_error(lobster_snapshots(data.frame(ts = 1)), "metadata")
  expect_error(lobster_process(), "archive")
})
