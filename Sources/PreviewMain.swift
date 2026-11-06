import AppKit

final class PreviewDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var scene: ClockSceneView!
    var timer: Timer?
    let settings = SettingsController()
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Location…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Neosaver", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let viewItem = NSMenuItem(); menu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View"); viewItem.submenu = viewMenu
        let full = viewMenu.addItem(withTitle: "Toggle Full Screen", action: #selector(toggleFullScreen), keyEquivalent: "f")
        full.target = self
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 750), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Neosaver — Preview"
        window.minSize = NSSize(width: 480, height: 300)
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior = [.fullScreenPrimary]
        scene = ClockSceneView(frame: window.contentView!.bounds)
        window.contentView = scene
        settings.onSave = { [weak self] in self?.scene.reloadSettings() }
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        scene.start()
        timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.scene.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, let window = self?.window, window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil); return nil
            }
            return event
        }
    }
    @objc func showSettings() { settings.show(for: window) }
    @objc func toggleFullScreen() { window.toggleFullScreen(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate(); scene?.stop() }
}

if CommandLine.arguments.contains("--agents-report") {
    let data = try JSONEncoder().encode(AgentStatusReader().sample())
    print(String(data: data, encoding: .utf8)!)
    exit(0)
}

if CommandLine.arguments.contains("--status-report") {
    let data = try JSONEncoder().encode(DeviceStatusReader().sample())
    print(String(data: data, encoding: .utf8)!)
    exit(0)
}

if CommandLine.arguments.contains("--metrics-report") {
    let reader = SystemStatsReader()
    _ = reader.sample()
    RunLoop.current.run(until: Date().addingTimeInterval(1.1))
    let data = try JSONEncoder().encode(reader.sample())
    print(String(data: data, encoding: .utf8)!)
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > index + 1 {
    let output = CommandLine.arguments[index + 1]
    let scene = ClockSceneView(frame: NSRect(x: 0, y: 0, width: 1440, height: 900))
    scene.fixedDate = ISO8601DateFormatter().date(from: "2026-11-05T19:35:00Z")
    if let index = CommandLine.arguments.firstIndex(of: "--background-time"), CommandLine.arguments.count > index + 1 {
        scene.fixedBackgroundTime = Double(CommandLine.arguments[index + 1])
    }
    scene.samplePrayer = PrayerTime(name: "Asr", date: scene.fixedDate!.addingTimeInterval(4083))
    scene.sampleAirPods = AirPodsBatteryStatus(earbuds: 78, chargingCase: 65)
    scene.sampleDeviceStatus = DeviceStatus(bluetooth: .airpods, wifiConnected: true, battery: BatteryStatus(percentage: 84, isCharging: false))
    scene.sampleAgents = AgentKind.allCases.map { AgentStatus(agent: $0, isRunning: $0 == .claude) }
    scene.sampleStats = SystemSample.referenceHistory
    scene.sampleWeather = WeatherReading(temperature: 8, code: 3, fetchedAt: Date())
    scene.tick()
    // Let the initial time jump settle before taking a reference snapshot.
    RunLoop.current.run(until: Date().addingTimeInterval(0.75))
    let bitmap = scene.bitmapImageRepForCachingDisplay(in: scene.bounds)!
    scene.cacheDisplay(in: scene.bounds, to: bitmap)
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
    print("Saved \(output)")
} else {
    let delegate = PreviewDelegate()
    app.delegate = delegate
    app.run()
}
