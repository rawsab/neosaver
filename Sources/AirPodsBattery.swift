import Foundation
import CoreFoundation

struct AirPodsBatteryStatus: Codable, Equatable {
    static let deviceName = "Rawsab's AirPods 4"
    private static let serialNumber = "C2CDX4JY6G"
    private static let modelNumber = "A3055"
    let earbuds: Int?
    let chargingCase: Int?
    var earbudsText: String { earbuds.map { "\($0)%" } ?? "—%" }
    var caseText: String { chargingCase.map { "\($0)%" } ?? "—%" }
    static let unavailable = AirPodsBatteryStatus(earbuds: nil, chargingCase: nil)
    static var cacheKey: String { "airpods.battery.v1.\(serialNumber)" }

    func retainingMissing(from previous: AirPodsBatteryStatus) -> AirPodsBatteryStatus {
        AirPodsBatteryStatus(earbuds: earbuds ?? previous.earbuds, chargingCase: chargingCase ?? previous.chargingCase)
    }

    private static func normalizedName(_ value: String) -> String {
        value.replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    private static func matches(name: String, info: [String: Any]) -> Bool {
        if let serial = info["device_serialNumber"] as? String ?? info["device_serial_number"] as? String {
            return serial.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == serialNumber
        }
        if let model = info["device_modelNumber"] as? String, model.hasPrefix("A"),
           model.dropFirst().allSatisfy(\.isNumber), model != modelNumber { return false }
        return normalizedName(name) == normalizedName(deviceName)
    }

    private static func percentage(_ value: Any?) -> Int? {
        let percentage: Int?
        if let string = value as? String {
            percentage = Int(string.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines))
        } else if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            percentage = number.intValue
        } else { percentage = nil }
        guard let percentage, (0...100).contains(percentage) else { return nil }
        return percentage
    }

    static func decode(_ data: Data) -> AirPodsBatteryStatus {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return .unavailable }
        for controller in controllers {
            guard let connected = controller["device_connected"] as? [[String: Any]] else { continue }
            for entry in connected {
                for (name, value) in entry {
                    guard let info = value as? [String: Any], matches(name: name, info: info) else { continue }
                    let individual = [percentage(info["device_batteryLevelLeft"]), percentage(info["device_batteryLevelRight"])].compactMap { $0 }
                    return AirPodsBatteryStatus(
                        earbuds: individual.min() ?? percentage(info["device_batteryLevelMain"]),
                        chargingCase: percentage(info["device_batteryLevelCase"]))
                }
            }
        }
        return .unavailable
    }
}

final class AirPodsBatteryMonitor {
    var onChange: (() -> Void)?
    private(set) var status: AirPodsBatteryStatus
    private let storage: UserDefaults
    private let queue = DispatchQueue(label: "com.neosaver.airpods-battery", qos: .utility)
    private var timer: DispatchSourceTimer?
    // Process ownership is confined to the main thread; reading/parsing runs off-thread.
    private var process: Process?
    private var generation = 0

    init(storage: UserDefaults = LocationSettings.storage) {
        self.storage = storage
        status = storage.data(forKey: AirPodsBatteryStatus.cacheKey).flatMap {
            try? JSONDecoder().decode(AirPodsBatteryStatus.self, from: $0)
        } ?? .unavailable
    }

    private func publish(_ reading: AirPodsBatteryStatus) {
        let updated = reading.retainingMissing(from: status)
        if updated != status {
            status = updated
            if let data = try? JSONEncoder().encode(status) {
                storage.set(data, forKey: AirPodsBatteryStatus.cacheKey)
            }
        }
        onChange?()
    }

    func start() {
        guard timer == nil else { return }
        generation += 1
        let version = generation
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 15, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in self?.refresh(version: version) }
        self.timer = timer
        timer.resume()
    }

    private func refresh(version: Int) {
        guard process == nil else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "mini", "-timeout", "5"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { publish(.unavailable); return }
        self.process = process
        let timeout = DispatchWorkItem { [weak process] in
            if let process, process.isRunning { process.terminate() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: timeout)
        queue.async { [weak self] in
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let status = process.terminationStatus == 0 ? AirPodsBatteryStatus.decode(data) : .unavailable
            DispatchQueue.main.async { [weak self] in
                timeout.cancel()
                guard let self, self.generation == version, self.timer != nil else { return }
                self.process = nil
                self.publish(status)
            }
        }
    }

    func stop() {
        generation += 1
        timer?.cancel(); timer = nil
        if let process, process.isRunning { process.terminate() }
        process = nil
    }
    deinit {
        timer?.cancel()
        if let process, process.isRunning { process.terminate() }
    }
}
