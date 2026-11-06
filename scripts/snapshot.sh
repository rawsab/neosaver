#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ARCH="$(uname -m)"
if [[ ! -f "build/preview-$ARCH" ]]; then ./scripts/build.sh; fi
"./build/preview-$ARCH" --snapshot "${1:-build/preview.png}"
