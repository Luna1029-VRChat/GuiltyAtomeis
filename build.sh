#!/bin/bash
set -euo pipefail

echo "============================================"
echo "  GuiltyAtomeis V11 -- Linux Build"
echo "============================================"

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SRC_DIR"

echo "[1/1] Building atmc..."
nim cpp -f -o:atmc -d:release --app:console \
    --path:src \
    --cincludes:src \
    src/atmc.nim

echo ""
echo "============================================"
echo "  Build Complete!"
echo "============================================"
echo "  atmc             - Compiler (with embedded runtime)"
echo "============================================"
