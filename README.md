# Neosaver

A native, dark macOS screensaver with live system-stat graphs, a dithered cloud field, translucent flip clock with a smaller non-flipping seconds display, live Celsius weather, and a standalone preview app. Built with AppKit and Apple’s ScreenSaver framework; no web runtime or API key.

## Preview

Open **build/Neosaver Preview.app**, or run:

```sh
./scripts/preview.sh
```

The preview renders exactly the same view as the screensaver. **⌘F** toggles fullscreen; **Esc** leaves fullscreen. **⌘,** opens location settings. Close the window or use **⌘Q** to quit.

## Install

Open **build/Neosaver.saver** (or run `./scripts/install.sh`) and choose the current-user installation in macOS’s dialog. Then select **Neosaver** in **System Settings → Screen Saver**. Location settings are also available through **Screen Saver Options**.

After rebuilding an already installed version, quit System Settings, open the new `.saver`, and replace the old installation. The installed bundle is a copy; rebuilding does not update it automatically.

The clock digits use **Geist Regular** from your local font installation, with tabular numerals. Hours, minutes, and seconds use a flat fill at 75% opacity. The AM/PM, date, weather, and location labels retain their monospaced font. If the Geist font is unavailable on another Mac, the clock falls back to the system digit font; the font file is not bundled.

## Location and weather

The initial location is **Waterloo, Ontario** (43.4643, −80.5204). Change the city label and latitude/longitude in Location settings. The clock always follows your Mac’s local time zone and uses 12-hour time with leading zeroes.

Current temperature and condition codes come from [Open-Meteo](https://open-meteo.com/), refreshed every 15 minutes. Only the configured coordinates are sent; GPS permission is not required. A cached reading is retained for up to one hour. Without a recent reading, the temperature displays **—°C** until a request succeeds. The cloud icon is a placeholder while weather is unavailable. Clear, partly cloudy, overcast, fog, rain, snow, and thunderstorm conditions have native monochrome icons. The provider’s day/night flag selects a moon for clear or mainly clear nights and a cloud-and-moon for partly cloudy nights, based on daylight at the configured location.

The background is deterministic procedural art generated on-device, with ordered dithering. The undithered clouds drift through slow, seamless cycles at 30 frames per second. Each frame samples their brightness through a stationary screen-space dither pattern, with a fixed grain layer. The clock stays fixed, with seconds digits staying fully visible and updating once per second. The seconds glass tile stays visible, and the main clock flips on minute changes.

## Upcoming prayer

Below the clock, an SF Symbols clock icon precedes the next prayer, its 12-hour start time, and a countdown in hours and minutes: FAJR at 5:43 AM • 1 hour 24 minutes. The bullet and countdown use 50% opacity. Partial minutes round up. The five daily prayers come from [Aladhan](https://aladhan.com/prayer-times-api), using the configured latitude/longitude, ISNA's North American calculation method, and Hanafi Asr. Prayer times use the Mac's time zone to match the clock.

Today's and tomorrow's schedules are cached locally, including tomorrow's Fajr after Isha. Location changes reload the schedule. Failed requests retry after five minutes; without a valid schedule, the line reads **Prayer times unavailable**. No API key or GPS permission is required.

## Device status

The top-right corner shows Bluetooth, Wi-Fi, and battery status followed by the battery percentage. Bluetooth and Wi-Fi refresh every five seconds in the background. Battery updates independently on macOS power-change notifications, with a one-second polling fallback, so connectivity checks cannot delay charging or unplugging updates.

- Bluetooth uses the standard rune, with a slash only when the controller explicitly reports off. Unavailable or uninitialized power readings use a dimmed regular rune; connected Bluetooth audio can still select an audio-device icon. A connected Bluetooth audio output whose name contains “AirPods” selects `airpods.gen4` (or `airpods` on older macOS); any other connected Bluetooth audio output selects `headphones`. Core Audio must report the device as alive with output streams; keyboards, mice, microphones without output, and disconnected devices do not trigger audio icons. AirPods take priority when multiple devices are connected. The basic Bluetooth rune is drawn natively because SF Symbols does not include it.
- Wi-Fi uses `wifi` only when its radio is on and its network link is active; otherwise it uses `wifi.slash`. This does not require reading the network name or requesting location access.
- The battery icon uses the nearest of 25%, 50%, 75%, or 100%. Active charging overrides it with `battery.100percent.bolt`. At 25% or below while not charging, **• CHARGE** appears after the percentage; at 80% or above, **• UNPLUG** appears. Both are followed by an `exclamationmark.triangle` icon; the prompt and icon use **#F94207**, and the status row shifts left to make room. A missing battery displays **—%** with a dimmed icon. Unavailable Bluetooth data also uses a dimmed icon. macOS may require Bluetooth access to report connected devices.

To read live status without opening a window, run `./build/preview-$(uname -m) --status-report`.

## AirPods battery

The bottom-right row displays **RAWSAB'S AIRPODS 4**, the `airpods.gen4` icon with the earbuds percentage, and `airpods.gen4.chargingcase.wireless.fill` with the case percentage. Older macOS versions use the corresponding available AirPods icons.

The screensaver reads macOS's Bluetooth report every 15 seconds in the background. It matches the configured device name (including curly apostrophes), or the supplied serial number when macOS reports it. A conflicting reported serial is rejected; the model is checked when no serial is available. The earbuds percentage uses the lower reported left/right charge, falling back to a combined reading. Missing readings retain the last reported percentage independently for the earbuds and case, including while disconnected or the case is asleep. These last known values are saved across restarts; **—%** appears only until that component has reported its first percentage. It does not wake or pair devices or invent battery levels.

## Live system statistics

The top-left panel uses **#F94207** for labels and compact CPU/GPU line graphs with downward-fading orange fills. Percentages and memory values use **#FFA88B** at 80% opacity. The memory breakdown includes compressed, cached, and swap usage. Weather and location share a centered line above the clock: weather icon, Celsius temperature, location icon, and uppercase city name.

- Samples once per second on a background queue, independently of the 30 fps cloud animation.
- CPU usage is normalized to total system capacity (0–100%), calculated from Mach CPU tick differences.
- GPU usage comes from the driver's IORegistry performance statistics. On a multi-GPU Mac, the busiest available GPU is shown.
- Memory excludes reclaimable cache from used memory, with compressed, cached, and swap values shown separately. Labels use the familiar 1024-based GB convention (16 GiB displays as 16 GB).
- Graph history covers up to the last two minutes of the current session. Each graph stretches its available readings across the full width from startup; a single reading appears as a flat line until more arrive. It does not collect while the screensaver is stopped.
- Missing or restricted metrics show **—**, rather than a fabricated zero. CPU needs two readings, so its first value appears after about a second. Driver counter access depends on the Mac and host permissions.

The normal preview has been verified with live CPU, GPU, memory, and swap readings. The restricted command-line environment may deny swap access, in which case the swap label shows a dash. No admin helper or extra monitoring application is used.

Reference snapshots deliberately use sample stats and weather for reproducible visual checks; the regular preview and screensaver use live readings. To inspect live metrics from the build executable:

```sh
./build/preview-$(uname -m) --metrics-report
```

## Agents

Below memory, an **AGENTS** section lists Claude, Codex, and Cursor. **ACTIVE** means the desktop application or a native executable named `claude`, `codex`, or `cursor` is running; it does not indicate whether an AI request is in progress. Background crash reporters and Electron helpers do not count as running agents. Detection uses macOS running-application bundle identifiers and main application or native CLI executable paths and refreshes once per second with system statistics. If the host restricts process enumeration, running-application detection still works.

Each agent has a `circle.fill` icon when active or a `circle` icon when inactive, matching the name’s opacity. The heading and active names are white. Status suffixes and inactive names use white at 50% opacity. The heading-to-list spacing matches MEMORY-to-Compressed.

To inspect detected states without opening a window, run `./build/preview-$(uname -m) --agents-report`.

## Build and verify

Requires Xcode / the macOS SDK. Targets macOS 13 or later, with universal Apple silicon and Intel binaries.

```sh
./scripts/build.sh
./scripts/test.sh
```

Builds both bundles in `build/` and signs them locally with an ad hoc signature. These are local development builds, not notarized releases for distribution.

Generate a reference image with a fixed clock and sample weather:

```sh
./scripts/snapshot.sh
```

The test suite checks midnight/noon/year rollovers, weather decoding, condition icons, and loading and starting the actual `.saver` bundle. System Settings selection and the macOS idle activation lifecycle should also be checked on the target Mac.

## Files

- `Sources/ClockSceneView.swift`: shared clock, glass cards, flip animation, and layout.
- `Sources/GlassSurface.swift`: live backdrop blur for the shadow-free clock cards, with a uniform smoked tint. The complete backdrop-and-tint surface is composited at 70% opacity so the original texture remains visible.
- `Sources/CloudBackground.swift`: cached procedural cloud texture.
- `Sources/SystemStats.swift`: native CPU/GPU/memory readers, one-second sampling, and bounded history.
- `Sources/StatsPanel.swift`: orange typography and axis-free gradient-filled graphs.
- `Sources/Model.swift`: time formatting, location storage, and weather service.
- `Sources/NeosaverView.swift`: native screensaver entry point.
- `Sources/PreviewMain.swift`: standalone preview and fullscreen controls.
- `Sources/SettingsController.swift`: location options shared by both hosts.

Framework contract: [Apple ScreenSaverView](https://developer.apple.com/documentation/screensaver/screensaverview). Weather fields: [Open-Meteo documentation](https://open-meteo.com/en/docs).
