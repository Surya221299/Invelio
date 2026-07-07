"""
AI Saham Indonesia — Ticker Symbol Helper

Sebelumnya seluruh kode (fundamental_collector.py, scoring_agent.py, data.py)
membangun simbol ticker yfinance dengan hardcode suffix ".JK" dari
`settings.yfinance_market_suffix`. Itu valid untuk saham IDX, tapi SALAH
untuk saham/ETF NASDAQ (yang tidak pakai suffix sama sekali) — jika
dipaksakan, yfinance akan gagal fetch dan seluruh skor teknikal/QoQ growth
diam-diam jatuh ke nilai default netral.

Modul ini memusatkan logika "kode saham + market -> simbol yfinance yang
benar" di satu tempat, supaya menambah market baru cukup edit dict di bawah.

Penggunaan:
    from backend.utils.ticker import get_yf_symbol

    get_yf_symbol("BBCA", "IDX")     -> "BBCA.JK"
    get_yf_symbol("SNPS", "NASDAQ")  -> "SNPS"
    get_yf_symbol("QQQ", "ETF")      -> "QQQ"
"""

from backend.config import settings

# Suffix yfinance per market. Default "IDX" tetap pakai settings.yfinance_market_suffix
# (".JK") supaya perilaku lama untuk 20 saham IDX yang sudah ada TIDAK berubah.
# Tambahkan market baru di sini jika perlu (mis. "LSE": ".L", "TSE": ".T").
_MARKET_SUFFIX: dict[str, str] = {
    "IDX": settings.yfinance_market_suffix,  # ".JK"
    "NASDAQ": "",
    "NYSE": "",
    "ETF": "",
}

DEFAULT_MARKET = "IDX"


def normalize_market(market: str | None) -> str:
    """Normalisasi nilai market: None/kosong -> 'IDX' (perilaku lama)."""
    if not market:
        return DEFAULT_MARKET
    m = market.strip().upper()
    return m if m in _MARKET_SUFFIX else DEFAULT_MARKET


def get_yf_symbol(kode: str, market: str | None = None) -> str:
    """
    Bangun simbol ticker yfinance yang benar berdasarkan market asal saham.

    Args:
        kode: Kode saham tanpa suffix (mis. "BBCA", "SNPS")
        market: "IDX" | "NASDAQ" | "NYSE" | "ETF" (default: "IDX" jika None,
                supaya kode lama yang belum sempat diisi field market tetap jalan)

    Returns:
        Simbol siap pakai untuk yf.Ticker(...), mis. "BBCA.JK" atau "SNPS"
    """
    kode_clean = kode.strip().upper()
    market_clean = normalize_market(market)
    suffix = _MARKET_SUFFIX.get(market_clean, "")
    return f"{kode_clean}{suffix}"
