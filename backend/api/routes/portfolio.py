"""
AI Saham Indonesia — Router Portfolio Health

Endpoint stateless untuk menganalisis portofolio yang dikirim aplikasi iOS.
Backend tidak menyimpan holdings — holdings masuk lewat request body, hasil
analisis (kesehatan, alokasi sektor, kontributor, narasi harian) keluar lewat
response. Lihat backend/agents/portfolio_agent.py.
"""

from typing import Optional
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field
from loguru import logger

from backend.agents.portfolio_agent import analisis_portofolio

router = APIRouter(
    prefix="/portfolio",
    tags=["Portfolio"],
)


class HoldingIn(BaseModel):
    symbol: str = Field(..., description="Kode saham, mis. BBCA")
    quantity: float = Field(..., ge=0, description="Jumlah lembar dimiliki")
    cost_basis: float = Field(0.0, ge=0, description="Total modal beli (IDR)")
    market: str = Field("IDX", description="IDX | NASDAQ | NYSE | ETF")


class PortfolioAnalyzeRequest(BaseModel):
    holdings: list[HoldingIn] = Field(default_factory=list)


@router.post("/analyze")
async def analyze_portfolio(request: PortfolioAnalyzeRequest):
    """
    Analisis kesehatan portofolio + narasi harian "Explain My Portfolio Today".

    Body:
        { "holdings": [ {symbol, quantity, cost_basis, market}, ... ] }
    """
    try:
        holdings = [h.model_dump() for h in request.holdings]
        hasil = await analisis_portofolio(holdings)
        return hasil
    except Exception as e:
        logger.error(f"❌ Gagal menganalisis portofolio: {e}")
        raise HTTPException(status_code=500, detail=f"Gagal menganalisis portofolio: {str(e)}")
