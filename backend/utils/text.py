"""
AI Saham Indonesia — Pembersih Teks Alasan LLM

Logika membuang "noise" dari teks alasan yang dihasilkan LLM (header bracket
seperti [RISIKO]/[REKOMENDASI] dan baris yang hanya berisi kata rekomendasi
terisolasi) sebelumnya disalin di dua tempat: agents/scoring_agent.py dan
api/routes/rekomendasi.py. Modul ini memusatkan inti logikanya.
"""

# Kata rekomendasi terisolasi yang dibuang jika muncul sendirian di satu baris.
_ISOLATED_KEYWORDS = {
    "RECOMMENDED",
    "NEUTRAL",
    "NEGATIVE",
    "RECOMMENDATION",
    "REKOMENDASI",
    "BUY",
    "SELL",
    "HOLD",
}


def strip_alasan_noise(text: str) -> list[str]:
    """
    Ambil baris-baris bermakna dari teks alasan LLM.

    Membuang: baris kosong, header bracket (`[...]`), dan baris yang hanya
    berisi satu kata rekomendasi (mis. "BUY", "NEUTRAL").

    Returns:
        List baris yang sudah di-`strip()`, siap di-`join`.
    """
    lines: list[str] = []
    for line in (text or "").split("\n"):
        line_stripped = line.strip()
        if not line_stripped:
            continue
        # Hapus header bracket seperti [RISIKO], [REKOMENDASI], [ANALISIS]
        if line_stripped.startswith("[") and line_stripped.endswith("]"):
            continue
        # Hapus baris yang hanya berisi kata rekomendasi terisolasi
        if line_stripped.upper() in _ISOLATED_KEYWORDS:
            continue
        lines.append(line_stripped)
    return lines
