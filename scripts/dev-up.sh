#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SERVER_DIR="$ROOT_DIR/server"
VENV_DIR="$SERVER_DIR/.venv"

if [ ! -d "$VENV_DIR" ]; then
  echo "Virtual environment not found at $VENV_DIR" >&2
  echo "Create it with: python3 -m venv server/.venv" >&2
  exit 1
fi

source "$VENV_DIR/bin/activate"
cd "$SERVER_DIR"

uvicorn app:app --reload &
UVICORN_PID=$!

cleanup() {
  if kill -0 "$UVICORN_PID" 2>/dev/null; then
    kill "$UVICORN_PID"
    wait "$UVICORN_PID" 2>/dev/null || true
  fi
}

trap cleanup EXIT

echo "FastAPI dev server running. Health check: http://127.0.0.1:8000/healthz"
wait "$UVICORN_PID"
