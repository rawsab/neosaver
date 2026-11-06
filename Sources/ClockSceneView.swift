import AppKit
import QuartzCore
import CoreText

final class ClockSceneView: NSView {
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    var fixedDate: Date?
    var fixedBackgroundTime: TimeInterval?
    private let backgroundRenderer = CloudBackground.Renderer()
    private let glassSurface = GlassSurface()
    private var backdropFrame: CGImage?
    private var sceneScale: CGFloat = 1
    private var sceneOrigin: NSPoint = .zero
    var sampleWeather: WeatherReading?
    var sampleStats: [SystemSample]?
    var sampleAgents: [AgentStatus]?
    var sampleAirPods: AirPodsBatteryStatus?
    private let airpodsBattery = AirPodsBatteryMonitor()
    var sampleDeviceStatus: DeviceStatus?
    private let deviceStatus = DeviceStatusMonitor()
    var samplePrayer: PrayerTime?
    private var prayerLine = "Prayer times unavailable"
    private let prayers = PrayerService()
    private let stats = SystemStatsMonitor()
    private var current = ClockText(date: Date())
    private var previous = ClockText(date: Date())
    private var flipStart: CFTimeInterval = 0
    private let weather = WeatherService()
    private var running = false
    private var backgroundElapsed: TimeInterval = 0
    private var backgroundStartedAt: CFTimeInterval?
    private var backgroundTime: TimeInterval {
        fixedBackgroundTime ?? (backgroundElapsed + (backgroundStartedAt.map { CACurrentMediaTime() - $0 } ?? 0))
    }
    private var settings = LocationSettings.load()
    private let flipDuration = 0.68

    override init(frame: NSRect) {
        super.init(frame: frame)
        weather.onChange = { [weak self] _ in self?.needsDisplay = true }
        prayers.onChange = { [weak self] in self?.updatePrayerLine(); self?.needsDisplay = true }
        airpodsBattery.onChange = { [weak self] in self?.needsDisplay = true }
        deviceStatus.onChange = { [weak self] in self?.needsDisplay = true }
        stats.onChange = { [weak self] in self?.needsDisplay = true }
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    func start() {
        if !running { backgroundStartedAt = CACurrentMediaTime() }
        running = true; tick(); weather.refresh(); prayers.refresh(); stats.start(); deviceStatus.start(); airpodsBattery.start()
    }
    func stop() {
        backgroundElapsed = backgroundTime; backgroundStartedAt = nil
        running = false; weather.stop(); prayers.stop(); stats.stop(); deviceStatus.stop(); airpodsBattery.stop()
    }
    func reloadSettings() { settings = .load(); weather.reloadLocation(); prayers.reloadLocation(); updatePrayerLine(); needsDisplay = true }
    private var lastTickSecond: Int?
    private var flipActive = false
    func tick() {
        if running { needsDisplay = true }
        let date = fixedDate ?? Date()
        let timestamp = date.timeIntervalSince1970
        let second = Int(floor(timestamp))
        guard second != lastTickSecond else {
            if flipActive {
                needsDisplay = true
                if CACurrentMediaTime() - flipStart >= flipDuration { flipActive = false }
            }
            return
        }
        lastTickSecond = second
        let next = ClockText(date: date)
        if next.hour != current.hour || next.minute != current.minute {
            previous = current; current = next; flipStart = CACurrentMediaTime(); flipActive = true
        } else { current = next }
        if running && fixedDate == nil { weather.refresh(); prayers.refresh() }
        updatePrayerLine()
        // Time formatting runs once per second while background drawing continues at 30 fps.
        needsDisplay = true
    }
    private func updatePrayerLine() {
        let now = fixedDate ?? Date()
        let prayer = samplePrayer ?? prayers.next(now: now)
        prayerLine = prayer?.line(now: now) ?? "Prayer times unavailable"
    }
    private func text(_ string: String, rect: NSRect, size: CGFloat, weight: NSFont.Weight = .medium,
                      color: NSColor = .white, spacing: CGFloat = 0, alignment: NSTextAlignment = .left) {
        let p = NSMutableParagraphStyle(); p.alignment = alignment
        (string as NSString).draw(in: rect, withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: size, weight: weight),
                                                           .foregroundColor: color, .kern: spacing, .paragraphStyle: p])
    }
    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 0, bounds.height > 0, let ctx = NSGraphicsContext.current?.cgContext else { return }
        NSColor.black.setFill(); bounds.fill()
        // Dither in output coordinates after sampling the moving, undithered clouds.
        // Bound raster size while retaining a crisp pattern in large/fullscreen previews.
        let rasterScale = min(1, 1600 / max(bounds.width, bounds.height))
        let image = backgroundRenderer.frame(width: max(1, Int(bounds.width * rasterScale)),
            height: max(1, Int(bounds.height * rasterScale)), elapsed: backgroundTime)
        ctx.interpolationQuality = .none
        ctx.draw(image, in: bounds)
        // A soft central shade keeps the glass clock legible on every cloud shape.
        let shade = NSGradient(colors: [NSColor.black.withAlphaComponent(0.20), .clear])!
        shade.draw(in: bounds, relativeCenterPosition: NSPoint(x: 0, y: 0))
        let scale = min(bounds.width / 1440, bounds.height / 900)
        let clockScale = scale * 1.25
        let tileWidth: CGFloat = 138, tileHeight: CGFloat = 104, gap: CGFloat = 12
        let left = NSRect(x: -(tileWidth * 2 + gap) / 2, y: -tileHeight / 2, width: tileWidth, height: tileHeight)
        let right = left.offsetBy(dx: tileWidth + gap, dy: 0)
        let edge = right.maxX + 10
        let metadataFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        let metadataWidth = max(44, [current.period, current.weekday, current.date].map {
            ceil(($0 as NSString).size(withAttributes: [.font: metadataFont]).width)
        }.max() ?? 44)
        let periodRect = NSRect(x: edge, y: right.minY + 1, width: metadataWidth, height: 19)
        let secondsRect = NSRect(x: edge, y: right.maxY - 30, width: 44, height: 30)
        let weekdayRect = NSRect(x: edge, y: secondsRect.minY - 34, width: metadataWidth, height: 17)
        let dateRect = NSRect(x: edge, y: secondsRect.minY - 21, width: metadataWidth, height: 17)
        // Center the full visible composition, including the right-hand metadata/seconds column.
        let groupBounds = [left, right, secondsRect, periodRect, weekdayRect, dateRect]
            .dropFirst().reduce(left) { $0.union($1) }
        sceneOrigin = NSPoint(x: bounds.midX - groupBounds.midX * clockScale,
                              y: bounds.midY - groupBounds.midY * clockScale - 5 * scale)
        backdropFrame = image; sceneScale = clockScale
        ctx.saveGState()
        ctx.translateBy(x: sceneOrigin.x, y: sceneOrigin.y)
        ctx.scaleBy(x: clockScale, y: clockScale)
        let progress = min(1, max(0, (CACurrentMediaTime() - flipStart) / flipDuration))
        drawTile(current.hour, old: previous.hour, in: left, progress: progress)
        drawTile(current.minute, old: previous.minute, in: right, progress: progress)
        let muted = NSColor(white: 0.92, alpha: 0.75)
        text(current.period, rect: periodRect, size: 12, weight: .semibold, color: muted)
        text(current.weekday, rect: weekdayRect, size: 12, weight: .semibold, color: muted)
        text(current.date, rect: dateRect, size: 12, weight: .semibold, color: muted)
        drawTile(current.second, old: current.second, in: secondsRect, progress: 1, fontSize: 25, isPrimary: false)
        let prayerSize: CGFloat = 12
        let prayerText = NSMutableAttributedString(string: prayerLine, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: prayerSize, weight: .regular),
            .foregroundColor: NSColor(white: 0.92, alpha: 0.82)
        ])
        let countdownStart = (prayerLine as NSString).range(of: "•")
        if countdownStart.location != NSNotFound {
            prayerText.addAttribute(.foregroundColor, value: NSColor(white: 0.92, alpha: 0.5),
                                    range: NSRange(location: countdownStart.location,
                                                   length: prayerText.length - countdownStart.location))
        }
        let prayerWidth = ceil(prayerText.size().width)
        let iconWidth: CGFloat = 16, iconGap: CGFloat = 7
        let prayerX = groupBounds.midX - (prayerWidth + iconWidth + iconGap) / 2
        let clockLineGap: CGFloat = 22
        let clockLineHeight: CGFloat = 18
        let clockLineIconOffset: CGFloat = -1
        let prayerY = groupBounds.maxY + clockLineGap - clockLineIconOffset
        drawSymbol("clock", in: NSRect(x: prayerX, y: prayerY + clockLineIconOffset, width: iconWidth, height: clockLineHeight),
                   pointSize: 15, opacity: 0.82)
        prayerText.draw(in: NSRect(x: prayerX + iconWidth + iconGap, y: prayerY, width: prayerWidth + 1, height: 20))
        let weatherSize: CGFloat = 12
        let reading = sampleWeather ?? weather.reading
        let symbol = reading?.symbol ?? "cloud"
        let temperature = reading.map { "\(Int($0.temperature.rounded()))°C" } ?? "—°C"
        let weatherFont = NSFont.monospacedSystemFont(ofSize: weatherSize, weight: .medium)
        let temperatureWidth = ceil((temperature as NSString).size(withAttributes: [.font: weatherFont]).width)
        let city = settings.city.uppercased()
        let citySpacing: CGFloat = 2
        let cityWidth = min(240, ceil((city as NSString).size(withAttributes: [.font: weatherFont, .kern: citySpacing]).width) + 1)
        let weatherIconWidth: CGFloat = 20, locationIconWidth: CGFloat = 15
        let weatherIconGap: CGFloat = 7, locationIconGap: CGFloat = 7, itemGap: CGFloat = 18
        let weatherRowWidth = weatherIconWidth + weatherIconGap + temperatureWidth + itemGap + locationIconWidth + locationIconGap + cityWidth
        let weatherX = groupBounds.midX - weatherRowWidth / 2
        let weatherY = groupBounds.minY - clockLineGap - clockLineHeight - clockLineIconOffset + 3
        drawSymbol(symbol, in: NSRect(x: weatherX, y: weatherY + clockLineIconOffset, width: weatherIconWidth, height: clockLineHeight),
                   pointSize: 17, opacity: 0.82)
        let temperatureX = weatherX + weatherIconWidth + weatherIconGap
        text(temperature, rect: NSRect(x: temperatureX, y: weatherY, width: temperatureWidth + 1, height: 20),
             size: weatherSize, color: NSColor(white: 0.92, alpha: 0.85))
        let locationX = temperatureX + temperatureWidth + itemGap
        drawSymbol("location", in: NSRect(x: locationX, y: weatherY + clockLineIconOffset, width: locationIconWidth, height: clockLineHeight),
                   pointSize: weatherSize, opacity: 0.65)
        text(city, rect: NSRect(x: locationX + locationIconWidth + locationIconGap, y: weatherY, width: cityWidth, height: 20),
             size: weatherSize, color: NSColor(white: 0.92, alpha: 0.65), spacing: citySpacing)
        ctx.restoreGState()
        let margin = max(10, 18 * scale)
        drawDeviceStatus(sampleDeviceStatus ?? deviceStatus.status, scale: scale, margin: margin)
        drawAirPodsBattery(sampleAirPods ?? airpodsBattery.status, scale: scale, margin: margin)
        ctx.saveGState()
        ctx.translateBy(x: margin, y: margin)
        ctx.scaleBy(x: scale, y: scale)
        StatsPanel.draw(history: sampleStats ?? stats.history.samples, agents: sampleAgents ?? stats.agents)
        ctx.restoreGState()
    }
    private func drawAirPodsBattery(_ status: AirPodsBatteryStatus, scale: CGFloat, margin: CGFloat) {
        // Fit the entire row on small screens while preserving the bottom/right margins.
        let desiredSize = max(10, 13 * scale)
        let name = AirPodsBatteryStatus.deviceName.uppercased()
        func measure(_ value: String, size: CGFloat) -> CGFloat {
            ceil((value as NSString).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: size, weight: .medium)]).width)
        }
        let naturalWidth = measure(name, size: desiredSize) + measure(status.earbudsText, size: desiredSize) +
            measure(status.caseText, size: desiredSize) + desiredSize * 7.2
        let size = desiredSize * min(1, (bounds.width - margin * 2) / naturalWidth)
        let nameWidth = measure(name, size: size)
        let earbudsWidth = measure(status.earbudsText, size: size), caseWidth = measure(status.caseText, size: size)
        let itemGap = size, iconGap = size * 0.6, iconWidth = size * 2
        let rowWidth = nameWidth + earbudsWidth + caseWidth + itemGap * 2 + iconGap * 2 + iconWidth * 2
        let x = bounds.maxX - margin - rowWidth
        let iconHeight = size * 1.5
        let y = bounds.maxY - margin - iconHeight
        let color = NSColor(white: 0.92, alpha: 0.85)
        text(name, rect: NSRect(x: x, y: y + 2 * scale, width: nameWidth + 1, height: size * 2),
             size: size, color: NSColor(white: 0.92, alpha: 0.5))
        let earbudsX = x + nameWidth + itemGap
        let earbudsSymbol = NSImage(systemSymbolName: "airpods.gen4", accessibilityDescription: nil) != nil ? "airpods.gen4" : "airpods"
        drawSymbol(earbudsSymbol, in: NSRect(x: earbudsX, y: y, width: iconWidth, height: iconHeight), pointSize: size + 3, opacity: 0.82)
        let earbudsTextX = earbudsX + iconWidth + iconGap
        text(status.earbudsText, rect: NSRect(x: earbudsTextX, y: y + 2 * scale, width: earbudsWidth + 1, height: size * 2), size: size, color: color)
        let caseX = earbudsTextX + earbudsWidth + itemGap
        let caseSymbol = NSImage(systemSymbolName: "airpods.gen4.chargingcase.wireless.fill", accessibilityDescription: nil) != nil ?
            "airpods.gen4.chargingcase.wireless.fill" : "airpods.chargingcase.fill"
        drawSymbol(caseSymbol, in: NSRect(x: caseX, y: y, width: iconWidth, height: iconHeight), pointSize: size + 3, opacity: 0.82)
        text(status.caseText, rect: NSRect(x: caseX + iconWidth + iconGap, y: y + 2 * scale, width: caseWidth + 1, height: size * 2), size: size, color: color)
    }

    private func drawDeviceStatus(_ status: DeviceStatus, scale: CGFloat, margin: CGFloat) {
        let size = max(10, 13 * scale)
        let iconHeight = size * 1.4
        let bluetoothWidth = size * 1.6, wifiWidth = size * 1.7, batteryWidth = size * 2
        let iconGap = size * 0.85, labelGap = size * 0.45
        let labelWidth = ceil((status.batteryText as NSString).size(withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
        ]).width)
        let prompt = status.batteryPrompt
        let promptGap = prompt == nil ? 0 : size * 0.6
        let promptWidth = prompt.map { ceil(($0 as NSString).size(withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
        ]).width) } ?? 0
        let warningGap = prompt == nil ? 0 : size * 0.5
        let warningWidth = prompt == nil ? 0 : size * 1.3
        let totalWidth = bluetoothWidth + wifiWidth + batteryWidth + iconGap * 2 + labelGap + labelWidth + promptGap + promptWidth + warningGap + warningWidth
        let x = bounds.maxX - margin - totalWidth
        let bluetoothBox = NSRect(x: x, y: margin, width: bluetoothWidth, height: iconHeight)
        switch status.bluetooth {
        case .airpods:
            let symbol = NSImage(systemSymbolName: "airpods.gen4", accessibilityDescription: nil) != nil ? "airpods.gen4" : "airpods"
            drawSymbol(symbol, in: bluetoothBox, pointSize: size + 3, opacity: 0.82)
        case .device:
            drawSymbol("headphones", in: bluetoothBox, pointSize: size + 3, opacity: 0.82)
        case .on, .off, .unavailable:
            drawBluetooth(in: bluetoothBox, slashed: status.bluetooth == .off,
                          opacity: status.bluetooth == .unavailable ? 0.35 : 0.82)
        }
        let wifiX = bluetoothBox.maxX + iconGap
        drawSymbol(status.wifiSymbol, in: NSRect(x: wifiX, y: margin, width: wifiWidth, height: iconHeight),
                   pointSize: size + 3, opacity: 0.82)
        let batteryX = wifiX + wifiWidth + iconGap
        drawSymbol(status.batterySymbol, in: NSRect(x: batteryX, y: margin, width: batteryWidth, height: iconHeight),
                   pointSize: size + 3, opacity: status.battery == nil ? 0.35 : 0.82)
        text(status.batteryText, rect: NSRect(x: batteryX + batteryWidth + labelGap, y: margin + 2 * scale,
                                            width: labelWidth + 1, height: size * 2),
             size: size, color: NSColor(white: 0.92, alpha: 0.85))
        if let prompt {
            text(prompt, rect: NSRect(x: batteryX + batteryWidth + labelGap + labelWidth + promptGap,
                                     y: margin + 2 * scale, width: promptWidth + 1, height: size * 2),
                 size: size, color: StatsPanel.orange)
            let warningX = batteryX + batteryWidth + labelGap + labelWidth + promptGap + promptWidth + warningGap
            drawSymbol("exclamationmark.triangle", in: NSRect(x: warningX, y: margin, width: warningWidth, height: iconHeight),
                       pointSize: size, opacity: 1, color: StatsPanel.orange)
        }
    }

    private func drawBluetooth(in box: NSRect, slashed: Bool, opacity: CGFloat) {
        // SF Symbols has no basic Bluetooth logo; draw the standard rune as a native path.
        let unit = box.height / 18
        let origin = NSPoint(x: box.midX - 5 * unit, y: box.midY - 8 * unit)
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: origin.x + x * unit, y: origin.y + y * unit)
        }
        let path = NSBezierPath()
        path.move(to: point(1, 4)); path.line(to: point(10, 12))
        path.line(to: point(5, 16)); path.line(to: point(5, 0))
        path.line(to: point(10, 4)); path.line(to: point(1, 12))
        if slashed { path.move(to: point(-2, 0)); path.line(to: point(12, 16)) }
        NSColor(white: 0.91, alpha: opacity).setStroke()
        path.lineWidth = 1.3 * unit; path.lineJoinStyle = .round; path.lineCapStyle = .round
        path.stroke()
    }

    private func drawSymbol(_ name: String, in box: NSRect, pointSize: CGFloat, opacity: CGFloat,
                            color: NSColor = NSColor(white: 0.91, alpha: 1)) {
        guard let icon = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .regular)),
              icon.size.width > 0, icon.size.height > 0 else { return }
        let factor = min(box.width / icon.size.width, box.height / icon.size.height)
        let rect = NSRect(x: box.midX - icon.size.width * factor / 2,
                          y: box.midY - icon.size.height * factor / 2,
                          width: icon.size.width * factor, height: icon.size.height * factor)
        let tinted = NSImage(size: icon.size, flipped: false) { bounds in
            icon.draw(in: bounds)
            color.setFill()
            bounds.fill(using: .sourceIn)
            return true
        }
        tinted.draw(in: rect, from: .zero, operation: .sourceOver, fraction: opacity,
                    respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    }
    private func drawTile(_ number: String, old: String, in rect: NSRect, progress: Double,
                          fontSize: CGFloat = 94, isPrimary: Bool = true) {
        let tileScale = rect.height / 104
        let path = NSBezierPath(roundedRect: rect, xRadius: 15 * tileScale, yRadius: 15 * tileScale)
        let screenRect = NSRect(x: sceneOrigin.x + rect.minX * sceneScale,
                                y: sceneOrigin.y + rect.minY * sceneScale,
                                width: rect.width * sceneScale, height: rect.height * sceneScale)
        let blurred = backdropFrame.flatMap {
            glassSurface.backdrop(from: $0, viewport: bounds, cardRect: screenRect, blurRadius: 3 * sceneScale)
        }
        func surface() {
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            glassSurface.drawBackground(blurred: blurred, in: rect, context: context, opacity: 0.7)
        }
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        surface()
        func digits(_ value: String) {
            let verticalNudge: CGFloat = isPrimary ? 2.5 * tileScale : 0
            ClockTypography.drawDigits(value, in: rect, size: fontSize, verticalNudge: verticalNudge)
        }
        if old == number || progress >= 1 {
            digits(number)
        } else {
            let top = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height / 2)
            let bottom = NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2)
            NSGraphicsContext.saveGraphicsState(); top.clip(); digits(number); NSGraphicsContext.restoreGraphicsState()
            NSGraphicsContext.saveGraphicsState(); bottom.clip(); digits(old); NSGraphicsContext.restoreGraphicsState()
            // Two hinged half-cards, with a cosine foreshortening around the seam.
            let first = progress < 0.5
            let half = first ? top : bottom
            let squeeze = CGFloat(first ? cos(progress * .pi) : -cos(progress * .pi))
            NSGraphicsContext.saveGraphicsState()
            half.clip()
            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.translateBy(x: 0, y: rect.midY)
                ctx.scaleBy(x: 1, y: max(0.001, squeeze))
                ctx.translateBy(x: 0, y: -rect.midY)
                surface()
                digits(first ? old : number)
                NSColor.black.withAlphaComponent((1 - squeeze) * 0.35).setFill(); half.fill()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.12).setStroke()
        path.lineWidth = 0.6
        path.stroke()
    }
}
