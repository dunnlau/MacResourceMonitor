import Foundation
import SwiftUI
import AppKit
import Darwin

struct ProcessTrafficRow: Identifiable, Equatable {
    let pid: Int32
    let name: String
    let subtitle: String?
    let bundlePath: String?
    let isProxyTunnel: Bool
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double
    let sessionDownloadedBytes: UInt64
    let sessionUploadedBytes: UInt64

    init(
        pid: Int32,
        name: String,
        subtitle: String? = nil,
        bundlePath: String? = nil,
        isProxyTunnel: Bool = false,
        downloadBytesPerSecond: Double,
        uploadBytesPerSecond: Double,
        sessionDownloadedBytes: UInt64,
        sessionUploadedBytes: UInt64
    ) {
        self.pid = pid
        self.name = name
        self.subtitle = subtitle
        self.bundlePath = bundlePath
        self.isProxyTunnel = isProxyTunnel
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.sessionDownloadedBytes = sessionDownloadedBytes
        self.sessionUploadedBytes = sessionUploadedBytes
    }

    var id: Int32 { pid }
    var currentBytesPerSecond: Double { downloadBytesPerSecond + uploadBytesPerSecond }
    var sessionBytes: UInt64 { sessionDownloadedBytes + sessionUploadedBytes }
}

struct ProcessTrafficDisplayState {
    var rows: [ProcessTrafficRow] = []
    var allRows: [ProcessTrafficRow] = []
    var downloadBytesPerSecond = 0.0
    var uploadBytesPerSecond = 0.0
    var sessionDownloadedBytes: UInt64 = 0
    var sessionUploadedBytes: UInt64 = 0
    var proxyTunnelDownloadBytesPerSecond = 0.0
    var proxyTunnelUploadBytesPerSecond = 0.0
    var proxyTunnelSessionBytes: UInt64 = 0
    var proxyTunnelNames: [String] = []
    var lastUpdatedAt: Date?
    var errorText: String?
    var isCollecting = false
}

struct ProcessTrafficSnapshot {
    let pid: Int32
    let name: String
    let subtitle: String?
    let bundlePath: String?
    let isProxyTunnel: Bool
    let processStartedAt: UInt64?
    let downloadedBytes: UInt64
    let uploadedBytes: UInt64
}

enum ProcessTrafficCollectionResult {
    case success(rows: [ProcessTrafficSnapshot])
    case failure(String)
}

enum ProcessTrafficConsumer: Hashable {
    case dashboard
    case menuBar
}

private enum ProcessTrafficCollector {
    private static let proxyKeywords: [String] = [
        "quantumult",
        "surge",
        "clash",
        "mihomo",
        "sing-box",
        "v2ray",
        "xray",
        "privoxy",
        "tun2socks",
        "shadowsocks",
        "loon",
        "stash",
        "wireguard",
        "tailscaled",
        "nesessionmanager"
    ]

    static func collect() -> ProcessTrafficCollectionResult {
        guard let result = CommandRunner.run(
            "/usr/bin/nettop",
            arguments: [
                "-P", "-n", "-x", "-c",
                "-L", "1",
                "-J", "bytes_in,bytes_out"
            ],
            timeout: 2
        ) else {
            return .failure("无法启动 macOS nettop")
        }

        if result.timedOut {
            return .failure("进程流量采样超时")
        }
        guard result.terminationStatus == 0 else {
            let detail = result.errorString.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(detail.isEmpty ? "nettop 返回错误 \(result.terminationStatus)" : detail)
        }

        guard let snapshots = parseSnapshot(result.outputString) else {
            return .failure("nettop 未返回进程流量快照")
        }

        return .success(rows: snapshots)
    }

    private static func parseSnapshot(_ output: String) -> [ProcessTrafficSnapshot]? {
        var rows: [ProcessTrafficSnapshot] = []
        var foundHeader = false

        for rawLine in output.split(whereSeparator: \Character.isNewline) {
            let fields = parseCSVLine(String(rawLine))
            guard fields.count >= 3 else { continue }

            if fields[1] == "bytes_in", fields[2] == "bytes_out" {
                foundHeader = true
                continue
            }

            guard foundHeader,
                  let identity = parseIdentity(fields[0]),
                  let downloaded = UInt64(fields[1]),
                  let uploaded = UInt64(fields[2]) else { continue }

            let metadata = resolveProcessMetadata(pid: identity.pid, fallback: identity.name)
            rows.append(ProcessTrafficSnapshot(
                pid: identity.pid,
                name: metadata.displayName,
                subtitle: metadata.subtitle,
                bundlePath: metadata.bundlePath,
                isProxyTunnel: metadata.isProxyTunnel,
                processStartedAt: processStartIdentifier(pid: identity.pid),
                downloadedBytes: downloaded,
                uploadedBytes: uploaded
            ))
        }

        return foundHeader ? rows : nil
    }

    private static func parseIdentity(_ value: String) -> (name: String, pid: Int32)? {
        guard let separator = value.lastIndex(of: "."),
              let pid = Int32(value[value.index(after: separator)...]) else { return nil }
        let name = String(value[..<separator]).trimmingCharacters(in: .whitespaces)
        return (name.isEmpty ? "未知进程" : name, pid)
    }

    private static func resolveProcessMetadata(
        pid: Int32,
        fallback: String
    ) -> (displayName: String, subtitle: String?, bundlePath: String?, isProxyTunnel: Bool) {
        let fullPath = processExecutablePath(pid: pid)
        let leafName = fullPath.map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? shortProcessName(pid: pid)
            ?? fallback

        var topAppBundlePath: String?
        var topAppName: String?
        var isAppExtension = false

        if let fullPath {
            if fullPath.contains(".appex/") {
                isAppExtension = true
            }
            let components = fullPath.split(separator: "/", omittingEmptySubsequences: false)
            var currentPath = ""
            for component in components {
                if component.isEmpty { continue }
                currentPath += "/\(component)"
                if component.hasSuffix(".app"), topAppBundlePath == nil {
                    topAppBundlePath = currentPath
                    topAppName = String(component.dropLast(4))
                }
            }
        }

        let combinedLower = "\(leafName) \(topAppName ?? "") \(fullPath ?? "")".lowercased()
        let isTunnel = isAppExtension && (combinedLower.contains("tunnel") || combinedLower.contains("packet") || combinedLower.contains("vpn"))
            || proxyKeywords.contains { combinedLower.contains($0) }

        if let topAppName, !topAppName.isEmpty {
            if isTunnel {
                let tunnelTitle = leafName.localizedCaseInsensitiveContains(topAppName) ? leafName : "\(topAppName) (\(leafName))"
                return (tunnelTitle, "代理 / TUN 隧道守护进程", topAppBundlePath, true)
            }
            if leafName != topAppName {
                return (topAppName, leafName, topAppBundlePath, false)
            }
            return (topAppName, nil, topAppBundlePath, false)
        }

        return (leafName, isTunnel ? "代理 / TUN 转发服务" : nil, nil, isTunnel)
    }

    private static func processExecutablePath(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let path = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    private static func shortProcessName(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 1024)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let name = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private static func processStartIdentifier(pid: Int32) -> UInt64? {
        var info = proc_bsdinfo()
        let expectedSize = Int32(MemoryLayout<proc_bsdinfo>.stride)
        let actualSize = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, expectedSize)
        guard actualSize == expectedSize else { return nil }
        return info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec
    }

    private static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var field = ""
        var isQuoted = false
        var index = line.startIndex

        while index < line.endIndex {
            let character = line[index]
            if character == "\"" {
                let next = line.index(after: index)
                if isQuoted, next < line.endIndex, line[next] == "\"" {
                    field.append("\"")
                    index = line.index(after: next)
                    continue
                }
                isQuoted.toggle()
            } else if character == ",", !isQuoted {
                fields.append(field)
                field = ""
            } else {
                field.append(character)
            }
            index = line.index(after: index)
        }
        fields.append(field)
        return fields
    }
}

final class ProcessNetworkMonitor: ObservableObject {
    private static let dashboardRefreshInterval: TimeInterval = 1.6
    private static let menuBarRefreshInterval: TimeInterval = 1.8
    private static let coldStartFastInterval: TimeInterval = 0.32
    private static let reusableBaselineMaxAge: TimeInterval = 15.0

    @Published private(set) var displayState = ProcessTrafficDisplayState()
    @Published var filterProxyTunnels: Bool = true {
        didSet {
            if filterProxyTunnels != oldValue {
                rebuildDisplayRows()
            }
        }
    }

    var rows: [ProcessTrafficRow] { displayState.rows }
    var downloadBytesPerSecond: Double { displayState.downloadBytesPerSecond }
    var uploadBytesPerSecond: Double { displayState.uploadBytesPerSecond }
    var sessionDownloadedBytes: UInt64 { displayState.sessionDownloadedBytes }
    var sessionUploadedBytes: UInt64 { displayState.sessionUploadedBytes }
    var lastUpdatedAt: Date? { displayState.lastUpdatedAt }
    var errorText: String? { displayState.errorText }
    var isCollecting: Bool { displayState.isCollecting }

    private struct SessionEntry {
        var name: String
        var subtitle: String?
        var bundlePath: String?
        var isProxyTunnel: Bool
        var processStartedAt: UInt64?
        var downloadedBytes: UInt64
        var uploadedBytes: UInt64
        var lastSeen: Date
    }

    private struct CumulativeCounter {
        var name: String
        var subtitle: String?
        var bundlePath: String?
        var isProxyTunnel: Bool
        var processStartedAt: UInt64?
        var downloadedBytes: UInt64
        var uploadedBytes: UInt64
    }

    private let queue = DispatchQueue(label: "local.mac-resource-monitor.process-network", qos: .userInitiated)
    private var sessionEntries: [Int32: SessionEntry] = [:]
    private var retiredSessionDownloadedBytes: UInt64 = 0
    private var retiredSessionUploadedBytes: UInt64 = 0
    private var previousCounters: [Int32: CumulativeCounter] = [:]
    private var previousSnapshotAt: Date?
    private var latestLiveRates: [Int32: (download: Double, upload: Double)] = [:]
    private var activeConsumers: Set<ProcessTrafficConsumer> = []
    private var collectionScheduled = false
    private var collectionGeneration: UInt64 = 0

    func setActive(_ active: Bool, for consumer: ProcessTrafficConsumer) {
        let wasCollecting = !activeConsumers.isEmpty
        let wasDashboardActive = activeConsumers.contains(.dashboard)
        if active {
            activeConsumers.insert(consumer)
        } else {
            activeConsumers.remove(consumer)
        }

        let shouldCollect = !activeConsumers.isEmpty
        let isDashboardActive = activeConsumers.contains(.dashboard)
        guard shouldCollect != wasCollecting || isDashboardActive != wasDashboardActive else { return }

        collectionGeneration &+= 1
        if shouldCollect {
            if !wasCollecting {
                var next = displayState
                next.errorText = nil
                next.isCollecting = true
                displayState = next
            }
            scheduleCollection()
        } else {
            // Keep previousCounters & previousSnapshotAt in memory so re-entering the view is instant!
            clearLiveRates()
        }
    }

    func resetSessionTotals() {
        collectionGeneration &+= 1
        sessionEntries.removeAll()
        retiredSessionDownloadedBytes = 0
        retiredSessionUploadedBytes = 0
        previousCounters.removeAll()
        previousSnapshotAt = nil
        latestLiveRates.removeAll()

        var next = ProcessTrafficDisplayState()
        next.isCollecting = !activeConsumers.isEmpty
        displayState = next

        if !activeConsumers.isEmpty {
            scheduleCollection()
        }
    }

    private func scheduleCollection() {
        guard !activeConsumers.isEmpty, !collectionScheduled else { return }
        collectionScheduled = true
        let generation = collectionGeneration
        let hadRecentBaseline: Bool = {
            guard let prev = previousSnapshotAt else { return false }
            return Date().timeIntervalSince(prev) <= Self.reusableBaselineMaxAge
        }()

        queue.async { [weak self] in
            let result = ProcessTrafficCollector.collect()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.collectionScheduled = false

                guard generation == self.collectionGeneration else {
                    let shouldContinue = !self.activeConsumers.isEmpty
                    self.setCollecting(shouldContinue)
                    if shouldContinue {
                        self.scheduleCollection()
                    }
                    return
                }

                guard !self.activeConsumers.isEmpty else {
                    self.setCollecting(false)
                    return
                }

                self.apply(result)
                // If we just captured a fresh baseline (or resumed after >15s), follow up in 0.32s for instant rates!
                let refreshInterval: TimeInterval
                if !hadRecentBaseline {
                    refreshInterval = Self.coldStartFastInterval
                } else if self.activeConsumers.contains(.dashboard) {
                    refreshInterval = Self.dashboardRefreshInterval
                } else {
                    refreshInterval = Self.menuBarRefreshInterval
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + refreshInterval) { [weak self] in
                    guard let self,
                          generation == self.collectionGeneration,
                          !self.activeConsumers.isEmpty else { return }
                    self.scheduleCollection()
                }
            }
        }
    }

    private func clearLiveRates() {
        latestLiveRates.removeAll()
        var next = displayState
        next.downloadBytesPerSecond = 0
        next.uploadBytesPerSecond = 0
        next.proxyTunnelDownloadBytesPerSecond = 0
        next.proxyTunnelUploadBytesPerSecond = 0
        next.isCollecting = false
        next.allRows = next.allRows.map {
            ProcessTrafficRow(
                pid: $0.pid,
                name: $0.name,
                subtitle: $0.subtitle,
                bundlePath: $0.bundlePath,
                isProxyTunnel: $0.isProxyTunnel,
                downloadBytesPerSecond: 0,
                uploadBytesPerSecond: 0,
                sessionDownloadedBytes: $0.sessionDownloadedBytes,
                sessionUploadedBytes: $0.sessionUploadedBytes
            )
        }
        next.rows = filterProxyTunnels ? next.allRows.filter { !$0.isProxyTunnel } : next.allRows
        displayState = next
    }

    private func setCollecting(_ collecting: Bool) {
        guard displayState.isCollecting != collecting else { return }
        var next = displayState
        next.isCollecting = collecting
        displayState = next
    }

    private static func isSameProcess(
        _ previous: CumulativeCounter?,
        _ current: CumulativeCounter
    ) -> Bool {
        matchesProcess(
            previousName: previous?.name,
            previousStart: previous?.processStartedAt,
            current: current
        )
    }

    private static func isSameProcess(
        _ previous: SessionEntry?,
        _ current: CumulativeCounter
    ) -> Bool {
        matchesProcess(
            previousName: previous?.name,
            previousStart: previous?.processStartedAt,
            current: current
        )
    }

    private static func matchesProcess(
        previousName: String?,
        previousStart: UInt64?,
        current: CumulativeCounter
    ) -> Bool {
        guard let previousName else { return false }
        if let previousStart, let currentStart = current.processStartedAt {
            return previousStart == currentStart
        }
        return previousName == current.name
    }

    func apply(_ result: ProcessTrafficCollectionResult) {
        switch result {
        case let .failure(message):
            clearLiveRates()
            var next = displayState
            next.errorText = message
            next.isCollecting = false
            displayState = next

        case let .success(snapshots):
            let now = Date()
            let currentCounters = Dictionary(
                snapshots.map { snapshot in
                    (
                        snapshot.pid,
                        CumulativeCounter(
                            name: snapshot.name,
                            subtitle: snapshot.subtitle,
                            bundlePath: snapshot.bundlePath,
                            isProxyTunnel: snapshot.isProxyTunnel,
                            processStartedAt: snapshot.processStartedAt,
                            downloadedBytes: snapshot.downloadedBytes,
                            uploadedBytes: snapshot.uploadedBytes
                        )
                    )
                },
                uniquingKeysWith: { _, latest in latest }
            )

            guard let previousSnapshotAt,
                  now.timeIntervalSince(previousSnapshotAt) <= Self.reusableBaselineMaxAge else {
                previousCounters = currentCounters
                self.previousSnapshotAt = now
                var next = displayState
                next.errorText = nil
                next.isCollecting = true
                displayState = next
                return
            }

            let safeDuration = max(0.1, now.timeIntervalSince(previousSnapshotAt))
            let activePIDs = Set(currentCounters.keys)
            var liveRates: [Int32: (download: Double, upload: Double)] = [:]

            for (pid, counter) in currentCounters {
                let previous = previousCounters[pid]
                let isSameProcess = Self.isSameProcess(previous, counter)
                let downloadedDelta = isSameProcess
                    ? counter.downloadedBytes.subtractingWithoutUnderflow(previous?.downloadedBytes ?? counter.downloadedBytes)
                    : 0
                let uploadedDelta = isSameProcess
                    ? counter.uploadedBytes.subtractingWithoutUnderflow(previous?.uploadedBytes ?? counter.uploadedBytes)
                    : 0
                let current = sessionEntries[pid]
                let continuesSession = Self.isSameProcess(current, counter)
                if let current, !continuesSession, !current.isProxyTunnel {
                    retiredSessionDownloadedBytes += current.downloadedBytes
                    retiredSessionUploadedBytes += current.uploadedBytes
                }
                sessionEntries[pid] = SessionEntry(
                    name: counter.name,
                    subtitle: counter.subtitle,
                    bundlePath: counter.bundlePath,
                    isProxyTunnel: counter.isProxyTunnel,
                    processStartedAt: counter.processStartedAt,
                    downloadedBytes: (continuesSession ? current?.downloadedBytes ?? 0 : 0) + downloadedDelta,
                    uploadedBytes: (continuesSession ? current?.uploadedBytes ?? 0 : 0) + uploadedDelta,
                    lastSeen: now
                )
                liveRates[pid] = (
                    Double(downloadedDelta) / safeDuration,
                    Double(uploadedDelta) / safeDuration
                )
            }

            previousCounters = currentCounters
            self.previousSnapshotAt = now
            self.latestLiveRates = liveRates

            let expiredEntries = sessionEntries.filter { pid, entry in
                !activePIDs.contains(pid) && now.timeIntervalSince(entry.lastSeen) >= 120
            }
            for entry in expiredEntries.values where !entry.isProxyTunnel {
                retiredSessionDownloadedBytes += entry.downloadedBytes
                retiredSessionUploadedBytes += entry.uploadedBytes
            }
            sessionEntries = sessionEntries.filter { pid, entry in
                activePIDs.contains(pid) || now.timeIntervalSince(entry.lastSeen) < 120
            }

            rebuildDisplayRows(at: now)
        }
    }

    private func rebuildDisplayRows(at timestamp: Date? = nil) {
        let allRows = sessionEntries.map { pid, entry in
            let rate = latestLiveRates[pid] ?? (0, 0)
            return ProcessTrafficRow(
                pid: pid,
                name: entry.name,
                subtitle: entry.subtitle,
                bundlePath: entry.bundlePath,
                isProxyTunnel: entry.isProxyTunnel,
                downloadBytesPerSecond: rate.download,
                uploadBytesPerSecond: rate.upload,
                sessionDownloadedBytes: entry.downloadedBytes,
                sessionUploadedBytes: entry.uploadedBytes
            )
        }
        .sorted {
            if $0.currentBytesPerSecond != $1.currentBytesPerSecond {
                return $0.currentBytesPerSecond > $1.currentBytesPerSecond
            }
            return $0.sessionBytes > $1.sessionBytes
        }

        let visibleRows = filterProxyTunnels
            ? allRows.filter { !$0.isProxyTunnel }
            : allRows

        let tunnelRows = allRows.filter(\.isProxyTunnel)
        let appRows = allRows.filter { !$0.isProxyTunnel }

        var next = displayState
        next.allRows = Array(allRows.prefix(120))
        next.rows = Array(visibleRows.prefix(100))
        next.downloadBytesPerSecond = appRows.reduce(0) { $0 + $1.downloadBytesPerSecond }
        next.uploadBytesPerSecond = appRows.reduce(0) { $0 + $1.uploadBytesPerSecond }
        next.sessionDownloadedBytes = retiredSessionDownloadedBytes
            + appRows.reduce(0) { $0 + $1.sessionDownloadedBytes }
        next.sessionUploadedBytes = retiredSessionUploadedBytes
            + appRows.reduce(0) { $0 + $1.sessionUploadedBytes }
        next.proxyTunnelDownloadBytesPerSecond = tunnelRows.reduce(0) { $0 + $1.downloadBytesPerSecond }
        next.proxyTunnelUploadBytesPerSecond = tunnelRows.reduce(0) { $0 + $1.uploadBytesPerSecond }
        next.proxyTunnelSessionBytes = tunnelRows.reduce(0) { $0 + $1.sessionBytes }
        next.proxyTunnelNames = Array(Set(tunnelRows.map(\.name))).sorted()
        if let timestamp {
            next.lastUpdatedAt = timestamp
            next.errorText = nil
            next.isCollecting = false
        }
        displayState = next
    }
}

private extension UInt64 {
    func subtractingWithoutUnderflow(_ previous: UInt64) -> UInt64 {
        self >= previous ? self - previous : 0
    }
}
