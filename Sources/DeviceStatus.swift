import Foundation
import CoreWLAN
import CoreAudio
import IOBluetooth
import IOKit.ps
import SystemConfiguration

struct BatteryStatus: Codable {
    let percentage: Int
    let isCharging: Bool

    var symbol: String {
        if isCharging { return "battery.100percent.bolt" }
        let level = [25, 50, 75, 100].min { abs($0 - percentage) < abs($1 - percentage) } ?? 25
        return "battery.\(level)percent"
    }

    static func from(_ description: [String: Any]) -> BatteryStatus? {
        guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
              let current = description[kIOPSCurrentCapacityKey] as? NSNumber,
              let maximum = description[kIOPSMaxCapacityKey] as? NSNumber,
              maximum.doubleValue > 0, current.doubleValue >= 0 else { return nil }
        let percentage = Int(min(100, current.doubleValue / maximum.doubleValue * 100).rounded())
        return BatteryStatus(percentage: percentage, isCharging: (description[kIOPSIsChargingKey] as? Bool) ?? false)
    }
}

struct AudioDeviceStatus {
    let name: String
    let transport: UInt32
    let isAlive: Bool
    let hasOutputStreams: Bool
    var isBluetoothOutput: Bool {
        isAlive && hasOutputStreams &&
            (transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE)
    }
}

enum BluetoothStatus: String, Codable {
    case unavailable, off, on, airpods, device

    static func poweredOn(controllerState: BluetoothHCIPowerState?) -> Bool? {
        switch controllerState {
        case kBluetoothHCIPowerStateON: return true
        case kBluetoothHCIPowerStateOFF: return false
        default: return nil // Includes the unavailable/uninitialized controller state (255).
        }
    }

    static func resolve(poweredOn: Bool?, audioDevices: [AudioDeviceStatus]) -> BluetoothStatus {
        if poweredOn == false { return .off }
        let outputs = audioDevices.filter(\.isBluetoothOutput)
        if outputs.contains(where: { $0.name.localizedCaseInsensitiveContains("airpods") }) { return .airpods }
        if !outputs.isEmpty { return .device }
        return poweredOn == true ? .on : .unavailable
    }
}

struct DeviceStatus: Codable {
    let bluetooth: BluetoothStatus
    let wifiConnected: Bool
    let battery: BatteryStatus?
    var wifiSymbol: String { wifiConnected ? "wifi" : "wifi.slash" }
    var batterySymbol: String { battery?.symbol ?? "battery.25percent" }
    var batteryText: String { battery.map { "\($0.percentage)%" } ?? "—%" }
    var batteryPrompt: String? {
        guard let battery else { return nil }
        if battery.percentage <= 25 && !battery.isCharging { return "• CHARGE" }
        if battery.percentage >= 80 { return "• UNPLUG" }
        return nil
    }
    static let unavailable = DeviceStatus(bluetooth: .unavailable, wifiConnected: false, battery: nil)
}

final class DeviceStatusReader {
    func sample() -> DeviceStatus {
        let battery = Self.readBattery()
        let connectivity = sampleConnectivity()
        return DeviceStatus(bluetooth: connectivity.bluetooth, wifiConnected: connectivity.wifiConnected, battery: battery)
    }

    func sampleConnectivity() -> DeviceStatus {
        DeviceStatus(bluetooth: readBluetooth(), wifiConnected: readWiFi(), battery: nil)
    }

    static func readBattery() -> BatteryStatus? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            if let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
               let battery = BatteryStatus.from(description) { return battery }
        }
        return nil
    }

    private func readWiFi() -> Bool {
        let interfaces = CWWiFiClient.shared().interfaces() ?? []
        return interfaces.contains { interface in
            guard interface.powerOn(), let name = interface.interfaceName else { return false }
            // Link state avoids reading the SSID, which macOS can redact without location access.
            let key = "State:/Network/Interface/\(name)/Link" as CFString
            let link = SCDynamicStoreCopyValue(nil, key) as? [String: Any]
            return link?[kSCPropNetLinkActive as String] as? Bool == true
        }
    }

    private func readAudioDevices() -> [AudioDeviceStatus] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        let result = devices.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(system, &address, 0, nil, &size, $0.baseAddress!)
        }
        guard result == noErr else { return [] }
        return devices.compactMap { device in
            func number(_ selector: AudioObjectPropertySelector) -> UInt32? {
                var property = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                         mElement: kAudioObjectPropertyElementMain)
                var value: UInt32 = 0
                var size = UInt32(MemoryLayout<UInt32>.size)
                guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr else { return nil }
                return value
            }
            guard let transport = number(kAudioDevicePropertyTransportType),
                  transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE,
                  number(kAudioDevicePropertyDeviceIsAlive) == 1 else { return nil }
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                     mScope: kAudioDevicePropertyScopeOutput,
                                                     mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamSize) == noErr,
                  streamSize >= MemoryLayout<AudioStreamID>.size else { return nil }
            var nameProperty = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                          mScope: kAudioObjectPropertyScopeGlobal,
                                                          mElement: kAudioObjectPropertyElementMain)
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            _ = withUnsafeMutablePointer(to: &name) {
                AudioObjectGetPropertyData(device, &nameProperty, 0, nil, &nameSize, $0)
            }
            let deviceName = name?.takeRetainedValue() as String? ?? ""
            return AudioDeviceStatus(name: deviceName, transport: transport, isAlive: true, hasOutputStreams: true)
        }
    }

    private func readBluetooth() -> BluetoothStatus {
        let poweredOn = BluetoothStatus.poweredOn(controllerState: IOBluetoothHostController.default()?.powerState)
        return .resolve(poweredOn: poweredOn, audioDevices: poweredOn == false ? [] : readAudioDevices())
    }
}

// Power changes have their own queue so a Bluetooth/Wi-Fi query cannot hold up the battery.
final class BatteryMonitor {
    var onChange: ((BatteryStatus?) -> Void)?
    private let readBattery: () -> BatteryStatus?
    private let queue = DispatchQueue(label: "com.neosaver.battery", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var powerSource: CFRunLoopSource?
    private var generation = 0

    init(readBattery: @escaping () -> BatteryStatus? = DeviceStatusReader.readBattery) {
        self.readBattery = readBattery
    }

    func start() {
        guard timer == nil else { return }
        generation += 1
        let context = Unmanaged.passUnretained(self).toOpaque()
        powerSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue().refresh()
        }, context)?.takeRetainedValue()
        if let powerSource { CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.refresh() }
        self.timer = timer
        timer.resume()
    }

    func refresh() {
        guard timer != nil else { return }
        let version = generation
        queue.async { [weak self] in
            guard let self else { return }
            let battery = self.readBattery()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == version, self.timer != nil else { return }
                self.onChange?(battery)
            }
        }
    }

    func stop() {
        generation += 1
        timer?.cancel(); timer = nil
        if let powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .commonModes)
            CFRunLoopSourceInvalidate(powerSource)
        }
        powerSource = nil
    }
    deinit {
        timer?.cancel()
        if let powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .commonModes)
            CFRunLoopSourceInvalidate(powerSource)
        }
    }
}

// Connectivity polling and power notifications publish independently on the main thread.
final class DeviceStatusMonitor {
    var onChange: (() -> Void)?
    private(set) var status = DeviceStatus.unavailable
    private let readConnectivity: () -> DeviceStatus
    private let batteryMonitor: BatteryMonitor
    private let queue = DispatchQueue(label: "com.neosaver.device-status", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var generation = 0

    init(readConnectivity: (() -> DeviceStatus)? = nil, batteryMonitor: BatteryMonitor = BatteryMonitor()) {
        self.readConnectivity = readConnectivity ?? DeviceStatusReader().sampleConnectivity
        self.batteryMonitor = batteryMonitor
        batteryMonitor.onChange = { [weak self] battery in
            guard let self, self.timer != nil else { return }
            self.status = DeviceStatus(bluetooth: self.status.bluetooth, wifiConnected: self.status.wifiConnected, battery: battery)
            self.onChange?()
        }
    }

    func start() {
        guard timer == nil else { return }
        generation += 1
        let version = generation
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 5, leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let connectivity = self.readConnectivity()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == version, self.timer != nil else { return }
                // Never let a delayed connectivity snapshot overwrite a newer battery reading.
                self.status = DeviceStatus(bluetooth: connectivity.bluetooth, wifiConnected: connectivity.wifiConnected,
                                           battery: self.status.battery)
                self.onChange?()
            }
        }
        self.timer = timer
        timer.resume()
        batteryMonitor.start()
    }
    func stop() { generation += 1; timer?.cancel(); timer = nil; batteryMonitor.stop() }
    deinit { timer?.cancel(); batteryMonitor.stop() }
}
