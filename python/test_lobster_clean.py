"""Tests for lobster_clean.py on the synthetic days in tests/testthat/fixtures.

Run from the repository root:  python -m pytest python
The same files are used by the R tests (tests/testthat/test-clean.R); the
expected values here are the same as there.
"""
import datetime as dt
import os
import shutil
import subprocess
import sys

import polars as pl
import pytest

sys.path.insert(0, os.path.dirname(__file__))
import lobster_clean as lc  # noqa: E402

FX = os.path.join(os.path.dirname(__file__), "..", "tests", "testthat", "fixtures")
STEM = {"a": "TEST_2024-03-20_28800000_61200000", "b": "TEST_2024-11-29_32400000_50400000"}


def fixture(day, kind):
    return os.path.join(FX, f"{STEM[day]}_{kind}_3.csv")


def clean_a(**kw):
    kw.setdefault("depth_bp", [0, 1, 5])
    return lc.lobster_clean(fixture("a", "message"), fixture("a", "orderbook"), **kw)


def clean_b(**kw):
    kw.setdefault("trading_hours", ("09:30", "13:00"))
    return lc.lobster_clean(fixture("b", "message"), fixture("b", "orderbook"), **kw)


def at(s, hms):
    return s.filter(pl.col("ts").dt.strftime("%H:%M:%S") == hms).row(0, named=True)


def test_file_info():
    info = lc.lobster_file_info([
        "dir/SPY_2024-03-20_34200000_57600000_message_50.csv",
        "BRK.B_2024-03-20_34200000_57600000_orderbook_10.csv.gz",
        "SPY_2024-02-27_2024-03-26_50.7z", "notes.txt"])
    assert info["file"].to_list() == ["message", "orderbook", "archive", None]
    assert info["ticker"].to_list() == ["SPY", "BRK.B", "SPY", None]
    assert info["levels"].to_list() == [50, 10, 50, None]
    assert info["last_date"][2] == dt.date(2024, 3, 26)
    assert info["window_end"][0] == 57600


def test_file_info_api_names():
    # Files from the lobsterdata.com API carry no requested window
    info = lc.lobster_file_info(["LQDT_2025-06-11_message_10.csv",
                                 "BRK.B_2025-06-11_orderbook_10.csv"])
    assert info["file"].to_list() == ["message", "orderbook"]
    assert info["ticker"].to_list() == ["LQDT", "BRK.B"]
    assert info["date"].to_list() == [dt.date(2025, 6, 11)] * 2
    assert info["levels"].to_list() == [10, 10]
    assert info["window_start"].to_list() == [None, None]


def test_crosses_and_session():
    d = clean_a()
    assert d.crosses["kind"].to_list() == ["opening", "other", "closing"]
    assert d.crosses["dollar_volume"].to_list() == [500050, 70014, 800160]
    assert d.log["session_start"] == 34200.5 and d.log["session_end"] == 57600
    m = d.messages
    assert m["ts"].min() > 34200.5 and m["ts"].max() < 57600
    assert not m["type"].is_in([6, 7]).any()
    y = clean_a(cut_at_crosses=False)
    assert 34200.2 in y.messages["ts"].to_list()


def test_halts():
    d = clean_a()
    assert d.halts["start"].to_list() == [39600] and d.halts["end"].to_list() == [39900]
    assert d.halts["resumed"].to_list() == [True]
    b = clean_b()
    assert b.halts["end"].to_list() == [46800] and b.halts["resumed"].to_list() == [False]
    assert lc._pair_halts([1, 2, 3, 4, 5, 6], [1, -1, -1, 0, 1, -1])[0].tolist() == [2, 6]
    assert d.halts["ended_by"].to_list() == ["resumption"] and b.halts["ended_by"].to_list() == ["close"]


def test_execution_ends_halt():
    s, e, how = lc._pair_halts([10, 20], [-1, -1], [5, 15, 30])
    assert s.tolist() == [10, 20] and e.tolist() == [14, 29] and how == ["execution", "execution"]
    s, e, how = lc._pair_halts([10, 12], [-1, 1], [15])
    assert e.tolist() == [12] and how == ["resumption"]


def test_sum_by_is_float_without_data():
    import numpy as np
    out = lc._sum_by(np.array([]), np.array([]), 3)
    assert out.dtype == np.float64 and out.tolist() == [0, 0, 0]


def test_signs_and_book():
    m = clean_a().messages
    tr = m.filter(pl.col("type").is_in([4, 5]))

    def sign(t):
        return tr.filter(pl.col("ts") == t)["trade_sign"].to_list()

    assert sign(34202) == [1] and sign(34206) == [-1, 1]
    assert sign(34203) == [0, 1] and sign(34204) == [-1] and sign(43200.5) == [0]
    r = m.filter(pl.col("ts") == 34201).row(0, named=True)
    assert (r["depth0_ask"], r["depth1_ask"], r["depth5_ask"]) == (400, 600, 700)
    assert r["depth1_truncated"] is False and r["depth5_truncated"] is True
    assert m.filter(pl.col("ts") == 43200)["midquote"].to_list() == [None]


def test_snapshots():
    s = lc.lobster_snapshots(clean_a())
    assert s.height == 4680
    a = at(s, "09:30:05")
    assert a["signed_volume"] == 90
    assert a["midpoint_volume"] == pytest.approx(5000.5)
    assert a["depth0_ask"] == pytest.approx((0.5 * 300 + 400 + 3 * 300) / 4.5)
    assert at(s, "09:30:10")["signed_volume"] == -300
    e = at(s, "09:30:15")
    assert e["n_messages"] == 0 and e["signed_volume"] is None and e["depth0_ask"] == 200
    assert s["halted"].sum() == 60
    h = at(s, "11:02:00")
    assert h["spread"] is None and h["midquote"] == pytest.approx(100.01)
    assert at(s, "11:05:05")["depth0_ask"] == pytest.approx((100 + 4 * 300) / 5)
    assert s.row(-1, named=True)["depth0_ask"] == pytest.approx((4 * 300 + 200) / 5)
    legacy = lc.lobster_snapshots(clean_a(), split_edges=False)
    assert at(legacy, "09:30:05")["depth0_ask"] == pytest.approx(320)
    assert legacy["trading_volume"].to_list() == s["trading_volume"].to_list()


def test_early_close():
    b = clean_b()
    s = lc.lobster_snapshots(b, freq=60)
    assert s["ts"].dt.strftime("%H:%M").to_list()[-1] == "13:00"
    late = s.filter(pl.col("ts").dt.strftime("%H:%M") > "12:30")
    assert late["halted"].all() and late["spread"].null_count() == late.height
    with pytest.warns(UserWarning, match="closing cross"):
        b16 = lc.lobster_clean(fixture("b", "message"), fixture("b", "orderbook"))
    assert b16.log["session_end"] == pytest.approx(46800.1)


@pytest.mark.skipif(shutil.which("7z") is None, reason="needs the 7z program")
def test_archive(tmp_path):
    arch = tmp_path / "TEST_2024-03-20_2024-03-20_3.7z"
    subprocess.run(["7z", "a", "-bso0", "-bsp0", str(arch), fixture("a", "message"),
                    fixture("a", "orderbook")], check=True)
    files = lc.lobster_archive_files(str(arch))
    assert files.height == 1
    day = lc.lobster_process(archive=str(arch), depth_bp=[0, 1, 5])
    assert day.snapshots.equals(lc.lobster_snapshots(clean_a()))


def test_one_sided_book():
    b = clean_b()
    r = b.messages.filter(pl.col("ts") == 36000).row(0, named=True)
    assert r["midquote"] is None and r["spread"] is None and r["best_bid"] is None
    assert (r["depth0_ask"], r["depth5_ask"], r["depth0_bid"], r["depth5_bid"]) == (200, 400, 0, 0)
    assert r["depth5_truncated"] is False
    s = lc.lobster_snapshots(b, freq=60)
    m = s.filter(pl.col("ts").dt.strftime("%H:%M") == "10:01").row(0, named=True)
    assert m["depth0_bid"] == pytest.approx((2 * 0 + 58 * 400) / 60)
    assert m["depth0_ask"] == 200
    assert m["spread"] == pytest.approx(10000 * 0.02 / 20.01)
