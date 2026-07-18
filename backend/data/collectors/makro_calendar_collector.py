"""
AI Saham Indonesia — Kalender Faktor Makro AS

Menyediakan "kalender ekonomi" faktor makro pemerintah AS yang menggerakkan
pasar saham (inflasi, tenaga kerja, data ekonomi lain, fiskal/politik, yield
Treasury). Ditampilkan di bawah chart CME FedWatch pada tab Release.

APA YANG DIHITUNG:
    - Tanggal rilis BERIKUTNYA tiap indikator, dihitung dari ATURAN JADWAL
      rutin (mis. NFP = Jumat pertama tiap bulan, jobless claims = tiap Kamis,
      CPI ~pertengahan bulan). Ditandai `is_estimate=True` karena tanggal pasti
      hanya dari kalender resmi BLS/BEA/The Fed — ini perkiraan terjadwal, bukan
      angka yang di-scrape.
    - Yield US Treasury 10 tahun LIVE dari Yahoo Finance (ticker ^TNX), termasuk
      perubahan harian. Ini satu-satunya angka "live" di modul ini.

ANGKA AKTUAL (FRED):
    Bila FRED_API_KEY di-set (backend/config.py), tiap indikator diperkaya angka
    aktual terkini + nilai sebelumnya dari FRED API (mis. CPI YoY, NFP MoM).
    Konsensus/forecast TIDAK tersedia gratis, jadi tetap tak ditampilkan. ISM PMI
    & Conference Board tak ada di FRED (proprietary) → hanya jadwal + edukasi.

Penggunaan:
    from backend.data.collectors.makro_calendar_collector import collect_makro_calendar
    data = await collect_makro_calendar()   # -> dict siap dikirim sebagai JSON
"""

import asyncio
import time as _time
from datetime import date, datetime, time, timedelta
from typing import Any, Callable
from zoneinfo import ZoneInfo

import httpx
import yfinance as yf
from loguru import logger

from backend.config import settings

# Semua rilis makro AS memakai waktu Eastern (ET); DST ditangani oleh zoneinfo.
ET = ZoneInfo("America/New_York")

# Cache in-memory (pola sama dengan fedwatch_collector).
_cache: dict[str, Any] = {}
_CACHE_TTL = 3600  # 1 jam — jadwal & yield tidak berubah cepat


# ---------------------------------------------------------------------------
# Helper tanggal/jadwal (semua bekerja dalam kalender ET)
# ---------------------------------------------------------------------------

def _now_et() -> datetime:
    return datetime.now(ET)


def _at(d: date, hh: int, mm: int) -> datetime:
    """Gabungkan tanggal + jam (ET-aware)."""
    return datetime.combine(d, time(hh, mm), tzinfo=ET)


def _to_weekday(d: date) -> date:
    """Geser akhir pekan ke hari Senin berikutnya (rilis hanya di hari kerja)."""
    if d.weekday() == 5:      # Sabtu
        return d + timedelta(days=2)
    if d.weekday() == 6:      # Minggu
        return d + timedelta(days=1)
    return d


def _add_month(year: int, month: int) -> tuple[int, int]:
    return (year + 1, 1) if month == 12 else (year, month + 1)


def _nth_weekday(year: int, month: int, weekday: int, n: int) -> date:
    """Kemunculan ke-n `weekday` (Senin=0) dalam bulan (n mulai dari 1)."""
    first = date(year, month, 1)
    offset = (weekday - first.weekday()) % 7
    return first + timedelta(days=offset + 7 * (n - 1))


def _last_weekday(year: int, month: int, weekday: int) -> date:
    """Kemunculan TERAKHIR `weekday` (Senin=0) dalam bulan."""
    ny, nm = _add_month(year, month)
    last = date(ny, nm, 1) - timedelta(days=1)
    offset = (last.weekday() - weekday) % 7
    return last - timedelta(days=offset)


def _nth_business_day(year: int, month: int, n: int) -> date:
    """Hari kerja ke-n (Sen–Jum) dalam bulan (n mulai dari 1)."""
    d = date(year, month, 1)
    count = 0
    while True:
        if d.weekday() < 5:
            count += 1
            if count == n:
                return d
        d += timedelta(days=1)


def _last_business_day(year: int, month: int) -> date:
    ny, nm = _add_month(year, month)
    d = date(ny, nm, 1) - timedelta(days=1)
    while d.weekday() >= 5:
        d -= timedelta(days=1)
    return d


def _next_monthly(builder: Callable[[int, int], datetime], now: datetime,
                  look_ahead: int = 4) -> datetime:
    """
    Rilis bulanan berikutnya: coba bulan ini, kalau sudah lewat lanjut ke bulan
    berikutnya sampai ketemu datetime di masa depan.
    """
    y, m = now.year, now.month
    for _ in range(look_ahead + 1):
        dt = builder(y, m)
        if dt > now:
            return dt
        y, m = _add_month(y, m)
    return builder(y, m)


def _next_weekly_thursday(now: datetime) -> datetime:
    """Kamis berikutnya jam 08:30 ET (initial jobless claims)."""
    today = now.date()
    offset = (3 - today.weekday()) % 7          # Kamis = 3
    cand = _at(today + timedelta(days=offset), 8, 30)
    if cand <= now:
        cand = _at(today + timedelta(days=offset + 7), 8, 30)
    return cand


# ---------------------------------------------------------------------------
# Builder tanggal per-indikator (perkiraan terjadwal — VERIFIKASI vs BLS/BEA)
# ---------------------------------------------------------------------------

def _cpi(y: int, m: int) -> datetime:          # ~tgl 10–15, 08:30 ET
    return _at(_to_weekday(date(y, m, 12)), 8, 30)


def _ppi(y: int, m: int) -> datetime:          # sekitar CPI, 08:30 ET
    return _at(_to_weekday(date(y, m, 13)), 8, 30)


def _pce(y: int, m: int) -> datetime:          # akhir bulan, 08:30 ET
    return _at(_last_business_day(y, m), 8, 30)


def _nfp(y: int, m: int) -> datetime:          # Jumat pertama, 08:30 ET
    return _at(_nth_weekday(y, m, 4, 1), 8, 30)


def _jolts(y: int, m: int) -> datetime:        # ~awal bulan, 10:00 ET
    return _at(_nth_business_day(y, m, 2), 10, 0)


def _gdp(y: int, m: int) -> datetime:          # ~akhir bulan (advance/revisi), 08:30 ET
    return _at(_to_weekday(date(y, m, 27)), 8, 30)


def _retail(y: int, m: int) -> datetime:       # ~pertengahan bulan, 08:30 ET
    return _at(_to_weekday(date(y, m, 15)), 8, 30)


def _ism_mfg(y: int, m: int) -> datetime:      # hari kerja pertama, 10:00 ET
    return _at(_nth_business_day(y, m, 1), 10, 0)


def _ism_svc(y: int, m: int) -> datetime:      # hari kerja ke-3, 10:00 ET
    return _at(_nth_business_day(y, m, 3), 10, 0)


def _conf_board(y: int, m: int) -> datetime:   # Selasa terakhir, 10:00 ET
    return _at(_last_weekday(y, m, 1), 10, 0)


def _michigan(y: int, m: int) -> datetime:     # Jumat kedua (prelim), 10:00 ET
    return _at(_nth_weekday(y, m, 4, 2), 10, 0)


# ---------------------------------------------------------------------------
# Konten kalender: kategori + item + teks edukasi/dampak (bahasa Indonesia)
# ---------------------------------------------------------------------------

def _monthly(builder: Callable[[int, int], datetime], now: datetime) -> str:
    return _next_monthly(builder, now).isoformat()


def _build_categories(now: datetime) -> list[dict[str, Any]]:
    return [
        {
            "key": "inflasi",
            "title": "Data Inflasi",
            "icon": "chart.line.uptrend.xyaxis",
            "items": [
                {
                    "key": "cpi",
                    "name": "CPI (Consumer Price Index)",
                    "schedule_label": "Bulanan · ~tgl 10–15 · 08:30 ET",
                    "next_release": _monthly(_cpi, now),
                    "is_estimate": True,
                    "impact": "Kalau inflasi lebih tinggi dari ekspektasi → market takut Fed hawkish → saham turun. Lebih rendah → biasanya rally.",
                },
                {
                    "key": "pce",
                    "name": "PCE",
                    "schedule_label": "Bulanan · akhir bulan · 08:30 ET",
                    "next_release": _monthly(_pce, now),
                    "is_estimate": True,
                    "impact": "Ukuran inflasi favorit The Fed. Jadi acuan utama arah kebijakan suku bunga.",
                },
                {
                    "key": "ppi",
                    "name": "PPI (Producer Price Index)",
                    "schedule_label": "Bulanan · sekitar CPI · 08:30 ET",
                    "next_release": _monthly(_ppi, now),
                    "is_estimate": True,
                    "impact": "Inflasi di tingkat produsen — indikator awal (leading) untuk arah CPI.",
                },
            ],
        },
        {
            "key": "tenaga_kerja",
            "title": "Data Tenaga Kerja",
            "icon": "person.2.fill",
            "items": [
                {
                    "key": "nfp",
                    "name": "Non-Farm Payrolls (NFP)",
                    "schedule_label": "Jumat pertama tiap bulan · 08:30 ET",
                    "next_release": _monthly(_nfp, now),
                    "is_estimate": True,
                    "impact": "Jumlah lapangan kerja baru, tingkat pengangguran, dan pertumbuhan upah. Logikanya kadang terbalik: data terlalu kuat bisa negatif untuk saham karena Fed tak perlu buru-buru menurunkan suku bunga (\"good news is bad news\").",
                },
                {
                    "key": "jolts",
                    "name": "JOLTS (lowongan kerja)",
                    "schedule_label": "Bulanan · ~awal bulan · 10:00 ET",
                    "next_release": _monthly(_jolts, now),
                    "is_estimate": True,
                    "impact": "Jumlah lowongan kerja terbuka — ukuran kekuatan permintaan tenaga kerja.",
                },
                {
                    "key": "jobless_claims",
                    "name": "Initial Jobless Claims",
                    "schedule_label": "Mingguan · tiap Kamis · 08:30 ET",
                    "next_release": _next_weekly_thursday(now).isoformat(),
                    "is_estimate": True,
                    "impact": "Klaim pengangguran mingguan — sinyal tercepat kondisi pasar tenaga kerja.",
                },
            ],
        },
        {
            "key": "ekonomi_lain",
            "title": "Data Ekonomi Lainnya",
            "icon": "chart.bar.fill",
            "items": [
                {
                    "key": "gdp",
                    "name": "GDP (Produk Domestik Bruto)",
                    "schedule_label": "Kuartalan · 3 versi (advance/second/final)",
                    "next_release": _monthly(_gdp, now),
                    "is_estimate": True,
                    "impact": "Pertumbuhan ekonomi kuartalan. Dirilis 3 versi: advance, second, dan final.",
                },
                {
                    "key": "retail_sales",
                    "name": "Retail Sales",
                    "schedule_label": "Bulanan · ~pertengahan bulan · 08:30 ET",
                    "next_release": _monthly(_retail, now),
                    "is_estimate": True,
                    "impact": "Indikator belanja konsumen — penting karena konsumsi ≈ 70% ekonomi AS.",
                },
                {
                    "key": "ism_mfg",
                    "name": "ISM Manufacturing PMI",
                    "schedule_label": "Bulanan · hari kerja pertama · 10:00 ET",
                    "next_release": _monthly(_ism_mfg, now),
                    "is_estimate": True,
                    "impact": "Di atas 50 = ekspansi, di bawah 50 = kontraksi sektor manufaktur.",
                },
                {
                    "key": "ism_svc",
                    "name": "ISM Services PMI",
                    "schedule_label": "Bulanan · ~hari kerja ke-3 · 10:00 ET",
                    "next_release": _monthly(_ism_svc, now),
                    "is_estimate": True,
                    "impact": "Di atas 50 = ekspansi, di bawah 50 = kontraksi sektor jasa.",
                },
                {
                    "key": "consumer_confidence",
                    "name": "Consumer Confidence",
                    "schedule_label": "Bulanan · Selasa terakhir · 10:00 ET",
                    "next_release": _monthly(_conf_board, now),
                    "is_estimate": True,
                    "impact": "Kepercayaan konsumen (Conference Board) terhadap kondisi ekonomi.",
                },
                {
                    "key": "michigan_sentiment",
                    "name": "Michigan Sentiment",
                    "schedule_label": "Bulanan · Jumat kedua (prelim) · 10:00 ET",
                    "next_release": _monthly(_michigan, now),
                    "is_estimate": True,
                    "impact": "Sentimen konsumen versi Univ. Michigan — rilis prelim & final tiap bulan.",
                },
            ],
        },
        {
            "key": "fiskal_politik",
            "title": "Kebijakan Fiskal & Politik",
            "icon": "building.columns.fill",
            "items": [
                {
                    "key": "tarif",
                    "name": "Kebijakan Tarif / Perang Dagang",
                    "schedule_label": "Tidak terjadwal · sewaktu-waktu",
                    "next_release": None,
                    "is_estimate": False,
                    "impact": "Sangat menggerakkan sektor tertentu (chip, otomotif, retail).",
                },
                {
                    "key": "anggaran",
                    "name": "Anggaran & Government Shutdown",
                    "schedule_label": "Tidak terjadwal · sewaktu-waktu",
                    "next_release": None,
                    "is_estimate": False,
                    "impact": "Anggaran pemerintah, ancaman government shutdown, dan drama debt ceiling.",
                },
                {
                    "key": "regulasi",
                    "name": "Regulasi Sektor",
                    "schedule_label": "Tidak terjadwal · sewaktu-waktu",
                    "next_release": None,
                    "is_estimate": False,
                    "impact": "Antitrust big tech, aturan energi, harga obat farmasi.",
                },
                {
                    "key": "pemilu_pajak",
                    "name": "Pemilu & Pajak Korporasi",
                    "schedule_label": "Tidak terjadwal · sewaktu-waktu",
                    "next_release": None,
                    "is_estimate": False,
                    "impact": "Pemilu dan perubahan kebijakan pajak korporasi.",
                },
            ],
        },
    ]


# ---------------------------------------------------------------------------
# Angka aktual via FRED API (opsional — hanya kalau FRED_API_KEY di-set)
# ---------------------------------------------------------------------------
#
# Tiap indikator dipetakan ke satu series FRED + transformasi `units`:
#   pc1 = persen perubahan dari tahun lalu (YoY)  → CPI/PCE/PPI
#   pch = persen perubahan dari periode sebelumnya (MoM/QoQ)
#   chg = perubahan absolut dari periode sebelumnya → NFP (ribu pekerja)
#   lin = level apa adanya → unemployment, GDP growth, jobless claims, dll
# `scale` mengubah satuan level (mis. ICSA dalam orang → dibagi 1000 = ribu).
# ISM PMI & Conference Board TIDAK ada di FRED (data proprietary) → tanpa angka.

_FRED_BASE = "https://api.stlouisfed.org/fred/series/observations"

_FRED_SERIES: dict[str, dict[str, Any]] = {
    "cpi":                {"series": "CPIAUCSL",           "units": "pc1", "dec": 1, "suffix": "%",   "unit_label": "YoY"},
    "pce":                {"series": "PCEPILFE",           "units": "pc1", "dec": 1, "suffix": "%",   "unit_label": "core YoY"},
    "ppi":                {"series": "PPIFIS",             "units": "pc1", "dec": 1, "suffix": "%",   "unit_label": "YoY"},
    "nfp":                {"series": "PAYEMS",             "units": "chg", "dec": 0, "suffix": " rb", "unit_label": "MoM", "sign": True},
    "jolts":             {"series": "JTSJOL",             "units": "lin", "dec": 1, "suffix": " jt", "unit_label": "lowongan", "scale": 0.001},
    "jobless_claims":     {"series": "ICSA",               "units": "lin", "dec": 0, "suffix": " rb", "unit_label": "klaim", "scale": 0.001},
    "gdp":                {"series": "A191RL1Q225SBEA",    "units": "lin", "dec": 1, "suffix": "%",   "unit_label": "QoQ tahunan", "quarterly": True},
    "retail_sales":       {"series": "RSAFS",              "units": "pch", "dec": 1, "suffix": "%",   "unit_label": "MoM", "sign": True},
    "michigan_sentiment": {"series": "UMCSENT",            "units": "lin", "dec": 1, "suffix": "",    "unit_label": "indeks"},
}

_ID_MONTHS = ["", "Jan", "Feb", "Mar", "Apr", "Mei", "Jun",
              "Jul", "Agu", "Sep", "Okt", "Nov", "Des"]


def _fmt_num(value: float, dec: int, suffix: str, sign: bool) -> str:
    """Format angka gaya Indonesia (koma desimal) + suffix, opsional tanda +."""
    txt = f"{value:.{dec}f}".replace(".", ",")
    if sign and value > 0:
        txt = "+" + txt
    return txt + suffix


def _period_label(iso_date: str, quarterly: bool = False) -> str:
    """'2026-06-01' → 'Jun 2026' (atau 'Q2 2026' untuk data kuartalan)."""
    try:
        d = datetime.strptime(iso_date, "%Y-%m-%d").date()
        if quarterly:
            return f"Q{(d.month - 1) // 3 + 1} {d.year}"
        return f"{_ID_MONTHS[d.month]} {d.year}"
    except Exception:  # noqa: BLE001
        return iso_date


async def _fetch_fred_one(client: httpx.AsyncClient, key: str,
                          cfg: dict[str, Any]) -> dict[str, Any] | None:
    """Ambil 2 observasi terbaru satu series FRED → dict actual siap kirim."""
    params = {
        "series_id": cfg["series"],
        "api_key": settings.fred_api_key,
        "file_type": "json",
        "units": cfg["units"],
        "sort_order": "desc",
        "limit": 2,
    }
    try:
        resp = await client.get(_FRED_BASE, params=params, timeout=15.0)
        resp.raise_for_status()
        obs = [o for o in resp.json().get("observations", []) if o.get("value") not in (None, ".")]
        if not obs:
            return None

        scale = cfg.get("scale", 1.0)
        latest = float(obs[0]["value"]) * scale
        prev = float(obs[1]["value"]) * scale if len(obs) > 1 else None

        direction = "flat"
        if prev is not None:
            direction = "up" if latest > prev else "down" if latest < prev else "flat"

        return {
            "value_text": _fmt_num(latest, cfg["dec"], cfg["suffix"], cfg.get("sign", False)),
            "unit_label": cfg["unit_label"],
            "previous_text": (_fmt_num(prev, cfg["dec"], cfg["suffix"], cfg.get("sign", False))
                              if prev is not None else None),
            "direction": direction,
            "period": _period_label(obs[0].get("date", ""), cfg.get("quarterly", False)),
            "source": "fred",
        }
    except Exception as e:  # noqa: BLE001
        logger.warning(f"[makro-kalender] gagal fetch FRED {cfg['series']}: {e}")
        return None


async def _fetch_fred_all() -> dict[str, dict[str, Any]]:
    """Ambil semua series FRED paralel. Kosong kalau FRED_API_KEY tak di-set."""
    if not settings.fred_api_key:
        logger.info("[makro-kalender] FRED_API_KEY kosong — angka aktual dilewati.")
        return {}

    async with httpx.AsyncClient() as client:
        keys = list(_FRED_SERIES.keys())
        results = await asyncio.gather(
            *(_fetch_fred_one(client, k, _FRED_SERIES[k]) for k in keys),
            return_exceptions=True,
        )

    out: dict[str, dict[str, Any]] = {}
    for k, r in zip(keys, results):
        if isinstance(r, dict):
            out[k] = r
    logger.info(f"[makro-kalender] FRED: {len(out)}/{len(keys)} indikator berhasil.")
    return out


# ---------------------------------------------------------------------------
# Yield US Treasury 10 tahun (LIVE via Yahoo Finance ^TNX)
# ---------------------------------------------------------------------------

def _fetch_treasury_10y() -> dict[str, Any] | None:
    """Yield UST 10Y + perubahan harian (sinkron; dipanggil via to_thread)."""
    try:
        hist = yf.Ticker("^TNX").history(period="5d")
        closes = hist["Close"].dropna()
        if closes.empty:
            return None
        last = float(closes.iloc[-1])
        prev = float(closes.iloc[-2]) if len(closes) >= 2 else last
        # ^TNX umumnya sudah dalam persen (mis. 4.54). Jaga-jaga bila di-quote ×10.
        if last > 20:
            last, prev = last / 10, prev / 10
        return {
            "yield": round(last, 3),
            "change": round(last - prev, 3),
            "as_of": date.today().isoformat(),
            "source": "live",
        }
    except Exception as e:  # noqa: BLE001
        logger.warning(f"[makro-kalender] gagal fetch ^TNX: {e}")
        return None


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

async def collect_makro_calendar(force: bool = False) -> dict[str, Any]:
    """
    Snapshot kalender faktor makro AS: jadwal rilis + edukasi + yield UST 10Y +
    angka aktual FRED (bila FRED_API_KEY di-set). Selalu mengembalikan dict valid
    (yield/actual bisa None kalau fetch gagal).

    Angka aktual per item ada di `item["actual"]` (None untuk item tanpa series
    FRED, mis. ISM PMI & Conference Board yang datanya proprietary). Lihat
    `_FRED_SERIES` untuk pemetaan indikator → series + transformasi.
    """
    now_t = _time.time()
    if not force and "data" in _cache and now_t - _cache.get("ts", 0) < _CACHE_TTL:
        return _cache["data"]

    now = _now_et()
    # Treasury (thread, yfinance sinkron) + FRED (async httpx) paralel.
    treasury, fred = await asyncio.gather(
        asyncio.to_thread(_fetch_treasury_10y),
        _fetch_fred_all(),
    )

    categories = _build_categories(now)
    # Sisipkan angka aktual FRED ke tiap item yang punya series.
    for cat in categories:
        for item in cat["items"]:
            item["actual"] = fred.get(item["key"])

    data = {
        "as_of": date.today().isoformat(),
        "treasury_10y": treasury,      # bisa None kalau fetch gagal
        "categories": categories,
    }
    _cache["data"], _cache["ts"] = data, now_t
    return data
