import AppKit

final class SettingsController: NSObject {
    let window: NSWindow
    private let city = NSTextField(string: "")
    private let latitude = NSTextField(string: "")
    private let longitude = NSTextField(string: "")
    private let error = NSTextField(labelWithString: "")
    var onSave: (() -> Void)?
    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 310), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "Neosaver Location"
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        let content = window.contentView!
        let fields = [("City", city), ("Latitude", latitude), ("Longitude", longitude)]
        for (index, pair) in fields.enumerated() {
            let y = 245 - index * 48
            let label = NSTextField(labelWithString: pair.0)
            label.frame = NSRect(x: 24, y: y + 3, width: 85, height: 22); content.addSubview(label)
            pair.1.frame = NSRect(x: 112, y: y, width: 282, height: 26); content.addSubview(pair.1)
        }
        let note = NSTextField(wrappingLabelWithString: "Weather uses Open-Meteo. Coordinates select the weather location; the clock uses your Mac’s time zone.")
        note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor
        note.frame = NSRect(x: 24, y: 76, width: 370, height: 45); content.addSubview(note)
        error.font = .systemFont(ofSize: 11); error.textColor = .systemRed
        error.frame = NSRect(x: 24, y: 52, width: 370, height: 22); content.addSubview(error)
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelSettings))
        cancel.frame = NSRect(x: 210, y: 14, width: 90, height: 32); cancel.keyEquivalent = "\u{1b}"; content.addSubview(cancel)
        let save = NSButton(title: "Save", target: self, action: #selector(saveSettings))
        save.frame = NSRect(x: 304, y: 14, width: 90, height: 32); save.keyEquivalent = "\r"; content.addSubview(save)
    }
    func prepare() {
        let value = LocationSettings.load()
        city.stringValue = value.city; latitude.stringValue = String(value.latitude); longitude.stringValue = String(value.longitude)
        error.stringValue = ""
    }
    func show(for parent: NSWindow?) {
        prepare()
        if let parent { parent.beginSheet(window) } else { window.center(); window.makeKeyAndOrderFront(nil) }
    }
    @objc private func cancelSettings() { close() }
    private func close() {
        if let parent = window.sheetParent { parent.endSheet(window) }
        window.orderOut(nil)
    }
    @objc private func saveSettings() {
        let name = city.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80,
              let lat = Double(latitude.stringValue), let lon = Double(longitude.stringValue),
              lat.isFinite, lon.isFinite, (-90...90).contains(lat), (-180...180).contains(lon) else {
            error.stringValue = "Enter a city, latitude −90…90, and longitude −180…180."; return
        }
        LocationSettings(city: name, latitude: lat, longitude: lon).save()
        onSave?(); close()
    }
}
