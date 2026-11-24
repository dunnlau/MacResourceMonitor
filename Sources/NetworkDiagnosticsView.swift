import SwiftUI

struct NetworkDiagnosticsView: View {
    @ObservedObject var model: NetworkDiagnosticsMonitor
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let snap = model.snapshot
        VStack(alignment: .leading, spacing: InterfaceMetrics.sectionSpacing) {
            HStack(spacing: 12) {
                MetricSummaryCard(
                    title: "Wi-Fi 信号强度",
                    value: snap.wifi.rssiDbm.map { "\($0) dBm" } ?? "--",
                    detail: wifiSignalDetail(snap.wifi),
                    symbol: "wifi",
                    tint: wifiTint(snap.wifi.rssiDbm)
                )
                MetricSummaryCard(
                    title: "物理协商速率",
                    value: snap.wifi.transmitRateMbps.map { String(format: "%.0f Mbps", $0) } ?? "--",
                    detail: wifiChannelDetail(snap.wifi),
                    symbol: "speedometer",
                    tint: InterfacePalette.accent
                )
                MetricSummaryCard(
                    title: "网关 / 公网延迟",
                    value: latencyHeadline(gateway: snap.gatewayLatencyMs, internet: snap.internetLatencyMs),
                    detail: "路由器 \(formatMs(snap.gatewayLatencyMs)) · 1.1.1.1 \(formatMs(snap.internetLatencyMs))",
                    symbol: "waveform.path.ecg",
                    tint: InterfacePalette.signal
                )
            }

            latencyChartCard

            networkConfigCard(snap.config, wifi: snap.wifi)
        }
        .onAppear { model.setActive(true) }
        .onDisappear { model.setActive(false) }
    }

    private var latencyChartCard: some View {
        let allValues = (model.gatewayHistory + model.internetHistory).compactMap { $0 }
        let peak = max(20.0, (allValues.max() ?? 20.0) * 1.15)

        return VStack(alignment: .leading, spacing: 12) {
            SectionCardHeader(
                title: "网络延迟走势",
                subtitle: "每 3 秒探测 · 刻度上限 \(String(format: "%.0f ms", peak))",
                symbol: "waveform.path.ecg",
                tint: InterfacePalette.signal
            ) {
                HStack(spacing: 8) {
                    ChartLegendPill(label: "默认网关", color: InterfacePalette.signal)
                    ChartLegendPill(label: "公网 1.1.1.1", color: InterfacePalette.accent)
                }
            }

            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    Path { path in
                        for step in 1..<4 {
                            let y = size.height * CGFloat(step) / 4.0
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                        }
                    }
                    .stroke(
                        InterfacePalette.chartGrid,
                        style: StrokeStyle(lineWidth: 1, dash: [3, 4])
                    )

                    optionalAreaPath(values: model.internetHistory, peak: peak, size: size)
                        .fill(
                            LinearGradient(
                                colors: [
                                    InterfacePalette.accent.opacity(colorScheme == .dark ? 0.22 : 0.14),
                                    InterfacePalette.accent.opacity(0.01)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    optionalSeriesPath(values: model.gatewayHistory, peak: peak, size: size)
                        .stroke(InterfacePalette.signal, style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))

                    optionalSeriesPath(values: model.internetHistory, peak: peak, size: size)
                        .stroke(InterfacePalette.accent, style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(height: 98)
            .clipped()
        }
        .padding(InterfaceMetrics.cardPadding)
        .stableDashboardCard()
    }

    private func optionalSeriesPath(values: [Double?], peak: Double, size: CGSize) -> Path {
        Path { path in
            guard values.count > 1, peak > 0 else { return }
            let stepX = size.width / CGFloat(values.count - 1)
            var started = false
            for (index, rawValue) in values.enumerated() {
                guard let value = rawValue else {
                    started = false
                    continue
                }
                let x = CGFloat(index) * stepX
                let normalized = min(1, max(0, value / peak))
                let y = size.height * (1 - CGFloat(normalized))
                if !started {
                    path.move(to: CGPoint(x: x, y: y))
                    started = true
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
    }

    private func optionalAreaPath(values: [Double?], peak: Double, size: CGSize) -> Path {
        Path { path in
            guard values.count > 1, peak > 0 else { return }
            let stepX = size.width / CGFloat(values.count - 1)
            var segmentStartX: CGFloat?
            var lastX: CGFloat = 0

            for (index, rawValue) in values.enumerated() {
                if let value = rawValue {
                    let x = CGFloat(index) * stepX
                    let normalized = min(1, max(0, value / peak))
                    let y = size.height * (1 - CGFloat(normalized))
                    if segmentStartX == nil {
                        segmentStartX = x
                        path.move(to: CGPoint(x: x, y: size.height))
                        path.addLine(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    lastX = x
                } else if segmentStartX != nil {
                    path.addLine(to: CGPoint(x: lastX, y: size.height))
                    path.closeSubpath()
                    segmentStartX = nil
                }
            }

            if segmentStartX != nil {
                path.addLine(to: CGPoint(x: lastX, y: size.height))
                path.closeSubpath()
            }
        }
    }

    private func networkConfigCard(_ config: NetworkConfigSnapshot, wifi: WiFiStatusSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionCardHeader(
                title: "接口与路由配置",
                subtitle: "活跃网卡、IP 地址、DNS 与系统代理",
                symbol: "point.3.connected.trianglepath.dotted",
                tint: InterfacePalette.accent
            ) {
                StatusBadge(text: config.primaryInterface, tint: InterfacePalette.accent, showDot: true)
            }

            VStack(spacing: 2) {
                detailRow("Wi-Fi 网络", wifi.available ? "\(wifi.ssidDisplay)（\(wifi.interfaceName)）" : wifi.ssidDisplay)
                Divider().opacity(0.35)
                detailRow("本机 IPv4", config.localIPv4 ?? "--")
                Divider().opacity(0.35)
                detailRow("本机 IPv6", config.localIPv6 ?? "未分配")
                Divider().opacity(0.35)
                detailRow("默认网关", config.routerIP ?? "--")
                if let routerIPv6 = config.routerIPv6, !routerIPv6.isEmpty {
                    Divider().opacity(0.35)
                    detailRow("IPv6 网关", routerIPv6)
                }
                Divider().opacity(0.35)
                detailRow("DNS 服务器", config.dnsServers.isEmpty ? "--" : config.dnsServers.joined(separator: ", "))
                Divider().opacity(0.35)
                detailRow("系统代理", config.proxySummary)
            }
        }
        .padding(InterfaceMetrics.cardPadding)
        .stableDashboardCard()
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(InterfaceTypography.caption)
                .foregroundStyle(InterfacePalette.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .hoverRowHighlight(cornerRadius: 6)
    }

    private func wifiSignalDetail(_ wifi: WiFiStatusSnapshot) -> String {
        guard wifi.available else { return "未连接或使用有线网卡" }
        var parts = [wifi.signalQualityText]
        if let noise = wifi.noiseDbm { parts.append("噪声 \(noise) dBm") }
        if let snr = wifi.snrDb { parts.append("SNR \(snr) dB") }
        return parts.joined(separator: " · ")
    }

    private func wifiChannelDetail(_ wifi: WiFiStatusSnapshot) -> String {
        guard wifi.available else { return "无无线协商信息" }
        var parts: [String] = []
        if let band = wifi.bandLabel { parts.append(band) }
        if let ch = wifi.channelNumber { parts.append("信道 \(ch)") }
        if let width = wifi.channelWidthLabel { parts.append(width) }
        return parts.isEmpty ? wifi.interfaceName : parts.joined(separator: " · ")
    }

    private func wifiTint(_ rssi: Int?) -> Color {
        guard let rssi else { return InterfacePalette.textSecondary }
        if rssi >= -67 { return InterfacePalette.signal }
        if rssi >= -75 { return InterfacePalette.upload }
        return InterfacePalette.temperature
    }

    private func latencyHeadline(gateway: Double?, internet: Double?) -> String {
        if let internet { return String(format: "%.0f ms", internet) }
        if let gateway { return String(format: "%.1f ms", gateway) }
        return "--"
    }

    private func formatMs(_ value: Double?) -> String {
        guard let value else { return "--" }
        return value < 10 ? String(format: "%.1f ms", value) : String(format: "%.0f ms", value)
    }
}
