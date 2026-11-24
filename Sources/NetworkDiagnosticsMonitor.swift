import Foundation
import SystemConfiguration
import CoreWLAN

struct WiFiStatusSnapshot: Equatable {
    var available = false
    var interfaceName = "--"
    var ssidDisplay = "未连接"
    var rssiDbm: Int? = nil
    var noiseDbm: Int? = nil
    var snrDb: Int? = nil
    var transmitRateMbps: Double? = nil
    var channelNumber: Int? = nil
    var bandLabel: String? = nil
    var channelWidthLabel: String? = nil

    var signalQualityText: String {
        guard let rssi = rssiDbm else { return "--" }
        if rssi >= -55 { return "极佳" }
        if rssi >= -67 { return "良好" }
        if rssi >= -75 { return "一般" }
        return "较弱"
    }
}

struct NetworkConfigSnapshot: Equatable {
    var primaryInterface = "--"
    var localIPv4: String? = nil
    var routerIP: String? = nil
    var dnsServers: [String] = []
    var proxySummary = "未开启系统代理"
    var isProxyEnabled = false
}

struct NetworkDiagnosticsSnapshot: Equatable {
    var wifi = WiFiStatusSnapshot()
    var config = NetworkConfigSnapshot()
    var gatewayLatencyMs: Double? = nil
    var internetLatencyMs: Double? = nil
    var updatedAt: Date? = nil
}

enum NetworkDiagnosticsParser {
    /// Extracts RTT milliseconds from macOS `ping -c 1` output, e.g. `time=12.345 ms`.
    static func parsePingLatencyMs(_ output: String) -> Double? {
        guard let range = output.range(of: #"time=([0-9]+(?:\.[0-9]+)?)\s*ms"#, options: .regularExpression) else {
            return nil
        }
        let matched = String(output[range])
        guard let eqIndex = matched.firstIndex(of: "=") else { return nil }
        let afterEq = matched[matched.index(after: eqIndex)...]
            .replacingOccurrences(of: "ms", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(afterEq), value.isFinite, value >= 0 else { return nil }
        return value
    }
}

/// Accessed exclusively on NetworkDiagnosticsMonitor's serial queue.
final class NetworkDiagnosticsCollector: @unchecked Sendable {
    func collect(includeLatencyProbe: Bool = true) -> NetworkDiagnosticsSnapshot {
        let wifi = readWiFi()
        let config = readNetworkConfig()
        var gatewayMs: Double? = nil
        var internetMs: Double? = nil

        if includeLatencyProbe {
            if let router = config.routerIP, !router.isEmpty {
                gatewayMs = pingOnce(host: router)
            }
            internetMs = pingOnce(host: "1.1.1.1")
        }

        return NetworkDiagnosticsSnapshot(
            wifi: wifi,
            config: config,
            gatewayLatencyMs: gatewayMs,
            internetLatencyMs: internetMs,
            updatedAt: Date()
        )
    }

    private func readWiFi() -> WiFiStatusSnapshot {
        guard let iface = CWWiFiClient.shared().interface() else {
            return WiFiStatusSnapshot()
        }
        let ifaceName = iface.interfaceName ?? "en0"
        let rssi = iface.rssiValue()
        let noise = iface.noiseMeasurement()
        let txRate = iface.transmitRate()
        let connected = rssi != 0 || txRate > 0

        guard connected else {
            return WiFiStatusSnapshot(
                available: false,
                interfaceName: ifaceName,
                ssidDisplay: "未连接 Wi-Fi"
            )
        }

        let ssidRaw = iface.ssid()?.trimmingCharacters(in: .whitespacesAndNewlines)
        let ssidDisplay = (ssidRaw?.isEmpty == false) ? ssidRaw! : "已连接（SSID 受隐私保护）"

        var channelNumber: Int? = nil
        var bandLabel: String? = nil
        var widthLabel: String? = nil
        if let channel = iface.wlanChannel() {
            channelNumber = channel.channelNumber
            switch channel.channelBand {
            case .band2GHz: bandLabel = "2.4 GHz"
            case .band5GHz: bandLabel = "5 GHz"
            case .band6GHz: bandLabel = "6 GHz"
            default: bandLabel = nil
            }
            switch channel.channelWidth {
            case .width20MHz: widthLabel = "20 MHz"
            case .width40MHz: widthLabel = "40 MHz"
            case .width80MHz: widthLabel = "80 MHz"
            case .width160MHz: widthLabel = "160 MHz"
            default: widthLabel = nil
            }
        }

        let validNoise = noise != 0 ? noise : nil
        let snr = validNoise.map { rssi - $0 }

        return WiFiStatusSnapshot(
            available: true,
            interfaceName: ifaceName,
            ssidDisplay: ssidDisplay,
            rssiDbm: rssi != 0 ? rssi : nil,
            noiseDbm: validNoise,
            snrDb: snr,
            transmitRateMbps: txRate > 0 ? txRate : nil,
            channelNumber: channelNumber,
            bandLabel: bandLabel,
            channelWidthLabel: widthLabel
        )
    }

    private func readNetworkConfig() -> NetworkConfigSnapshot {
        guard let store = SCDynamicStoreCreate(nil, "MacResourceMonitor.NetDiag" as CFString, nil, nil) else {
            return NetworkConfigSnapshot()
        }

        var primaryIface = "--"
        var routerIP: String? = nil
        var primaryServiceID: String? = nil

        if let globalIPv4 = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] {
            if let iface = globalIPv4["PrimaryInterface"] as? String, !iface.isEmpty {
                primaryIface = iface
            }
            routerIP = globalIPv4["Router"] as? String
            primaryServiceID = globalIPv4["PrimaryService"] as? String
        }

        var localIPv4: String? = nil
        if let serviceID = primaryServiceID,
           let serviceIPv4 = SCDynamicStoreCopyValue(
               store,
               "State:/Network/Service/\(serviceID)/IPv4" as CFString
           ) as? [String: Any],
           let addresses = serviceIPv4["Addresses"] as? [String] {
            localIPv4 = addresses.first
        }

        var dnsServers: [String] = []
        if let dns = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any],
           let servers = dns["ServerAddresses"] as? [String] {
            dnsServers = servers
        }

        var proxyParts: [String] = []
        if let proxies = SCDynamicStoreCopyProxies(store) as? [String: Any] {
            if (proxies[kSCPropNetProxiesHTTPEnable as String] as? NSNumber)?.boolValue == true,
               let host = proxies[kSCPropNetProxiesHTTPProxy as String] as? String {
                let port = (proxies[kSCPropNetProxiesHTTPPort as String] as? NSNumber)?.intValue
                proxyParts.append("HTTP \(host)\(port.map { ":\($0)" } ?? "")")
            }
            if (proxies[kSCPropNetProxiesHTTPSEnable as String] as? NSNumber)?.boolValue == true,
               let host = proxies[kSCPropNetProxiesHTTPSProxy as String] as? String {
                let port = (proxies[kSCPropNetProxiesHTTPSPort as String] as? NSNumber)?.intValue
                proxyParts.append("HTTPS \(host)\(port.map { ":\($0)" } ?? "")")
            }
            if (proxies[kSCPropNetProxiesSOCKSEnable as String] as? NSNumber)?.boolValue == true,
               let host = proxies[kSCPropNetProxiesSOCKSProxy as String] as? String {
                let port = (proxies[kSCPropNetProxiesSOCKSPort as String] as? NSNumber)?.intValue
                proxyParts.append("SOCKS \(host)\(port.map { ":\($0)" } ?? "")")
            }
        }

        return NetworkConfigSnapshot(
            primaryInterface: primaryIface,
            localIPv4: localIPv4,
            routerIP: routerIP,
            dnsServers: dnsServers,
            proxySummary: proxyParts.isEmpty ? "未开启系统代理" : proxyParts.joined(separator: " · "),
            isProxyEnabled: !proxyParts.isEmpty
        )
    }

    private func pingOnce(host: String) -> Double? {
        guard let result = CommandRunner.run(
            "/sbin/ping",
            arguments: ["-c", "1", "-t", "2", host],
            timeout: 2.5
        ), !result.timedOut, result.terminationStatus == 0 else {
            return nil
        }
        return NetworkDiagnosticsParser.parsePingLatencyMs(result.outputString)
    }
}

@MainActor
final class NetworkDiagnosticsMonitor: ObservableObject {
    @Published private(set) var snapshot = NetworkDiagnosticsSnapshot()
    @Published private(set) var gatewayHistory: [Double?] = Array(repeating: nil, count: 40)
    @Published private(set) var internetHistory: [Double?] = Array(repeating: nil, count: 40)
    @Published private(set) var isRefreshing = false

    private let collector = NetworkDiagnosticsCollector()
    private let queue = DispatchQueue(label: "local.mac-resource-monitor.net-diag", qos: .utility)
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
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
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
            let next = collector.collect(includeLatencyProbe: true)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isRefreshing = false
                guard self.generation == currentGen else { return }
                self.snapshot = next
                self.gatewayHistory = Array(self.gatewayHistory.suffix(39)) + [next.gatewayLatencyMs]
                self.internetHistory = Array(self.internetHistory.suffix(39)) + [next.internetLatencyMs]
            }
        }
    }
}
