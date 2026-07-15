"""
AI Saham — Explainable Recommendations

Membangun penjelasan TERSTRUKTUR & DETERMINISTIK atas skor rekomendasi
sebuah saham. Berbeda dengan field `alasan` (prosa naratif hasil LLM yang
bisa berhalusinasi pada angka), modul ini menghasilkan atribusi faktor
murni dari data yang SUDAH tersimpan di `ScoringMingguan` + `Fundamental`:

    kontribusi_komponen = skor_komponen × bobot_komponen

Karena skor total adalah weighted-sum (bobot berjumlah 1.0), penjumlahan
seluruh kontribusi ≈ skor_total. Ini memungkinkan UI menampilkan panel
"Kenapa skor ini?" yang jujur dan bisa diaudit: faktor mana yang mendorong,
faktor mana yang menahan, masing-masing dengan angka nyatanya.

Semua fungsi di sini PURE (tanpa I/O, tanpa LLM) sehingga mudah dites dan
tidak menambah latency ke pemanggil.

Penggunaan:
    from backend.utils.explain import bangun_penjelasan_skor

    penjelasan = bangun_penjelasan_skor(
        skor_total=82.0,
        komponen={
            "fundamental": {"skor": 85.0, "bobot": 0.40},
            "sentimen":    {"skor": 60.0, "bobot": 0.00},
            "sektor":      {"skor": 70.0, "bobot": 0.20},
            "makro":       {"skor": 75.0, "bobot": 0.25},
            "risiko":      {"skor": 55.0, "bobot": 0.15},
        },
        fundamental={"roe": 18.0, "pbv": 1.2, "der": 0.4, "pe_ratio": 12.0},
    )
"""

from __future__ import annotations

from typing import Any

# ── Ambang klasifikasi arah faktor (skala skor 0-100) ──────────────
# Semua komponen skor berlaku "makin tinggi makin baik" (termasuk risiko:
# skor risiko tinggi = risiko rendah / aman).
_AMBANG_POSITIF = 65.0
_AMBANG_NETRAL = 50.0
# Faktor dianggap "penahan" (drag) jika skornya di bawah ini DAN dibobot.
_AMBANG_PENAHAN = 55.0

# ── Definisi komponen: (key, label, deskripsi band) ────────────────
# Urutan menentukan urutan default di list faktor.
_KOMPONEN = [
    ("fundamental", "Fundamental"),
    ("sentimen", "Sentimen Berita"),
    ("sektor", "Sektor"),
    ("makro", "Kondisi Makro"),
    ("risiko", "Profil Risiko"),
]

# Deskripsi generik per band skor untuk komponen non-fundamental
# (fundamental punya deskripsi khusus berbasis rasio, lihat _deskripsi_fundamental).
_DESKRIPSI_BAND: dict[str, dict[str, str]] = {
    "sentimen": {
        "positif": "berita terbaru cenderung positif",
        "netral": "sentimen berita cenderung netral/campuran",
        "negatif": "sentimen berita cenderung negatif",
    },
    "sektor": {
        "positif": "sektor sedang menarik dibanding sektor lain",
        "netral": "kinerja sektor relatif netral",
        "negatif": "sektor sedang kurang mendukung",
    },
    "makro": {
        "positif": "kondisi makro (suku bunga, inflasi, kurs) mendukung",
        "netral": "kondisi makro relatif netral",
        "negatif": "kondisi makro sedang menjadi hambatan",
    },
    "risiko": {
        "positif": "profil risiko rendah (utang & likuiditas sehat)",
        "netral": "profil risiko moderat",
        "negatif": "profil risiko tinggi (utang/likuiditas/berita negatif)",
    },
}


def _arah(skor: float) -> str:
    """Klasifikasi arah faktor berdasarkan skornya."""
    if skor >= _AMBANG_POSITIF:
        return "positif"
    if skor >= _AMBANG_NETRAL:
        return "netral"
    return "negatif"


def _deskripsi_fundamental(fundamental: dict[str, Any] | None) -> str:
    """
    Susun deskripsi fundamental dari rasio nyata (ROE, PBV, DER, PE, dividen).

    Hanya menyebut rasio yang tersedia (tidak None). Rasio bersifat
    currency-agnostic sehingga deskripsi ini valid untuk saham IDX maupun US.
    """
    if not fundamental:
        return ""

    bagian: list[str] = []

    roe = fundamental.get("roe")
    if roe is not None:
        if roe >= 15:
            bagian.append(f"ROE {roe:.0f}% (sangat sehat)")
        elif roe >= 10:
            bagian.append(f"ROE {roe:.0f}% (sehat)")
        elif roe >= 5:
            bagian.append(f"ROE {roe:.0f}% (cukup)")
        else:
            bagian.append(f"ROE {roe:.0f}% (lemah)")

    pbv = fundamental.get("pbv")
    if pbv is not None and pbv > 0:
        if pbv < 1:
            bagian.append(f"PBV {pbv:.1f}x (sangat murah)")
        elif pbv < 2:
            bagian.append(f"PBV {pbv:.1f}x (wajar)")
        elif pbv < 3:
            bagian.append(f"PBV {pbv:.1f}x (agak mahal)")
        else:
            bagian.append(f"PBV {pbv:.1f}x (mahal)")

    der = fundamental.get("der")
    if der is not None:
        if der < 0.5:
            bagian.append(f"DER {der:.1f}x (utang rendah)")
        elif der < 1:
            bagian.append(f"DER {der:.1f}x (utang moderat)")
        elif der < 2:
            bagian.append(f"DER {der:.1f}x (utang tinggi)")
        else:
            bagian.append(f"DER {der:.1f}x (utang sangat tinggi)")

    pe = fundamental.get("pe_ratio")
    if pe is not None and pe > 0:
        if pe < 10:
            bagian.append(f"PE {pe:.0f}x (murah)")
        elif pe < 20:
            bagian.append(f"PE {pe:.0f}x (wajar)")
        elif pe < 30:
            bagian.append(f"PE {pe:.0f}x (agak mahal)")
        else:
            bagian.append(f"PE {pe:.0f}x (mahal)")

    div = fundamental.get("dividend_yield")
    if div is not None and div > 0:
        if div >= 4:
            bagian.append(f"dividend yield {div:.1f}% (menarik)")
        elif div >= 2:
            bagian.append(f"dividend yield {div:.1f}% (moderat)")

    return ", ".join(bagian)


def _deskripsi_komponen(key: str, arah: str, fundamental: dict[str, Any] | None) -> str:
    """Deskripsi natural untuk satu komponen sesuai arah/band."""
    if key == "fundamental":
        detail = _deskripsi_fundamental(fundamental)
        if detail:
            return detail
        # Fallback bila rasio fundamental tidak tersedia
        return {
            "positif": "rasio fundamental tergolong kuat",
            "netral": "rasio fundamental tergolong wajar",
            "negatif": "rasio fundamental tergolong lemah",
        }[arah]
    return _DESKRIPSI_BAND.get(key, {}).get(arah, "")


def bangun_penjelasan_skor(
    *,
    skor_total: float,
    komponen: dict[str, dict[str, float]],
    fundamental: dict[str, Any] | None = None,
    market: str = "IDX",
) -> dict[str, Any]:
    """
    Bangun penjelasan terstruktur atas skor rekomendasi sebuah saham.

    Args:
        skor_total: Skor total 0-100.
        komponen: Peta {key -> {"skor": float, "bobot": float}} untuk kelima
            komponen ("fundamental", "sentimen", "sektor", "makro", "risiko").
            Komponen yang hilang dianggap skor 0 / bobot 0.
        fundamental: Rasio fundamental opsional (roe, pbv, der, pe_ratio,
            dividend_yield) untuk memperkaya deskripsi komponen fundamental.
        market: Market saham (disimpan untuk konteks; tidak mengubah angka).

    Returns:
        Dict:
        {
          "ringkasan": str,                 # 1 kalimat inti "kenapa skor ini"
          "skor_total": float,
          "faktor": [                       # daftar semua komponen, terurut kontribusi desc
            {
              "komponen": "fundamental",
              "label": "Fundamental",
              "skor": 85.0,
              "bobot": 0.40,
              "kontribusi": 34.0,           # skor * bobot (poin ke skor total)
              "kontribusi_persen": 41.5,    # porsi terhadap skor total
              "arah": "positif",            # positif | netral | negatif | informasi
              "deskripsi": "ROE 18% (sangat sehat), PBV 1.2x (wajar), ...",
            }, ...
          ],
          "pendorong_utama": ["Fundamental", "Kondisi Makro"],
          "penahan_utama": ["Profil Risiko"],
        }
    """
    faktor: list[dict[str, Any]] = []

    for key, label in _KOMPONEN:
        data = komponen.get(key) or {}
        skor = float(data.get("skor", 0.0) or 0.0)
        bobot = float(data.get("bobot", 0.0) or 0.0)
        kontribusi = round(skor * bobot, 1)
        kontribusi_persen = (
            round(kontribusi / skor_total * 100, 1) if skor_total > 0 else 0.0
        )

        # Komponen tak-dibobot (mis. sentimen "UI only") ditandai "informasi"
        # supaya jelas ia tidak ikut menentukan skor, hanya konteks.
        arah = "informasi" if bobot <= 0 else _arah(skor)

        faktor.append({
            "komponen": key,
            "label": label,
            "skor": round(skor, 1),
            "bobot": round(bobot, 2),
            "kontribusi": kontribusi,
            "kontribusi_persen": kontribusi_persen,
            "arah": arah,
            "deskripsi": _deskripsi_komponen(key, _arah(skor), fundamental),
        })

    # Urutkan faktor berdasarkan kontribusi terbesar (paling menentukan di atas)
    faktor.sort(key=lambda f: f["kontribusi"], reverse=True)

    # Pendorong utama: faktor dibobot dengan arah positif, kontribusi terbesar
    pendorong = [
        f["label"] for f in faktor
        if f["bobot"] > 0 and f["arah"] == "positif"
    ][:2]

    # Penahan utama: faktor dibobot berskor rendah, diurutkan berdasarkan
    # "drag" = bobot × (100 − skor), yaitu berapa poin yang hilang karenanya.
    penahan_kandidat = [
        f for f in faktor
        if f["bobot"] > 0 and f["skor"] < _AMBANG_PENAHAN
    ]
    penahan_kandidat.sort(key=lambda f: f["bobot"] * (100 - f["skor"]), reverse=True)
    penahan = [f["label"] for f in penahan_kandidat][:2]

    ringkasan = _bangun_ringkasan(skor_total, pendorong, penahan)

    return {
        "ringkasan": ringkasan,
        "skor_total": round(skor_total, 1),
        "faktor": faktor,
        "pendorong_utama": pendorong,
        "penahan_utama": penahan,
    }


def _bangun_ringkasan(
    skor_total: float,
    pendorong: list[str],
    penahan: list[str],
) -> str:
    """Susun satu kalimat ringkasan 'kenapa skor ini'."""
    if pendorong:
        inti = f"didorong terutama oleh {_gabung(pendorong)}"
    else:
        inti = "tidak ada faktor pendorong yang menonjol"

    if penahan:
        akhir = f", tertahan oleh {_gabung(penahan)}"
    else:
        akhir = ", tanpa penahan yang berarti"

    return f"Skor {skor_total:.0f}/100 — {inti}{akhir}."


def _gabung(items: list[str]) -> str:
    """Gabungkan daftar label secara natural: [A] -> 'A', [A,B] -> 'A dan B'."""
    items = [i.lower() for i in items]
    if len(items) == 1:
        return items[0]
    return " dan ".join(items)


def penjelasan_dari_scoring(scoring_obj: Any, fundamental_obj: Any | None = None,
                            market: str = "IDX") -> dict[str, Any]:
    """
    Adapter praktis: bangun penjelasan langsung dari objek ORM
    `ScoringMingguan` (+ opsional `Fundamental`).

    Memisahkan ekstraksi field ORM dari logika murni `bangun_penjelasan_skor`
    supaya logika inti tetap gampang dites tanpa DB.
    """
    komponen = {
        "fundamental": {"skor": scoring_obj.skor_fundamental, "bobot": scoring_obj.bobot_fundamental},
        "sentimen": {"skor": scoring_obj.skor_sentimen, "bobot": scoring_obj.bobot_sentimen},
        "sektor": {"skor": scoring_obj.skor_sektor, "bobot": scoring_obj.bobot_sektor},
        "makro": {"skor": scoring_obj.skor_makro, "bobot": scoring_obj.bobot_makro},
        "risiko": {"skor": scoring_obj.skor_risiko, "bobot": scoring_obj.bobot_risiko},
    }

    fundamental = None
    if fundamental_obj is not None:
        fundamental = {
            "roe": fundamental_obj.roe,
            "pbv": fundamental_obj.pbv,
            "der": fundamental_obj.der,
            "pe_ratio": fundamental_obj.pe_ratio,
            "dividend_yield": fundamental_obj.dividend_yield,
        }

    return bangun_penjelasan_skor(
        skor_total=scoring_obj.skor_total,
        komponen=komponen,
        fundamental=fundamental,
        market=market,
    )
