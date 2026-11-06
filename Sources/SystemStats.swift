import Foundation
import Darwin
import IOKit

struct CPUCounters {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32
    func usage(since previous: CPUCounters) -> Double? {
        let busy = UInt64(user &- previous.user) + UInt64(system &- previous.system) + UInt64(nice &- previous.nice)
        let total = busy + UInt64(idle &- previous.idle)
        return total > 0 ? min(100, Double(busy) / Double(total) * 100) : nil
    }
}

struct MemorySample: Codable {
    let used: Double
    let total: Double
    let compressed: Double
    let cached: Double
    let swap: Double?

    static func from(_ stats: vm_statistics64_data_t, pageSize: Double, total: Double, swap: Double?) -> MemorySample {
        let compressed = Double(stats.compressor_page_count) * pageSize
        let cached = (Double(stats.purgeable_count) + Double(stats.external_page_count)) * pageSize
        let resident = (Double(stats.active_count) + Double(stats.inactive_count) + Double(stats.speculative_count) + Double(stats.wire_count)) * pageSize
        return MemorySample(used: min(total, max(0, resident + compressed - cached)), total: total,
                            compressed: compressed, cached: cached, swap: swap)
    }
    static func gb(_ bytes: Double, precision: Int = 2) -> String {
        String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), precision, bytes / 1_073_741_824)
    }
}

struct SystemSample: Codable {
    let time: TimeInterval
    let cpu: Double?
    let gpu: Double?
    let memory: MemorySample?

    // Only used by the explicit reference-image command; live views always collect real data.
    static var referenceHistory: [SystemSample] {
        (0..<120).map { index in
            let x = Double(index)
            return SystemSample(time: x,
                cpu: index == 119 ? 9 : max(1, 9 + sin(x * 0.19) * 3 + sin(x * 0.73) * 1.6 + 17 * exp(-pow((x - 72) / 6, 2))),
                gpu: index == 119 ? 18 : max(1, 18 + sin(x * 0.15) * 4 + sin(x * 0.61) * 1.4 + 14 * exp(-pow((x - 41) / 5, 2))),
                memory: MemorySample(used: 12.12 * 1_073_741_824, total: 16 * 1_073_741_824,
                    compressed: 4.06 * 1_073_741_824, cached: 2.81 * 1_073_741_824, swap: 2.86 * 1_073_741_824))
        }
    }
}

struct StatsHistory {
    private(set) var samples: [SystemSample] = []
    mutating func append(_ sample: SystemSample) {
        samples.append(sample)
        samples.removeAll { $0.time < sample.time - 119 }
        if samples.count > 120 { samples.removeFirst(samples.count - 120) }
    }
}

// All reads run on a dedicated serial queue, never in draw() or the animation timer.
final class SystemStatsReader {
    private var previousCPU: CPUCounters?
    private let host = mach_host_self()
    deinit { mach_port_deallocate(mach_task_self_, host) }
    func reset() { previousCPU = nil }

    func sample() -> SystemSample {
        SystemSample(time: ProcessInfo.processInfo.systemUptime, cpu: readCPU(), gpu: readGPU(), memory: readMemory())
    }
    private func readCPU() -> Double? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { previousCPU = nil; return nil }
        let ticks = info.cpu_ticks
        let current = CPUCounters(user: ticks.0, system: ticks.1, idle: ticks.2, nice: ticks.3)
        defer { previousCPU = current }
        return previousCPU.flatMap { current.usage(since: $0) }
    }
    static func gpuUsage(in properties: [String: Any]) -> Double? {
        for key in ["Device Utilization %", "GPU Activity(%)"] {
            if let value = (properties[key] as? NSNumber)?.doubleValue, value.isFinite, (0...100).contains(value) { return value }
        }
        return nil
    }
    private func readGPU() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var values: [Double] = []
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            if let properties = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
               let value = Self.gpuUsage(in: properties) { values.append(value) }
        }
        // On multi-GPU machines display the busiest device; Apple silicon has one GPU.
        return values.max()
    }
    private func readMemory() -> MemorySample? {
        var basic = host_basic_info_data_t()
        var basicCount = mach_msg_type_number_t(MemoryLayout.size(ofValue: basic) / MemoryLayout<integer_t>.size)
        let basicResult = withUnsafeMutablePointer(to: &basic) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(basicCount)) {
                host_info(host, HOST_BASIC_INFO, $0, &basicCount)
            }
        }
        guard basicResult == KERN_SUCCESS, basic.max_mem > 0 else { return nil }
        var stats = vm_statistics64_data_t()
        // Request the revision supported by macOS 13+, not newer SDK-only trailing fields.
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.offset(of: \.swapped_count)! / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS else { return nil }
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let swapResult = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0)
        return MemorySample.from(stats, pageSize: Double(pageSize), total: Double(basic.max_mem),
                                 swap: swapResult == 0 ? Double(swap.xsu_used) : nil)
    }
}

final class SystemStatsMonitor {
    var onChange: (() -> Void)?
    private(set) var history = StatsHistory()
    private let reader = SystemStatsReader()
    private let agentReader = AgentStatusReader()
    private(set) var agents = AgentStatus.inactive
    private let queue = DispatchQueue(label: "com.neosaver.metrics", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var generation = 0

    func start() {
        guard timer == nil else { return }
        generation += 1
        let version = generation
        history = StatsHistory()
        queue.async { [reader] in reader.reset() }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let sample = self.reader.sample()
            let agents = self.agentReader.sample()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == version, self.timer != nil else { return }
                self.history.append(sample); self.agents = agents; self.onChange?()
            }
        }
        self.timer = timer
        timer.resume()
    }
    func stop() { generation += 1; timer?.cancel(); timer = nil }
    deinit { timer?.cancel() }
}
