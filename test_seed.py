import asyncio
from backend.workers import seed_saham_if_empty
asyncio.run(seed_saham_if_empty())
