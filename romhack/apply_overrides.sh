#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.."; pwd)"
SRC="$ROOT/romhack/overrides"
DST="$ROOT/romhack/pokeemerald"

rsync -av --exclude='.git' "$SRC/" "$DST/"
echo "Overrides applied to submodule."
