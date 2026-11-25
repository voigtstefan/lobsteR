"""Clean LOBSTER data and aggregate it to regular snapshots, with polars.

Python counterpart of the R functions lobster_clean(), lobster_snapshots(),
lobster_process(), lobster_file_info() and lobster_archive_files() in the
lobsteR package. Both implementations follow the same steps and give the same
output to floating-point precision; see the R documentation (?lobster_clean,
?lobster_snapshots) for the definitions of all columns.

Requirements: polars and numpy; the `7z` program for reading from .7z
archives. Files inside archives are streamed (`7z e -so`), never unpacked to
disk, and the order book is processed block by block, so memory use does not
grow with the size of the order book file.

Example
-------
>>> import lobster_clean as lc
>>> day = lc.lobster_process(archive="SPY_2024-02-27_2024-03-26_50.7z",
...                          date="2024-03-20")
>>> day.snapshots            # 5-second snapshots (polars DataFrame)
>>> day.crosses, day.halts   # opening/closing crosses, trading halts
>>> day.log                  # message counts
"""

from __future__ import annotations

import dataclasses
import datetime as dt
import gzip
import os
import re
import shutil
import subprocess
from typing import Callable, Iterable, Sequence

import numpy as np
import polars as pl

__all__ = [
    "LobsterDay",
    "lobster_file_info",
    "lobster_archive_files",
    "lobster_clean",
    "lobster_snapshots",
    "lobster_process",
]

NY = "America/New_York"
ASK_EMPTY = 9999990000.0  # dummy ask price 9999999999 = empty level
BID_EMPTY = 0.0  # dummy bid price -9999999999 = empty level


# --------------------------------------------------------------------- files

_RE_FILE = re.compile(
    r"^([^_]+)_([0-9]{4}-[0-9]{2}-[0-9]{2})_([0-9]+)_([0-9]+)_"
    r"(message|orderbook)_([0-9]+)\.(csv(\.(gz|bz2|xz))?|parquet)$"
)
_RE_ARCHIVE = re.compile(
    r"^([^_]+)_([0-9]{4}-[0-9]{2}-[0-9]{2})_([0-9]{4}-[0-9]{2}-[0-9]{2})_"
    r"([0-9]+)\.(7z|zip)$"
)


def lobster_file_info(paths: str | Iterable[str]) -> pl.DataFrame:
    """Parse LOBSTER file names ({ticker}_{date}_{start}_{end}_{type}_{levels}.csv)
    and archive names ({ticker}_{first}_{last}_{levels}.7z).

    Returns one row per path with columns path, file ("message", "orderbook",
    "archive" or null), ticker, date, last_date, window_start, window_end
    (requested window in seconds after midnight) and levels.
    """
    if isinstance(paths, str):
        paths = [paths]
    rows = []
    for p in paths:
        name = os.path.basename(p)
        r = dict(path=p, file=None, ticker=None, date=None, last_date=None,
                 window_start=None, window_end=None, levels=None)
        m = _RE_FILE.match(name)
        if m:
            d = dt.date.fromisoformat(m.group(2))
            r.update(file=m.group(5), ticker=m.group(1), date=d, last_date=d,
                     window_start=int(m.group(3)) / 1000,
                     window_end=int(m.group(4)) / 1000, levels=int(m.group(6)))
        else:
            m = _RE_ARCHIVE.match(name)
            if m:
                r.update(file="archive", ticker=m.group(1),
                         date=dt.date.fromisoformat(m.group(2)),
                         last_date=dt.date.fromisoformat(m.group(3)),
                         levels=int(m.group(4)))
        rows.append(r)
    schema = dict(path=pl.String, file=pl.String, ticker=pl.String, date=pl.Date,
                  last_date=pl.Date, window_start=pl.Float64,
                  window_end=pl.Float64, levels=pl.Int32)
    return pl.DataFrame(rows, schema=schema)


def _sevenzip() -> str:
    """The 7-Zip program: 7z (p7zip or 7-Zip), 7zz or 7za."""
    for name in ("7z", "7zz", "7za"):
        path = shutil.which(name)
        if path:
            return path
    raise FileNotFoundError("reading .7z archives needs the 7z program (7-Zip or p7zip)")


def _archive_members(archive: str) -> list[str]:
    out = subprocess.run([_sevenzip(), "l", "-slt", archive], check=True,
                         capture_output=True, text=True).stdout
    # the first "Path = " line is the archive itself; lobster_file_info() ignores it
    return [line[7:] for line in out.splitlines() if line.startswith("Path = ")]


def lobster_archive_files(archive: str) -> pl.DataFrame:
    """Pair each day's message and order book file inside a LOBSTER .7z archive."""
    info = lobster_file_info(_archive_members(archive))
    info = info.filter(pl.col("file").is_in(["message", "orderbook"]))
    msg = info.filter(pl.col("file") == "message")
    ob = info.filter(pl.col("file") == "orderbook").select(
        "ticker", "date", "levels", pl.col("path").alias("orderbook_file"))
    return (msg.select("ticker", "date", "levels", pl.col("path").alias("message_file"),
                       "window_start", "window_end")
            .join(ob, on=["ticker", "date", "levels"], how="left")
            .select("ticker", "date", "levels", "message_file", "orderbook_file",
                    "window_start", "window_end")
            .sort("ticker", "date"))


class _Input:
    """A file, a gzip file or a member of a .7z archive as a binary stream."""

    def __init__(self, file: str, archive: str | None = None):
        self.proc = None
        if archive is None:
            if not os.path.exists(file):
                raise FileNotFoundError(file)
            self.stream = gzip.open(file, "rb") if file.endswith(".gz") else open(file, "rb")
        else:
            if not os.path.exists(archive):
                raise FileNotFoundError(archive)
            self.proc = subprocess.Popen([_sevenzip(), "e", "-so", archive, file],
                                         stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            self.stream = self.proc.stdout

    def __enter__(self):
        return self.stream

    def __exit__(self, *exc):
        self.stream.close()
        if self.proc is not None:
            self.proc.kill()
            self.proc.wait()


def _read_csv_blocks(stream, parse: Callable[[bytes], object], block_size: int) -> list:
    """Call parse() on blocks of about block_size bytes that end at a line break."""
    out, left = [], b""
    while True:
        b = stream.read(block_size)
        if not b:
            if left:
                out.append(parse(left + b"\n"))
            break
        if left:
            b = left + b
        i = b.rfind(b"\n")
        if i < 0:
            left = b
            continue
        left = b[i + 1:]
        out.append(parse(b[: i + 1]))
    return out


def _count_fields(file: str, archive: str | None) -> int:
    with _Input(file, archive) as s:
        first = s.read(65536).split(b"\n", 1)[0]
    return first.count(b",") + 1


def _read_block(text: bytes, ncol: int, float_first: bool = False) -> pl.DataFrame:
    cols = [f"column_{i}" for i in range(ncol)]
    over = {c: pl.Int64 for c in cols}
    if float_first:
        over["column_0"] = pl.Float64
    return pl.read_csv(text, has_header=False, columns=cols, schema_overrides=over)


def _parse_clock(x) -> float:
    if isinstance(x, (int, float)):
        return float(x)
    p = [float(v) for v in str(x).split(":")]
    if len(p) == 2:
        p.append(0.0)
    if len(p) != 3:
        raise ValueError(f"cannot read trading hours {x!r}; use 'HH:MM' or 'HH:MM:SS'")
    return p[0] * 3600 + p[1] * 60 + p[2]


def _ny_time(seconds, date: dt.date) -> pl.Series:
    """Seconds after midnight (New York clock) -> Datetime(ns, America/New_York)."""
    ns = np.round(np.asarray(seconds, dtype=np.float64) * 1e9).astype(np.int64)
    base = (dt.date(date.year, date.month, date.day) - dt.date(1970, 1, 1)).days * 86_400 * 10**9
    return (pl.Series(ns + base, dtype=pl.Int64).cast(pl.Datetime("ns"))
            .dt.replace_time_zone(NY))


# ---------------------------------------------------------------- order book

def _book_accumulate(level: Callable[[int], tuple], k_max: int, n_levels: int,
                     depth_bp: Sequence[float]) -> dict:
    """Depth within each bp distance of the best price, level by level (see R)."""
    ap1, as1, bp1, bs1 = level(1)
    a1, b1 = ap1, bp1
    n, nb = len(a1), len(depth_bp)
    thr_a = [(10000.0 + bp) * a1 for bp in depth_bp]
    thr_b = [(10000.0 - bp) * b1 for bp in depth_bp]
    jmax = int(np.argmax(depth_bp)) if nb else None
    da = [np.zeros(n) for _ in range(nb)]
    db = [np.zeros(n) for _ in range(nb)]
    stopped, i = False, 0
    pa = pb = ap = bp_ = None
    for i in range(1, k_max + 1):
        ap, sa, bp_, sb = (ap1, as1, bp1, bs1) if i == 1 else level(i)
        pa, pb = 10000.0 * ap, 10000.0 * bp_
        for j in range(nb):
            da[j] = da[j] + sa * (pa <= thr_a[j])
            db[j] = db[j] + sb * (pb >= thr_b[j])
        if nb == 0 or max(depth_bp) <= 0:
            stopped = True
            break
        strict = ((pa < thr_a[jmax]) & (ap < ASK_EMPTY)) | ((pb > thr_b[jmax]) & (bp_ >= BID_EMPTY))
        if not strict.any():
            stopped = True
            break
    complete = stopped or k_max >= n_levels
    trunc = []
    for j in range(nb):
        if not stopped and complete:
            trunc.append(((pa < thr_a[j]) & (ap < ASK_EMPTY)) | ((pb > thr_b[j]) & (bp_ >= BID_EMPTY)))
        else:
            trunc.append(np.zeros(n, dtype=bool))
    return dict(complete=complete, need=i, a1=a1, as1=as1, b1=b1, bs1=bs1,
                da=da, db=db, trunc=trunc)


def _levels_from_frame(d: pl.DataFrame):
    def level(i):
        c = d.columns[4 * i - 4: 4 * i]
        return tuple(d[x].cast(pl.Float64).to_numpy() for x in c)
    return level


def _book_concat(parts: list[dict], nb: int) -> dict:
    def cat(f):
        return np.concatenate([f(p) for p in parts]) if parts else np.zeros(0)

    out = dict(a1=cat(lambda p: p["a1"]), as1=cat(lambda p: p["as1"]),
               b1=cat(lambda p: p["b1"]), bs1=cat(lambda p: p["bs1"]))
    for j in range(nb):
        out[f"da{j}"] = cat(lambda p: p["da"][j])
        out[f"db{j}"] = cat(lambda p: p["db"][j])
        out[f"tr{j}"] = cat(lambda p: p["trunc"][j])
    return out


def _read_book_csv(file, archive, n_levels, depth_bp, block_size):
    state = dict(k=n_levels, used=0)

    def parse(text):
        k = state["k"]
        d = _read_block(text, 4 * k)
        res = _book_accumulate(_levels_from_frame(d), k, n_levels, depth_bp)
        if not res["complete"]:
            d = _read_block(text, 4 * n_levels)
            res = _book_accumulate(_levels_from_frame(d), n_levels, n_levels, depth_bp)
        state["used"] = max(state["used"], res["need"])
        state["k"] = min(n_levels, res["need"] + 2)
        return res

    with _Input(file, archive) as s:
        parts = _read_csv_blocks(s, parse, block_size)
    out = _book_concat(parts, len(depth_bp))
    out["levels_read"] = state["used"]
    return out


def _read_book_parquet(file, n_levels, depth_bp):
    lf = pl.scan_parquet(file)
    names = lf.collect_schema().names()

    def level(i):
        c = names[4 * i - 4: 4 * i]
        d = lf.select(c).collect()
        return tuple(d[x].cast(pl.Float64).to_numpy() for x in c)

    res = _book_accumulate(level, n_levels, n_levels, depth_bp)
    out = _book_concat([res], len(depth_bp))
    out["levels_read"] = res["need"]
    return out


# ------------------------------------------------------------------ cleaning

@dataclasses.dataclass
class LobsterDay:
    """One cleaned LOBSTER day.

    messages:   one row per message of continuous trading (see ?lobster_clean in R)
    crosses:    all cross messages (type 6) with kind, size, price, dollar volume
    halts:      trading halts that overlap continuous trading
    boundaries: book states at the session start, halt ends, and markers
    info:       ticker, date, levels, trading hours, session start and end, ...
    log:        message counts (dropped, kept, invalid books, trades)
    snapshots:  filled by lobster_process()
    """
    messages: pl.DataFrame | None
    crosses: pl.DataFrame
    halts: pl.DataFrame
    boundaries: pl.DataFrame
    info: dict
    log: dict
    snapshots: pl.DataFrame | None = None


def _depth_names(depth_bp):
    def fmt(bp):
        s = repr(float(bp))
        return s[:-2] if s.endswith(".0") else s
    bps = [fmt(b) for b in depth_bp]
    return ([f"depth{b}_ask" for b in bps], [f"depth{b}_bid" for b in bps],
            [f"depth{b}_truncated" for b in bps])


def lobster_clean(message_file: str, orderbook_file: str, archive: str | None = None,
                  ticker: str | None = None, date=None,
                  trading_hours=("09:30:00", "16:00:00"), depth_bp=(0, 5),
                  cut_at_crosses: bool = True, block_size: int = 2 ** 27) -> LobsterDay:
    """Clean one day of LOBSTER data; same steps and arguments as lobster_clean() in R."""
    depth_bp = sorted({float(b) for b in (depth_bp or [])})
    if any(b < 0 for b in depth_bp):
        raise ValueError("depth_bp must hold non-negative numbers")
    hours = [_parse_clock(h) for h in trading_hours]
    if len(hours) != 2 or hours[0] >= hours[1]:
        raise ValueError("trading_hours must give a start before an end")

    info_m = lobster_file_info(message_file).row(0, named=True)
    info_o = lobster_file_info(orderbook_file).row(0, named=True)
    ticker = ticker or info_m["ticker"] or info_o["ticker"]
    if date is None:
        date = info_m["date"] or info_o["date"]
    if date is None:
        raise ValueError("cannot read the date from the file names; pass date")
    if isinstance(date, str):
        date = dt.date.fromisoformat(date)

    is_parquet = orderbook_file.endswith(".parquet")
    if is_parquet:
        if archive is not None:
            raise ValueError("a parquet order book cannot be read from an archive")
        n_cols = len(pl.scan_parquet(orderbook_file).collect_schema())
    else:
        n_cols = _count_fields(orderbook_file, archive)
    if n_cols % 4:
        raise ValueError(f"the order book has {n_cols} columns, not a multiple of 4")
    n_levels = n_cols // 4
    if info_o["levels"] is not None and info_o["levels"] != n_levels:
        import warnings
        warnings.warn(f"the file name says {info_o['levels']} levels, the file holds {n_levels}")

    with _Input(message_file, archive) as s:
        parts = _read_csv_blocks(s, lambda t: _read_block(t, 6, float_first=True), block_size)
    msg = pl.concat(parts) if parts else _read_block(b"0,0,0,0,0,0\n", 6, True).clear()
    msg.columns = ["ts", "type", "order_id", "size", "price", "direction"]

    book = (_read_book_parquet(orderbook_file, n_levels, depth_bp) if is_parquet
            else _read_book_csv(orderbook_file, archive, n_levels, depth_bp, block_size))
    if len(book["a1"]) != msg.height:
        raise ValueError(f"the message file has {msg.height} rows but the order book "
                         f"{len(book['a1'])}")
    return _clean_day(msg, book, ticker=ticker, date=date, n_levels=n_levels,
                      levels_read=book["levels_read"], hours=hours, depth_bp=depth_bp,
                      cut_at_crosses=cut_at_crosses,
                      window=(info_m["window_start"], info_m["window_end"]))


def _pair_halts(ts_ns, price):
    starts, ends, open_ = [], [], None
    for t, p in zip(ts_ns, price):
        if p == -1 and open_ is None:
            open_ = t
        elif p == 1 and open_ is not None:
            starts.append(open_)
            ends.append(t)
            open_ = None
    if open_ is not None:
        starts.append(open_)
        ends.append(np.inf)
    return np.array(starts, dtype=np.float64), np.array(ends, dtype=np.float64)


def _clean_day(msg, book, ticker, date, n_levels, levels_read, hours, depth_bp,
               cut_at_crosses, window) -> LobsterDay:
    n = msg.height
    ts = msg["ts"].cast(pl.Float64).to_numpy()
    ts_ns = np.round(ts * 1e9)
    if np.any(np.diff(ts_ns) < 0):
        raise ValueError("message time stamps are not in order")
    typ = msg["type"].cast(pl.Int64).to_numpy()
    order_id = msg["order_id"].cast(pl.Float64).to_numpy()
    size = msg["size"].cast(pl.Float64).to_numpy()
    price = msg["price"].cast(pl.Float64).to_numpy()
    direction = msg["direction"].cast(pl.Int64).to_numpy()

    a1, b1 = book["a1"], book["b1"]
    ask_ok = a1 < ASK_EMPTY
    bid_ok = b1 >= BID_EMPTY
    valid = ask_ok & bid_ok & (a1 >= b1)
    crossed = ask_ok & bid_ok & (a1 < b1)
    x2 = a1 + b1

    # hidden trades: quote just before the trade, from the full message stream
    pre_x2 = np.concatenate([[np.nan], x2[:-1]])
    pre_valid = np.concatenate([[False], valid[:-1]])
    sign = np.full(n, np.nan)
    vis = typ == 4
    sign[vis] = -direction[vis]
    hid = typ == 5
    sign[hid] = 0
    hv = hid & pre_valid
    p2 = 2 * price
    with np.errstate(invalid="ignore"):
        sign[hv & (p2 < pre_x2)] = -1
        sign[hv & (p2 > pre_x2)] = 1
        midpoint = hv & (p2 == pre_x2)

    open_ns, close_ns = hours[0] * 1e9, hours[1] * 1e9
    i6 = np.flatnonzero(typ == 6)
    kind = np.where(order_id[i6] == -1, "opening", np.where(order_id[i6] == -2, "closing", "other"))
    crosses = pl.DataFrame({
        "ts": ts[i6],
        "time": _ny_time(ts[i6], date),
        "kind": pl.Series(kind.tolist(), dtype=pl.String),
        "order_id": order_id[i6],
        "size": size[i6],
        "price": pl.Series(np.where((size[i6] > 0) & (price[i6] > 0), price[i6] / 10000, np.nan),
                           nan_to_null=True),
        "dollar_volume": price[i6] * size[i6] / 10000,
    })
    start_ns, end_ns = open_ns, close_ns
    start_after = end_before = False
    in_hours6 = (ts_ns[i6] >= open_ns) & (ts_ns[i6] <= close_ns)
    if cut_at_crosses:
        oc = i6[in_hours6 & (order_id[i6] == -1)]
        if len(oc):
            start_ns, start_after = ts_ns[oc[0]], True
        cc = i6[in_hours6 & (order_id[i6] == -2)]
        if len(cc):
            end_ns, end_before = ts_ns[cc[0]], True
            if end_ns < close_ns:
                import warnings
                warnings.warn("the closing cross lies inside the trading hours; continuous "
                              "trading ends there. Set trading_hours to the early close "
                              "(e.g. ('09:30', '13:00'))?")
    if end_ns <= start_ns:
        raise ValueError("no continuous trading between the crosses and the trading hours")
    hs, he = _pair_halts(ts_ns[typ == 7], price[typ == 7])
    ov = (hs < end_ns) & (he > start_ns)
    hs, he = hs[ov], he[ov]

    in_session = ((ts_ns > start_ns) if start_after else (ts_ns >= start_ns)) & \
                 ((ts_ns < end_ns) if end_before else (ts_ns <= end_ns))
    in_halt = np.zeros(n, dtype=bool)
    for s_, e_ in zip(hs, he):
        in_halt |= (ts_ns >= s_) & (ts_ns <= e_)
    keep = in_session & ~in_halt & (typ >= 1) & (typ <= 5)

    ask_n, bid_n, tr_n = _depth_names(depth_bp)
    pos = [j for j, b in enumerate(depth_bp) if b > 0]

    def book_vars(idx):
        """idx: integer row indices, -1 = no state"""
        none = idx < 0
        idx = np.where(none, 0, idx)
        ok = valid[idx] & ~none
        ok_depth = ~crossed[idx] & ~none   # one-sided books: the empty side has depth 0

        def na_if(v):
            return np.where(ok, v, np.nan)

        with np.errstate(divide="ignore", invalid="ignore"):
            spread = 20000 * (a1[idx] - b1[idx]) / x2[idx]
        out = {
            "best_ask": np.where(ask_ok[idx] & ~none, a1[idx] / 10000, np.nan),
            "best_bid": np.where(bid_ok[idx] & ~none, b1[idx] / 10000, np.nan),
            "midquote": na_if(x2[idx] / 20000),
            "spread": na_if(spread),
        }
        for j in range(len(depth_bp)):
            out[ask_n[j]] = np.where(ok_depth, book[f"da{j}"][idx], np.nan)
            out[bid_n[j]] = np.where(ok_depth, book[f"db{j}"][idx], np.nan)
        trs = {tr_n[j]: (book[f"tr{j}"][idx], ok_depth) for j in pos}
        return out, trs

    def frame(cols, trs):
        cols = dict(cols)
        for name, (v, ok) in trs.items():
            cols[name] = pl.Series(np.where(ok, v.astype(np.float64), np.nan),
                                   nan_to_null=True).cast(pl.Boolean)
        return pl.DataFrame({k: pl.Series(v, nan_to_null=True) if isinstance(v, np.ndarray)
                             and v.dtype == np.float64 else v for k, v in cols.items()})

    k = np.flatnonzero(keep)
    bv, btr = book_vars(k)
    messages = frame({
        "ts": ts[k],
        "time": _ny_time(ts[k], date),
        "type": pl.Series(typ[k], dtype=pl.Int32),
        "order_id": order_id[k],
        "size": size[k],
        "price": price[k] / 10000,
        "direction": pl.Series(direction[k], dtype=pl.Int32),
        "trade_sign": pl.Series(sign[k], nan_to_null=True).cast(pl.Int32),
        "midpoint": pl.Series(midpoint[k]),
        **bv,
    }, btr)

    def state_row(t_ns, strictly_before):
        side = "left" if strictly_before else "right"
        return int(np.searchsorted(ts_ns, t_ns, side=side)) - 1   # -1 = none

    # (time, kind, row of the book state in force; -1 = no state)
    bounds = [(start_ns, "session_start", state_row(start_ns, not start_after)),
              (end_ns, "session_end", -1)]
    for s_, e_ in zip(hs, he):
        bounds.append((max(s_, start_ns), "halt_start", -1))
        if e_ < end_ns:
            bounds.append((e_, "halt_end", state_row(e_, False)))
    b_ts, b_kind, b_row = (list(v) for v in zip(*bounds))
    bv, btr = book_vars(np.array(b_row, dtype=np.int64))
    del bv["best_ask"], bv["best_bid"]
    boundaries = frame({"ts_ns": np.array(b_ts, dtype=np.float64),
                        "kind": pl.Series(b_kind, dtype=pl.String), **bv}, btr) \
        .sort("ts_ns", maintain_order=True)

    he_c = np.minimum(he, close_ns)
    halts = pl.DataFrame({
        "start": hs / 1e9, "end": he_c / 1e9,
        "start_time": _ny_time(hs / 1e9, date), "end_time": _ny_time(he_c / 1e9, date),
        "resumed": np.isfinite(he),
    }, schema={"start": pl.Float64, "end": pl.Float64,
               "start_time": pl.Datetime("ns", NY), "end_time": pl.Datetime("ns", NY),
               "resumed": pl.Boolean})

    typ_k = typ[k]
    log = dict(
        n_raw=n, first_ts=float(ts[0]) if n else None, last_ts=float(ts[-1]) if n else None,
        n_outside_session=int(np.sum(~in_session & (typ >= 1) & (typ <= 5))),
        n_in_halts=int(np.sum(in_session & in_halt & (typ >= 1) & (typ <= 5))),
        n_cross_messages=int(len(i6)), n_halt_messages=int(np.sum(typ == 7)),
        n_kept=int(len(k)), n_invalid_book=int(np.sum(~valid[k])),
        n_crossed_book=int(np.sum(crossed[k])),
        n_trades=int(np.sum((typ_k == 4) | (typ_k == 5))),
        n_midpoint_trades=int(np.sum(midpoint[k])),
        session_start=start_ns / 1e9, session_end=end_ns / 1e9,
        levels=n_levels, levels_read=levels_read,
    )
    info = dict(ticker=ticker, date=date, levels=n_levels, levels_read=levels_read,
                window=window, trading_hours=tuple(hours), depth_bp=list(depth_bp),
                open_ns=open_ns, close_ns=close_ns, start_ns=float(start_ns),
                end_ns=float(end_ns), halts_ns=(hs, he))
    return LobsterDay(messages=messages, crosses=crosses, halts=halts,
                      boundaries=boundaries, info=info, log=log)


# ----------------------------------------------------------------- snapshots

def _sum_by(b, v, n):
    ok = ~np.isnan(b)
    return np.bincount(b[ok].astype(np.int64) - 1, weights=np.asarray(v, dtype=np.float64)[ok],
                       minlength=n)[:n]


def _locf_index(mask_fill: np.ndarray) -> np.ndarray:
    """Index of the last row at or before each row where mask_fill is False (-1 if none)."""
    idx = np.where(~mask_fill, np.arange(len(mask_fill)), -1)
    return np.maximum.accumulate(idx) if len(idx) else idx


def lobster_snapshots(day: LobsterDay, freq: float = 5, split_edges: bool = True) -> pl.DataFrame:
    """Aggregate a cleaned day to snapshots every `freq` seconds (see ?lobster_snapshots in R)."""
    x, info = day.messages, day.info
    f = float(round(freq * 1e9))
    if not f > 0:
        raise ValueError("freq must be a positive number of seconds")
    depth_bp = info["depth_bp"]
    ask_n, bid_n, tr_n = _depth_names(depth_bp)
    avg_cols = ["spread"] + [c for pair in zip(ask_n, bid_n) for c in pair]
    tr_cols = [tr_n[j] for j, b in enumerate(depth_bp) if b > 0]
    state_cols = ["midquote"] + avg_cols + tr_cols

    first_edge = np.floor(info["open_ns"] / f) * f
    labels = np.arange(first_edge + f, np.ceil(info["end_ns"] / f) * f + f / 2, f)
    n_lab = len(labels)

    def lab_index(b):
        i = (b - labels[0]) / f + 1
        return np.where((i >= 1) & (i <= n_lab), i, np.nan)

    ts_ns = np.round(x["ts"].to_numpy() * 1e9)
    typ = x["type"].to_numpy()
    size = x["size"].to_numpy()
    bucket = lab_index(np.ceil(ts_ns / f) * f)
    trade = (typ == 4) | (typ == 5)
    dollars = np.round(x["price"].to_numpy() * 10000) * size
    n_messages = _sum_by(bucket, np.ones(len(bucket)), n_lab)
    n_trades = _sum_by(bucket[trade], np.ones(int(trade.sum())), n_lab)
    trading_volume = _sum_by(bucket[trade], dollars[trade], n_lab) / 10000
    sgn = x["trade_sign"].cast(pl.Float64).fill_null(0).to_numpy()
    signed_volume = _sum_by(bucket[trade], (sgn * size)[trade], n_lab)
    signed_volume[n_trades == 0] = np.nan
    mp = trade & x["midpoint"].to_numpy()
    midpoint_volume = _sum_by(bucket[mp], dollars[mp], n_lab) / 10000

    def col(df, c):
        return df[c].cast(pl.Float64).fill_null(np.nan).to_numpy()

    last = np.ones(len(ts_ns), dtype=bool)
    if len(ts_ns) > 1:
        last[:-1] = ts_ns[1:] != ts_ns[:-1]
    st = {"ts_ns": ts_ns[last], "prio": np.ones(int(last.sum()))}
    for c in state_cols:
        st[c] = col(x, c)[last]
    bd = day.boundaries
    kinds = bd["kind"].to_numpy()
    bdd = {"ts_ns": bd["ts_ns"].to_numpy(),
           "prio": np.where(kinds == "session_start", 0.0, np.where(kinds == "halt_end", 1.0, 2.0))}
    for c in state_cols:
        bdd[c] = col(bd, c)

    def stack(*parts):
        keys = parts[0].keys()
        return {k: np.concatenate([p[k] for p in parts]) for k in keys}

    def order(d):
        o = np.lexsort((d["prio"], d["ts_ns"]))   # stable: ts first, then prio
        return {k: v[o] for k, v in d.items()}

    mq = order(stack(st, bdd))
    okm = ~np.isnan(mq["midquote"])
    mq_ts, mq_v = mq["ts_ns"][okm], mq["midquote"][okm]
    hit = np.searchsorted(mq_ts, labels, side="right")
    midquote = np.where(hit > 0, mq_v[np.maximum(hit, 1) - 1], np.nan)

    hs, he = info["halts_ns"]
    if split_edges:
        edges = {"ts_ns": np.concatenate([[first_edge], labels]),
                 "prio": np.full(n_lab + 1, 3.0)}
        for c in state_cols:
            edges[c] = np.full(n_lab + 1, np.nan)
        tl = order(stack(st, bdd, edges))
        src = _locf_index(tl["prio"] == 3)
        for c in state_cols:
            v = tl[c]
            tl[c] = np.where(src >= 0, v[np.maximum(src, 0)], np.nan)
        for s_, e_ in zip(hs, he):
            in_h = (tl["ts_ns"] >= s_) & (tl["ts_ns"] < e_)
            for c in state_cols:
                tl[c][in_h] = np.nan
        w = np.append(np.diff(tl["ts_ns"]), 0.0)
        wb = lab_index(np.floor(tl["ts_ns"] / f) * f + f)
    else:
        tl = st
        w = np.append(np.diff(tl["ts_ns"]), 0.0)
        wb = lab_index(np.ceil(tl["ts_ns"] / f) * f)

    avg = {}
    for c in avg_cols:
        v = tl[c]
        ok = ~np.isnan(v) & ~np.isnan(wb) & (w > 0)
        num = _sum_by(wb[ok], w[ok] * v[ok], n_lab)
        den = _sum_by(wb[ok], w[ok], n_lab)
        with np.errstate(invalid="ignore", divide="ignore"):
            avg[c] = np.where(den > 0, num / den, np.nan)
    trunc = {}
    for c in tr_cols:
        v = tl[c]
        ok = ~np.isnan(v) & ~np.isnan(wb) & (w > 0)
        t = (_sum_by(wb[ok], v[ok], n_lab) > 0).astype(np.float64)
        t[_sum_by(wb[ok], np.ones(int(ok.sum())), n_lab) == 0] = np.nan   # no book state
        trunc[c] = t
    if not split_edges:
        for c in avg_cols:
            v = avg[c]
            src = _locf_index(np.isnan(v))
            avg[c] = np.where(src >= 0, v[np.maximum(src, 0)], np.nan)

    halted = np.zeros(n_lab, dtype=bool)
    for s_, e_ in zip(hs, he):
        halted |= (s_ < labels) & (e_ > labels - f)

    out = {"ts": _ny_time(labels / 1e9, info["date"]),
           "midquote": midquote, "signed_volume": signed_volume,
           "trading_volume": trading_volume, "midpoint_volume": midpoint_volume}
    for c in avg_cols[1:]:
        out[c] = avg[c]
    out.update(spread=avg["spread"],
               n_messages=pl.Series(n_messages.astype(np.int32)),
               n_trades=pl.Series(n_trades.astype(np.int32)),
               halted=pl.Series(halted))
    df = pl.DataFrame({k: pl.Series(v, nan_to_null=True) if isinstance(v, np.ndarray) else v
                       for k, v in out.items()})
    if tr_cols:
        df = df.with_columns([pl.Series(trunc[c], nan_to_null=True).cast(pl.Boolean).alias(c)
                              for c in tr_cols])
    return df


def lobster_process(message_file: str | None = None, orderbook_file: str | None = None,
                    archive: str | None = None, date=None, freq: float = 5,
                    split_edges: bool = True, keep_messages: bool = False, **kwargs) -> LobsterDay:
    """Clean one day and aggregate it to snapshots (lobster_process() in R).

    With an archive, the day's files are found by date (not needed when the
    archive holds one day). Returns a LobsterDay with .snapshots filled; the
    per-message table is dropped unless keep_messages=True.
    """
    if message_file is None or orderbook_file is None:
        if archive is None:
            raise ValueError("give message_file and orderbook_file, or an archive")
        days = lobster_archive_files(archive)
        if date is not None:
            d = dt.date.fromisoformat(date) if isinstance(date, str) else date
            days = days.filter(pl.col("date") == d)
        if days.height != 1:
            raise ValueError("no files for this date in the archive" if days.height == 0
                             else "the archive holds several days; choose one with date")
        message_file, orderbook_file = days["message_file"][0], days["orderbook_file"][0]
    day = lobster_clean(message_file, orderbook_file, archive=archive, date=date, **kwargs)
    day.snapshots = lobster_snapshots(day, freq=freq, split_edges=split_edges)
    if not keep_messages:
        day.messages = None
    return day


if __name__ == "__main__":  # minimal command line: one day to a parquet file
    import argparse
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    for name in ("--message-file", "--orderbook-file", "--archive", "--date"):
        ap.add_argument(name)
    ap.add_argument("--freq", type=float, default=5)
    ap.add_argument("--trading-hours", nargs=2, default=["09:30:00", "16:00:00"])
    ap.add_argument("--depth-bp", type=float, nargs="*", default=[0, 5])
    ap.add_argument("--legacy-weights", action="store_true")
    ap.add_argument("out")
    a = ap.parse_args()
    day = lobster_process(a.message_file, a.orderbook_file, archive=a.archive, date=a.date,
                          freq=a.freq, split_edges=not a.legacy_weights,
                          trading_hours=a.trading_hours, depth_bp=a.depth_bp)
    day.snapshots.write_parquet(a.out)
    print(f"{day.snapshots.height} snapshots -> {a.out}; crosses {day.crosses.height}, "
          f"halts {day.halts.height}")
