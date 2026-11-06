#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/build/module-cache"
xcrun swiftc -O -swift-version 5 -module-cache-path "$CLANG_MODULE_CACHE_PATH" -framework AppKit -framework ScreenSaver -framework Accelerate -framework CoreText -framework IOKit -framework CoreAudio -framework CoreWLAN -framework IOBluetooth -framework SystemConfiguration Sources/Model.swift Sources/CloudBackground.swift Sources/GlassSurface.swift Sources/ClockTypography.swift Sources/AgentStatus.swift Sources/SystemStats.swift Sources/StatsPanel.swift Sources/DeviceStatus.swift Sources/AirPodsBattery.swift Tests/main.swift -o build/neosaver-tests
./build/neosaver-tests
codesign --verify --strict build/Neosaver.saver
codesign --verify --strict 'build/Neosaver Preview.app'
plutil -lint build/Neosaver.saver/Contents/Info.plist 'build/Neosaver Preview.app/Contents/Info.plist'
