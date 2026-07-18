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

KENAPA TIDAK ADA ANGKA AKTUAL CPI/NFP DI SINI:
    Angka aktual + konsensus tiap rilis tidak tersedia gratis lengkap. Modul ini
    fokus pada JADWAL + EDUKASI (kapan rilis, apa artinya, dampak ke pasar) plus
    yield Treasury live. Untuk menambah angka aktual, integrasikan FRED API
    (butuh API key gratis) — lihat catatan di collect_makro_calendar().

Penggunaan:
    from backend.data.collectors.makro_calendar_collector import collect_makro_calendar
    data = await collect_makro_calendar()   # -> dict siap dikirim sebagai JSON
"""

import asyncio
import time as _time
from datetime import date, datetime, time, timedelta
from typing import Any, Callable
from zoneinfo import ZoneInfo

import yfinance as yf
from loguru import logger

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
    Snapshot kalender faktor makro AS: jadwal rilis + edukasi + yield UST 10Y.
    Selalu mengembalikan dict valid (yield bisa None kalau fetch gagal).

    UNTUK MENAMBAH ANGKA AKTUAL (opsional, butuh FRED API key gratis):
        Ambil series FRED — CPIAUCSL (CPI), PCEPILFE (core PCE), PPIFIS (PPI),
        PAYEMS (NFP), UNRATE, ICSA (jobless claims), GDPC1, RSAFS (retail),
        UMCSENT (Michigan), DGS10 — lalu sisipkan "actual"/"previous" per item.
    """
    now_t = _time.time()
    if not force and "data" in _cache and now_t - _cache.get("ts", 0) < _CACHE_TTL:
        return _cache["data"]

    now = _now_et()
    treasury = await asyncio.to_thread(_fetch_treasury_10y)

    data = {
        "as_of": date.today().isoformat(),
        "treasury_10y": treasury,      # bisa None kalau fetch gagal
        "categories": _build_categories(now),
    }
    _cache["data"], _cache["ts"] = data, now_t
    return data
