import asyncio
from backend.db.postgres import async_session, Saham, SimbolReferensi
from sqlalchemy import select

async def run():
    async with async_session() as session:
        res1 = await session.execute(select(Saham).where(Saham.kode == 'SPCX'))
        saham = res1.scalar_one_or_none()
        print('Saham:', saham.market if saham else 'None')
        
        res2 = await session.execute(select(SimbolReferensi).where(SimbolReferensi.kode == 'SPCX'))
        ref = res2.scalar_one_or_none()
        print('Ref:', ref.market if ref else 'None')

asyncio.run(run())
