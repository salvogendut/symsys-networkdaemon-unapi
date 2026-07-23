#!/usr/bin/env bash
# Build UNAPISPK with openMSXnet, serve a local HTTP endpoint, and capture output.
set -euo pipefail
cd "$(dirname "$0")/.."

PORT="${MSX_SMOKE_PORT:-8080}"
SHOT_TIME="${MSX_SMOKE_SHOT:-120}"

MSX_UNAPI_TSR="${MSX_UNAPI_TSR:-../geobench/build/openmsxnet-test/UNAPINET.COM}" make msx-spike

python3 -m http.server "$PORT" --bind 127.0.0.1 &
srv=$!
trap 'kill "$srv" 2>/dev/null || true' EXIT
sleep 1

MSX_SHOTS="$SHOT_TIME" bash tools/run_msx.sh
