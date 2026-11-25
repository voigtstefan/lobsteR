# Order book features, computed level by level without ever holding the whole
# order book in memory.
#
# All prices stay in LOBSTER's integer units (USD x 10000). Level i of a side
# is within `bp` basis points of the best price when
#   ask: 10000 * ask_price_i <= (10000 + bp) * ask_price_1
#   bid: 10000 * bid_price_i >= (10000 - bp) * bid_price_1
# Both sides of these comparisons are exact in double precision for integer
# `bp`, so R and Python give identical depth.
#
# Distinct levels have distinct prices, so level i + 1 can only lie within the
# threshold when level i lies strictly inside it. This gives an exact stopping
# rule (read deeper levels only while some row needs them) and the truncation
# flag: depth is truncated when the deepest level in the file is non-empty and
# strictly inside the threshold, so that further levels the file does not
# contain may hold volume within the threshold too.

ask_empty <- 9999990000 # dummy ask price 9999999999 = empty level
bid_empty <- 0 # dummy bid price -9999999999 = empty level

# `level(i)` returns list(ap, as, bp, bs) for level i (vectors of equal
# length). `k_max` is the deepest level `level()` can provide, `n_levels` the
# number of levels in the file.
book_accumulate <- function(level, k_max, n_levels, depth_bp) {
  l1 <- level(1L)
  a1 <- as.double(l1[[1]])
  b1 <- as.double(l1[[3]])
  n <- length(a1)
  nb <- length(depth_bp)
  thr_a <- lapply(depth_bp, function(bp) (10000 + bp) * a1)
  thr_b <- lapply(depth_bp, function(bp) (10000 - bp) * b1)
  jmax <- if (nb) which.max(depth_bp) else NA_integer_
  da <- rep(list(numeric(n)), nb)
  db <- rep(list(numeric(n)), nb)
  stopped <- FALSE
  i <- 0L
  for (i in seq_len(k_max)) {
    li <- if (i == 1L) l1 else level(i)
    ap <- as.double(li[[1]])
    bp <- as.double(li[[3]])
    pa <- 10000 * ap
    pb <- 10000 * bp
    for (j in seq_len(nb)) {
      da[[j]] <- da[[j]] + li[[2]] * (pa <= thr_a[[j]])
      db[[j]] <- db[[j]] + li[[4]] * (pb >= thr_b[[j]])
    }
    if (nb == 0L || max(depth_bp) <= 0) {
      stopped <- TRUE # only the best level is needed
      break
    }
    strict <- (pa < thr_a[[jmax]] & ap < ask_empty) |
      (pb > thr_b[[jmax]] & bp >= bid_empty)
    if (!any(strict)) {
      stopped <- TRUE
      break
    }
  }
  complete <- stopped || k_max >= n_levels
  trunc <- vector("list", nb)
  for (j in seq_len(nb)) {
    trunc[[j]] <- if (!stopped && complete) {
      (pa < thr_a[[j]] & ap < ask_empty) | (pb > thr_b[[j]] & bp >= bid_empty)
    } else {
      logical(n)
    }
  }
  list(
    complete = complete,
    need = i, # deepest level that had to be read
    a1 = a1,
    as1 = as.double(l1[[2]]),
    b1 = b1,
    bs1 = as.double(l1[[4]]),
    da = da,
    db = db,
    trunc = trunc
  )
}

book_to_table <- function(parts, depth_bp) {
  nb <- length(depth_bp)
  cat_list <- function(f) unlist(lapply(parts, f), use.names = FALSE)
  out <- list(
    a1 = cat_list(function(p) p$a1),
    as1 = cat_list(function(p) p$as1),
    b1 = cat_list(function(p) p$b1),
    bs1 = cat_list(function(p) p$bs1)
  )
  for (j in seq_len(nb)) {
    out[[paste0("da", j)]] <- cat_list(function(p) p$da[[j]])
    out[[paste0("db", j)]] <- cat_list(function(p) p$db[[j]])
    out[[paste0("tr", j)]] <- cat_list(function(p) p$trunc[[j]])
  }
  out
}

# Order book from a CSV file or archive member, block by block. Each block is
# parsed with only the first `k` levels; when a block needs deeper levels it
# is parsed again with all of them.
read_book_csv <- function(file, archive, n_levels, depth_bp, block_size) {
  con <- open_input(file, archive)
  on.exit(close(con))
  k <- n_levels
  k_used <- 0L
  parse <- function(path) {
    d <- fread_block(path, select = seq_len(4L * k))
    res <- book_accumulate(
      function(i) .subset(d, (4L * i - 3L):(4L * i)),
      k, n_levels, depth_bp
    )
    if (!res$complete) {
      d <- fread_block(path, select = seq_len(4L * n_levels))
      res <- book_accumulate(
        function(i) .subset(d, (4L * i - 3L):(4L * i)),
        n_levels, n_levels, depth_bp
      )
    }
    k_used <<- max(k_used, res$need)
    k <<- min(n_levels, res$need + 2L)
    res
  }
  parts <- read_csv_blocks(con, parse, block_size)
  out <- book_to_table(parts, depth_bp)
  attr(out, "levels_read") <- k_used
  out
}

# Order book from a parquet file (columns in LOBSTER order), level by level:
# only the columns of the levels that are needed are ever read.
read_book_parquet <- function(file, n_levels, depth_bp) {
  if (!requireNamespace("nanoparquet", quietly = TRUE)) {
    stop("Reading parquet order books needs the 'nanoparquet' package.",
      call. = FALSE
    )
  }
  level <- function(i) {
    # free the previous level's buffers before reading the next one
    gc(verbose = FALSE)
    nanoparquet::read_parquet(file, col_select = (4L * i - 3L):(4L * i))
  }
  res <- book_accumulate(level, n_levels, n_levels, depth_bp)
  out <- book_to_table(list(res), depth_bp)
  attr(out, "levels_read") <- res$need
  out
}
