import AppKit
import Darwin

enum AgentKind: String, CaseIterable, Codable {
    case claude, codex, cursor

    var name: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .claude: return "com.anthropic.claudefordesktop"
        case .codex: return "com.openai.codex"
        case .cursor: return "com.todesktop.230313mzl4w4u92"
        }
    }

    func matchesExecutable(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        // A crash reporter or Electron helper can outlive its app. Match the
        // actual agent executable, never just an enclosing application folder.
        if url.lastPathComponent.lowercased() == rawValue { return true }
        let mainExecutable = self == .codex ? "chatgpt" : rawValue
        let mainPath = ["\(rawValue).app", "contents", "macos", mainExecutable]
        return Array(url.pathComponents.suffix(4)).map { $0.lowercased() } == mainPath
    }
}

struct AgentStatus: Codable {
    let agent: AgentKind
    let isRunning: Bool
    static let inactive = AgentKind.allCases.map { AgentStatus(agent: $0, isRunning: false) }
}

final class AgentStatusReader {
    static func statuses(bundleIdentifiers: Set<String>, executablePaths: [String]) -> [AgentStatus] {
        AgentKind.allCases.map { agent in
            AgentStatus(agent: agent, isRunning: bundleIdentifiers.contains(agent.bundleIdentifier) ||
                        executablePaths.contains(where: agent.matchesExecutable))
        }
    }

    func sample() -> [AgentStatus] {
        let bundleIdentifiers = Set(NSWorkspace.shared.runningApplications.compactMap { app in
            app.isTerminated ? nil : app.bundleIdentifier
        })
        let estimatedCount = proc_listallpids(nil, 0)
        guard estimatedCount > 0 else {
            return Self.statuses(bundleIdentifiers: bundleIdentifiers, executablePaths: [])
        }
        var pids = [pid_t](repeating: 0, count: Int(estimatedCount) + 64)
        let capacity = Int32(pids.count * MemoryLayout<pid_t>.size)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, capacity) }
        var paths: [String] = []
        for pid in pids.prefix(max(0, min(Int(count), pids.count))) where pid > 0 {
            var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            let length = path.withUnsafeMutableBytes {
                proc_pidpath(pid, $0.baseAddress, UInt32($0.count))
            }
            if length > 0 { paths.append(String(cString: path)) }
        }
        return Self.statuses(bundleIdentifiers: bundleIdentifiers, executablePaths: paths)
    }
}
