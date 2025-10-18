#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENV="$ROOT/server/.venv"
UVICORN_ARGS=("uvicorn" "app:app" "--reload" "--host" "127.0.0.1" "--port" "8000")

if [[ ! -d "$VENV" ]]; then
  cat <<'MSG' >&2
[dev-up] Missing virtual environment at server/.venv.
Create it with:
  cd server
  python3 -m venv .venv
  source .venv/bin/activate
  pip install -r requirements.txt
MSG
  exit 1
fi

source "$VENV/bin/activate"
cd "$ROOT/server"

HEALTH_URL="http://127.0.0.1:8000/health"
echo "[dev-up] FastAPI starting via ${UVICORN_ARGS[*]}"
echo "[dev-up] Health check: $HEALTH_URL"

"${UVICORN_ARGS[@]}"
