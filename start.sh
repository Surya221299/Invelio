#!/usr/bin/env bash
# Start the Invelio backend server
set -e

# Pindah ke folder tempat script ini berada
cd "$(dirname "$0")"

# Aktifkan virtual environment
source venv/bin/activate

# Jalankan server
uvicorn backend.main:app --host 0.0.0.0 --port 8080 --reload
