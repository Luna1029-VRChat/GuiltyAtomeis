#!/bin/bash
set -euo pipefail

echo "============================================"
echo "  GuiltyAtomeis V10 -- Linux Build"
echo "============================================"

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SRC_DIR"

echo "[1/3] Building atomeis_runtime..."
nim cpp -f -o:atomeis_runtime -d:release --app:console \
    --path:src \
    src/atomeis_runtime.nim

echo "[2/3] Building atmc..."
nim cpp -f -o:atmc -d:release --app:console \
    --path:src \
    src/atmc.nim

echo ""
echo "============================================"
echo "  Build Complete!"
echo "============================================"
echo "  atomeis_runtime  - Runtime stub"
echo "  atmc             - Compiler"
echo "============================================"
