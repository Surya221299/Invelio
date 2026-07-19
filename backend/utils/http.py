"""
AI Saham Indonesia — HTTP Fetch Helper

Sebelumnya blok `httpx.AsyncClient(...)` + `get()` + `raise_for_status()` +
konstanta `_USER_AGENT` disalin berulang di beberapa collector
(berita_collector.py, makro_collector.py). Modul ini memusatkan pola fetch
HTML/teks async yang sama di satu tempat.

Penanganan error TETAP di sisi pemanggil: `fetch_html` melempar
`httpx.TimeoutException` / `httpx.HTTPStatusError` seperti sebelumnya,
jadi blok `except httpx.*` di collector tidak berubah perilakunya.

Penggunaan:
    from backend.utils.http import fetch_html, USER_AGENT

    html = await fetch_html(url, timeout=15.0)
    soup = BeautifulSoup(html, "html.parser")
"""

import httpx

# User-Agent browser desktop — sebelumnya didefinisikan identik di
# berita_collector.py dan makro_collector.py.
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Apple Silicon Mac OS X) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)


async def fetch_html(
    url: str,
    *,
    timeout: float = 15.0,
    follow_redirects: bool = True,
    user_agent: str | None = USER_AGENT,
    params: dict | None = None,
) -> str:
    """
    GET satu URL dan kembalikan body teksnya.

    Args:
        url: URL target.
        timeout: Timeout total (detik).
        follow_redirects: Ikuti redirect HTTP (default True).
        user_agent: Nilai header User-Agent. `None` untuk tidak mengirim header
            User-Agent sama sekali (perilaku beberapa fetch RSS lama).
        params: Query params opsional.

    Returns:
        Body respons sebagai `str`.

    Raises:
        httpx.TimeoutException, httpx.HTTPStatusError — ditangani pemanggil.
    """
    headers = {"User-Agent": user_agent} if user_agent else None
    async with httpx.AsyncClient(
        timeout=timeout,
        follow_redirects=follow_redirects,
        headers=headers,
    ) as client:
        response = await client.get(url, params=params)
        response.raise_for_status()
        return response.text
