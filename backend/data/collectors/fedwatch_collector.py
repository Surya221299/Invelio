"""
AI Saham Indonesia — CME FedWatch Collector

Menghitung probabilitas target range suku bunga The Fed (ala CME FedWatch)
untuk rapat FOMC berikutnya, dari harga 30-Day Fed Funds Futures (ZQ) di
Yahoo Finance.

KENAPA DIHITUNG SENDIRI, BUKAN SCRAPE cmegroup.com:
    - Halaman FedWatch publik me-render angka lewat JavaScript (widget
      QuikStrike) → tidak bisa di-GET langsung.
    - API resmi CME FedWatch butuh OAuth2 + lisensi berbayar.
    - Menghitung dari futures ZQ = metodologi yang sama dengan CME, memakai
      data publik gratis (yfinance sudah jadi dependency project).

METODOLOGI (single-meeting, stabil):
    Kontrak ZQ menyelesaikan pada rata-rata Fed Funds rate bulanan, jadi
    "harga → rata-rata rate = 100 - harga". Untuk mengisolasi ekspektasi rate
    PASCA-rapat, kita pakai kontrak bulan tepat SETELAH bulan rapat yang tidak
    memuat rapat FOMC lain — bulan itu berjalan penuh di suku bunga baru,
    sehingga:  r_baru = 100 - harga(kontrak bulan-referensi).
    (Memakai kontrak bulan-rapat langsung tidak stabil bila rapat jatuh di
    akhir bulan — hanya sedikit hari yang memakai rate baru.)

    r_baru lalu diposisikan di antara dua midpoint target range 25 bps;
    probabilitas tiap range = interpolasi linear posisi r_baru.

KETERBATASAN (perbaiki untuk produksi):
    - Model single-meeting → 2 bar (naik/tetap atau turun/tetap). Distribusi
      "tangga" penuh butuh chaining beberapa kontrak/rapat (TODO).
    - Bila bulan-referensi ternyata memuat rapat FOMC lain, hasilnya bias
      (di-log sebagai warning).
    - Futures settle pada EFFR (≈ upper_bound - 8 bps). Pemetaan ke midpoint
      target range diberi EFFR_OFFSET (default 0) — set bila butuh presisi.
    - FOMC_MEETINGS_2026 & CURRENT_TARGET_LOWER WAJIB diverifikasi/di-update
      tiap keputusan FOMC baru. Idealnya tarik dari sumber resmi Fed.

Penggunaan:
    from backend.data.collectors.fedwatch_collector import collect_fedwatch
    data = await collect_fedwatch()   # -> dict siap dikirim sebagai JSON
"""

import asyncio
import math
import time
from datetime import date
from typing import Any

import yfinance as yf
from loguru import logger

# ---------------------------------------------------------------------------
# KONFIGURASI — VERIFIKASI/UPDATE saat ada keputusan FOMC baru.
# ---------------------------------------------------------------------------

# Batas bawah target range Fed saat ini (mis. 3.75 untuk range 3.75%–4.00%,
# ditampilkan "375-400" dalam basis point ala FedWatch).
CURRENT_TARGET_LOWER = 3.75

# Selisih EFFR terhadap midpoint range (0.0 = pakai apa adanya).
EFFR_OFFSET = 0.0

# Tanggal keputusan FOMC 2026 (hari terakhir rapat). SUMBER: kalender Fed —
# verifikasi angkanya, ini estimasi terjadwal.
FOMC_MEETINGS_2026 = [
    date(2026, 1, 28),
    date(2026, 3, 18),
    date(2026, 4, 29),
    date(2026, 6, 17),
    date(2026, 7, 29),
    date(2026, 9, 16),
    date(2026, 10, 28),
    date(2026, 12, 9),
]

# Kode bulan kontrak futures CME (Jan..Des).
_MONTH_CODES = ["F", "G", "H", "J", "K", "M", "N", "Q", "U", "V", "X", "Z"]

_STEP = 0.25          # ukuran satu langkah kebijakan (25 bps)
_RANGE_WIDTH = 0.25   # lebar satu target range

# Cache in-memory (pola sama dengan data.py).
_cache: dict[str, Any] = {}
_CACHE_TTL = 3600  # 1 jam — FedWatch tidak berubah cepat


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _all_meetings() -> list[date]:
    return sorted(FOMC_MEETINGS_2026)


def _next_fomc_meeting(today: date) -> date | None:
    """Rapat FOMC terjadwal berikutnya (>= hari ini)."""
    upcoming = [m for m in _all_meetings() if m >= today]
    return min(upcoming) if upcoming else None


def _first_of_next_month(d: date) -> date:
    return date(d.year + 1, 1, 1) if d.month == 12 else date(d.year, d.month + 1, 1)


def _month_has_meeting(d: date) -> bool:
    return any(m.year == d.year and m.month == d.month for m in _all_meetings())


def _zq_symbol(d: date) -> str:
    """Simbol yfinance kontrak ZQ untuk bulan `d`, mis. 'ZQQ26.CBT' (Agu 2026)."""
    code = _MONTH_CODES[d.month - 1]
    return f"ZQ{code}{d.year % 100:02d}.CBT"


def _fmt_range(lo: float) -> str:
    """Label range dalam basis point ala FedWatch: '375-400'."""
    hi = lo + _RANGE_WIDTH
    return f"{round(lo * 100)}-{round(hi * 100)}"


def _fetch_last_close(symbol: str) -> float | None:
    """Harga penutupan terakhir kontrak (sinkron; dipanggil via to_thread)."""
    try:
        hist = yf.Ticker(symbol).history(period="5d")
        if not hist.empty:
            return float(hist["Close"].dropna().iloc[-1])
    except Exception as e:  # noqa: BLE001
        logger.warning(f"[fedwatch] gagal fetch {symbol}: {e}")
    return None


def _distribute(r_new: float) -> list[dict[str, Any]]:
    """
    Posisikan ekspektasi rate pasca-rapat (r_new) di antara dua target range
    25 bps → probabilitas tiap range (interpolasi linear).
    """
    r_new += EFFR_OFFSET
    base_mid = CURRENT_TARGET_LOWER + _RANGE_WIDTH / 2  # midpoint range kini
    k = math.floor((r_new - base_mid) / _STEP)          # indeks range bawah (bisa negatif)
    lower_mid = base_mid + k * _STEP
    frac = max(0.0, min(1.0, (r_new - lower_mid) / _STEP))

    lower_lo = CURRENT_TARGET_LOWER + k * _STEP
    upper_lo = lower_lo + _STEP

    outcomes = []
    if frac < 0.999:
        outcomes.append({"range_label": _fmt_range(lower_lo), "probability": round((1 - frac) * 100, 1)})
    if frac > 0.001:
        outcomes.append({"range_label": _fmt_range(upper_lo), "probability": round(frac * 100, 1)})
    return sorted(outcomes, key=lambda o: o["range_label"])


def _placeholder(meeting: date | None) -> dict[str, Any]:
    """Fallback bila data futures tak tersedia — ditandai supaya app tahu."""
    label = f"Rapat FOMC · {meeting:%b %Y}" if meeting else "Rapat FOMC"
    return {
        "meeting_label": f"{label} (estimasi)",
        "meeting_date": meeting.isoformat() if meeting else None,
        "as_of": None,
        "source": "placeholder",
        "outcomes": [
            {"range_label": _fmt_range(CURRENT_TARGET_LOWER - 0.25), "probability": 15.0},
            {"range_label": _fmt_range(CURRENT_TARGET_LOWER), "probability": 85.0},
        ],
    }


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

async def collect_fedwatch(force: bool = False) -> dict[str, Any]:
    """
    Snapshot FedWatch untuk rapat FOMC berikutnya. Selalu mengembalikan dict
    valid (fallback placeholder bila data gagal), jadi endpoint aman.
    """
    now = time.time()
    if not force and "data" in _cache and now - _cache.get("ts", 0) < _CACHE_TTL:
        return _cache["data"]

    meeting = _next_fomc_meeting(date.today())
    if meeting is None:
        logger.warning("[fedwatch] tak ada rapat FOMC terjadwal — cek FOMC_MEETINGS")
        return _placeholder(None)

    # Bulan referensi = bulan tepat setelah rapat, idealnya tanpa rapat lain.
    ref = _first_of_next_month(meeting)
    if _month_has_meeting(ref):
        logger.warning(f"[fedwatch] bulan referensi {ref:%b %Y} memuat rapat FOMC lain — hasil bisa bias")

    # Coba kontrak bulan-referensi, fallback ke front-month generik.
    price = await asyncio.to_thread(_fetch_last_close, _zq_symbol(ref))
    if price is None:
        price = await asyncio.to_thread(_fetch_last_close, "ZQ=F")
    if price is None:
        return _placeholder(meeting)

    try:
        r_new = 100.0 - price
        outcomes = _distribute(r_new)
        if not outcomes:
            return _placeholder(meeting)
        data = {
            "meeting_label": f"Rapat FOMC · {meeting:%b %Y}",
            "meeting_date": meeting.isoformat(),
            "as_of": date.today().isoformat(),
            "source": "live",
            "outcomes": outcomes,
        }
        _cache["data"], _cache["ts"] = data, now
        return data
    except Exception as e:  # noqa: BLE001
        logger.exception(f"[fedwatch] gagal menghitung probabilitas: {e}")
        return _placeholder(meeting)
