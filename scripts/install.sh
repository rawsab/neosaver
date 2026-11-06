#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -d build/Neosaver.saver ]]; then ./scripts/build.sh; fi
# macOS presents its standard screensaver installation dialog.
open build/Neosaver.saver
