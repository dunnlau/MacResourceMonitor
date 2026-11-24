import Foundation
import Darwin

struct LocalPortEntry: Identifiable, Equatable {
    let id: String
    let pid: Int32
    let processName: String
    let subtitle: String?
    let bundlePath: String?
    let port: Int
    let bindAddress: String
    let ipVersion: String

    var isLoopbackOnly: Bool {
        bindAddress == "127.0.0.1" || bindAddress == "::1" || bindAddress == "localhost"
    }

    var localURLString: String {
        "http://localhost:\(port)"
    }
}

struct LocalPortsSnapshot: Equatable {
    var entries: [LocalPortEntry] = []
    var errorText: String? = nil
    var updatedAt: Date? = nil
}

enum LocalPortsParser {
    /// Parses `lsof -nP -iTCP -sTCP:LISTEN -F pcPn` machine-readable output.
    static func parseLsofFieldOutput(
        _ output: String,
        resolveMetadata: (Int32, String) -> (name: String, subtitle: String?, bundlePath: String?) = { _, fallback in
            (fallback, nil, nil)
        }
    ) -> [LocalPortEntry] {
        var currentPID: Int32?
        var currentCommand = ""
        var currentProto = "TCP"
        var entries: [LocalPortEntry] = []
        var seen = Set<String>()

        for rawLine in output.split(whereSeparator: \.isNewline) {
            guard let prefix = rawLine.first else { continue }
            let value = String(rawLine.dropFirst())
            switch prefix {
            case "p":
                currentPID = Int32(value)
                currentCommand = ""
            case "c":
                currentCommand = value
            case "P":
                currentProto = value
            case "n":
                guard let pid = currentPID, currentProto.uppercased() == "TCP" else { continue }
                guard let parsed = parseEndpoint(value) else { continue }
                let dedupeKey = "\(pid)-\(parsed.address)-\(parsed.port)"
                guard seen.insert(dedupeKey).inserted else { continue }
                let meta = resolveMetadata(pid, currentCommand.isEmpty ? "PID \(pid)" : currentCommand)
                entries.append(LocalPortEntry(
                    id: dedupeKey,
                    pid: pid,
                    processName: meta.name,
                    subtitle: meta.subtitle,
                    bundlePath: meta.bundlePath,
                    port: parsed.port,
                    bindAddress: parsed.address,
                    ipVersion: parsed.ipVersion
                ))
            default:
                continue
            }
        }

        return entries.sorted { lhs, rhs in
            if lhs.port != rhs.port { return lhs.port < rhs.port }
            return lhs.pid < rhs.pid
        }
    }

    private static func parseEndpoint(_ raw: String) -> (address: String, port: Int, ipVersion: String)? {
        let cleaned = raw
            .replacingOccurrences(of: " (LISTEN)", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let colonIndex = cleaned.lastIndex(of: ":") else { return nil }
        let portString = String(cleaned[cleaned.index(after: colonIndex)...])
        guard let port = Int(portString), port > 0, port <= 65535 else { return nil }
        let hostRaw = String(cleaned[..<colonIndex])
        let isIPv6 = hostRaw.hasPrefix("[") && hostRaw.hasSuffix("]")
        let address = isIPv6
            ? String(hostRaw.dropFirst().dropLast())
            : (hostRaw.isEmpty ? "*" : hostRaw)
        let ipVersion = (isIPv6 || address.contains(":")) ? "IPv6" : "IPv4"
        return (address, port, ipVersion)
    }
}

/// Accessed exclusively on a dedicated background queue.
final class LocalPortsCollector: @unchecked Sendable {
    func collect() -> LocalPortsSnapshot {
        guard let result = CommandRunner.run(
            "/usr/sbin/lsof",
            arguments: ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcPn"],
            timeout: 4
        ) else {
            return LocalPortsSnapshot(errorText: "无法启动 lsof 扫描监听端口", updatedAt: Date())
        }
        if result.timedOut {
            return LocalPortsSnapshot(errorText: "端口扫描超时", updatedAt: Date())
        }
        // lsof returns exit code 1 when no listening TCP sockets match for current user.
        if result.terminationStatus != 0 && result.standardOutput.isEmpty {
            return LocalPortsSnapshot(entries: [], errorText: nil, updatedAt: Date())
        }

        let entries = LocalPortsParser.parseLsofFieldOutput(result.outputString) { pid, fallback in
            Self.resolveProcess(pid: pid, fallback: fallback)
        }
        return LocalPortsSnapshot(entries: entries, errorText: nil, updatedAt: Date())
    }

    private static func resolveProcess(
        pid: Int32,
        fallback: String
    ) -> (name: String, subtitle: String?, bundlePath: String?) {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else {
            return (fallback, nil, nil)
        }
        let fullPath = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fullPath.isEmpty else { return (fallback, nil, nil) }
        let leafName = URL(fileURLWithPath: fullPath).lastPathComponent

        let components = fullPath.split(separator: "/", omittingEmptySubsequences: false)
        var currentPath = ""
        for component in components {
            if component.isEmpty { continue }
            currentPath += "/\(component)"
            if component.hasSuffix(".app") {
                let appName = String(component.dropLast(4))
                if !appName.isEmpty {
                    let sub = leafName == appName ? nil : leafName
                    return (appName, sub, currentPath)
                }
            }
        }
        return (leafName.isEmpty ? fallback : leafName, nil, nil)
    }
}

@MainActor
final class LocalPortsMonitor: ObservableObject {
    @Published private(set) var snapshot = LocalPortsSnapshot()
    @Published private(set) var isRefreshing = false

    private let collector = LocalPortsCollector()
    private let queue = DispatchQueue(label: "local.mac-resource-monitor.local-ports", qos: .utility)
    private var isActive = false
    private var pollTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    deinit { pollTask?.cancel() }

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        generation &+= 1
        pollTask?.cancel()
        pollTask = nil

        if active {
            refresh()
            let currentGen = generation
            pollTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 3_500_000_000)
                    guard !Task.isCancelled, let self, self.isActive, self.generation == currentGen else { break }
                    self.refresh()
                }
            }
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let collector = self.collector
        let currentGen = generation
        queue.async { [weak self] in
            let next = collector.collect()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isRefreshing = false
                guard self.generation == currentGen else { return }
                self.snapshot = next
            }
        }
    }

    func terminateProcess(pid: Int32) {
        guard pid > 1, pid != getpid() else { return }
        _ = kill(pid, SIGTERM)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            self?.refresh()
        }
    }
}
