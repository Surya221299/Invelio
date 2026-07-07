"""
AI Saham Indonesia — Seeder untuk SimbolReferensi (universe search NASDAQ + ETF)

Mengisi tabel `simbol_referensi` dengan ribuan simbol NASDAQ + ETF dari
NASDAQ Trader Symbol Directory, supaya search bar bisa menemukan saham di
luar 20 watchlist IDX (mis. user ketik "SNPS" lalu klik Analyze).

PENTING: script ini TIDAK menyentuh tabel `Saham` (watchlist) sama sekali —
murni mengisi universe pencarian yang ringan. Aman dijalankan ulang kapan
saja (upsert, bukan insert blind) dan TIDAK menambah beban job terjadwal.

Butuh akses internet ke ftp.nasdaqtrader.com. Jalankan manual sesekali
(mis. mingguan via cron terpisah) untuk menyegarkan daftar simbol:

    python -m backend.scripts.seed_simbol_referensi
"""

import asyncio
import sys

from loguru import logger
from sqlalchemy.dialects.postgresql import insert as pg_insert

from backend.db.init_db import init_database
from backend.db.postgres import async_session, Saham, SimbolReferensi
from backend.data.collectors.nasdaq_collector import collect_nasdaq_universe


async def run_seeder() -> None:
    logger.info("=" * 60)
    logger.info("🌱 SEEDING SIMBOL_REFERENSI (universe search NASDAQ + ETF)")
    logger.info("=" * 60)

    try:
        await init_database()
    except Exception as e:
        logger.critical(f"❌ Inisialisasi DB gagal: {e}. Pastikan Docker Compose sudah berjalan.")
        sys.exit(1)

    logger.info("Step 1: Mengambil daftar simbol dari NASDAQ Trader Symbol Directory...")
    try:
        universe = await collect_nasdaq_universe()
    except Exception as e:
        logger.critical(f"❌ Gagal mengambil universe simbol: {e}")
        sys.exit(1)

    if not universe:
        logger.warning("⚠️ Universe simbol kosong — cek koneksi internet ke ftp.nasdaqtrader.com.")
        return

    logger.info(f"Step 2: Upsert {len(universe)} simbol ke tabel simbol_referensi...")
    batch_size = 500
    upserted = 0
    async with async_session() as session:
        for i in range(0, len(universe), batch_size):
            batch = universe[i : i + batch_size]
            for item in batch:
                stmt = pg_insert(SimbolReferensi).values(
                    kode=item["kode"],
                    nama=item["nama"],
                    market=item["market"],
                    tipe=item["tipe"],
                    exchange=item["exchange"],
                )
                stmt = stmt.on_conflict_do_update(
                    index_elements=["kode"],
                    set_={
                        "nama": item["nama"],
                        "market": item["market"],
                        "tipe": item["tipe"],
                        "exchange": item["exchange"],
                    },
                )
                await session.execute(stmt)
                upserted += 1
            await session.commit()
            logger.info(f"   ...{min(i + batch_size, len(universe))}/{len(universe)} simbol diproses")

    logger.info(f"✅ {upserted} simbol berhasil di-upsert ke simbol_referensi.")

    # Opsional: pastikan 20 saham IDX watchlist existing juga muncul di hasil
    # search (supaya search bar konsisten untuk IDX maupun NASDAQ/ETF).
    logger.info("Step 3: Menyinkronkan watchlist IDX existing ke simbol_referensi...")
    async with async_session() as session:
        from sqlalchemy import select
        res = await session.execute(select(Saham))
        for s in res.scalars().all():
            stmt = pg_insert(SimbolReferensi).values(
                kode=s.kode,
                nama=s.nama_perusahaan,
                market=s.market,
                tipe="STOCK",
                exchange="IDX",
            )
            stmt = stmt.on_conflict_do_nothing(index_elements=["kode"])
            await session.execute(stmt)
        await session.commit()

    logger.info("=" * 60)
    logger.info("🎉 SEEDING SIMBOL_REFERENSI SELESAI.")
    logger.info("=" * 60)


if __name__ == "__main__":
    asyncio.run(run_seeder())
