"""
AI Saham Indonesia — Router Analyze & Watchlist

Endpoint untuk alur "search saham di luar 20 IDX (NASDAQ/ETF) -> klik
Analyze -> AI scoring & scrape fundamental HANYA untuk 1 saham itu",
tanpa membebani job terjadwal yang berjalan untuk seluruh watchlist.

Lihat workers.py (get_or_create_saham, set_watchlist_status,
analyze_single_saham, scoring_lock) untuk detail kenapa desain ini aman:
- Saham hasil "Analyze" disimpan dengan is_watchlist=False (FK terpenuhi,
  tapi TIDAK ikut tersapu scheduler).
- scoring_lock dipakai bersama dengan job scoring mingguan terjadwal,
  supaya request ke Ollama (LLM lokal) tidak pernah jalan bersamaan.
"""

from fastapi import APIRouter, Depends, HTTPException
from loguru import logger
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from backend.db.postgres import get_db_session, Saham, SimbolReferensi
from backend.utils.ticker import normalize_market
from backend.workers import (
    analyze_single_saham,
    get_or_create_saham,
    set_watchlist_status,
    scoring_lock,
)

router = APIRouter(
    tags=["Analyze & Watchlist"],
)


@router.post("/saham/{kode}/analyze")
async def analyze_saham(kode: str, db: AsyncSession = Depends(get_db_session)):
    """
    Jalankan analisis on-demand (fundamental + AI scoring) untuk SATU saham,
    biasanya hasil dari search (mis. user ketik "SNPS" lalu klik Analyze).

    Saham TIDAK otomatis masuk watchlist — ini cuma snapshot sekali jalan.
    Kalau saham sudah ada di watchlist, endpoint ini berfungsi sebagai
    refresh manual untuk saham tersebut saja.
    """
    kode_clean = kode.strip().upper()

    # Cari metadata dari universe referensi dulu (kalau ada), supaya nama/sektor
    # terisi otomatis daripada cuma jadi "Unknown"
    res_ref = await db.execute(select(SimbolReferensi).where(SimbolReferensi.kode == kode_clean))
    ref = res_ref.scalar_one_or_none()

    market = ref.market if ref else "IDX"
    nama = ref.nama if ref else None

    try:
        hasil = await analyze_single_saham(
            kode_clean,
            market=market,
            nama_perusahaan=nama,
        )
        return hasil
    except Exception as e:
        logger.error(f"❌ Gagal analyze on-demand untuk {kode_clean}: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Gagal menjalankan analisis untuk {kode_clean}: {str(e)}"
        )


@router.post("/saham/{kode}/watchlist")
async def tambah_watchlist(kode: str, db: AsyncSession = Depends(get_db_session)):
    """
    Tambahkan saham ke watchlist aktif (is_watchlist=True), supaya mulai ikut
    job terjadwal (scoring mingguan, scrape fundamental harian, update harga
    30 menit, pre-warming candle 15 menit).

    Kalau saham belum pernah dianalisis sama sekali (belum ada baris di
    tabel `Saham`), endpoint ini akan langsung menjalankan analisis on-demand
    sekali supaya user dapat data instan, bukan menunggu job terjadwal berikutnya.
    """
    kode_clean = kode.strip().upper()

    res = await db.execute(select(Saham).where(Saham.kode == kode_clean))
    existing = res.scalar_one_or_none()

    if existing:
        updated = await set_watchlist_status(kode_clean, True)
        return {"kode": kode_clean, "is_watchlist": True, "market": updated.market}

    # Belum pernah ada -> cari metadata di simbol_referensi, lalu jalankan
    # analisis on-demand sekali (otomatis insert dengan is_watchlist=False dulu)
    res_ref = await db.execute(select(SimbolReferensi).where(SimbolReferensi.kode == kode_clean))
    ref = res_ref.scalar_one_or_none()
    market = ref.market if ref else "IDX"
    nama = ref.nama if ref else None

    try:
        await analyze_single_saham(kode_clean, market=market, nama_perusahaan=nama)
    except Exception as e:
        logger.warning(f"⚠️ Analisis awal {kode_clean} gagal saat ditambah ke watchlist: {e}")

    updated = await set_watchlist_status(kode_clean, True)
    if not updated:
        raise HTTPException(status_code=404, detail=f"Gagal menambahkan {kode_clean} ke watchlist.")
    return {"kode": kode_clean, "is_watchlist": True, "market": updated.market}


@router.delete("/saham/{kode}/watchlist")
async def hapus_watchlist(kode: str):
    """
    Keluarkan saham dari watchlist aktif (is_watchlist=False). Saham berhenti
    ikut job terjadwal, tapi histori fundamental/scoring/berita TIDAK dihapus.
    """
    kode_clean = kode.strip().upper()
    updated = await set_watchlist_status(kode_clean, False)
    if not updated:
        raise HTTPException(status_code=404, detail=f"Saham '{kode_clean}' tidak ditemukan.")
    return {"kode": kode_clean, "is_watchlist": False}
