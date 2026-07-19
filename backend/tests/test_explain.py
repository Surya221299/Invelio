"""
AI Saham — Unit Tests untuk Explainable Recommendations (utils/explain.py)

Memvalidasi bahwa atribusi faktor bersifat deterministik dan konsisten:
1. Kontribusi tiap komponen = skor × bobot, dan penjumlahannya ≈ skor_total.
2. Faktor terurut dari kontribusi terbesar.
3. Pendorong/penahan utama teridentifikasi dengan benar.
4. Komponen tak-dibobot ditandai "informasi" (tidak ikut menentukan skor).
5. Deskripsi fundamental memakai rasio nyata bila tersedia.
"""

import unittest

from backend.utils.explain import (
    bangun_penjelasan_skor,
    _deskripsi_fundamental,
    _arah,
)


def _komponen(fund, sen, sek, mak, ris, bobot=(0.40, 0.0, 0.20, 0.25, 0.15)):
    bf, bs, bsek, bm, br = bobot
    return {
        "fundamental": {"skor": fund, "bobot": bf},
        "sentimen": {"skor": sen, "bobot": bs},
        "sektor": {"skor": sek, "bobot": bsek},
        "makro": {"skor": mak, "bobot": bm},
        "risiko": {"skor": ris, "bobot": br},
    }


class TestExplain(unittest.TestCase):
    def test_kontribusi_menjumlah_ke_skor_total(self):
        """Total kontribusi seluruh komponen harus ≈ skor_total (weighted sum)."""
        komp = _komponen(85, 60, 70, 75, 55)
        # skor_total = 85*.4 + 60*0 + 70*.2 + 75*.25 + 55*.15 = 34+0+14+18.75+8.25 = 75
        hasil = bangun_penjelasan_skor(skor_total=75.0, komponen=komp)
        total_kontribusi = sum(f["kontribusi"] for f in hasil["faktor"])
        self.assertAlmostEqual(total_kontribusi, 75.0, places=1)

    def test_faktor_terurut_kontribusi_desc(self):
        komp = _komponen(85, 60, 70, 75, 55)
        hasil = bangun_penjelasan_skor(skor_total=75.0, komponen=komp)
        kontribusi = [f["kontribusi"] for f in hasil["faktor"]]
        self.assertEqual(kontribusi, sorted(kontribusi, reverse=True))
        # Fundamental (34) harus jadi faktor teratas
        self.assertEqual(hasil["faktor"][0]["komponen"], "fundamental")

    def test_pendorong_dan_penahan(self):
        # Fundamental sangat kuat (pendorong), risiko sangat rendah skornya (penahan)
        komp = _komponen(90, 50, 70, 68, 30)
        hasil = bangun_penjelasan_skor(skor_total=70.0, komponen=komp)
        self.assertIn("Fundamental", hasil["pendorong_utama"])
        self.assertIn("Profil Risiko", hasil["penahan_utama"])

    def test_komponen_tak_dibobot_ditandai_informasi(self):
        """Sentimen dengan bobot 0 harus berarah 'informasi', bukan positif/negatif."""
        komp = _komponen(85, 95, 70, 75, 55)
        hasil = bangun_penjelasan_skor(skor_total=75.0, komponen=komp)
        sentimen = next(f for f in hasil["faktor"] if f["komponen"] == "sentimen")
        self.assertEqual(sentimen["arah"], "informasi")
        self.assertEqual(sentimen["kontribusi"], 0.0)
        # Tidak boleh muncul sebagai pendorong walau skornya tinggi
        self.assertNotIn("Sentimen Berita", hasil["pendorong_utama"])

    def test_arah_threshold(self):
        self.assertEqual(_arah(80), "positif")
        self.assertEqual(_arah(55), "netral")
        self.assertEqual(_arah(40), "negatif")

    def test_deskripsi_fundamental_pakai_rasio_nyata(self):
        desc = _deskripsi_fundamental({"roe": 18.0, "pbv": 1.2, "der": 0.4, "pe_ratio": 12.0})
        self.assertIn("ROE 18%", desc)
        self.assertIn("PBV 1.2x", desc)
        self.assertIn("DER 0.4x", desc)
        self.assertIn("PE 12x", desc)

    def test_deskripsi_fundamental_lewati_none(self):
        """Rasio None tidak boleh muncul di deskripsi."""
        desc = _deskripsi_fundamental({"roe": 12.0, "pbv": None, "der": None, "pe_ratio": None})
        self.assertIn("ROE 12%", desc)
        self.assertNotIn("PBV", desc)
        self.assertNotIn("None", desc)

    def test_ringkasan_tanpa_penahan(self):
        komp = _komponen(85, 60, 80, 78, 90)
        hasil = bangun_penjelasan_skor(skor_total=84.0, komponen=komp)
        self.assertEqual(hasil["penahan_utama"], [])
        self.assertIn("tanpa penahan", hasil["ringkasan"])

    def test_skor_total_nol_tidak_error(self):
        """Skor total 0 tidak boleh menyebabkan pembagian nol."""
        komp = _komponen(0, 0, 0, 0, 0)
        hasil = bangun_penjelasan_skor(skor_total=0.0, komponen=komp)
        self.assertEqual(hasil["faktor"][0]["kontribusi_persen"], 0.0)


if __name__ == "__main__":
    unittest.main()
