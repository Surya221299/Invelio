"""
AI Saham Indonesia — Berita Collector

Mengambil berita terkait saham Indonesia dari berbagai sumber RSS:
- Google News RSS: pencarian per kode emiten + berita pasar umum
- Kontan RSS: berita ekonomi dan pasar modal

Data berita disimpan sebagai metadata di PostgreSQL. Teks lengkap
akan di-embed ke ChromaDB oleh modul terpisah (indexer).

Penggunaan:
    from backend.data.collectors.berita_collector import (
        collect_berita,
        collect_berita_batch,
        collect_berita_pasar,
    )

    # Berita untuk satu saham
    berita = await collect_berita("BBCA", hari_terakhir=7)

    # Berita untuk banyak saham sekaligus
    berita = await collect_berita_batch(["BBCA", "TLKM"], hari_terakhir=7)

    # Berita pasar umum
    berita = await collect_berita_pasar(hari_terakhir=3)

Catatan:
    - Deduplikasi otomatis berdasarkan URL
    - Berita yang lebih tua dari `hari_terakhir` akan difilter
    - Error pada satu sumber TIDAK menghentikan sumber lainnya
"""

import asyncio
import base64
from datetime import datetime, timedelta, timezone
import re
from typing import Any
from urllib.parse import quote_plus

from bs4 import BeautifulSoup
import feedparser
import httpx
from loguru import logger

from backend.config import settings
from backend.utils.http import fetch_html

# Timezone WIB (UTC+7) untuk parsing tanggal berita Indonesia
_WIB = timezone(timedelta(hours=7))

# Timeout untuk HTTP requests (detik)
_HTTP_TIMEOUT = 30.0

# Delay antar request RSS untuk menghindari rate limiting
_REQUEST_DELAY_SECONDS: float = 2.0


# ============================================================
# News Profile — dukungan multi-market (Indonesia & US)
# ============================================================
#
# Collector ini awalnya khusus saham Indonesia (Google News locale id/ID,
# keyword & prompt LLM berbahasa Indonesia). Untuk mendukung saham US
# (NASDAQ/NYSE/ETF) kita perkenalkan konsep "news locale":
#
#   market  -> locale berita
#   IDX     -> "ID"  (berita berbahasa Indonesia, Google News id/ID)
#   NASDAQ  -> "US"  (berita berbahasa Inggris, Google News en-US/US)
#   NYSE    -> "US"
#   ETF     -> "US"
#
# Semua fungsi collector menerima parameter `market` (default "IDX" agar
# perilaku lama saham IDX TIDAK berubah). Locale menentukan: parameter
# Google News RSS, template query pencarian, keyword filter relevansi, dan
# bahasa prompt LLM-as-a-judge.


def _news_locale(market: str | None) -> str:
    """
    Petakan market saham ke locale berita.

    IDX (atau kosong/None) -> "ID" (perilaku lama, berita Indonesia).
    Market US (NASDAQ/NYSE/ETF/dll) -> "US" (berita Inggris).
    """
    m = (market or "IDX").strip().upper()
    return "ID" if m in ("", "IDX") else "US"


# Parameter locale Google News RSS per locale berita.
_GOOGLE_NEWS_LOCALE: dict[str, str] = {
    "ID": "hl=id&gl=ID&ceid=ID:id",
    "US": "hl=en-US&gl=US&ceid=US:en",
}

# Template query pencarian per emiten (di-format dengan `kode`).
_EMITEN_QUERIES: dict[str, list[str]] = {
    "ID": [
        "saham {kode} IDX",
        "{kode} emiten bursa",
    ],
    "US": [
        "{kode} stock news",
        "{kode} stock earnings",
    ],
}

# Query pencarian berita pasar umum (tidak spesifik satu emiten).
_PASAR_QUERIES: dict[str, list[str]] = {
    "ID": [
        "IHSG bursa efek indonesia",
        "pasar modal indonesia saham",
    ],
    "US": [
        "US stock market S&P 500 today",
        "Wall Street stocks Nasdaq Dow Jones",
    ],
}

# Keyword penanda NOISE (berita non-investasi) per locale.
_NOISE_KEYWORDS: dict[str, list[str]] = {
    "ID": [
        "promo", "diskon", "voucher", "katalog belanja", "undian",
        "mudik", "lebaran", "ramadan", "ramadhan", "giveaway",
        "csr", "donasi", "bantuan sosial", "bansos", "beasiswa",
        "lowongan kerja", "loker", "magang", "rekrutmen", "karir",
        "olahraga", "sepak bola", "klasemen", "skor liga", "resep",
        "kuliner", "makanan", "wisata", "liburan", "traveling",
        "konser", "festival", "film", "sinopsis", "drama", "artis",
        "gosip", "bencana alam", "gempa", "kecelakaan maut", "kebakaran",
        "tawuran", "kriminal", "pembunuhan", "perampokan", "mudik gratis",
        "tips diet", "kecantikan", "makeup", "fashion", "zodiak",
    ],
    "US": [
        "coupon", "discount", "sale", "giveaway", "sweepstakes", "promo",
        "deal of the day", "black friday deal", "gift guide",
        "recipe", "food", "restaurant review", "travel guide", "vacation",
        "concert", "festival", "movie review", "tv show", "celebrity",
        "gossip", "horoscope", "sports", "nfl", "nba", "soccer",
        "fashion", "makeup", "beauty tips", "weight loss", "obituary",
        "how to watch", "streaming guide",
    ],
}

# Keyword penanda berita FINANSIAL/INVESTASI (positif) per locale.
_FINANCE_KEYWORDS: dict[str, list[str]] = {
    "ID": [
        "saham", "emiten", "laba", "rugi", "rupiah", "dolar", "investasi",
        "ihsg", "bursa", "idx", "bei", "ipo", "rups", "dividen", "obligasi",
        "reksadana", "sukuk", "gdp", "bi rate", "inflasi", "suku bunga",
        "fomc", "fed", "keuangan", "akuisisi", "merger", "kinerja",
        "kuartal", "q1", "q2", "q3", "q4", "fy", "semester", "revenue",
        "pendapatan", "omzet", "ekspansi", "utang", "obligasi", "korporasi",
        "harga saham", "rebound", "bullish", "bearish", "sideways", "kapitalisasi",
    ],
    "US": [
        "stock", "shares", "earnings", "revenue", "profit", "loss", "dividend",
        "nasdaq", "nyse", "s&p 500", "dow jones", "wall street", "ipo",
        "guidance", "outlook", "analyst", "upgrade", "downgrade", "price target",
        "acquisition", "merger", "buyback", "quarter", "q1", "q2", "q3", "q4",
        "fiscal", "eps", "market cap", "fed", "fomc", "interest rate", "inflation",
        "bullish", "bearish", "rally", "selloff", "valuation", "guidance",
        "sec filing", "10-k", "10-q", "8-k", "forecast", "investor",
    ],
}


def decode_google_news_url(url: str) -> str:
    """
    Mendecode URL redirect Google News menggunakan googlenewsdecoder.
    """
    try:
        if "rss/articles" not in url and "articles/" not in url:
            return url
        from googlenewsdecoder import gnewsdecoder
        decoded_info = gnewsdecoder(url, interval=1)
        if decoded_info.get("status") and decoded_info.get("decoded_url"):
            logger.info(f"✅ Google News URL decoded: {decoded_info['decoded_url']}")
            return decoded_info["decoded_url"]
    except Exception as e:
        logger.warning(f"⚠️ Gagal mendecode URL Google News '{url}' dengan googlenewsdecoder: {e}")

    try:
        match = re.search(r"articles/([^?]+)", url)
        if not match:
            return url
        
        encoded_str = match.group(1)
        # Pad string base64 jika panjangnya tidak kelipatan 4
        padded = encoded_str + "=" * ((4 - len(encoded_str) % 4) % 4)
        decoded = base64.b64decode(padded)
        
        # Cari pola URL (http:// atau https://) di dalam bytes hasil decode
        url_match = re.search(b"(https?://[^\x00-\x1f\x7f-\xff]+)", decoded)
        if url_match:
            return url_match.group(1).decode("utf-8")
    except Exception as e:
        pass
    return url


async def fetch_article_content(url: str) -> str:
    """
    Mengambil isi berita lengkap secara async dari URL sumber, membersihkan HTML tag,
    dan mengekstrak teks berita utama.
    """
    # Decode Google News URL jika masih dalam format google news
    if "news.google.com" in url:
        url = decode_google_news_url(url)

    try:
        html = await fetch_html(url, timeout=15.0)

        soup = BeautifulSoup(html, "html.parser")
        
        # Bersihkan elemen yang tidak penting
        for element in soup(["script", "style", "nav", "header", "footer", "form", "aside", "iframe", "noscript"]):
            element.decompose()
            
        # Cari div konten berita berdasarkan class/tag umum portal berita.
        # Mencakup portal Indonesia (Kompas/Detik/Kontan/dll) dan portal US
        # (Yahoo Finance, CNBC, Reuters, MarketWatch, Bloomberg, dll).
        content_div = None
        for selector in [
            "article",
            # Portal berita Indonesia
            ".read__content",
            ".detail__body-text",
            ".post-content",
            ".entry-content",
            ".post-body",
            ".article-content",
            ".detail-text",
            ".news-content",
            # Portal berita US
            ".caas-body",            # Yahoo Finance
            ".ArticleBody-articleBody",  # CNBC
            ".article-body__content",    # Reuters
            ".paywall",              # WSJ/MarketWatch body wrapper
            "[data-component='ArticleBody']",
            ".article__content",
            ".body-content",
        ]:
            content_div = soup.select_one(selector)
            if content_div:
                break

        if content_div:
            paragraphs = content_div.find_all("p")
        else:
            paragraphs = soup.find_all("p")

        text_parts = []
        for p in paragraphs:
            text = p.get_text().strip()
            # Filter baris/paragraf boilerplate umum (ID + EN)
            if len(text) > 30 and not any(skip in text.lower() for skip in [
                # Indonesia
                "baca juga:", "download aplikasi", "simak breaking news", "follow instagram", "klik di sini",
                "halaman selanjutnya", "selengkapnya di",
                # US
                "read more:", "sign up for", "subscribe to", "follow us on", "click here",
                "advertisement", "related:", "story continues", "terms of service",
                "all rights reserved", "©",
            ]):
                text_parts.append(text)
                
        content = "\n\n".join(text_parts)
        return content[:10000].strip()  # Batasi max 10.000 karakter
    except Exception as e:
        logger.warning(f"⚠️ Gagal mengambil isi berita dari {url}: {e}")
        return ""
_JUDGE_PROMPTS: dict[str, dict[str, str]] = {
    "ID": {
        "system": "Kamu adalah juri investasi profesional. Jawab hanya dengan format JSON valid.",
        "prompt": """Kamu adalah analis investasi profesional yang bertindak sebagai juri (LLM as a Judge).
Tugasmu adalah menilai apakah berita keuangan berikut ini RELEVAN untuk analisis keputusan investasi saham emiten terkait, atau hanya berita promosi/CSR/iklan/noise yang tidak bernilai investasi.

Judul Berita: "{title}"
Isi Berita (Potongan):
"{content}"

Kriteria Relevan (True):
- Berita tentang kinerja keuangan, laba, pendapatan, dividen, aksi korporasi (akuisisi, merger, right issue), target harga, rekomendasi saham, restrukturisasi, sengketa bisnis penting, ekspansi bisnis, atau perubahan manajemen emiten.

Kriteria Tidak Relevan (False):
- Berita tentang promosi produk biasa, diskon belanja, lowongan kerja (loker), program CSR/beasiswa, kegiatan olahraga/donasi rutin, ucapan selamat hari raya, info traveling, gosip, kecelakaan minor, atau siaran pers promosi komersial biasa yang tidak mempengaruhi nilai saham secara fundamental.

Berikan penilaianmu dalam format JSON:
{{"relevan": boolean, "alasan": "penjelasan singkat 1 kalimat"}}
""",
    },
    "US": {
        "system": "You are a professional investment judge. Respond ONLY with valid JSON.",
        "prompt": """You are a professional investment analyst acting as a judge (LLM as a Judge).
Your task is to decide whether the following financial news is RELEVANT for making a stock investment decision about the related company, or is just promotional/PR/ad/noise with no investment value.

News Title: "{title}"
News Body (excerpt):
"{content}"

Relevant criteria (True):
- News about financial performance, earnings, revenue, dividends, corporate actions (acquisition, merger, buyback, split), analyst ratings/price targets, guidance/outlook, SEC filings, restructuring, major litigation, business expansion, or management changes.

Not relevant criteria (False):
- News about ordinary product promos, discounts/sales, job postings, CSR/scholarship programs, routine sports/donation activities, holiday greetings, travel guides, gossip, minor accidents, or ordinary commercial press releases that do not fundamentally affect the stock's value.

Give your verdict in JSON format:
{{"relevan": boolean, "alasan": "brief 1-sentence reason"}}
""",
    },
}


async def is_news_relevant_llm(title: str, content: str, market: str = "IDX") -> bool:
    """
    LLM as a Judge untuk memfilter relevansi berita (Kasus 6).
    Menilai apakah berita ini benar-benar relevan untuk analisis keputusan investasi saham
    atau hanya noise (CSR, diskon belanja, ucapan hari raya, dll).

    Bahasa prompt mengikuti locale berita (Indonesia untuk IDX, Inggris untuk US).
    """
    locale = _news_locale(market)

    # Lakukan filtering keyword cepat dulu agar tidak boros token ke LLM
    if not is_news_relevant(title, content, market=market):
        return False

    try:
        from langchain_ollama import ChatOllama
        from langchain_core.messages import SystemMessage, HumanMessage
        import json
        from backend.config import settings

        llm = ChatOllama(
            model="qwen2.5:3b",
            base_url=settings.ollama_base_url,
            temperature=0.0,
            timeout=20,
        )

        tmpl = _JUDGE_PROMPTS[locale]
        prompt = tmpl["prompt"].format(title=title, content=content[:1000])
        messages = [
            SystemMessage(content=tmpl["system"]),
            HumanMessage(content=prompt)
        ]

        response = await llm.ainvoke(messages)
        res_text = response.content.strip()

        if "```json" in res_text:
            res_text = res_text.split("```json")[1].split("```")[0].strip()
        elif "```" in res_text:
            res_text = res_text.split("```")[1].strip()

        data = json.loads(res_text.strip())
        is_rel = bool(data.get("relevan", False))
        logger.info(f"⚖️ Ingestion Judge: '{title[:50]}' -> Relevan: {is_rel} (Alasan: {data.get('alasan', '')})")
        return is_rel
    except Exception as e:
        logger.warning(f"⚠️ Ingestion Judge gagal ({e}). Fallback ke keyword filter.")
        return True  # Fallback ke True jika keyword filter sudah lolos


def is_news_relevant(title: str, content: str = "", market: str = "IDX") -> bool:
    """
    Reranking/filtering berita untuk menyaring berita tidak relevan (promo, diskon, dll).
    Mengembalikan True jika berita dinilai relevan dengan investasi/emiten/pasar modal.

    Keyword set mengikuti locale berita: bahasa Indonesia untuk IDX,
    bahasa Inggris untuk market US (NASDAQ/NYSE/ETF).
    """
    locale = _news_locale(market)
    title_lower = title.lower()
    content_lower = content.lower()

    # Kata kunci penanda berita spam, gaya hidup, atau non-investasi (negatif/noise filter)
    for kw in _NOISE_KEYWORDS[locale]:
        if kw in title_lower:
            return False

    # Kata kunci penanda berita finansial/investasi (positif filter)
    finance_keywords = _FINANCE_KEYWORDS[locale]
    has_finance = any(kw in title_lower for kw in finance_keywords) or \
                  (content_lower and any(kw in content_lower for kw in finance_keywords))

    return has_finance


def _parse_published_date(entry: dict[str, Any]) -> datetime | None:
    """
    Parse tanggal publish dari entry RSS feed.

    RSS feeds menggunakan berbagai format tanggal. feedparser
    menormalisasi ke struct_time di field `published_parsed`,
    tapi kadang field ini tidak tersedia.

    Args:
        entry: Satu entry dari feedparser

    Returns:
        datetime dengan timezone, atau None jika gagal parse
    """
    # Coba dari published_parsed (sudah di-parse oleh feedparser)
    parsed = entry.get("published_parsed")
    if parsed:
        try:
            dt = datetime(*parsed[:6], tzinfo=timezone.utc)
            return dt
        except (ValueError, TypeError):
            pass

    # Coba dari updated_parsed sebagai fallback
    updated = entry.get("updated_parsed")
    if updated:
        try:
            dt = datetime(*updated[:6], tzinfo=timezone.utc)
            return dt
        except (ValueError, TypeError):
            pass

    # Fallback: gunakan waktu sekarang
    logger.debug(
        f"⚠️  Tidak bisa parse tanggal untuk: {entry.get('title', 'unknown')}"
    )
    return None


def _normalize_berita_entry(
    entry: dict[str, Any],
    kode_saham: str | None,
    sumber: str,
) -> dict[str, Any] | None:
    """
    Normalisasi satu entry RSS menjadi format dict yang sesuai model Berita.

    Args:
        entry: Satu entry dari feedparser
        kode_saham: Kode saham terkait (None untuk berita pasar umum)
        sumber: Nama sumber berita

    Returns:
        Dict siap simpan ke PostgreSQL, atau None jika data tidak valid
    """
    judul = entry.get("title", "").strip()
    url = entry.get("link", "").strip()

    # Validasi minimal: judul dan URL harus ada
    if not judul or not url:
        return None

    # URL google news akan didecode nanti saat akan di-scrape untuk mempercepat proses normalisasi awal

    tanggal_publish = _parse_published_date(entry)
    if tanggal_publish is None:
        return None

    return {
        "kode_saham": kode_saham,
        "judul": judul[:500],  # Batasi panjang judul sesuai model (VARCHAR 500)
        "url": url[:1000],     # Batasi panjang URL sesuai model (VARCHAR 1000)
        "sumber": sumber,
        "tanggal_publish": tanggal_publish,
        "skor_sentimen": None,        # Akan diisi oleh sentiment analyzer
        "sudah_diembedding": False,   # Belum di-embed ke ChromaDB
    }


async def _fetch_rss_feed(url: str) -> list[dict[str, Any]]:
    """
    Fetch dan parse RSS feed dari URL menggunakan httpx (async) + feedparser.

    Args:
        url: URL RSS feed

    Returns:
        List of entries dari RSS feed (bisa kosong jika gagal)
    """
    try:
        text = await fetch_html(url, timeout=_HTTP_TIMEOUT)

        # Bersihkan karakter ampersand yang tidak valid (&) agar XML feedparser tidak error
        import re
        cleaned_text = re.sub(r'&(?!amp;|lt;|gt;|quot;|apos;|#[0-9]+;)', '&amp;', text)

        # feedparser bisa parse string XML langsung
        feed = await asyncio.to_thread(feedparser.parse, cleaned_text)

        if feed.bozo and not feed.entries:
            # bozo = feed tidak valid, tapi kadang masih punya entries
            logger.warning(
                f"⚠️  RSS feed mungkin tidak valid: {url} "
                f"(bozo_exception: {feed.get('bozo_exception', 'unknown')})"
            )
            return []

        logger.debug(f"📰 Ditemukan {len(feed.entries)} entries dari {url}")
        return feed.entries

    except httpx.TimeoutException:
        logger.error(f"⏱️  Timeout saat mengambil RSS: {url}")
        return []
    except httpx.HTTPStatusError as e:
        logger.error(f"🚫 HTTP {e.response.status_code} dari RSS: {url}")
        return []
    except Exception as e:
        logger.error(f"❌ Gagal fetch RSS {url}: {type(e).__name__}: {e}")
        return []


async def _collect_from_google_news(
    kode_saham: str | None,
    query: str,
    hari_terakhir: int,
    market: str = "IDX",
) -> list[dict[str, Any]]:
    """
    Ambil berita dari Google News RSS berdasarkan query pencarian.

    Args:
        kode_saham: Kode saham terkait (atau None untuk berita umum)
        query: Query pencarian Google News
        hari_terakhir: Hanya ambil berita dalam N hari terakhir
        market: Market saham; menentukan locale Google News (IDX -> id/ID,
                US -> en-US/US)

    Returns:
        List of dict berita yang sudah dinormalisasi
    """
    locale = _news_locale(market)
    locale_params = _GOOGLE_NEWS_LOCALE[locale]

    # Encode query untuk URL
    encoded_query = quote_plus(query)
    url = (
        f"https://news.google.com/rss/search"
        f"?q={encoded_query}+when:{hari_terakhir}d"
        f"&{locale_params}"
    )

    logger.debug(f"🔍 Google News query: '{query}' ({hari_terakhir} hari)")

    entries = await _fetch_rss_feed(url)
    cutoff = datetime.now(timezone.utc) - timedelta(days=hari_terakhir)

    results: list[dict[str, Any]] = []
    for entry in entries:
        berita = _normalize_berita_entry(entry, kode_saham, "google_news")
        if berita is None:
            continue

        # Filter: hanya berita dalam rentang waktu yang diminta
        if berita["tanggal_publish"] < cutoff:
            continue

        results.append(berita)

    return results


async def _collect_from_kontan(
    hari_terakhir: int,
) -> list[dict[str, Any]]:
    """
    Ambil berita dari Kontan RSS feed.

    Kontan adalah salah satu portal berita ekonomi terbesar di Indonesia.
    Feed RSS-nya berisi berita pasar modal, makroekonomi, dan emiten.

    Args:
        hari_terakhir: Hanya ambil berita dalam N hari terakhir

    Returns:
        List of dict berita yang sudah dinormalisasi
    """
    logger.debug(f"📰 Mengambil berita dari Kontan RSS...")

    entries = await _fetch_rss_feed(settings.kontan_rss_url)
    cutoff = datetime.now(timezone.utc) - timedelta(days=hari_terakhir)

    results: list[dict[str, Any]] = []
    for entry in entries:
        # Berita Kontan bersifat umum, kode_saham = None
        berita = _normalize_berita_entry(entry, None, "kontan")
        if berita is None:
            continue

        if berita["tanggal_publish"] < cutoff:
            continue

        results.append(berita)

    return results


def _deduplikasi_berita(berita_list: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """
    Hapus berita duplikat berdasarkan URL.

    Berita dari berbagai sumber bisa memiliki URL yang sama
    (misalnya Google News mengarahkan ke Kontan). Fungsi ini
    memastikan setiap URL hanya muncul sekali.

    Args:
        berita_list: List berita yang mungkin mengandung duplikat

    Returns:
        List berita tanpa duplikat (URL pertama yang muncul dipertahankan)
    """
    seen_urls: set[str] = set()
    unique: list[dict[str, Any]] = []

    for berita in berita_list:
        url = berita["url"]
        if url not in seen_urls:
            seen_urls.add(url)
            unique.append(berita)

    jumlah_duplikat = len(berita_list) - len(unique)
    if jumlah_duplikat > 0:
        logger.info(f"🔄 Dihapus {jumlah_duplikat} berita duplikat (berdasarkan URL)")

    return unique


async def collect_berita(
    kode_saham: str,
    hari_terakhir: int = 7,
    market: str = "IDX",
) -> list[dict[str, Any]]:
    """
    Ambil berita terkait satu saham dari semua sumber RSS.

    Mencari berita dari Google News dengan query spesifik per emiten,
    lalu menggabungkan dan mendeduplikasi hasilnya.

    Args:
        kode_saham: Kode saham (contoh: "BBCA" untuk IDX, "AAPL" untuk US)
        hari_terakhir: Hanya ambil berita dalam N hari terakhir (default: 7)
        market: Market saham ("IDX", "NASDAQ", "NYSE", "ETF"). Menentukan
                locale berita, query, dan filter relevansi (default: "IDX")

    Returns:
        List of dict berita yang sudah dinormalisasi dan dideduplikasi

    Example:
        >>> berita = await collect_berita("BBCA", hari_terakhir=7)
        >>> print(berita[0])
        {
            "kode_saham": "BBCA",
            "judul": "BBCA Cetak Laba Bersih Rp 10 Triliun di Q1 2024",
            "url": "https://...",
            "sumber": "google_news",
            "tanggal_publish": datetime(...),
            "skor_sentimen": None,
            "sudah_diembedding": False,
        }
    """
    kode = kode_saham.strip().upper()
    locale = _news_locale(market)
    logger.info(f"📰 Mengumpulkan berita untuk {kode} (market={market}, {hari_terakhir} hari)...")

    all_berita: list[dict[str, Any]] = []

    # Sumber 1: Google News — query spesifik per emiten
    # Menggunakan beberapa variasi query untuk coverage yang lebih baik
    queries = [tmpl.format(kode=kode) for tmpl in _EMITEN_QUERIES[locale]]

    for query in queries:
        try:
            berita = await _collect_from_google_news(kode, query, hari_terakhir, market=market)
            all_berita.extend(berita)
        except Exception as e:
            logger.error(
                f"❌ Gagal ambil Google News untuk query '{query}': "
                f"{type(e).__name__}: {e}"
            )

        # Delay antar query
        await asyncio.sleep(_REQUEST_DELAY_SECONDS)

    # Deduplikasi
    unique_berita = _deduplikasi_berita(all_berita)

    # Batasi ke top 15 berita terbaru untuk di-scrape agar memiliki pool cadangan (Kasus 2)
    unique_berita = unique_berita[:15]

    relevant_berita: list[dict[str, Any]] = []
    for berita in unique_berita:
        title = berita["judul"]
        if is_news_relevant(title, market=market):
            url = berita["url"]
            # Decode URL di sini sebelum di-scrape agar lebih efisien dan hemat network call
            if "news.google.com" in url:
                url = decode_google_news_url(url)
                berita["url"] = url

            logger.info(f"📰 Mengambil isi berita: {title[:50]}...")
            content = await fetch_article_content(url)

            # Pastikan isi berita berhasil di-scrape dan cukup panjang (Kasus 2)
            if content and len(content.strip()) >= 200:
                # Verifikasi relevansi secara mendalam menggunakan LLM as a Judge (Kasus 6)
                if await is_news_relevant_llm(title, content, market=market):
                    berita["isi_berita"] = content
                    relevant_berita.append(berita)
                    # Batasi ke maksimal 5 berita berkualitas per emiten
                    if len(relevant_berita) >= 5:
                        logger.info(f"✅ Sudah mencapai batas 5 berita relevan untuk {kode}. Berhenti scraping.")
                        break
                else:
                    logger.info(f"🗑️ Membuang berita tidak relevan setelah cek isi (LLM Judge): {title[:50]}")
            else:
                logger.info(f"🗑️ Membuang berita karena gagal scrape isi atau isi terlalu pendek: {title[:50]}")
            
            # Delay kecil agar sopan ke server news
            await asyncio.sleep(1.0)
        else:
            logger.info(f"🗑️ Membuang berita tidak relevan berdasarkan judul: {title[:50]}")

    logger.info(
        f"📰 {kode}: ditemukan {len(relevant_berita)} berita relevan dari {len(unique_berita)} total unik"
    )

    return relevant_berita


async def collect_berita_batch(
    kode_saham_list: list[str],
    hari_terakhir: int = 7,
    progress_callback = None,
    market_map: dict[str, str] | None = None,
) -> list[dict[str, Any]]:
    """
    Ambil berita untuk banyak saham sekaligus.

    Proses berjalan sequential per saham dengan delay antar request
    untuk menghindari rate limiting.

    Args:
        kode_saham_list: List kode saham (contoh: ["BBCA", "TLKM", "AAPL"])
        hari_terakhir: Hanya ambil berita dalam N hari terakhir
        progress_callback: Callback function to update status/progress
        market_map: Peta {kode -> market} untuk watchlist campuran IDX & US.
                    Kode yang tidak ada di map default ke "IDX".
    """
    market_map = market_map or {}
    logger.info(
        f"📰 Batch berita: {len(kode_saham_list)} saham, "
        f"{hari_terakhir} hari terakhir"
    )

    all_berita: list[dict[str, Any]] = []

    for i, kode in enumerate(kode_saham_list):
        if progress_callback:
            await progress_callback(i + 1, len(kode_saham_list), kode)

        try:
            berita = await collect_berita(
                kode, hari_terakhir, market=market_map.get(kode.strip().upper(), "IDX")
            )
            all_berita.extend(berita)
        except Exception as e:
            logger.error(
                f"❌ Gagal batch berita untuk {kode}: "
                f"{type(e).__name__}: {e}"
            )

        # Delay antar saham (kecuali yang terakhir)
        if i < len(kode_saham_list) - 1:
            await asyncio.sleep(_REQUEST_DELAY_SECONDS)

    # Deduplikasi final (berita tentang satu emiten bisa muncul di query lain)
    unique_berita = _deduplikasi_berita(all_berita)

    logger.info(
        f"📰 Batch selesai: {len(unique_berita)} berita unik "
        f"untuk {len(kode_saham_list)} saham"
    )

    return unique_berita



async def collect_berita_pasar(
    hari_terakhir: int = 3,
    market: str = "IDX",
) -> list[dict[str, Any]]:
    """
    Ambil berita pasar modal umum (tidak spesifik ke satu saham).

    Mengambil dari Google News (query umum). Untuk market IDX juga menambah
    Kontan RSS. Berita ini berguna untuk analisis sentimen pasar keseluruhan.

    Args:
        hari_terakhir: Hanya ambil berita dalam N hari terakhir (default: 3)
        market: Market pasar ("IDX" -> pasar Indonesia, US -> Wall Street)

    Returns:
        List of dict berita pasar umum (kode_saham = None)
    """
    locale = _news_locale(market)
    logger.info(f"🌐 Mengumpulkan berita pasar umum (market={market}, {hari_terakhir} hari)...")

    all_berita: list[dict[str, Any]] = []

    # Sumber 1: Google News — berita pasar umum (sesuai locale)
    for query in _PASAR_QUERIES[locale]:
        try:
            berita = await _collect_from_google_news(None, query, hari_terakhir, market=market)
            all_berita.extend(berita)
        except Exception as e:
            logger.error(f"❌ Gagal Google News pasar '{query}': {e}")

        await asyncio.sleep(_REQUEST_DELAY_SECONDS)

    # Sumber 2: Kontan RSS — berita ekonomi (hanya relevan untuk pasar Indonesia)
    if locale == "ID":
        try:
            berita_kontan = await _collect_from_kontan(hari_terakhir)
            all_berita.extend(berita_kontan)
        except Exception as e:
            logger.error(f"❌ Gagal ambil Kontan RSS: {e}")

    # Deduplikasi
    unique_berita = _deduplikasi_berita(all_berita)

    # Batasi ke top 15 berita terbaru untuk di-scrape agar memiliki pool cadangan (Kasus 2)
    unique_berita = unique_berita[:15]

    relevant_berita: list[dict[str, Any]] = []
    for berita in unique_berita:
        title = berita["judul"]
        if is_news_relevant(title, market=market):
            url = berita["url"]
            # Decode URL di sini sebelum di-scrape agar lebih efisien dan hemat network call
            if "news.google.com" in url:
                url = decode_google_news_url(url)
                berita["url"] = url

            logger.info(f"🌐 Mengambil isi berita pasar: {title[:50]}...")
            content = await fetch_article_content(url)

            # Pastikan isi berita berhasil di-scrape dan cukup panjang (Kasus 2)
            if content and len(content.strip()) >= 200:
                # Verifikasi relevansi secara mendalam menggunakan LLM as a Judge (Kasus 6)
                if await is_news_relevant_llm(title, content, market=market):
                    berita["isi_berita"] = content
                    relevant_berita.append(berita)
                    # Batasi ke maksimal 5 berita berkualitas
                    if len(relevant_berita) >= 5:
                        logger.info("✅ Sudah mencapai batas 5 berita pasar relevan. Berhenti scraping.")
                        break
                else:
                    logger.info(f"🗑️ Membuang berita pasar tidak relevan setelah cek isi (LLM Judge): {title[:50]}")
            else:
                logger.info(f"🗑️ Membuang berita pasar karena gagal scrape isi atau isi terlalu pendek: {title[:50]}")
            
            # Delay kecil agar sopan ke server news
            await asyncio.sleep(1.0)
        else:
            logger.info(f"🗑️ Membuang berita pasar tidak relevan berdasarkan judul: {title[:50]}")

    logger.info(
        f"🌐 Berita pasar: ditemukan {len(relevant_berita)} berita relevan dari {len(unique_berita)} total unik"
    )

    return relevant_berita


# ============================================================
# Live Search — dipanggil REAL-TIME saat ada pertanyaan chatbot masuk
# ============================================================
#
# Beda dengan collect_berita()/collect_berita_pasar() (job terjadwal
# mingguan, hasilnya disimpan ke PostgreSQL lalu di-embed ke ChromaDB),
# fungsi ini dipanggil LANGSUNG dari chatbot_agent.py tiap ada pertanyaan
# yang butuh info ter-update (mis. "harga X hari ini", "berita terbaru Y").
# Hasilnya TIDAK disimpan ke DB — cuma dipakai sebagai konteks tambahan
# buat menjawab pertanyaan itu saja (mirip cara Claude web-search saat chat).
#
# Sengaja dibatasi (max_hasil kecil, tanpa LLM-judge relevansi macam
# collect_berita_pasar) supaya latency-nya tetap masuk akal untuk
# response time chatbot — bukan buat kualitas seakurat job mingguan.

async def live_search_berita(
    query: str,
    kode_saham: str | None = None,
    hari_terakhir: int = 3,
    max_hasil: int = 4,
    market: str = "IDX",
) -> list[dict[str, Any]]:
    """
    Cari & ambil isi berita TERBARU secara real-time buat konteks chatbot.

    Args:
        query: Query pencarian (biasanya dari pertanyaan user, atau
            "{kode_saham} saham berita terbaru" kalau ada saham spesifik).
        kode_saham: Kode saham terkait, kalau ada (buat metadata saja).
        hari_terakhir: Cuma ambil berita dalam N hari terakhir.
        max_hasil: Maksimal berapa artikel yang isinya di-fetch penuh
            (fetch isi lengkap itu paling lambat, jadi dibatasi ketat).
        market: Market saham ("IDX" -> berita Indonesia, US -> berita Inggris).

    Returns:
        List of dict siap dipakai sebagai konteks LLM:
        [{"judul", "url", "sumber", "tanggal_publish", "isi"}, ...]
        List kosong kalau gagal total (dijaga tidak raise exception ke
        caller, supaya chatbot tetap bisa jawab pakai konteks lain kalau
        live search-nya gagal/timeout).
    """
    try:
        entries = await _collect_from_google_news(
            kode_saham=kode_saham,
            query=query,
            hari_terakhir=hari_terakhir,
            market=market,
        )
    except Exception as e:
        logger.warning(f"⚠️ Live search gagal ambil RSS Google News untuk '{query}': {e}")
        return []

    if not entries:
        logger.info(f"ℹ️ Live search: tidak ada hasil untuk '{query}'")
        return []

    # Urutkan yang terbaru dulu, ambil beberapa teratas saja
    entries = sorted(entries, key=lambda e: e["tanggal_publish"], reverse=True)[:max_hasil]

    # Fetch isi semua artikel SECARA PARALEL (bukan satu-satu berurutan) —
    # penting karena ini dipanggil live saat user nunggu jawaban chatbot.
    # fetch_article_content masing-masing timeout 15 detik; kalau dilakukan
    # berurutan, worst-case bisa 15s x max_hasil (bisa 1 menit lebih) —
    # dengan gather, worst-case cuma ~15 detik total (paralel).
    async def _fetch_satu(entry: dict[str, Any]) -> dict[str, Any]:
        try:
            isi = await fetch_article_content(entry["url"])
        except Exception as e:
            logger.warning(f"⚠️ Live search gagal fetch isi artikel '{entry['judul'][:50]}': {e}")
            isi = ""
        if not isi or len(isi) < 100:
            # Isi terlalu pendek/gagal — tetap masukkan judul saja sebagai
            # sinyal minimal, lebih baik daripada tidak ada apa-apa.
            isi = entry["judul"]
        return {
            "judul":           entry["judul"],
            "url":             entry["url"],
            "sumber":          entry["sumber"],
            "tanggal_publish": entry["tanggal_publish"],
            "isi":             isi[:2000],  # batasi panjang biar tidak membengkak konteks LLM
        }

    hasil = await asyncio.gather(*(_fetch_satu(entry) for entry in entries))
    hasil = list(hasil)

    logger.info(f"🌐 Live search: {len(hasil)} artikel diambil untuk '{query}'")
    return hasil