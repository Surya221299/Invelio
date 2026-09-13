#!/usr/bin/env bash
# Start the Invelio backend server
set -e

# Pindah ke folder tempat script ini berada
cd "$(dirname "$0")"

# Pastikan container docker (PostgreSQL & ChromaDB) berjalan
if command -v docker &> /dev/null; then
    echo "Memeriksa container Docker..."
    docker start saham_postgres saham_chromadb 2>/dev/null || docker compose -p sahamapp-main up -d 2>/dev/null || true
fi

# Aktifkan virtual environment
source venv/bin/activate

# Jalankan server
uvicorn backend.main:app --host 0.0.0.0 --port 8080 --reload
