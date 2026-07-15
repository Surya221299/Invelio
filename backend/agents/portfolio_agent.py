"""
AI Saham Indonesia — Portfolio Health Agent (LangGraph)

Agent stateless yang menganalisis PORTOFOLIO milik user (bukan saham tunggal).
Input berupa daftar holdings yang dikirim aplikasi iOS; agent menghitung metrik
tingkat-portofolio, menilai kesehatan/risiko konsentrasi, lalu meng-generate
narasi harian "Explain My Portfolio Today" dalam Bahasa Indonesia.

Karena portofolio disimpan on-device (UserDefaults di iOS), backend TIDAK
menyimpan apa pun — holdings masuk lewat request, hasil analisis keluar lewat
response. Tanpa tabel baru, tanpa auth.

Arsitektur LangGraph StateGraph:

    START
      │
      ▼
    1. hitung_metrik      → harga/perubahan hari ini, sektor, sentimen, skor
      │                     rekomendasi per holding; bobot & kontribusi IDR
      ▼
    2. analisis_risiko    → diversifikasi (HHI), konsentrasi emiten/sektor,
      │                     skor kesehatan explainable, level risiko, flags
      ▼
    3. generate_narasi    → narasi harian + saran rebalancing via Qwen (Ollama)
      │                     (degradasi anggun bila LLM/Ollama mati)
      ▼
     END

Penggunaan:
    from backend.agents.portfolio_agent import analisis_portofolio

    hasil = await analisis_portofolio([
        {"symbol": "BBCA", "quantity": 100, "cost_basis": 900_000},
        {"symbol": "TLKM", "quantity": 200, "cost_basis": 700_000},
    ])
"""

import asyncio
from datetime import datetime, timedelta, timezone
from typing import Any, TypedDict

from langchain_core.messages import HumanMessage, SystemMessage
from langchain_ollama import ChatOllama
from langgraph.graph import END, START, StateGraph
from loguru import logger
from sqlalchemy import func, select

from backend.config import settings
from backend.utils.text import strip_alasan_noise
from backend.db.postgres import async_session, Saham, Berita, ScoringMingguan, Makro
from backend.api.routes.data import get_single_stock_price_stats

# Timezone WIB (UTC+7)
_WIB = timezone(timedelta(hours=7))

# Kurs fallback USD->IDR bila data kurs belum ada di tabel Makro.
_KURS_FALLBACK_USD_IDR = 16000.0

# Batasi jumlah holding yang diproses konkuren. Tiap task memakai satu koneksi
# DB dari pool (pool_size=10 + overflow=20); tanpa batas, portofolio besar bisa
# menguras pool. 8 cukup untuk paralelisme tanpa risiko exhaustion.
_MAX_KONKUREN_HOLDING = 8


def _is_usd_market(market: str | None) -> bool:
    """
    True bila saham diperdagangkan dalam USD (NASDAQ/NYSE/ETF/dll), False
    untuk IDX (IDR). Menentukan apakah nilai holding perlu dikonversi ke IDR
    sebelum diagregasi ke level portofolio.
    """
    return (market or "IDX").strip().upper() != "IDX"


async def _get_kurs_usd_idr(db) -> float:
    """
    Ambil kurs USD->IDR terbaru dari tabel Makro (indikator 'kurs_usd_idr').
    Tanpa network call — dipakai untuk menormalkan nilai holding US ke IDR
    supaya total, bobot, HHI, dan P/L portofolio tidak mencampur mata uang.
    Fallback ke konstanta bila data kurs belum tersedia.
    """
    try:
        stmt = (
            select(Makro.nilai)
            .where(Makro.indikator == "kurs_usd_idr")
            .order_by(Makro.tanggal.desc())
            .limit(1)
        )
        val = await db.scalar(stmt)
        if val and float(val) > 0:
            return float(val)
    except Exception as e:
        logger.warning(f"⚠️ Gagal ambil kurs USD/IDR dari DB, pakai fallback: {e}")
    return _KURS_FALLBACK_USD_IDR


# ============================================================
# State Definition
# ============================================================

class PortfolioState(TypedDict, total=False):
    """State yang mengalir melalui pipeline analisis portofolio."""
    holdings_input: list[dict]   # Input: [{symbol, quantity, cost_basis, market}]
    per_holding: list[dict]      # Node 1: metrik per emiten
    total_value: float           # Node 1
    total_cost: float            # Node 1
    kesehatan: dict              # Node 2
    alokasi_sektor: list[dict]   # Node 2
    kontributor: dict            # Node 2
    narasi_harian: str           # Node 3
    saran_rebalancing: list[str] # Node 3


# ============================================================
# LLM Setup (pola sama dengan scoring_agent._get_llm)
# ============================================================

def _get_llm() -> ChatOllama:
    """Buat instance ChatOllama yang terhubung ke Qwen3 lokal."""
    return ChatOllama(
        model=settings.ollama_model,
        base_url=settings.ollama_base_url,
        temperature=settings.ollama_temperature,
        num_ctx=settings.ollama_num_ctx,
        timeout=settings.ollama_timeout,
    )


# ============================================================
# NODE 1: Hitung Metrik Per Holding
# ============================================================

async def _metrik_satu_holding(h: dict, kurs_usd_idr: float, sem: asyncio.Semaphore) -> dict:
    """
    Ambil data pasar + fundamental untuk satu holding.

    Membuka sesi DB SENDIRI karena dipanggil paralel via asyncio.gather —
    satu AsyncSession TIDAK aman dipakai beberapa task konkuren (akan melempar
    "another operation is in progress"). Sesi-per-task aman dari connection pool,
    dan `sem` membatasi berapa sesi terbuka bersamaan agar pool tidak habis.

    Semua nilai uang dinormalkan ke IDR: harga saham US datang dalam USD, jadi
    value/cost/kontribusi dikali kurs supaya agregasi portofolio (total, bobot,
    HHI, P/L) tidak mencampur mata uang. price/change/pct_change tetap dalam mata
    uang asal untuk ditampilkan per-lembar.
    """
    symbol = str(h.get("symbol", "")).strip().upper()
    quantity = float(h.get("quantity") or 0.0)
    cost_basis = float(h.get("cost_basis") or 0.0)
    market = str(h.get("market") or "IDX").strip().upper()
    # Faktor konversi ke IDR: 1.0 untuk IDX, kurs untuk pasar USD.
    fx = kurs_usd_idr if _is_usd_market(market) else 1.0

    async with sem, async_session() as db:
        # Harga & perubahan hari ini (reuse helper dari data route)
        try:
            price, change, pct_change = await get_single_stock_price_stats(symbol, db, market)
        except Exception as e:
            logger.warning(f"⚠️ Gagal ambil harga {symbol}: {e}")
            price, change, pct_change = 0.0, 0.0, 0.0

        # Metadata saham (sektor & nama) — hanya untuk emiten yang dikenal DB
        sektor, nama = "Lainnya", symbol
        try:
            saham = await db.get(Saham, symbol)
            if saham:
                sektor = saham.sektor or "Lainnya"
                nama = saham.nama_perusahaan or symbol
        except Exception:
            pass

        # Sentimen berita 7 hari terakhir (rata-rata skor_sentimen)
        sentimen = None
        try:
            sejak = datetime.now(_WIB) - timedelta(days=7)
            stmt_sent = (
                select(func.avg(Berita.skor_sentimen))
                .where(Berita.kode_saham == symbol)
                .where(Berita.tanggal_publish >= sejak)
                .where(Berita.skor_sentimen.isnot(None))
            )
            sentimen = await db.scalar(stmt_sent)
        except Exception:
            pass

        # Skor rekomendasi terakhir (dipakai untuk komponen "kualitas" health & narasi)
        skor_rekomendasi = None
        try:
            stmt_score = (
                select(ScoringMingguan.skor_total)
                .where(ScoringMingguan.kode_saham == symbol)
                .order_by(ScoringMingguan.tanggal_scoring.desc())
                .limit(1)
            )
            skor_rekomendasi = await db.scalar(stmt_score)
        except Exception:
            pass

    # Nilai-nilai uang dalam IDR (setelah konversi kurs bila pasar USD)
    value = price * quantity * fx
    cost_basis_idr = cost_basis * fx
    return {
        "symbol": symbol,
        "nama": nama,
        "sektor": sektor,
        "market": market,
        "quantity": quantity,
        "price": price,                # per-lembar, mata uang asal (untuk tampilan)
        "change": change,              # per-lembar, mata uang asal
        "pct_change": pct_change,
        "value": value,                # IDR
        "cost_basis": cost_basis_idr,  # IDR
        "profit_idr": value - cost_basis_idr,
        "profit_pct": ((value - cost_basis_idr) / cost_basis_idr * 100.0) if cost_basis_idr > 0 else 0.0,
        "kontribusi_idr": change * quantity * fx,  # dampak pergerakan hari ini ke nilai portofolio (IDR)
        "sentimen": float(sentimen) if sentimen is not None else None,
        "skor_rekomendasi": float(skor_rekomendasi) if skor_rekomendasi is not None else None,
    }


async def hitung_metrik(state: PortfolioState) -> dict[str, Any]:
    """Node 1: hitung metrik pasar & P/L untuk setiap holding (paralel)."""
    logger.info("📊 NODE 1: Hitung metrik per holding")
    holdings = [h for h in state.get("holdings_input", []) if float(h.get("quantity") or 0) > 0]

    if not holdings:
        return {"per_holding": [], "total_value": 0.0, "total_cost": 0.0}

    # Ambil kurs sekali (dipakai untuk semua holding US). Sesi terpisah & pendek.
    async with async_session() as db:
        kurs_usd_idr = await _get_kurs_usd_idr(db)

    # Tiap task membuka sesinya sendiri (lihat _metrik_satu_holding) → aman paralel.
    # Semaphore membatasi jumlah sesi terbuka bersamaan.
    sem = asyncio.Semaphore(_MAX_KONKUREN_HOLDING)
    per_holding = await asyncio.gather(
        *[_metrik_satu_holding(h, kurs_usd_idr, sem) for h in holdings]
    )

    per_holding = list(per_holding)
    total_value = sum(p["value"] for p in per_holding)
    total_cost = sum(p["cost_basis"] for p in per_holding)

    # Bobot tiap holding terhadap total nilai pasar
    for p in per_holding:
        p["weight"] = (p["value"] / total_value) if total_value > 0 else 0.0

    logger.info(f"   → {len(per_holding)} holding, total nilai Rp {total_value:,.0f}")
    return {"per_holding": per_holding, "total_value": total_value, "total_cost": total_cost}


# ============================================================
# NODE 2: Analisis Risiko & Kesehatan
# ============================================================

def _level_risiko(max_emiten: float, max_sektor: float) -> str:
    if max_emiten > 0.50 or max_sektor > 0.70:
        return "Tinggi"
    if max_emiten > 0.35 or max_sektor > 0.50:
        return "Sedang"
    return "Rendah"


async def analisis_risiko(state: PortfolioState) -> dict[str, Any]:
    """Node 2: diversifikasi (HHI), konsentrasi, skor kesehatan explainable."""
    logger.info("🩺 NODE 2: Analisis risiko & kesehatan portofolio")
    per_holding = state.get("per_holding", [])
    total_value = state.get("total_value", 0.0)

    if not per_holding or total_value <= 0:
        return {
            "kesehatan": {
                "skor_kesehatan": 0.0,
                "skor_diversifikasi": 0.0,
                "level_risiko": "Rendah",
                "jumlah_emiten": len(per_holding),
                "jumlah_sektor": 0,
                "konsentrasi_emiten": None,
                "konsentrasi_sektor": None,
                "flags": [],
            },
            "alokasi_sektor": [],
            "kontributor": {"teratas": [], "terbawah": []},
        }

    # --- Diversifikasi via HHI antar emiten ---
    hhi = sum(p["weight"] ** 2 for p in per_holding)
    skor_diversifikasi = max(0.0, min(100.0, (1.0 - hhi) * 100.0))

    # --- Alokasi & konsentrasi per sektor ---
    sektor_value: dict[str, float] = {}
    for p in per_holding:
        sektor_value[p["sektor"]] = sektor_value.get(p["sektor"], 0.0) + p["value"]
    alokasi_sektor = sorted(
        [
            {"sektor": s, "value": v, "persen": round(v / total_value * 100.0, 2)}
            for s, v in sektor_value.items()
        ],
        key=lambda x: x["persen"],
        reverse=True,
    )
    hhi_sektor = sum((v / total_value) ** 2 for v in sektor_value.values())
    skor_sebaran_sektor = max(0.0, min(100.0, (1.0 - hhi_sektor) * 100.0))

    # --- Konsentrasi emiten & sektor terbesar ---
    emiten_terbesar = max(per_holding, key=lambda p: p["weight"])
    konsentrasi_emiten = {
        "symbol": emiten_terbesar["symbol"],
        "persen": round(emiten_terbesar["weight"] * 100.0, 2),
    }
    sektor_terbesar = alokasi_sektor[0]
    konsentrasi_sektor = {
        "sektor": sektor_terbesar["sektor"],
        "persen": sektor_terbesar["persen"],
    }

    # --- Komponen skor kesehatan (explainable) ---
    jumlah_emiten = len(per_holding)
    komponen_jumlah = min(jumlah_emiten / 8.0, 1.0) * 100.0  # 8+ emiten = penuh
    skor_rekom = [p["skor_rekomendasi"] for p in per_holding if p["skor_rekomendasi"] is not None]
    komponen_kualitas = (sum(skor_rekom) / len(skor_rekom)) if skor_rekom else 55.0  # netral bila tak ada data

    skor_kesehatan = round(
        0.35 * skor_diversifikasi
        + 0.25 * skor_sebaran_sektor
        + 0.15 * komponen_jumlah
        + 0.25 * komponen_kualitas,
        1,
    )

    # --- Flags peringatan (proxy korelasi = konsentrasi sektor) ---
    flags: list[str] = []
    if konsentrasi_emiten["persen"] >= 40:
        flags.append(
            f"{konsentrasi_emiten['symbol']} mendominasi {konsentrasi_emiten['persen']:.0f}% portofolio — risiko konsentrasi tinggi."
        )
    if konsentrasi_sektor["persen"] >= 50:
        flags.append(
            f"Sektor {konsentrasi_sektor['sektor']} menyerap {konsentrasi_sektor['persen']:.0f}% aset — rawan koreksi serentak bila sektor tertekan."
        )
    if jumlah_emiten < 3:
        flags.append("Portofolio terdiri dari sangat sedikit emiten — pertimbangkan menambah diversifikasi.")

    kesehatan = {
        "skor_kesehatan": skor_kesehatan,
        "skor_diversifikasi": round(skor_diversifikasi, 1),
        "skor_sebaran_sektor": round(skor_sebaran_sektor, 1),
        "komponen_jumlah": round(komponen_jumlah, 1),
        "komponen_kualitas": round(komponen_kualitas, 1),
        "level_risiko": _level_risiko(emiten_terbesar["weight"], sektor_terbesar["persen"] / 100.0),
        "jumlah_emiten": jumlah_emiten,
        "jumlah_sektor": len(sektor_value),
        "konsentrasi_emiten": konsentrasi_emiten,
        "konsentrasi_sektor": konsentrasi_sektor,
        "flags": flags,
    }

    # --- Kontributor pergerakan hari ini ---
    bergerak = [p for p in per_holding if abs(p["kontribusi_idr"]) > 0]
    teratas = sorted(bergerak, key=lambda p: p["kontribusi_idr"], reverse=True)[:3]
    terbawah = sorted(bergerak, key=lambda p: p["kontribusi_idr"])[:3]

    def _kontrib(p: dict) -> dict:
        return {
            "symbol": p["symbol"],
            "pct_change": round(p["pct_change"], 2),
            "kontribusi_idr": round(p["kontribusi_idr"], 0),
        }

    kontributor = {
        "teratas": [_kontrib(p) for p in teratas if p["kontribusi_idr"] > 0],
        "terbawah": [_kontrib(p) for p in terbawah if p["kontribusi_idr"] < 0],
    }

    return {"kesehatan": kesehatan, "alokasi_sektor": alokasi_sektor, "kontributor": kontributor}


# ============================================================
# NODE 3: Generate Narasi Harian (LLM)
# ============================================================

def _narasi_fallback(state: PortfolioState) -> tuple[str, list[str]]:
    """Narasi non-LLM bila Ollama tidak tersedia — tetap informatif."""
    total_value = state.get("total_value", 0.0)
    total_cost = state.get("total_cost", 0.0)
    kesehatan = state.get("kesehatan", {})
    kontributor = state.get("kontributor", {})

    dampak = sum(
        p["kontribusi_idr"] for p in state.get("per_holding", [])
    )
    arah = "menguat" if dampak > 0 else ("melemah" if dampak < 0 else "relatif datar")
    profit = total_value - total_cost
    posisi = "untung" if profit >= 0 else "rugi"

    bagian = [f"Portofolio kamu {arah} hari ini dan secara keseluruhan sedang {posisi} Rp {abs(profit):,.0f}."]
    teratas = kontributor.get("teratas", [])
    terbawah = kontributor.get("terbawah", [])
    if teratas:
        bagian.append(f"Penopang utama: {teratas[0]['symbol']} ({teratas[0]['pct_change']:+.1f}%).")
    if terbawah:
        bagian.append(f"Penekan utama: {terbawah[0]['symbol']} ({terbawah[0]['pct_change']:+.1f}%).")
    narasi = " ".join(bagian)
    return narasi, list(kesehatan.get("flags", []))


async def generate_narasi(state: PortfolioState) -> dict[str, Any]:
    """Node 3: narasi 'Explain My Portfolio Today' + saran rebalancing via LLM."""
    logger.info("🤖 NODE 3: Generate narasi harian portofolio")
    per_holding = state.get("per_holding", [])
    if not per_holding:
        return {
            "narasi_harian": "Portofoliomu masih kosong. Tambahkan holding untuk mulai memantau kesehatan dan performa harian.",
            "saran_rebalancing": [],
        }

    total_value = state.get("total_value", 0.0)
    total_cost = state.get("total_cost", 0.0)
    kesehatan = state.get("kesehatan", {})
    kontributor = state.get("kontributor", {})
    alokasi_sektor = state.get("alokasi_sektor", [])

    # Ringkas holdings untuk grounding LLM (hindari halusinasi angka)
    ringkas_holdings = "\n".join(
        f"- {p['symbol']} ({p['sektor']}): bobot {p['weight']*100:.0f}%, "
        f"hari ini {p['pct_change']:+.1f}%, P/L {p['profit_pct']:+.1f}%"
        + (f", sentimen berita {p['sentimen']:+.2f}" if p["sentimen"] is not None else "")
        for p in sorted(per_holding, key=lambda x: x["weight"], reverse=True)
    )
    teratas = kontributor.get("teratas", [])
    terbawah = kontributor.get("terbawah", [])
    penopang = ", ".join(f"{k['symbol']} ({k['pct_change']:+.1f}%)" for k in teratas) or "tidak ada"
    penekan = ", ".join(f"{k['symbol']} ({k['pct_change']:+.1f}%)" for k in terbawah) or "tidak ada"
    profit = total_value - total_cost
    profit_pct = (profit / total_cost * 100.0) if total_cost > 0 else 0.0
    # Dampak HARI INI = jumlah pergerakan harga hari ini × lembar (beda dari P/L kumulatif)
    dampak_hari_ini = sum(p["kontribusi_idr"] for p in per_holding)
    dampak_hari_ini_pct = (dampak_hari_ini / total_value * 100.0) if total_value > 0 else 0.0
    arah_hari_ini = "menguat" if dampak_hari_ini > 0 else ("melemah" if dampak_hari_ini < 0 else "relatif datar")

    prompt = f"""Kamu adalah asisten investasi yang menjelaskan kondisi PORTOFOLIO seorang investor Indonesia hari ini.

PERGERAKAN HARI INI (gunakan ini untuk kalimat 'hari ini'):
- Arah portofolio hari ini: {arah_hari_ini}
- Dampak nilai hari ini: Rp {dampak_hari_ini:,.0f} ({dampak_hari_ini_pct:+.2f}%)

POSISI KUMULATIF (sejak pembelian, BUKAN pergerakan hari ini):
- Total nilai pasar: Rp {total_value:,.0f}
- Total modal: Rp {total_cost:,.0f}
- Untung/Rugi kumulatif: Rp {profit:,.0f} ({profit_pct:+.1f}%)

KESEHATAN:
- Skor kesehatan: {kesehatan.get('skor_kesehatan', 0)}/100 (risiko {kesehatan.get('level_risiko', '-')})
- Diversifikasi: {kesehatan.get('jumlah_emiten', 0)} emiten di {kesehatan.get('jumlah_sektor', 0)} sektor

HOLDINGS:
{ringkas_holdings}

PENOPANG HARI INI: {penopang}
PENEKAN HARI INI: {penekan}

PERINGATAN KONSENTRASI:
{chr(10).join('- ' + f for f in kesehatan.get('flags', [])) or '- Tidak ada'}

INSTRUKSI:
1. Tulis 2-3 kalimat mengalir: arah portofolio HARI INI (pakai bagian PERGERAKAN HARI INI, jangan pakai angka kumulatif untuk kata 'hari ini'), penopang/penekan utama, lalu boleh sebut posisi untung/rugi kumulatif secara terpisah bila relevan.
2. HANYA gunakan angka yang tersedia di atas — jangan mengarang data, jangan menukar angka kumulatif dengan pergerakan harian.
3. Bahasa Indonesia natural, tanpa markdown, tanpa tanda kurung siku.
4. Setelah itu, beri 1-3 saran rebalancing singkat & actionable berdasarkan peringatan konsentrasi (jika tidak ada peringatan, beri 1 saran menjaga kedisiplinan).

Format:
[NARASI]
(2-3 kalimat)

[SARAN]
- (saran 1)
- (saran 2)"""

    try:
        llm = _get_llm()
        messages = [
            SystemMessage(content=(
                "Kamu asisten investasi yang ringkas, akurat, dan hanya memakai data yang diberikan. "
                "Jawab langsung dalam Bahasa Indonesia. /no_think"
            )),
            HumanMessage(content=prompt),
        ]
        response = await llm.ainvoke(messages)
        narasi, saran = _parse_narasi_response(response.content or "")
        if not narasi:
            raise ValueError("Narasi kosong dari LLM")
        # Selalu sertakan flags sebagai saran bila LLM tidak menghasilkan saran
        if not saran:
            saran = list(kesehatan.get("flags", []))
        return {"narasi_harian": narasi, "saran_rebalancing": saran}
    except Exception as e:
        logger.warning(f"⚠️ LLM narasi gagal, pakai fallback: {e}")
        narasi, saran = _narasi_fallback(state)
        return {"narasi_harian": narasi, "saran_rebalancing": saran}


def _parse_narasi_response(text: str) -> tuple[str, list[str]]:
    """Pisahkan blok [NARASI] dan [SARAN] dari output LLM (buang <think> dsb)."""
    # Buang tag think Qwen bila ada
    if "</think>" in text:
        text = text.split("</think>", 1)[-1]

    narasi_lines: list[str] = []
    saran: list[str] = []
    mode = "narasi"
    for line in text.split("\n"):
        s = line.strip()
        if not s:
            continue
        up = s.upper()
        if up.startswith("[NARASI]"):
            mode = "narasi"
            continue
        if up.startswith("[SARAN]") or up.startswith("[REKOMENDASI]"):
            mode = "saran"
            continue
        if s.startswith("[") and s.endswith("]"):
            continue
        if mode == "narasi":
            narasi_lines.append(s)
        else:
            saran.append(s.lstrip("-•* ").strip())

    narasi = " ".join(strip_alasan_noise("\n".join(narasi_lines))).strip()
    saran = [x for x in saran if x]
    return narasi, saran


# ============================================================
# Graph Assembly
# ============================================================

def _build_graph():
    graph = StateGraph(PortfolioState)
    graph.add_node("hitung_metrik", hitung_metrik)
    graph.add_node("analisis_risiko", analisis_risiko)
    graph.add_node("generate_narasi", generate_narasi)
    graph.add_edge(START, "hitung_metrik")
    graph.add_edge("hitung_metrik", "analisis_risiko")
    graph.add_edge("analisis_risiko", "generate_narasi")
    graph.add_edge("generate_narasi", END)
    return graph.compile()


_compiled_graph = _build_graph()


# ============================================================
# Entry Point
# ============================================================

async def analisis_portofolio(holdings: list[dict]) -> dict[str, Any]:
    """
    Entry point utama — dipanggil oleh router POST /portfolio/analyze.

    Args:
        holdings: [{symbol, quantity, cost_basis, market?}]

    Returns:
        dict berisi ringkasan, kesehatan, alokasi_sektor, kontributor,
        narasi_harian, dan saran_rebalancing.
    """
    final: PortfolioState = await _compiled_graph.ainvoke({"holdings_input": holdings})

    total_value = final.get("total_value", 0.0)
    total_cost = final.get("total_cost", 0.0)
    profit = total_value - total_cost

    return {
        "ringkasan": {
            "total_value": round(total_value, 0),
            "total_cost": round(total_cost, 0),
            "profit_idr": round(profit, 0),
            "profit_pct": round((profit / total_cost * 100.0) if total_cost > 0 else 0.0, 2),
        },
        "kesehatan": final.get("kesehatan", {}),
        "alokasi_sektor": final.get("alokasi_sektor", []),
        "kontributor": final.get("kontributor", {"teratas": [], "terbawah": []}),
        "narasi_harian": final.get("narasi_harian", ""),
        "saran_rebalancing": final.get("saran_rebalancing", []),
        "generated_at": datetime.now(_WIB).isoformat(),
    }
