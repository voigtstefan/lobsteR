# Writes the synthetic LOBSTER files used by the tests (R and Python).
# Run: Rscript make-fixtures.R [OUTPUT_DIR]   (default: the current directory)
# All prices are made up; no real LOBSTER data.

args <- commandArgs(trailingOnly = TRUE)
if (length(args)) setwd(args[1])

px <- function(usd) round(usd * 10000)
empty_ask <- c(9999999999, 0)
empty_bid <- c(-9999999999, 0)

# a book side as LOBSTER columns; missing levels become dummies
side <- function(prices, sizes, levels, empty) {
  out <- numeric(0)
  for (i in seq_len(levels)) {
    out <- c(out, if (i <= length(prices)) c(px(prices[i]), sizes[i]) else empty)
  }
  matrix(out, nrow = 2)
}
book_row <- function(ap, as, bp, bs, levels = 3) {
  a <- side(ap, as, levels, empty_ask)
  b <- side(bp, bs, levels, empty_bid)
  as.vector(rbind(a[1, ], a[2, ], b[1, ], b[2, ]))
}

write_day <- function(stem, events, mpid = TRUE) {
  msg <- do.call(rbind, lapply(events, function(e) {
    data.frame(
      ts = sprintf("%.9f", e$t), type = e$type, id = e$id, size = e$size,
      price = format(e$price, scientific = FALSE), dir = e$dir
    )
  }))
  if (mpid) msg$mpid <- "TEST"
  ob <- do.call(rbind, lapply(events, function(e) {
    format(e$book, scientific = FALSE, trim = TRUE)
  }))
  write.table(msg, paste0(stem, "_message_3.csv"),
    sep = ",", quote = FALSE, row.names = FALSE, col.names = FALSE
  )
  write.table(ob, paste0(stem, "_orderbook_3.csv"),
    sep = ",", quote = FALSE, row.names = FALSE, col.names = FALSE
  )
}

clock <- function(h, m, s) h * 3600 + m * 60 + s
ev <- function(t, type, id, size, price, dir, book) {
  list(t = t, type = type, id = id, size = size, price = price, dir = dir,
    book = book)
}

# ---- day A: 2024-03-20, regular hours ---------------------------------------
full <- book_row(c(100.02, 100.03, 100.04), c(300, 200, 100),
  c(100.00, 99.99, 99.98), c(400, 200, 100))
a400 <- book_row(c(100.02, 100.03, 100.04), c(400, 200, 100),
  c(100.00, 99.99, 99.98), c(400, 200, 100))
swept <- book_row(c(100.02, 100.03, 100.04), c(200, 200, 100),
  c(99.99, 99.98), c(200, 100))
during_halt <- book_row(c(100.05, 100.06, 100.07), c(100, 100, 100),
  c(100.00, 99.99, 99.98), c(400, 200, 100))
resumed <- book_row(c(100.03, 100.04, 100.05), c(100, 100, 100),
  c(100.01, 100.00, 99.99), c(100, 400, 200))
crossed <- book_row(c(99.99, 100.03, 100.04), c(50, 200, 100),
  c(100.00, 99.99, 99.98), c(400, 200, 100))

day_a <- list(
  # pre-market, one-sided book (ask side empty)
  ev(clock(8, 0, 0), 1, 1, 400, px(100.00), 1,
    book_row(numeric(0), numeric(0), 100.00, 400)),
  ev(clock(9, 0, 0), 1, 2, 300, px(100.02), -1, full),
  # executed before the opening cross: not continuous trading
  ev(clock(9, 30, 0.2), 4, 2, 10, px(100.02), -1, full),
  ev(clock(9, 30, 0.5), 6, -1, 5000, px(100.01), -1, full),
  ev(clock(9, 30, 0.5), 3, 9, 50, px(100.05), -1, full),
  # continuous trading
  ev(clock(9, 30, 1), 1, 3, 100, px(100.02), -1, a400),
  ev(clock(9, 30, 2), 4, 3, 100, px(100.02), -1, full),
  ev(clock(9, 30, 3), 5, 0, 50, px(100.01), 1, full),
  ev(clock(9, 30, 3), 5, 0, 20, px(100.015), 1, full),
  ev(clock(9, 30, 4), 5, 0, 30, px(100.005), 1, full),
  # sweep at one time stamp, both sides
  ev(clock(9, 30, 6), 4, 1, 400, px(100.00), 1,
    book_row(c(100.02, 100.03, 100.04), c(300, 200, 100),
      c(99.99, 99.98), c(200, 100))),
  ev(clock(9, 30, 6), 4, 2, 100, px(100.02), -1, swept),
  # nothing until 09:30:17: two empty intervals
  ev(clock(9, 30, 17), 1, 4, 400, px(100.00), 1,
    book_row(c(100.02, 100.03, 100.04), c(200, 200, 100),
      c(100.00, 99.99, 99.98), c(400, 200, 100))),
  ev(clock(9, 30, 18), 1, 5, 100, px(100.02), -1, full),
  # halt 11:00:00 - 11:05:00 with quoting resuming at 11:04:00
  ev(clock(11, 0, 0), 7, 0, 0, -1, -1, full),
  ev(clock(11, 2, 0), 1, 6, 100, px(100.05), -1, during_halt),
  ev(clock(11, 4, 0), 7, 0, 0, 0, -1, during_halt),
  ev(clock(11, 4, 30), 1, 7, 100, px(100.01), 1, resumed),
  ev(clock(11, 5, 0), 7, 0, 0, 1, -1, resumed),
  ev(clock(11, 5, 0), 6, -3, 700, px(100.02), -1, resumed),
  ev(clock(11, 5, 1), 4, 7, 100, px(100.01), 1, full),
  # a crossed book for one second
  ev(clock(12, 0, 0), 1, 8, 50, px(99.99), -1, crossed),
  ev(clock(12, 0, 0.5), 5, 0, 10, px(100.00), 1, crossed),
  ev(clock(12, 0, 1), 3, 8, 50, px(99.99), -1, full),
  ev(clock(15, 59, 59), 4, 2, 100, px(100.02), -1,
    book_row(c(100.02, 100.03, 100.04), c(200, 200, 100),
      c(100.00, 99.99, 99.98), c(400, 200, 100))),
  # closing cross exactly at 16:00:00, then a message after it
  ev(clock(16, 0, 0), 6, -2, 8000, px(100.02), -1, full),
  ev(clock(16, 0, 0), 3, 5, 100, px(100.02), -1, full),
  ev(clock(17, 0, 0), 1, 10, 100, px(100.03), -1, full)
)
write_day("TEST_2024-03-20_28800000_61200000", day_a, mpid = TRUE)

# ---- day B: 2024-11-29, early close at 13:00, halt without resumption ---
day_b <- list(
  ev(clock(9, 0, 0), 1, 1, 300, px(20.02), -1,
    book_row(c(20.02, 20.03), c(300, 200), c(20.00, 19.99, 19.98),
      c(400, 200, 100))),
  ev(clock(9, 30, 0.1), 6, -1, 1000, px(20.01), -1,
    book_row(c(20.02, 20.03), c(300, 200), c(20.00, 19.99, 19.98),
      c(400, 200, 100))),
  ev(clock(9, 30, 1), 4, 1, 100, px(20.02), -1,
    book_row(c(20.02, 20.03), c(200, 200), c(20.00, 19.99, 19.98),
      c(400, 200, 100))),
  # bid side empties: one-sided book
  ev(clock(10, 0, 0), 3, 2, 400, px(20.00), 1,
    book_row(c(20.02, 20.03), c(200, 200), numeric(0), numeric(0))),
  ev(clock(10, 0, 2), 1, 3, 400, px(20.00), 1,
    book_row(c(20.02, 20.03), c(200, 200), c(20.00, 19.99, 19.98),
      c(400, 200, 100))),
  ev(clock(12, 0, 0), 5, 0, 100, px(20.01), 1,
    book_row(c(20.02, 20.03), c(200, 200), c(20.00, 19.99, 19.98),
      c(400, 200, 100))),
  ev(clock(12, 30, 0), 7, 0, 0, -1, -1,
    book_row(c(20.02, 20.03), c(200, 200), c(20.00, 19.99, 19.98),
      c(400, 200, 100))),
  ev(clock(12, 45, 0), 1, 4, 100, px(20.05), -1,
    book_row(c(20.02, 20.03, 20.05), c(200, 200, 100),
      c(20.00, 19.99, 19.98), c(400, 200, 100))),
  ev(clock(13, 0, 0.1), 6, -2, 0, 0, -1,
    book_row(c(20.02, 20.03, 20.05), c(200, 200, 100),
      c(20.00, 19.99, 19.98), c(400, 200, 100))),
  ev(clock(13, 30, 0), 1, 5, 100, px(20.04), -1,
    book_row(c(20.02, 20.03, 20.04), c(200, 200, 100),
      c(20.00, 19.99, 19.98), c(400, 200, 100)))
)
write_day("TEST_2024-11-29_32400000_50400000", day_b, mpid = FALSE)
