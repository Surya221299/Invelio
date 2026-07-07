"""
AI Saham Indonesia — Router Data Saham & Makro

Endpoint API untuk mengambil metadata saham, data fundamental harian,
dan indikator makroekonomi terupdate dari database.
"""

import asyncio
from collections import defaultdict
from datetime import date
from typing import Any
from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect
from loguru import logger
import pandas as pd
import pytz
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased
import yfinance as yf

from backend.db.postgres import get_db_session, Saham, Fundamental, Makro, SimbolReferensi
from backend.utils.ticker import get_yf_symbol, normalize_market

router = APIRouter(
    tags=["Data Keuangan & Makro"],
)


@router.get("/saham/list")
@router.get("/data/saham/list")
async def get_saham_list(db: AsyncSession = Depends(get_db_session)):
    """
    Mengambil seluruh kode emiten WATCHLIST (is_watchlist=True) beserta nama
    perusahaan dan sektornya. Saham hasil "Analyze" on-demand yang belum
    ditambahkan ke watchlist sengaja TIDAK muncul di sini — pakai
    `/saham/search` untuk menemukan saham di luar watchlist.
    """
    try:
        stmt = select(Saham).where(Saham.is_watchlist == True).order_by(Saham.kode)
        result = await db.execute(stmt)
        saham_list = result.scalars().all()
        
        return [
            {
                "kode": s.kode,
                "nama_perusahaan": s.nama_perusahaan,
                "sektor": s.sektor,
                "sub_sektor": s.sub_sektor,
                "market": s.market,
            }
            for s in saham_list
        ]
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Gagal mengambil daftar saham: {str(e)}"
        )


@router.get("/saham/search")
@router.get("/data/saham/search")
async def search_saham(
    q: str,
    limit: int = 20,
    db: AsyncSession = Depends(get_db_session)
):
    """
    Search ringan di universe `simbol_referensi` (ribuan saham NASDAQ/ETF + IDX).

    Tabel ini TERPISAH dari watchlist (`Saham`) dan TIDAK pernah disentuh
    scheduler — jadi query ILIKE di sini tetap cepat & murah berapa pun
    banyaknya simbol yang sudah diisi. Setiap hasil ditandai `is_watchlist`
    supaya frontend tahu apakah perlu tombol "Analyze" (belum pernah
    dipantau) atau cukup tampilkan data existing.
    """
    q_clean = q.strip()
    if not q_clean:
        return []
    if limit < 1:
        limit = 1
    if limit > 50:
        limit = 50

    try:
        pattern = f"%{q_clean}%"
        stmt = (
            select(SimbolReferensi)
            .where(
                (SimbolReferensi.kode.ilike(pattern)) | (SimbolReferensi.nama.ilike(pattern))
            )
            # Prioritaskan exact/prefix match kode di atas, baru match nama
            .order_by(
                (SimbolReferensi.kode == q_clean.upper()).desc(),
                SimbolReferensi.kode.startswith(q_clean.upper()).desc(),
                SimbolReferensi.kode,
            )
            .limit(limit)
        )
        result = await db.execute(stmt)
        simbol_list = result.scalars().all()

        if not simbol_list:
            return []

        # Cek mana saja yang sudah jadi watchlist aktif (1 query, bukan N+1)
        kode_list = [s.kode for s in simbol_list]
        stmt_wl = select(Saham.kode).where(
            Saham.kode.in_(kode_list), Saham.is_watchlist == True
        )
        res_wl = await db.execute(stmt_wl)
        watchlist_set = set(res_wl.scalars().all())

        return [
            {
                "kode": s.kode,
                "nama": s.nama,
                "market": s.market,
                "tipe": s.tipe,
                "exchange": s.exchange,
                "is_watchlist": s.kode in watchlist_set,
            }
            for s in simbol_list
        ]
    except Exception as e:
        logger.error(f"Gagal search simbol untuk query '{q_clean}': {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Gagal melakukan pencarian simbol: {str(e)}"
        )


@router.get("/saham/{kode}/fundamental")
@router.get("/data/saham/{kode}/fundamental")
async def get_fundamental_saham(
    kode: str,
    db: AsyncSession = Depends(get_db_session)
):
    """
    Mengambil data snapshot fundamental keuangan terbaru untuk saham tertentu.
    """
    kode_upper = kode.strip().upper()
    try:
        # Cek saham
        stmt_saham = select(Saham).where(Saham.kode == kode_upper)
        res_saham = await db.execute(stmt_saham)
        saham_obj = res_saham.scalar_one_or_none()

        if not saham_obj:
            raise HTTPException(
                status_code=404,
                detail=f"Saham dengan kode '{kode_upper}' tidak terdaftar."
            )

        # Query fundamental terbaru
        stmt_fund = (
            select(Fundamental)
            .where(Fundamental.kode_saham == kode_upper)
            .order_by(Fundamental.tanggal.desc())
            .limit(1)
        )
        res_fund = await db.execute(stmt_fund)
        fund = res_fund.scalar_one_or_none()

        if not fund:
            raise HTTPException(
                status_code=404,
                detail=f"Saham '{kode_upper}' belum memiliki data fundamental harian."
            )

        return {
            "kode_saham": fund.kode_saham,
            "nama_perusahaan": saham_obj.nama_perusahaan,
            "tanggal_update": fund.tanggal.isoformat(),
            "harga_terakhir": fund.harga_terakhir,
            "volume": fund.volume,
            "roe": fund.roe,
            "eps": fund.eps,
            "pbv": fund.pbv,
            "der": fund.der,
            "market_cap": fund.market_cap,
            "pe_ratio": fund.pe_ratio,
            "dividend_yield": fund.dividend_yield,
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Gagal mengambil fundamental saham {kode_upper}: {str(e)}"
        )


@router.get("/makro/terbaru")
@router.get("/data/makro/terbaru")
async def get_makro_terbaru(db: AsyncSession = Depends(get_db_session)):
    """
    Mengambil snapshot kondisi indikator makroekonomi terkini (BI rate, inflasi, kurs, IHSG, asing net buy).
    """
    indikator_list = ["bi_rate", "kurs_usd_idr", "ihsg", "inflasi_yoy", "asing_net_buy"]
    makro_data = {}

    try:
        for ind in indikator_list:
            stmt = (
                select(Makro)
                .where(Makro.indikator == ind)
                .order_by(Makro.tanggal.desc())
                .limit(1)
            )
            result = await db.execute(stmt)
            obj = result.scalar_one_or_none()

            if obj:
                makro_data[ind] = {
                    "nilai": obj.nilai,
                    "satuan": obj.satuan,
                    "tanggal": obj.tanggal.isoformat(),
                    "sumber": obj.sumber
                }
            else:
                makro_data[ind] = None

        return {
            "tanggal_fetch": date.today().isoformat(),
            "indikator": makro_data
        }
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Gagal mengambil data makroekonomi terbaru: {str(e)}"
        )


import time

# In-memory caches for yfinance fetches
_yf_single_cache = {}
YF_SINGLE_CACHE_TTL = 180  # 3 minutes

_yf_candles_cache = {}
YF_CANDLES_CACHE_TTL = 300  # 5 minutes


def fetch_yf_single(symbol: str, market: str = "IDX") -> tuple[float, float, float]:
    """
    Mengambil data harga penutupan terakhir dan perubahan harga dari yfinance (synchronous)
    dengan dukungan in-memory caching untuk meningkatkan performa response.
    """
    symbol_upper = symbol.strip().upper()
    market_clean = normalize_market(market)
    cache_key = (symbol_upper, market_clean)
    now = time.time()
    
    # Cek cache (cache key ikut market supaya kode yang sama di market berbeda tidak bentrok)
    if cache_key in _yf_single_cache:
        cached_time, cached_data = _yf_single_cache[cache_key]
        if now - cached_time < YF_SINGLE_CACHE_TTL:
            return cached_data
            
    try:
        ticker = yf.Ticker(get_yf_symbol(symbol_upper, market_clean))
        hist = ticker.history(period="2d")
        if not hist.empty:
            if len(hist) >= 2:
                price = float(hist['Close'].iloc[-1])
                prev_close = float(hist['Close'].iloc[-2])
                change = price - prev_close
                pct_change = (change / prev_close) * 100.0 if prev_close > 0 else 0.0
                result = (round(price, 2), round(change, 2), round(pct_change, 2))
                _yf_single_cache[cache_key] = (now, result)
                return result
            else:
                price = float(hist['Close'].iloc[-1])
                result = (round(price, 2), 0.0, 0.0)
                _yf_single_cache[cache_key] = (now, result)
                return result
    except Exception as e:
        logger.error(f"Gagal mengambil fallback yfinance untuk {symbol_upper} ({market_clean}): {e}")
        
    return 0.0, 0.0, 0.0


# ============================================================
# WebSocket: Streaming Harga Saham (near-real-time)
# ============================================================
#
# CATATAN PENTING soal sumber data (yfinance):
#   - yfinance BUKAN feed tick-by-tick per detik. Granularitas tercepatnya
#     adalah candle 1 menit, dan untuk banyak bursa (termasuk IDX) datanya
#     delay ~15-20 menit dari harga pasar sebenarnya.
#   - Polling yfinance tiap detik BERISIKO kena rate-limit / block dari Yahoo,
#     apalagi kalau banyak client subscribe ke banyak simbol sekaligus.
#   - Karena itu manager di bawah ini melakukan SATU polling loop per simbol
#     (dibagi ke semua subscriber websocket-nya, bukan 1 polling per client),
#     dengan jeda POLL_INTERVAL_SECONDS yang aman. Client tetap merasakan
#     "streaming" karena push terjadi otomatis tanpa perlu refresh manual,
#     walau angka barunya baru berubah secepat data sumbernya sendiri update.


POLL_INTERVAL_SECONDS = 5.0


class PriceStreamManager:
    """
    Mengelola subscriber WebSocket per simbol saham dan satu polling loop
    yang di-share untuk semua subscriber simbol yang sama (hemat request
    ke yfinance dibanding polling per-koneksi).
    """

    def __init__(self):
        self.subscribers: dict[str, set[WebSocket]] = {}
        self._loop_tasks: dict[str, asyncio.Task] = {}

    async def subscribe(self, symbol: str, market: str, ws: WebSocket):
        self.subscribers.setdefault(symbol, set()).add(ws)
        if symbol not in self._loop_tasks or self._loop_tasks[symbol].done():
            self._loop_tasks[symbol] = asyncio.create_task(self._poll_loop(symbol, market))

    def unsubscribe(self, symbol: str, ws: WebSocket):
        subs = self.subscribers.get(symbol)
        if subs:
            subs.discard(ws)
            if not subs:
                # Tidak ada subscriber lagi -> hentikan polling loop simbol ini
                task = self._loop_tasks.pop(symbol, None)
                if task:
                    task.cancel()

    async def _poll_loop(self, symbol: str, market: str):
        loop = asyncio.get_running_loop()
        try:
            while self.subscribers.get(symbol):
                try:
                    price, change, pct_change = await loop.run_in_executor(
                        None, fetch_yf_single, symbol, market
                    )
                    payload = {
                        "symbol": symbol,
                        "price": price,
                        "change": change,
                        "pct_change": pct_change,
                        "ts": time.time(),
                    }
                    dead = []
                    for client in list(self.subscribers.get(symbol, set())):
                        try:
                            await client.send_json(payload)
                        except Exception:
                            dead.append(client)
                    for client in dead:
                        self.unsubscribe(symbol, client)
                except Exception as e:
                    logger.error(f"❌ Gagal polling harga streaming untuk {symbol}: {e}")

                await asyncio.sleep(POLL_INTERVAL_SECONDS)
        except asyncio.CancelledError:
            pass


stream_manager = PriceStreamManager()


@router.websocket("/ws/stocks/{symbol}")
async def stock_price_ws(websocket: WebSocket, symbol: str, market: str = "IDX"):
    """
    Streaming harga saham per simbol via WebSocket. Frontend (SwiftUI) tinggal
    connect ke ws(s)://<host>/ws/stocks/{symbol} dan akan menerima JSON payload
    `{symbol, price, change, pct_change, ts}` setiap ~5 detik selama masih
    ada perubahan/refresh dari sumber data.
    """
    await websocket.accept()
    symbol_upper = symbol.strip().upper()
    market_clean = normalize_market(market)
    await stream_manager.subscribe(symbol_upper, market_clean, websocket)
    try:
        while True:
            # Tidak butuh data masuk dari client, ini cuma menjaga koneksi
            # tetap terbuka & mendeteksi disconnect.
            await websocket.receive_text()
    except WebSocketDisconnect:
        pass
    finally:
        stream_manager.unsubscribe(symbol_upper, websocket)


async def get_single_stock_price_stats(symbol: str, db: AsyncSession, market: str = "IDX") -> tuple[float, float, float]:
    """
    Mengambil data harga penutupan terakhir, nominal perubahan, dan persentase perubahan untuk satu saham.
    """
    symbol_upper = symbol.strip().upper()
    try:
        stmt_fund = (
            select(Fundamental)
            .where(Fundamental.kode_saham == symbol_upper)
            .order_by(Fundamental.tanggal.desc())
            .limit(2)
        )
        res_fund = await db.execute(stmt_fund)
        funds = res_fund.scalars().all()
        if len(funds) >= 2 and funds[0].harga_terakhir is not None and funds[1].harga_terakhir is not None:
            price = float(funds[0].harga_terakhir)
            prev_price = float(funds[1].harga_terakhir)
            change = price - prev_price
            pct_change = (change / prev_price) * 100.0 if prev_price > 0 else 0.0
            return round(price, 2), round(change, 2), round(pct_change, 2)
    except Exception as e:
        logger.warning(f"Gagal query DB fundamental untuk {symbol_upper}: {e}")
        
    # Fallback ke yfinance
    loop = asyncio.get_running_loop()
    return await loop.run_in_executor(None, fetch_yf_single, symbol_upper, market)


def fetch_candles_yf(symbol: str, range_val: str, market: str = "IDX") -> list[dict]:
    """
    Mengambil data chart candles menggunakan yfinance (synchronous)
    dengan dukungan in-memory caching untuk menghindari network fetch lambat berulang kali.
    """
    symbol_upper = symbol.strip().upper()
    range_upper = range_val.strip().upper()
    market_clean = normalize_market(market)
    cache_key = (symbol_upper, range_upper, market_clean)
    now = time.time()
    
    # Cek cache
    if cache_key in _yf_candles_cache:
        cached_time, cached_data = _yf_candles_cache[cache_key]
        if now - cached_time < YF_CANDLES_CACHE_TTL:
            return cached_data
            
    ticker_symbol = get_yf_symbol(symbol_upper, market_clean)
    
    # Map range to period and interval
    range_map = {
        "1D": ("1d", "5m"),
        "1W": ("5d", "15m"),
        "1M": ("1mo", "1d"),
        "3M": ("3mo", "1d"),
        "YTD": ("ytd", "1d"),
        "1Y": ("1y", "1d"),
        "5Y": ("5y", "1wk"),
    }
    
    period, interval = range_map.get(range_upper, ("1d", "5m"))
    try:
        ticker = yf.Ticker(ticker_symbol)
        df = ticker.history(period=period, interval=interval)
        
        candles = []
        if df.empty:
            return candles
            
        for ts, row in df.iterrows():
            if ts.tzinfo is None:
                jkt_tz = pytz.timezone("Asia/Jakarta")
                ts_aware = jkt_tz.localize(ts)
            else:
                jkt_tz = pytz.timezone("Asia/Jakarta")
                ts_aware = ts.astimezone(jkt_tz)
                
            candles.append({
                "ts": ts_aware.isoformat(),
                "open": float(row["Open"]) if not pd.isna(row["Open"]) else None,
                "high": float(row["High"]) if not pd.isna(row["High"]) else None,
                "low": float(row["Low"]) if not pd.isna(row["Low"]) else None,
                "close": float(row["Close"]),
                "volume": int(row["Volume"]) if not pd.isna(row["Volume"]) else 0
            })
            
        _yf_candles_cache[cache_key] = (now, candles)
        return candles
    except Exception as e:
        logger.error(f"Gagal mengambil candles yfinance untuk {ticker_symbol}: {e}")
        return []



# ============================================================
# Jadwal Rilis Laporan Keuangan (Earnings) & Rally Streak
# ============================================================

_yf_earnings_cache = {}
YF_EARNINGS_CACHE_TTL = 6 * 3600  # 6 jam — jadwal earnings jarang berubah dalam sehari


def fetch_earnings_info(symbol: str, market: str = "IDX") -> dict:
    """
    Mengambil perkiraan jadwal rilis laporan keuangan (earnings) berikutnya
    beserta estimasi EPS/revenue dari yfinance (synchronous), dengan caching.

    CATATAN: tanggal & estimasi dari yfinance sifatnya PERKIRAAN (bersumber
    dari konsensus analis), bisa berubah/meleset dari tanggal rilis aktual —
    terutama untuk emiten IDX yang cakupan datanya lebih tipis dibanding
    saham AS. Selalu tampilkan sebagai "perkiraan", bukan kepastian.
    """
    symbol_upper = symbol.strip().upper()
    market_clean = normalize_market(market)
    cache_key = (symbol_upper, market_clean)
    now = time.time()

    if cache_key in _yf_earnings_cache:
        cached_time, cached_data = _yf_earnings_cache[cache_key]
        if now - cached_time < YF_EARNINGS_CACHE_TTL:
            return cached_data

    result: dict[str, Any] = {
        "kode_saham": symbol_upper,
        "next_earnings_date": None,
        "eps_estimate": None,
        "eps_estimate_low": None,
        "eps_estimate_high": None,
        "revenue_estimate": None,
        "is_estimate": True,
        "sumber": "yfinance",
    }

    try:
        ticker = yf.Ticker(get_yf_symbol(symbol_upper, market_clean))

        # 1. Tanggal earnings terdekat + estimasi EPS dari get_earnings_dates()
        try:
            edf = ticker.get_earnings_dates(limit=8)
            if edf is not None and not edf.empty:
                now_ts = pd.Timestamp.now(tz=edf.index.tz) if edf.index.tz is not None else pd.Timestamp.now()
                upcoming = edf[edf.index >= now_ts].sort_index()
                if not upcoming.empty:
                    earnings_date = upcoming.index[0]
                    row = upcoming.iloc[0]
                    result["next_earnings_date"] = earnings_date.isoformat()
                    eps_est = row.get("EPS Estimate")
                    if pd.notna(eps_est):
                        result["eps_estimate"] = float(eps_est)
        except Exception as e:
            logger.warning(f"Tidak bisa ambil get_earnings_dates untuk {symbol_upper}: {e}")

        # 2. Fallback / pelengkap dari ticker.calendar (revenue estimate, dsb.)
        #    Struktur calendar berubah-ubah antar versi yfinance (dict / DataFrame),
        #    jadi ditangani secara defensif.
        try:
            cal = ticker.calendar
            if isinstance(cal, dict):
                if not result["next_earnings_date"]:
                    dates = cal.get("Earnings Date")
                    if dates:
                        d = dates[0] if isinstance(dates, list) else dates
                        result["next_earnings_date"] = str(d)
                rev_avg = cal.get("Revenue Average")
                if rev_avg:
                    result["revenue_estimate"] = float(rev_avg)
                eps_low = cal.get("Earnings Low")
                eps_high = cal.get("Earnings High")
                if eps_low is not None:
                    result["eps_estimate_low"] = float(eps_low)
                if eps_high is not None:
                    result["eps_estimate_high"] = float(eps_high)
        except Exception as e:
            logger.warning(f"Tidak bisa ambil ticker.calendar untuk {symbol_upper}: {e}")

    except Exception as e:
        logger.error(f"Gagal mengambil info earnings untuk {symbol_upper}: {e}")

    _yf_earnings_cache[cache_key] = (now, result)
    return result


def compute_rally_streak(candles: list[dict]) -> dict:
    """
    Menghitung "rally streak": jumlah candle harian berturut-turut (dari yang
    paling baru mundur ke belakang) dengan close > close hari sebelumnya
    ("hijau"). `candles` diasumsikan terurut kronologis (lama -> baru),
    sesuai output fetch_candles_yf().
    """
    streak = 0
    for i in range(len(candles) - 1, 0, -1):
        curr = candles[i].get("close")
        prev = candles[i - 1].get("close")
        if curr is not None and prev is not None and curr > prev:
            streak += 1
        else:
            break
    return {
        "streak_hari": streak,
        "is_rally_streak": streak >= 3,  # threshold default: 3 hari hijau berturut-turut
    }


@router.get("/saham/{kode}/earnings")
@router.get("/data/saham/{kode}/earnings")
async def get_earnings_schedule(
    kode: str,
    db: AsyncSession = Depends(get_db_session)
):
    """
    Mengambil perkiraan jadwal rilis laporan keuangan (earnings) berikutnya
    untuk satu emiten, beserta estimasi EPS/revenue (kalau tersedia).
    """
    kode_upper = kode.strip().upper()
    stmt_saham = select(Saham).where(Saham.kode == kode_upper)
    res_saham = await db.execute(stmt_saham)
    saham_obj = res_saham.scalar_one_or_none()
    if not saham_obj:
        raise HTTPException(
            status_code=404,
            detail=f"Saham dengan kode '{kode_upper}' tidak terdaftar."
        )

    loop = asyncio.get_running_loop()
    info = await loop.run_in_executor(None, fetch_earnings_info, kode_upper, saham_obj.market)
    return info


@router.get("/saham/{kode}/rally-streak")
@router.get("/data/saham/{kode}/rally-streak")
async def get_rally_streak(
    kode: str,
    db: AsyncSession = Depends(get_db_session)
):
    """
    Menghitung rally streak (hari hijau berturut-turut) berdasarkan candle
    harian ~1 bulan terakhir.
    """
    kode_upper = kode.strip().upper()
    stmt_saham = select(Saham).where(Saham.kode == kode_upper)
    res_saham = await db.execute(stmt_saham)
    saham_obj = res_saham.scalar_one_or_none()
    if not saham_obj:
        raise HTTPException(
            status_code=404,
            detail=f"Saham dengan kode '{kode_upper}' tidak terdaftar."
        )

    loop = asyncio.get_running_loop()
    candles = await loop.run_in_executor(None, fetch_candles_yf, kode_upper, "1M", saham_obj.market)
    result = compute_rally_streak(candles)
    result["kode_saham"] = kode_upper
    return result


@router.get("/stocks")
@router.get("/data/stocks")
async def get_stocks_prices(db: AsyncSession = Depends(get_db_session)):
    """
    Mengambil daftar seluruh saham LQ45 beserta data harga penutupan terakhir,
    nominal perubahan harga, dan persentase perubahan harga.
    Mendahulukan data dari database 'fundamental' (2 tanggal terbaru),
    dan menggunakan yfinance sebagai fallback.
    """
    try:
        # 1. Ambil saham WATCHLIST saja (ad-hoc hasil Analyze tidak ikut tampil di sini)
        stmt_saham = select(Saham).where(Saham.is_watchlist == True).order_by(Saham.kode)
        res_saham = await db.execute(stmt_saham)
        saham_list = res_saham.scalars().all()
        
        # 2. Ambil data fundamental terbaru (maks 2 per saham)
        subq = (
            select(
                Fundamental,
                func.row_number().over(
                    partition_by=Fundamental.kode_saham,
                    order_by=Fundamental.tanggal.desc()
                ).label("rn")
            )
        ).subquery()
        
        fund_alias = aliased(Fundamental, subq)
        stmt_funds = select(fund_alias).where(subq.c.rn <= 2)
        res_funds = await db.execute(stmt_funds)
        funds_list = res_funds.scalars().all()
        
        db_funds = defaultdict(list)
        for f in funds_list:
            db_funds[f.kode_saham].append(f)
            
        # 3. Proses masing-masing saham
        results = []
        fallback_symbols = []
        fallback_markets = []
        fallback_indexes = []
        
        for idx, s in enumerate(saham_list):
            stock_funds = db_funds[s.kode]
            stock_funds.sort(key=lambda x: x.tanggal, reverse=True)
            
            price, change, pct_change = None, None, None
            if len(stock_funds) >= 2 and stock_funds[0].harga_terakhir is not None and stock_funds[1].harga_terakhir is not None:
                price = float(stock_funds[0].harga_terakhir)
                prev_price = float(stock_funds[1].harga_terakhir)
                change = price - prev_price
                pct_change = (change / prev_price) * 100.0 if prev_price > 0 else 0.0
                price = round(price, 2)
                change = round(change, 2)
                pct_change = round(pct_change, 2)
                
            if price is None:
                fallback_symbols.append(s.kode)
                fallback_markets.append(s.market)
                fallback_indexes.append(idx)
                
            results.append({
                "symbol": s.kode,
                "name": s.nama_perusahaan,
                "market": s.market,
                "price": price,
                "change": change,
                "pct_change": pct_change
            })
            
        # 4. Ambil fallback data secara paralel jika ada
        if fallback_symbols:
            logger.info(f"Mengambil fallback yfinance untuk {len(fallback_symbols)} saham: {fallback_symbols}")
            loop = asyncio.get_running_loop()
            
            tasks = [
                loop.run_in_executor(None, fetch_yf_single, sym, mkt)
                for sym, mkt in zip(fallback_symbols, fallback_markets)
            ]
            yf_results = await asyncio.gather(*tasks)
            
            for yf_idx, res in enumerate(yf_results):
                orig_idx = fallback_indexes[yf_idx]
                price, change, pct_change = res
                results[orig_idx]["price"] = price
                results[orig_idx]["change"] = change
                results[orig_idx]["pct_change"] = pct_change
                
        return results
    except Exception as e:
        logger.error(f"Gagal mengambil daftar stocks: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Gagal mengambil daftar saham beserta harga: {str(e)}"
        )


@router.get("/stocks/{symbol}/candles")
@router.get("/data/stocks/{symbol}/candles")
async def get_stock_candles(
    symbol: str,
    range: str = "1D",
    db: AsyncSession = Depends(get_db_session)
):
    """
    Mengambil data candlestick/history chart untuk saham tertentu.
    Parameter range: 1D, 1W, 1M, 3M, YTD, 1Y, 5Y.
    """
    symbol_upper = symbol.strip().upper()
    range_upper = range.strip().upper()
    
    valid_ranges = {"1D", "1W", "1M", "3M", "YTD", "1Y", "5Y"}
    if range_upper not in valid_ranges:
        raise HTTPException(
            status_code=400,
            detail=f"Range tidak valid. Pilih salah satu dari: {list(valid_ranges)}"
        )
        
    try:
        stmt_saham = select(Saham).where(Saham.kode == symbol_upper)
        res_saham = await db.execute(stmt_saham)
        saham_obj = res_saham.scalar_one_or_none()
        if not saham_obj:
            raise HTTPException(
                status_code=404,
                detail=f"Saham dengan kode '{symbol_upper}' tidak terdaftar."
            )
            
        loop = asyncio.get_running_loop()
        candles = await loop.run_in_executor(None, fetch_candles_yf, symbol_upper, range_upper, saham_obj.market)
        return candles
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Gagal mengambil candles untuk {symbol_upper}: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Gagal mengambil riwayat harga saham {symbol_upper}: {str(e)}"
        )


@router.get("/stocks/{symbol}")
@router.get("/data/stocks/{symbol}")
async def get_single_stock_price(
    symbol: str,
    db: AsyncSession = Depends(get_db_session)
):
    """
    Mengambil data harga penutupan terakhir, nominal perubahan, dan persentase perubahan
    untuk satu saham tertentu.
    """
    symbol_upper = symbol.strip().upper()
    try:
        # Cek apakah saham terdaftar
        stmt_saham = select(Saham).where(Saham.kode == symbol_upper)
        res_saham = await db.execute(stmt_saham)
        saham_obj = res_saham.scalar_one_or_none()
        if not saham_obj:
            raise HTTPException(
                status_code=404,
                detail=f"Saham dengan kode '{symbol_upper}' tidak terdaftar."
            )
            
        price, change, pct_change = await get_single_stock_price_stats(symbol_upper, db, saham_obj.market)
        return {
            "symbol": symbol_upper,
            "name": saham_obj.nama_perusahaan,
            "market": saham_obj.market,
            "price": price,
            "change": change,
            "pct_change": pct_change
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Gagal mengambil harga stock {symbol_upper}: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Gagal mengambil detail harga saham {symbol_upper}: {str(e)}"
        )
