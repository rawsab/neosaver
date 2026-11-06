#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -d "build/Neosaver Preview.app" ]]; then ./scripts/build.sh; fi
open "build/Neosaver Preview.app"
