# Neosaver

A quick macOS screensaver I made for my own personal use, to monitor my computer's performance (CPU/GPU usage and memory) and see active agents at a glance.

A native, dark macOS screensaver with live system-stat graphs, a dithered cloud field, translucent flip clock with a smaller non-flipping seconds display, live weather, and a standalone preview app. Built with AppKit and Apple’s ScreenSaver framework; **no web runtime or API key**.

<img width="1467" height="916" alt="Screenshot 2026-11-05 at 10 30 27 PM" src="https://github.com/user-attachments/assets/2a012266-de27-43ed-ad9c-4c5455dca51f" />


## Preview

Open **build/Neosaver Preview.app**, or run:

```sh
./scripts/preview.sh
```

The preview renders exactly the same view as the screensaver. **⌘F** toggles fullscreen; **Esc** leaves fullscreen. **⌘,** opens location settings. Close the window or use **⌘Q** to quit.

## Install

Download **Neosaver.saver.zip** directly from the [GitHub releases page](https://github.com/rawsab/neosaver/releases). Unzip it, open **Neosaver.saver**, and choose the current-user installation in macOS’s dialog. Then select **Neosaver** in **System Settings → Screen Saver**. Location settings are also available through **Screen Saver Options**.

For a local build, open **build/Neosaver.saver** or run `./scripts/install.sh`.

After rebuilding an already installed version, quit System Settings, open the new `.saver`, and replace the old installation. The installed bundle is a copy; rebuilding does not update it automatically.

The clock digits use **Geist Regular** from your local font installation, with tabular numerals. Hours, minutes, and seconds use a flat fill at 75% opacity. The AM/PM, date, weather, and location labels retain their monospaced font. If the Geist font is unavailable on another Mac, the clock falls back to the system digit font; the font file is not bundled.

## Features

- **Location, clock, and weather:** Set the city and coordinates in Location settings. The clock follows your Mac’s time zone; current weather comes from Open-Meteo.
- **Background:** On-device dithered clouds drift behind the clock, which flips each minute.
- **Upcoming prayer:** Shows the next prayer, start time, and countdown using prayer times from Aladhan.
- **Device status:** Shows Bluetooth, Wi-Fi, and battery status, with low-battery and unplug prompts.
- **AirPods battery:** Shows the last known earbuds and case percentages for the configured AirPods.
- **System statistics:** Shows live CPU, GPU, and memory readings with recent history graphs.
- **Agents:** Shows whether Claude, Codex, and Cursor are running.

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

---

Framework contract: [Apple ScreenSaverView](https://developer.apple.com/documentation/screensaver/screensaverview). Weather fields: [Open-Meteo documentation](https://open-meteo.com/en/docs).
