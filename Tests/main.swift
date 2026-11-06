import AppKit
import CoreAudio
import IOBluetooth
import ScreenSaver

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}
let cpuBaseline = CPUCounters(user: 100, system: 100, idle: 800, nice: 0)
let cpuNext = CPUCounters(user: 105, system: 105, idle: 890, nice: 0)
check(cpuNext.usage(since: cpuBaseline) == 10, "CPU is normalized to total system capacity")
check(cpuBaseline.usage(since: cpuBaseline) == nil, "CPU needs a nonzero sampling interval")
let wrapped = CPUCounters(user: 4, system: 0, idle: 90, nice: 0)
let beforeWrap = CPUCounters(user: UInt32.max - 5, system: 0, idle: 0, nice: 0)
check(wrapped.usage(since: beforeWrap) == 10, "CPU counters tolerate wraparound")
check(SystemStatsReader.gpuUsage(in: ["Device Utilization %": 0]) == 0, "A real idle GPU stays zero")
check(SystemStatsReader.gpuUsage(in: ["GPU Activity(%)": 18]) == 18, "GPU key fallback")
check(SystemStatsReader.gpuUsage(in: [:]) == nil, "Missing GPU data never becomes zero")
check(SystemStatsReader.gpuUsage(in: ["Device Utilization %": 500]) == nil, "Invalid GPU readings are rejected")
var vm = vm_statistics64_data_t()
vm.active_count = 100; vm.inactive_count = 40; vm.speculative_count = 5; vm.wire_count = 20
vm.compressor_page_count = 10; vm.purgeable_count = 5; vm.external_page_count = 25
let memory = MemorySample.from(vm, pageSize: 16384, total: 200 * 16384, swap: nil)
check(memory.used == 145 * 16384 && memory.cached == 30 * 16384 && memory.compressed == 10 * 16384, "Memory uses the actual page size and excludes reclaimable cache")
check(memory.swap == nil, "Unavailable swap stays unavailable")
check(MemorySample.gb(16 * 1_073_741_824, precision: 0) == "16", "Memory labels preserve 16 GB convention")
var metricsHistory = StatsHistory()
for second in 0..<130 { metricsHistory.append(SystemSample(time: Double(second), cpu: 9, gpu: 18, memory: nil)) }
check(metricsHistory.samples.count == 120 && metricsHistory.samples.first?.time == 10, "Stats history stays bounded to two minutes")
metricsHistory.append(SystemSample(time: 1000, cpu: nil, gpu: nil, memory: nil))
check(metricsHistory.samples.count == 1, "Old graph data expires across long gaps")
let liveMonitor = SystemStatsMonitor()
var metricsCallbacks = 0
liveMonitor.onChange = { metricsCallbacks += 1 }
liveMonitor.start(); liveMonitor.start()
RunLoop.current.run(until: Date().addingTimeInterval(1.25))
check(metricsCallbacks >= 2, "Live metrics sample once per second")
check(liveMonitor.history.samples.last?.cpu != nil && liveMonitor.history.samples.last?.memory != nil, "Mach CPU and memory counters are readable")
liveMonitor.stop()
let stoppedCallbacks = metricsCallbacks
RunLoop.current.run(until: Date().addingTimeInterval(1.1))
check(metricsCallbacks == stoppedCallbacks, "Stats sampling stops with the screensaver")
print("PASS: CPU deltas/wrap, GPU availability, memory accounting, bounded history, live sampling/lifecycle")
let localFont = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Fonts/Geist-VariableFont_wght.ttf")
if FileManager.default.fileExists(atPath: localFont.path) {
    check(ClockTypography.digits(ofSize: 94).fontName == "Geist-Regular", "Clock uses the installed Geist Regular face")
    check(ClockTypography.digits(ofSize: 30).fontName == "Geist-Regular", "Seconds use the same Geist face")
    print("Clock font: Geist Regular")
}
let utc = TimeZone(secondsFromGMT: 0)!
let parser = ISO8601DateFormatter()
let cases: [(String, String, String, String, String, String)] = [
    ("2026-11-05T00:00:00Z", "12", "00", "AM", "THU", "NOV 5"),
    ("2026-11-05T12:00:00Z", "12", "00", "PM", "THU", "NOV 5"),
    ("2026-11-05T14:35:00Z", "02", "35", "PM", "THU", "NOV 5"),
    ("2026-12-31T23:59:00Z", "11", "59", "PM", "THU", "DEC 31"),
    ("2027-01-01T00:00:00Z", "12", "00", "AM", "FRI", "JAN 1")
]
for (iso, hour, minute, period, weekday, date) in cases {
    let value = ClockText(date: parser.date(from: iso)!, timeZone: utc)
    check(value.hour == hour && value.minute == minute && value.period == period && value.weekday == weekday && value.date == date, "Clock rollover: \(iso)")
}
let beforeMinute = ClockText(date: parser.date(from: "2026-11-05T14:35:59Z")!, timeZone: utc)
let afterMinute = ClockText(date: parser.date(from: "2026-11-05T14:36:00Z")!, timeZone: utc)
check(beforeMinute.second == "59" && beforeMinute.minute == "35", "Seconds before minute rollover")
check(afterMinute.second == "00" && afterMinute.minute == "36", "Seconds reset at minute rollover")
let payload = Data(#"{"current":{"temperature_2m":-3.4,"weather_code":63,"is_day":1}}"#.utf8)
let reading = try WeatherReading.decode(payload)
check(reading.temperature == -3.4 && reading.symbol == "cloud.rain", "Celsius weather decoding")
check(WeatherReading.symbol(for: 0) == "sun.max", "Clear weather")
check(WeatherReading.symbol(for: 3) == "cloud", "Cloudy weather")
check(WeatherReading.symbol(for: 75) == "cloud.snow", "Snow weather")
check(WeatherReading.symbol(for: 95) == "cloud.bolt.rain", "Thunder weather")
check(WeatherReading.symbol(for: 0, isDay: false) == "moon", "Clear nights use a moon")
check(WeatherReading.symbol(for: 1, isDay: false) == "moon", "Mainly clear nights use a moon")
check(WeatherReading.symbol(for: 2, isDay: false) == "cloud.moon", "Partly cloudy nights keep the cloud")
check(WeatherReading.symbol(for: 3, isDay: false) == "cloud", "Overcast nights keep the cloud")
check(WeatherReading.symbol(for: 63, isDay: false) == "cloud.rain", "Rainy nights keep the rain icon")
let nightPayload = Data(#"{"current":{"temperature_2m":8,"weather_code":0,"is_day":0}}"#.utf8)
let nightReading = try WeatherReading.decode(nightPayload)
check(!nightReading.isDay && nightReading.symbol == "moon", "Provider daylight flag controls the icon")
let cachedNight = try JSONDecoder().decode(WeatherReading.self, from: JSONEncoder().encode(nightReading))
check(cachedNight.symbol == "moon", "Cached weather preserves nighttime state")
check((try? WeatherReading.decode(Data("{}".utf8))) == nil, "Malformed weather is rejected")
// Real timestamp offsets keep countdowns correct across midnight and DST changes.
let prayerPayload = Data(#"{"code":200,"data":{"date":{"gregorian":{"date":"05-11-2026"}},"timings":{"Fajr":"2026-11-05T05:43:00-05:00","Sunrise":"2026-11-05T07:02:00-05:00","Dhuhr":"2026-11-05T12:05:00-05:00","Asr":"2026-11-05T15:15:00-05:00","Maghrib":"2026-11-05T17:05:00-05:00","Isha":"2026-11-05T18:27:00-05:00"}}}"#.utf8)
let prayerDay = try PrayerDay.decode(prayerPayload)
let toronto = TimeZone(identifier: "America/Toronto")!
let beforeFajr = parser.date(from: "2026-11-05T10:42:59Z")!
let fajr = PrayerTime.next(in: prayerDay.times, now: beforeFajr)!
check(prayerDay.key == "05-11-2026" && prayerDay.times.count == 5, "Decode the five prayers, excluding sunrise")
check(fajr.line(now: beforeFajr, timeZone: toronto) == "FAJR at 5:43 AM • 0 hours 1 minute", "Prayer time uses 12-hour formatting and a live countdown")
check(fajr.line(now: beforeFajr.addingTimeInterval(0.25), timeZone: toronto).hasSuffix("0 hours 1 minute"), "Countdown rounds a partial minute up until the prayer starts")
check(PrayerTime.next(in: prayerDay.times, now: fajr.date)?.name == "Dhuhr", "Switch to the next prayer at the exact start time")
let tomorrowFajr = PrayerTime(name: "Fajr", date: parser.date(from: "2026-11-06T10:44:00Z")!)
let afterIsha = parser.date(from: "2026-11-06T00:00:00Z")!
check(PrayerTime.next(in: prayerDay.times + [tomorrowFajr], now: afterIsha)?.date == tomorrowFajr.date, "After Isha, select tomorrow's Fajr")
check(tomorrowFajr.line(now: afterIsha, timeZone: toronto) == "FAJR at 5:44 AM • 10 hours 44 minutes", "Countdown spans midnight")
check(PrayerTime.next(in: prayerDay.times, now: afterIsha) == nil, "Expired prayer times are never displayed")
let dstPrayer = PrayerTime(name: "Fajr", date: parser.date(from: "2026-11-01T06:30:00-05:00")!)
check(dstPrayer.line(now: parser.date(from: "2026-11-01T00:30:00-04:00")!, timeZone: toronto).hasSuffix("7 hours 0 minutes"), "DST countdown uses elapsed time rather than wall-clock subtraction")
check(PrayerDay.key(for: parser.date(from: "2027-01-01T01:00:00Z")!, timeZone: toronto) == "31-12-2026", "API dates follow the clock time zone at year rollover")
check((try? PrayerDay.decode(Data("{}".utf8))) == nil, "Malformed prayer data is rejected")
let incompletePrayer = Data(String(decoding: prayerPayload, as: UTF8.self).replacingOccurrences(of: "2026-11-05T05:43:00-05:00", with: "invalid").utf8)
check((try? PrayerDay.decode(incompletePrayer)) == nil, "Incomplete prayer schedules are rejected")
let prayerURL = URLComponents(url: PrayerService.url(day: "05-11-2026", settings: .defaults, timeZone: toronto), resolvingAgainstBaseURL: false)!
let prayerQuery = Dictionary(uniqueKeysWithValues: prayerURL.queryItems!.map { ($0.name, $0.value!) })
check(prayerQuery["school"] == "1" && prayerQuery["method"] == "2", "Requests use Hanafi Asr and ISNA calculations")
check(prayerQuery["iso8601"] == "true" && prayerQuery["timezonestring"] == "America/Toronto", "Requests use offset timestamps in the clock time zone")
print("PASS: prayer decoding, Hanafi request, countdown, exact prayer rollover, next-day Fajr, DST, invalid schedules")

let batteryDescription: [String: Any] = ["Type": "InternalBattery", "Current Capacity": 84, "Max Capacity": 100, "Is Charging": false]
let batteryStatus = BatteryStatus.from(batteryDescription)!
check(batteryStatus.percentage == 84 && batteryStatus.symbol == "battery.75percent", "Battery reads capacity and chooses the nearest icon")
for (percentage, level) in [(0, 25), (37, 25), (38, 50), (62, 50), (63, 75), (87, 75), (88, 100), (100, 100)] {
    check(BatteryStatus(percentage: percentage, isCharging: false).symbol == "battery.\(level)percent", "Nearest battery icon at \(percentage)%")
}
check(BatteryStatus(percentage: 12, isCharging: true).symbol == "battery.100percent.bolt", "Charging overrides the battery level icon")
check(BatteryStatus.from(["Type": "UPS", "Current Capacity": 100, "Max Capacity": 100]) == nil, "External power sources are not the Mac's battery")
check(BatteryStatus.from(["Type": "InternalBattery", "Current Capacity": 1, "Max Capacity": 0]) == nil, "Invalid capacity is unavailable")
for (percentage, expected) in [(0, "• CHARGE"), (25, "• CHARGE"), (26, nil), (79, nil), (80, "• UNPLUG"), (85, "• UNPLUG"), (100, "• UNPLUG")] as [(Int, String?)] {
    for charging in [false, true] {
        let status = DeviceStatus(bluetooth: .on, wifiConnected: true,
                                  battery: BatteryStatus(percentage: percentage, isCharging: charging))
        let expectedPrompt = (percentage <= 25 && charging) || (percentage >= 80 && !charging) ? nil : expected
        check(status.batteryPrompt == expectedPrompt, "Battery prompt threshold at \(percentage)% while charging=\(charging)")
    }
}
check(DeviceStatus.unavailable.batteryPrompt == nil, "Missing battery data does not show a charging prompt")
check(DeviceStatus.unavailable.batteryText == "—%", "Missing battery data never invents a percentage")
check(BluetoothStatus.poweredOn(controllerState: kBluetoothHCIPowerStateON) == true, "Explicit Bluetooth on is recognized")
check(BluetoothStatus.poweredOn(controllerState: kBluetoothHCIPowerStateOFF) == false, "Only explicit Bluetooth off maps to off")
check(BluetoothStatus.poweredOn(controllerState: BluetoothHCIPowerState(rawValue: 255)) == nil, "Unavailable controller state 255 is never treated as Bluetooth off")
check(BluetoothStatus.poweredOn(controllerState: nil) == nil, "Missing controller state remains unknown")
let bluetoothHeadphones = AudioDeviceStatus(name: "Headphones", transport: kAudioDeviceTransportTypeBluetooth, isAlive: true, hasOutputStreams: true)
let bluetoothAirpods = AudioDeviceStatus(name: "My AIRPODS", transport: kAudioDeviceTransportTypeBluetoothLE, isAlive: true, hasOutputStreams: true)
check(BluetoothStatus.resolve(poweredOn: false, audioDevices: [bluetoothAirpods]) == .off, "Bluetooth off overrides stale audio device data")
check(BluetoothStatus.resolve(poweredOn: true, audioDevices: []) == .on, "Bluetooth on without audio outputs")
check(BluetoothStatus.resolve(poweredOn: true, audioDevices: [bluetoothHeadphones]) == .device, "A connected Bluetooth audio output uses headphones")
check(BluetoothStatus.resolve(poweredOn: true, audioDevices: [bluetoothHeadphones, bluetoothAirpods]) == .airpods, "Connected AirPods audio takes priority")
let nonBluetoothOutputs = [
    AudioDeviceStatus(name: "Keyboard", transport: kAudioDeviceTransportTypeBluetooth, isAlive: true, hasOutputStreams: false),
    AudioDeviceStatus(name: "Microphone", transport: kAudioDeviceTransportTypeBluetooth, isAlive: true, hasOutputStreams: false),
    AudioDeviceStatus(name: "Old AirPods", transport: kAudioDeviceTransportTypeBluetooth, isAlive: false, hasOutputStreams: true),
    AudioDeviceStatus(name: "USB headphones", transport: kAudioDeviceTransportTypeUSB, isAlive: true, hasOutputStreams: true),
    AudioDeviceStatus(name: "Mac speakers", transport: kAudioDeviceTransportTypeBuiltIn, isAlive: true, hasOutputStreams: true)
]
check(BluetoothStatus.resolve(poweredOn: true, audioDevices: nonBluetoothOutputs) == .on, "Keyboards, microphones, disconnected devices, and wired outputs do not trigger a Bluetooth audio icon")
check(BluetoothStatus.resolve(poweredOn: nil, audioDevices: []) == .unavailable, "An unreadable controller uses the dimmed regular Bluetooth icon")
check(BluetoothStatus.resolve(poweredOn: nil, audioDevices: [bluetoothAirpods]) == .airpods, "Connected AirPods remain detectable when controller power cannot be read")
check(BluetoothStatus.resolve(poweredOn: nil, audioDevices: [bluetoothHeadphones]) == .device, "Connected Bluetooth audio is positive evidence even without a controller reading")
check(DeviceStatus(bluetooth: .on, wifiConnected: true, battery: batteryStatus).wifiSymbol == "wifi", "Connected Wi-Fi icon")
check(DeviceStatus.unavailable.wifiSymbol == "wifi.slash", "Disconnected Wi-Fi icon")
for symbol in ["wifi", "wifi.slash", "headphones", "airpods", "battery.100percent", "battery.75percent", "battery.50percent", "battery.25percent", "battery.100percent.bolt"] {
    check(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "Status symbol available: \(symbol)")
}
print("PASS: battery capacity, nearest icon boundaries, charging, Bluetooth power/device priority, Wi-Fi state, status symbols")

// A blocked Bluetooth read must not freeze power updates or overwrite a newer charge state.
let batteryLock = NSLock()
var simulatedCharging = false
let powerMonitor = BatteryMonitor(readBattery: {
    batteryLock.lock(); defer { batteryLock.unlock() }
    return BatteryStatus(percentage: 24, isCharging: simulatedCharging)
})
let connectivityGate = DispatchSemaphore(value: 0)
let changingDeviceStatus = DeviceStatusMonitor(readConnectivity: {
    _ = connectivityGate.wait(timeout: .now() + 3)
    return DeviceStatus(bluetooth: .on, wifiConnected: true, battery: BatteryStatus(percentage: 24, isCharging: false))
}, batteryMonitor: powerMonitor)
var deviceCallbacks = 0
changingDeviceStatus.onChange = { deviceCallbacks += 1 }
changingDeviceStatus.start()
RunLoop.current.run(until: Date().addingTimeInterval(0.15))
check(changingDeviceStatus.status.batterySymbol == "battery.25percent", "Initial battery arrives independently of blocked connectivity")
batteryLock.lock(); simulatedCharging = true; batteryLock.unlock()
powerMonitor.refresh()
RunLoop.current.run(until: Date().addingTimeInterval(0.15))
check(changingDeviceStatus.status.batterySymbol == "battery.100percent.bolt", "Plugging in updates the icon without restarting")
connectivityGate.signal()
RunLoop.current.run(until: Date().addingTimeInterval(0.15))
check(changingDeviceStatus.status.wifiConnected, "Connectivity updates eventually arrive")
check(changingDeviceStatus.status.batterySymbol == "battery.100percent.bolt", "A stale connectivity snapshot cannot undo the charging update")
batteryLock.lock(); simulatedCharging = false; batteryLock.unlock()
powerMonitor.refresh()
RunLoop.current.run(until: Date().addingTimeInterval(0.15))
check(changingDeviceStatus.status.batterySymbol == "battery.25percent", "Unplugging restores the level icon without restarting")
changingDeviceStatus.stop()
let stoppedDeviceCallbacks = deviceCallbacks
powerMonitor.refresh()
RunLoop.current.run(until: Date().addingTimeInterval(0.15))
check(deviceCallbacks == stoppedDeviceCallbacks, "Power monitoring stops with the screensaver")
print("PASS: live plug/unplug state changes, battery independence from connectivity, stale-result protection, power lifecycle")

let desktopAgents = AgentStatusReader.statuses(bundleIdentifiers: [AgentKind.codex.bundleIdentifier], executablePaths: [])
check(desktopAgents.map(\.agent) == [.claude, .codex, .cursor], "Agent list order is Claude, Codex, Cursor")
check(desktopAgents.map(\.isRunning) == [false, true, false], "Desktop bundle identifiers detect the running agent")
let cliAgents = AgentStatusReader.statuses(bundleIdentifiers: [], executablePaths: ["/opt/homebrew/bin/claude", "/usr/local/bin/codex", "/Applications/Cursor.app/Contents/MacOS/Cursor"])
check(cliAgents.allSatisfy(\.isRunning), "Native CLI and desktop executable paths detect running agents")
check(AgentKind.codex.matchesExecutable("/Applications/Codex.app/Contents/MacOS/ChatGPT"), "Codex desktop's executable can have a different name")
let helperPaths = AgentKind.allCases.flatMap { agent in
    ["/Applications/\(agent.name).app/Contents/Frameworks/Electron Framework.framework/Versions/A/Helpers/chrome_crashpad_handler",
     "/Applications/\(agent.name).app/Contents/Frameworks/\(agent.name) Helper.app/Contents/MacOS/\(agent.name) Helper"]
}
let helperOnlyAgents = AgentStatusReader.statuses(bundleIdentifiers: [], executablePaths: helperPaths)
check(helperOnlyAgents.allSatisfy { !$0.isRunning }, "Lingering crash reporters and Electron helpers do not mark agents active")
let openCursor = AgentStatusReader.statuses(bundleIdentifiers: [AgentKind.cursor.bundleIdentifier], executablePaths: helperPaths)
check(openCursor.first(where: { $0.agent == .cursor })?.isRunning == true, "An open Cursor app remains active even when helpers also exist")
let unrelatedAgents = AgentStatusReader.statuses(bundleIdentifiers: ["com.example.codex-helper"], executablePaths: ["/tmp/codex-notes/node", "/usr/local/bin/claude-helper", "/tmp/cursor.log"])
check(unrelatedAgents.allSatisfy { !$0.isRunning }, "Partial names and unrelated paths do not mark agents active")
for running in [false, true] {
    let agentLine = StatsPanel.agentText(AgentStatus(agent: .claude, isRunning: running))
    check(agentLine.string == "Claude • \(running ? "ACTIVE" : "INACTIVE")", "Agent label reflects process state")
    let nameColor = agentLine.attribute(.foregroundColor, at: 0, effectiveRange: nil) as! NSColor
    let suffixColor = agentLine.attribute(.foregroundColor, at: 7, effectiveRange: nil) as! NSColor
    check(nameColor.alphaComponent == (running ? 1 : 0.5), "Inactive agent names are dimmed")
    check(suffixColor.alphaComponent == 0.5, "Both agent status suffixes use 50% opacity")
}
print("PASS: running agent bundle/CLI detection, exact matching, list order, active/inactive typography")

func airpodsReport(name: String = "Rawsab’s AirPods 4", info: [String: Any], connected: Bool = true) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["SPBluetoothDataType": [[connected ? "device_connected" : "device_not_connected": [[name: info]]]]])
}
let airpodsLevels = AirPodsBatteryStatus.decode(try airpodsReport(info: ["device_batteryLevelLeft": "85%", "device_batteryLevelRight": "72%", "device_batteryLevelCase": "41%", "device_modelNumber": "A3055"]))
check(airpodsLevels.earbuds == 72 && airpodsLevels.chargingCase == 41, "AirPods use the lower earbud level and separate case level")
let mainAirpods = AirPodsBatteryStatus.decode(try airpodsReport(info: ["device_batteryLevelMain": "100%", "device_batteryLevelCase": 0]))
check(mainAirpods.earbuds == 100 && mainAirpods.chargingCase == 0, "Combined readings and a genuine 0% case are supported")
let missingCase = AirPodsBatteryStatus.decode(try airpodsReport(info: ["device_batteryLevelLeft": "50%", "device_batteryLevelCase": "Unknown"]))
check(missingCase.earbudsText == "50%" && missingCase.caseText == "—%", "An unreported case level stays unavailable")
let wrongDevice = AirPodsBatteryStatus.decode(try airpodsReport(name: "Someone else's AirPods 4", info: ["device_batteryLevelMain": "99%"]))
check(wrongDevice.earbuds == nil, "Other people's AirPods are not displayed")
let wrongSerial = AirPodsBatteryStatus.decode(try airpodsReport(info: ["device_serialNumber": "OTHER-DEVICE", "device_batteryLevelMain": "99%"]))
check(wrongSerial.earbuds == nil, "A reported conflicting serial number rejects the device")
let renamedAirpods = AirPodsBatteryStatus.decode(try airpodsReport(name: "Renamed earbuds", info: ["device_serialNumber": "C2CDX4JY6G", "device_batteryLevelMain": "60%"]))
check(renamedAirpods.earbuds == 60, "A reported matching serial number identifies renamed AirPods")
let wrongModel = AirPodsBatteryStatus.decode(try airpodsReport(info: ["device_modelNumber": "A9999", "device_batteryLevelMain": "99%"]))
check(wrongModel.earbuds == nil, "A conflicting reported model is rejected")
let disconnectedAirpods = AirPodsBatteryStatus.decode(try airpodsReport(info: ["device_batteryLevelMain": "99%"], connected: false))
check(disconnectedAirpods.earbuds == nil, "Disconnected device data is never displayed as a current reading")
let invalidAirpods = AirPodsBatteryStatus.decode(try airpodsReport(info: ["device_batteryLevelMain": 255, "device_batteryLevelCase": -1]))
check(invalidAirpods.earbudsText == "—%" && invalidAirpods.caseText == "—%", "Invalid accessory battery values stay unavailable")
check(AirPodsBatteryStatus.decode(Data("{}".utf8)).earbuds == nil, "Malformed Bluetooth reports are handled")
let retainedCase = missingCase.retainingMissing(from: airpodsLevels)
check(retainedCase.earbuds == 50 && retainedCase.chargingCase == 41, "Missing case data retains only the last known case percentage")
let retainedEarbuds = AirPodsBatteryStatus(earbuds: nil, chargingCase: 32).retainingMissing(from: retainedCase)
check(retainedEarbuds.earbuds == 50 && retainedEarbuds.chargingCase == 32, "Missing earbud data retains the last known earbud percentage")
check(AirPodsBatteryStatus.unavailable.retainingMissing(from: retainedEarbuds) == retainedEarbuds, "Unavailable reports preserve both known percentages")
check(mainAirpods.retainingMissing(from: retainedEarbuds).chargingCase == 0, "A genuine zero reading replaces an older percentage")
let savedAirpods = try JSONDecoder().decode(AirPodsBatteryStatus.self, from: JSONEncoder().encode(retainedEarbuds))
check(savedAirpods == retainedEarbuds, "Last known battery readings survive cache serialization")
check(AirPodsBatteryStatus.unavailable.retainingMissing(from: .unavailable).caseText == "—%", "A never-reported value stays unavailable")
print("PASS: AirPods identity, individual/combined levels, case readings, missing-reading retention and cache serialization")

let textureSize = NSSize(width: 1600, height: 1000)
for viewport in [NSRect(x: 0, y: 0, width: 1440, height: 900),
                 NSRect(x: 0, y: 0, width: 2560, height: 1080),
                 NSRect(x: 0, y: 0, width: 900, height: 1440)] {
    for second in stride(from: 0.0, through: CloudBackground.motionCycleDuration, by: 0.5) {
        check(CloudBackground.imageRect(in: viewport, imageSize: textureSize, elapsed: second).contains(viewport), "Moving background must cover every edge")
    }
    let start = CloudBackground.imageRect(in: viewport, imageSize: textureSize, elapsed: 0)
    let later = CloudBackground.imageRect(in: viewport, imageSize: textureSize, elapsed: 5)
    check(abs(later.minX - start.minX) > 10, "Background visibly drifts over five seconds")
    let loop = CloudBackground.imageRect(in: viewport, imageSize: textureSize, elapsed: CloudBackground.motionCycleDuration)
    check(abs(loop.minX - start.minX) < 0.0001 && abs(loop.minY - start.minY) < 0.0001, "Background cycle is seamless")
}
let uniform = CloudBackground.Renderer(light: [Float](repeating: 0.18, count: 64 * 40), width: 64, height: 40)
let stationaryStart = uniform.frame(width: 128, height: 80, elapsed: 0).dataProvider!.data! as Data
let stationaryLater = uniform.frame(width: 128, height: 80, elapsed: 35).dataProvider!.data! as Data
check(stationaryStart == stationaryLater, "Dither and grain must stay fixed as the sampled cloud coordinates move")
let clouds = CloudBackground.Renderer()
let cloudStart = clouds.frame(width: 320, height: 200, elapsed: 0).dataProvider!.data! as Data
let cloudLater = clouds.frame(width: 320, height: 200, elapsed: 5).dataProvider!.data! as Data
check(cloudStart != cloudLater, "Moving luminance must update the dithered output")
let cloudRepeat = clouds.frame(width: 320, height: 200, elapsed: 0).dataProvider!.data! as Data
check(cloudStart == cloudRepeat, "Dithered rendering is deterministic")
let cloudLoop = clouds.frame(width: 320, height: 200, elapsed: CloudBackground.motionCycleDuration).dataProvider!.data! as Data
check(cloudStart == cloudLoop, "Re-dithered animation loops without a jump")
_ = clouds.frame(width: 1440, height: 900, elapsed: 0)
let renderStart = Date()
for frame in 1...12 { _ = clouds.frame(width: 1440, height: 900, elapsed: Double(frame) / 30) }
print(String(format: "Background render: %.1f ms/frame at 1440×900", Date().timeIntervalSince(renderStart) * 1000 / 12))
// Check the glass processes the pixels behind it, rather than drawing an opaque tint.
func checkerImage() -> CGImage {
    var bytes = [UInt8](repeating: 255, count: 128 * 128 * 4)
    for y in 0..<128 {
        for x in 0..<128 {
            let value: UInt8 = ((x / 4 + y / 4) % 2 == 0) ? 0 : 255
            let offset = (y * 128 + x) * 4
            bytes[offset] = value; bytes[offset + 1] = value; bytes[offset + 2] = value
        }
    }
    return CGImage(width: 128, height: 128, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: 128 * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
        provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil,
        shouldInterpolate: false, intent: .defaultIntent)!
}
func redValues(_ image: CGImage) -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    pixels.withUnsafeMutableBytes { bytes in
        let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return stride(from: 0, to: pixels.count, by: 4).map { pixels[$0] }
}
let glass = GlassSurface()
let frosted = glass.backdrop(from: checkerImage(), viewport: NSRect(x: 0, y: 0, width: 128, height: 128),
    cardRect: NSRect(x: 32, y: 32, width: 64, height: 64), blurRadius: 12)
check(frosted != nil, "Glass backdrop renders successfully")
let samples = redValues(frosted!)
check(Int(samples.max()!) - Int(samples.min()!) < 30, "Backdrop blur smooths high-frequency detail")
check(samples.allSatisfy { $0 > 40 && $0 < 235 }, "Blur blends the checkerboard behind the glass")
// Regression: translucent tint over an opaque blur still looks solid. Opacity must
// apply to the entire surface, preserving detail from the original background.
let cardContext = CGContext(data: nil, width: 128, height: 128, bitsPerComponent: 8,
    bytesPerRow: 128 * 4, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
cardContext.draw(checkerImage(), in: CGRect(x: 0, y: 0, width: 128, height: 128))
glass.drawBackground(blurred: frosted, in: CGRect(x: 32, y: 32, width: 64, height: 64), context: cardContext, opacity: 0.5)
let composited = cardContext.makeImage()!.cropping(to: CGRect(x: 40, y: 40, width: 48, height: 48))!
let compositedSamples = redValues(composited)
let remainingContrast = Int(compositedSamples.max()!) - Int(compositedSamples.min()!)
check(remainingContrast > 70 && remainingContrast < 210, "50% glass preserves original detail while softening its contrast")
let glassStart = glass.backdrop(from: clouds.frame(width: 320, height: 200, elapsed: 0),
    viewport: NSRect(x: 0, y: 0, width: 320, height: 200), cardRect: NSRect(x: 160, y: 70, width: 100, height: 60), blurRadius: 12)!
let glassLater = glass.backdrop(from: clouds.frame(width: 320, height: 200, elapsed: 5),
    viewport: NSRect(x: 0, y: 0, width: 320, height: 200), cardRect: NSRect(x: 160, y: 70, width: 100, height: 60), blurRadius: 12)!
check(redValues(glassStart) != redValues(glassLater), "Glass blur follows the live moving background")
let app = NSApplication.shared
// Load the actual built saver, not a source-only substitute.
let bundle = Bundle(path: FileManager.default.currentDirectoryPath + "/build/Neosaver.saver")!
try bundle.loadAndReturnError()
check(bundle.principalClass != nil, "Saver principal class loads")
let cls = bundle.principalClass as! ScreenSaverView.Type
let saver = cls.init(frame: NSRect(x: 0, y: 0, width: 320, height: 200), isPreview: true)!
check(saver.hasConfigureSheet && saver.configureSheet != nil, "Saver exposes location options")
saver.startAnimation(); saver.animateOneFrame(); saver.stopAnimation()
check(saver.subviews.count == 1, "Shared scene is attached")
print("PASS: midnight/noon/year rollover, weather parsing and icons, stationary dither/grain, moving luminance, background coverage, live glass blur, real saver bundle loading, settings, animation lifecycle")
