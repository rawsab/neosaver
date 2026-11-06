import AppKit

// Sharp mono typography and unboxed orange traces; no axes, ticks, or decorative chrome.
enum StatsPanel {
    static let orange = NSColor(srgbRed: 249 / 255, green: 66 / 255, blue: 7 / 255, alpha: 1)
    static let valueColor = NSColor(srgbRed: 255 / 255, green: 168 / 255, blue: 139 / 255, alpha: 0.8)
    static let width: CGFloat = 280
    private static let agentIcons: [Bool: NSImage] = {
        var icons: [Bool: NSImage] = [:]
        let configuration = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        for active in [false, true] {
            icons[active] = NSImage(systemSymbolName: active ? "circle.fill" : "circle", accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
        }
        return icons
    }()

    private static func label(_ string: String, x: CGFloat = 0, y: CGFloat, width: CGFloat = width,
                              opacity: CGFloat = 1, alignment: NSTextAlignment = .left, size: CGFloat = 12,
                              isValue: Bool = false) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = alignment
        let attributed = NSMutableAttributedString(string: string, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: size, weight: .medium),
            .foregroundColor: orange.withAlphaComponent(opacity), .paragraphStyle: paragraph
        ])
        let text = string as NSString
        let separator = text.range(of: "• ")
        if isValue {
            attributed.addAttribute(.foregroundColor, value: valueColor, range: NSRange(location: 0, length: text.length))
        } else if separator.location != NSNotFound {
            let start = NSMaxRange(separator)
            attributed.addAttribute(.foregroundColor, value: valueColor, range: NSRange(location: start, length: text.length - start))
        }
        attributed.draw(in: NSRect(x: x, y: y, width: width, height: 20))
    }
    static func draw(history: [SystemSample], agents: [AgentStatus]) {
        let current = history.last
        func percentage(_ value: Double?) -> String { value.map { "\(Int($0.rounded()))%" } ?? "—" }
        label("CPU USAGE • \(percentage(current?.cpu))", y: 0)
        graph(history: history, value: { $0.cpu }, rect: NSRect(x: 0, y: 25, width: width, height: 36))
        label("GPU USAGE • \(percentage(current?.gpu))", y: 83)
        graph(history: history, value: { $0.gpu }, rect: NSRect(x: 0, y: 108, width: width, height: 36))
        if let memory = current?.memory {
            let totalPrecision = memory.total.truncatingRemainder(dividingBy: 1_073_741_824) == 0 ? 0 : 2
            label("MEMORY • \(MemorySample.gb(memory.used)) GB / \(MemorySample.gb(memory.total, precision: totalPrecision)) GB", y: 168)
            memoryRow("Compressed", value: "\(MemorySample.gb(memory.compressed)) GB", y: 196)
            memoryRow("Cached", value: "\(MemorySample.gb(memory.cached)) GB", y: 219)
            memoryRow("Swap used", value: memory.swap.map { "\(MemorySample.gb($0)) GB" } ?? "—", y: 242)
        } else {
            label("MEMORY • —", y: 168)
            memoryRow("Compressed", value: "—", y: 196)
            memoryRow("Cached", value: "—", y: 219)
            memoryRow("Swap used", value: "—", y: 242)
        }
        let agentsY: CGFloat = 300
        ("AGENTS" as NSString).draw(in: NSRect(x: 0, y: agentsY, width: width, height: 20), withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white
        ])
        // Match MEMORY -> Compressed (28 points) and the memory list's 23-point row spacing.
        for (index, agent) in agents.enumerated() {
            let y = agentsY + 28 + CGFloat(index) * 23
            agentIcons[agent.isRunning]?.draw(in: NSRect(x: 0, y: y + 2, width: 10, height: 10),
                                              from: .zero, operation: .sourceOver,
                                              fraction: agent.isRunning ? 1 : 0.5, respectFlipped: true, hints: nil)
            agentText(agent).draw(in: NSRect(x: 17, y: y, width: width - 17, height: 20))
        }
    }

    static func agentText(_ status: AgentStatus) -> NSAttributedString {
        let name = status.agent.name
        let line = "\(name) • \(status.isRunning ? "ACTIVE" : "INACTIVE")"
        let attributed = NSMutableAttributedString(string: line, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(status.isRunning ? 1 : 0.5)
        ])
        let suffixStart = (name as NSString).length + 1
        attributed.addAttribute(.foregroundColor, value: NSColor.white.withAlphaComponent(0.5),
                                range: NSRange(location: suffixStart, length: attributed.length - suffixStart))
        return attributed
    }

    private static func memoryRow(_ name: String, value: String, y: CGFloat) {
        orange.withAlphaComponent(0.55).setFill()
        NSRect(x: 0, y: y + 1, width: 1, height: 13).fill()
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        let nameWidth = (name as NSString).size(withAttributes: [.font: font]).width
        let valueWidth = (value as NSString).size(withAttributes: [.font: font]).width
        let start = 11 + nameWidth + 8
        let end = width - valueWidth - 8
        if start < end {
            let dots = NSBezierPath()
            for x in stride(from: ceil(start / 4) * 4, through: end, by: 4) {
                dots.appendOval(in: NSRect(x: x - 0.5, y: y + 6.5, width: 1, height: 1))
            }
            orange.withAlphaComponent(0.35).setFill(); dots.fill()
        }
        label(name, x: 11, y: y, width: 145, opacity: 0.8, size: 11)
        label(value, x: 160, y: y, width: width - 160, alignment: .right, size: 11, isValue: true)
    }
    private static func graph(history: [SystemSample], value: (SystemSample) -> Double?, rect: NSRect) {
        let valid = history.compactMap(value)
        guard let first = history.first(where: { value($0) != nil }),
              let last = history.last(where: { value($0) != nil }) else { return }
        // A quiet adaptive ceiling makes low utilization legible without drawing axes.
        let ceiling = min(100, max(25, (valid.max() ?? 0) * 1.2))
        // Each metric spans the full width using its own available history.
        // CPU needs a baseline sample, so its first valid reading can start later than GPU.
        let duration = last.time - first.time
        var segments: [[NSPoint]] = []
        var segment: [NSPoint] = []
        var previousTime: TimeInterval?
        for sample in history {
            guard let usage = value(sample) else {
                if !segment.isEmpty { segments.append(segment); segment = [] }
                previousTime = nil; continue
            }
            if let previousTime, sample.time - previousTime > 2.5, !segment.isEmpty {
                segments.append(segment); segment = []
            }
            let x = duration > 0 ? rect.minX + CGFloat((sample.time - first.time) / duration) * rect.width : rect.minX
            let y = rect.maxY - CGFloat(min(1, max(0, usage / ceiling))) * (rect.height - 2)
            segment.append(NSPoint(x: x, y: y)); previousTime = sample.time
        }
        if !segment.isEmpty { segments.append(segment) }
        for var points in segments {
            if valid.count == 1, let point = points.first {
                // Hold the only measured value across the graph until more readings arrive.
                points = [NSPoint(x: rect.minX, y: point.y), NSPoint(x: rect.maxX, y: point.y)]
            }
            guard let first = points.first, let last = points.last else { continue }
            if points.count == 1 {
                orange.setFill(); NSRect(x: last.x - 1, y: last.y - 1, width: 2, height: 2).fill(); continue
            }
            let line = NSBezierPath(); line.move(to: first)
            for point in points.dropFirst() { line.line(to: point) }
            let fill = line.copy() as! NSBezierPath
            fill.line(to: NSPoint(x: last.x, y: rect.maxY)); fill.line(to: NSPoint(x: first.x, y: rect.maxY)); fill.close()
            NSGraphicsContext.saveGraphicsState()
            fill.addClip()
            if let context = NSGraphicsContext.current?.cgContext,
               let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [orange.withAlphaComponent(0.28).cgColor, orange.withAlphaComponent(0).cgColor] as CFArray,
                locations: [0, 1]) {
                context.drawLinearGradient(gradient,
                    start: CGPoint(x: rect.minX, y: points.map(\.y).min() ?? rect.minY),
                    end: CGPoint(x: rect.minX, y: rect.maxY), options: [])
            }
            NSGraphicsContext.restoreGraphicsState()
            orange.setStroke(); line.lineWidth = 1.25; line.lineJoinStyle = .miter; line.lineCapStyle = .butt; line.stroke()
        }
    }
}
