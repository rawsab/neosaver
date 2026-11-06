#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/build/module-cache"
COMMON=(Sources/Model.swift Sources/CloudBackground.swift Sources/ClockSceneView.swift Sources/SettingsController.swift Sources/GlassSurface.swift Sources/ClockTypography.swift Sources/AgentStatus.swift Sources/SystemStats.swift Sources/StatsPanel.swift Sources/DeviceStatus.swift Sources/AirPodsBattery.swift)
FLAGS=(-O -swift-version 5 -module-cache-path "$CLANG_MODULE_CACHE_PATH" -framework AppKit -framework ScreenSaver -framework QuartzCore -framework Accelerate -framework CoreText -framework IOKit -framework CoreAudio -framework CoreWLAN -framework IOBluetooth -framework SystemConfiguration)
SAVER="build/Neosaver.saver"
APP="build/Neosaver Preview.app"
mkdir -p "$SAVER/Contents/MacOS" "$APP/Contents/MacOS"
# Universal output runs natively on both Apple silicon and Intel Macs.
for ARCH in arm64 x86_64; do
  xcrun swiftc "${FLAGS[@]}" -target "$ARCH-apple-macosx13.0" -emit-library -module-name Neosaver "${COMMON[@]}" Sources/NeosaverView.swift -o "build/saver-$ARCH"
  cp Sources/PreviewMain.swift build/main.swift
  xcrun swiftc "${FLAGS[@]}" -target "$ARCH-apple-macosx13.0" -module-name NeosaverPreview "${COMMON[@]}" build/main.swift -o "build/preview-$ARCH"
done
lipo -create build/saver-arm64 build/saver-x86_64 -output "$SAVER/Contents/MacOS/Neosaver"
lipo -create build/preview-arm64 build/preview-x86_64 -output "$APP/Contents/MacOS/NeosaverPreview"
cat > "$SAVER/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.neosaver.screensaver</string>
<key>CFBundleName</key><string>Neosaver</string>
<key>CFBundleDisplayName</key><string>Neosaver</string>
<key>CFBundleExecutable</key><string>Neosaver</string>
<key>CFBundlePackageType</key><string>BNDL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>NSBluetoothAlwaysUsageDescription</key><string>Neosaver displays Bluetooth power and connected-device status.</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSPrincipalClass</key><string>NeosaverView</string>
</dict></plist>
PLIST
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.neosaver.preview</string>
<key>CFBundleName</key><string>Neosaver Preview</string>
<key>CFBundleExecutable</key><string>NeosaverPreview</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>NSBluetoothAlwaysUsageDescription</key><string>Neosaver displays Bluetooth power and connected-device status.</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$SAVER"
codesign --force --sign - "$APP"
printf 'Built:\n  %s/%s\n  %s/%s\n' "$PWD" "$SAVER" "$PWD" "$APP"
