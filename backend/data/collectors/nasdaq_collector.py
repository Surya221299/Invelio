"""
AI Saham Indonesia — NASDAQ/ETF Symbol Collector

Mengambil daftar simbol dari beberapa sumber secara berurutan (fallback):

  Sumber 1 (utama):
    https://www.nasdaqtrader.com/dynamic/SymDir/nasdaqlisted.txt
    https://www.nasdaqtrader.com/dynamic/SymDir/otherlisted.txt
    File resmi NASDAQ Trader, gratis, di-update harian.
    Butuh User-Agent header agar tidak di-block (403).

  Sumber 2 (fallback jika Sumber 1 timeout/block):
    https://raw.githubusercontent.com/rreichel3/US-Stock-Symbols/main/nasdaq/nasdaq_tickers.txt
    https://raw.githubusercontent.com/rreichel3/US-Stock-Symbols/main/nyse/nyse_tickers.txt
    Mirror GitHub yang di-update otomatis dari NASDAQ Trader.

PENTING: hanya mengisi tabel `simbol_referensi` (universe search).
TIDAK menyentuh tabel `Saham` (watchlist) dan TIDAK mempengaruhi
job terjadwal apapun.
"""

import asyncio
from typing import Any

import httpx
from loguru import logger

# --- URL Sumber ---
# Sumber 1: NASDAQ Trader resmi (butuh User-Agent agar tidak 403)
NASDAQ_LISTED_URL = "https://www.nasdaqtrader.com/dynamic/SymDir/nasdaqlisted.txt"
OTHER_LISTED_URL  = "https://www.nasdaqtrader.com/dynamic/SymDir/otherlisted.txt"

# Sumber 2: GitHub mirror rreichel3/US-Stock-Symbols (fallback)
GITHUB_NASDAQ_URL = "https://raw.githubusercontent.com/rreichel3/US-Stock-Symbols/main/nasdaq/nasdaq_tickers.txt"
GITHUB_NYSE_URL   = "https://raw.githubusercontent.com/rreichel3/US-Stock-Symbols/main/nyse/nyse_tickers.txt"
GITHUB_AMEX_URL   = "https://raw.githubusercontent.com/rreichel3/US-Stock-Symbols/main/amex/amex_tickers.txt"

# Header supaya tidak di-block NASDAQ Trader (mereka block request tanpa User-Agent)
_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/124.0.0.0 Safari/537.36"
    ),
    "Accept": "text/plain,text/html,*/*",
}
_TIMEOUT = httpx.Timeout(connect=10.0, read=60.0, write=10.0, pool=5.0)


# ─────────────────────────────────────────────────────────
# Helper: HTTP fetch
# ─────────────────────────────────────────────────────────

async def _fetch_text(url: str) -> str:
    async with httpx.AsyncClient(timeout=_TIMEOUT, headers=_HEADERS, follow_redirects=True) as client:
        resp = await client.get(url)
        resp.raise_for_status()
        return resp.text


# ─────────────────────────────────────────────────────────
# Sumber 1: NASDAQ Trader pipe-delimited
# ─────────────────────────────────────────────────────────

def _parse_pipe_delimited(raw_text: str) -> list[dict[str, str]]:
    """Parse file pipe-delimited NASDAQ Trader, skip header & footer."""
    lines = raw_text.strip().splitlines()
    if len(lines) < 2:
        return []
    header = lines[0].split("|")
    rows = []
    for line in lines[1:]:
        if line.startswith("File Creation Time"):
            continue
        cols = line.split("|")
        if len(cols) != len(header):
            continue
        rows.append(dict(zip(header, cols)))
    return rows


async def _collect_from_nasdaqtrader() -> list[dict[str, Any]]:
    """Ambil dari NASDAQ Trader resmi (pipe-delimited)."""
    hasil: list[dict[str, Any]] = []
    seen: set[str] = set()

    # nasdaqlisted.txt
    try:
        raw = await _fetch_text(NASDAQ_LISTED_URL)
        rows = _parse_pipe_delimited(raw)
        for row in rows:
            kode = row.get("Symbol", "").strip()
            nama = row.get("Security Name", "").strip()
            test = row.get("Test Issue", "N").strip()
            etf  = row.get("ETF", "N").strip()
            stat = row.get("Financial Status", "N").strip()
            if not kode or test == "Y" or stat == "D" or kode in seen:
                continue
            seen.add(kode)
            hasil.append({
                "kode": kode, "nama": nama or kode,
                "market": "ETF" if etf == "Y" else "NASDAQ",
                "tipe": "ETF" if etf == "Y" else "STOCK",
                "exchange": "NASDAQ",
            })
        logger.info(f"✅ nasdaqlisted.txt: {len(hasil)} simbol valid.")
    except Exception as e:
        logger.warning(f"⚠️  nasdaqlisted.txt gagal: {e}")

    count_before = len(hasil)

    # otherlisted.txt
    try:
        raw = await _fetch_text(OTHER_LISTED_URL)
        rows = _parse_pipe_delimited(raw)
        _EXCHANGE_MAP = {
            "N": "NYSE", "A": "NYSE American", "P": "NYSE Arca",
            "Z": "BATS", "V": "IEX",
        }
        for row in rows:
            kode = row.get("ACT Symbol", "").strip()
            nama = row.get("Security Name", "").strip()
            test = row.get("Test Issue", "N").strip()
            etf  = row.get("ETF", "N").strip()
            exc  = row.get("Exchange", "").strip()
            if not kode or test == "Y" or kode in seen:
                continue
            seen.add(kode)
            hasil.append({
                "kode": kode, "nama": nama or kode,
                "market": "ETF" if etf == "Y" else "NYSE",
                "tipe": "ETF" if etf == "Y" else "STOCK",
                "exchange": _EXCHANGE_MAP.get(exc, exc or "NYSE"),
            })
        logger.info(f"✅ otherlisted.txt: {len(hasil) - count_before} simbol tambahan.")
    except Exception as e:
        logger.warning(f"⚠️  otherlisted.txt gagal: {e}")

    return hasil


# ─────────────────────────────────────────────────────────
# Sumber 2: GitHub mirror (fallback, format 1 ticker per baris)
# ─────────────────────────────────────────────────────────

async def _collect_from_github() -> list[dict[str, Any]]:
    """
    Fallback: ambil dari mirror GitHub rreichel3/US-Stock-Symbols.
    Format: satu ticker per baris, tanpa nama perusahaan.
    """
    logger.info("🔄 Mencoba fallback GitHub mirror (rreichel3/US-Stock-Symbols)...")
    hasil: list[dict[str, Any]] = []
    seen: set[str] = set()

    sources = [
        (GITHUB_NASDAQ_URL, "NASDAQ"),
        (GITHUB_NYSE_URL,   "NYSE"),
        (GITHUB_AMEX_URL,   "NYSE American"),
    ]

    for url, market in sources:
        try:
            raw = await _fetch_text(url)
            tickers = [t.strip() for t in raw.splitlines() if t.strip() and not t.startswith("#")]
            added = 0
            for kode in tickers:
                if not kode or kode in seen:
                    continue
                seen.add(kode)
                hasil.append({
                    "kode": kode, "nama": kode,  # nama kosong, diisi kode saja
                    "market": market,
                    "tipe": "STOCK",
                    "exchange": market,
                })
                added += 1
            logger.info(f"✅ GitHub {market}: {added} ticker.")
        except Exception as e:
            logger.warning(f"⚠️  GitHub {market} gagal: {e}")

    return hasil


# ─────────────────────────────────────────────────────────
# Entry point utama
# ─────────────────────────────────────────────────────────

async def collect_nasdaq_universe() -> list[dict[str, Any]]:
    """
    Kumpulkan seluruh universe simbol US (NASDAQ + NYSE + ETF).

    Coba Sumber 1 (NASDAQ Trader resmi) dulu. Kalau gagal / kosong,
    fallback ke Sumber 2 (GitHub mirror).

    Returns:
        List of dict: {kode, nama, market, tipe, exchange}
    """
    logger.info("📡 Mencoba NASDAQ Trader resmi (nasdaqtrader.com)...")
    hasil = await _collect_from_nasdaqtrader()

    if not hasil:
        logger.warning("⚠️  NASDAQ Trader resmi gagal total. Mencoba GitHub mirror...")
        hasil = await _collect_from_github()

    logger.info(f"✅ Total universe simbol terkumpul: {len(hasil)}")
    return hasil