import SwiftUI

struct NetworkDiagnosticsView: View {
    @ObservedObject var model: NetworkDiagnosticsMonitor

    var body: some View {
        let snap = model.snapshot
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                summaryCard(
                    title: "Wi-Fi 信号强度",
                    value: snap.wifi.rssiDbm.map { "\($0) dBm" } ?? "--",
                    detail: wifiSignalDetail(snap.wifi),
                    symbol: "wifi",
                    tint: wifiTint(snap.wifi.rssiDbm)
                )
                summaryCard(
                    title: "物理协商速率",
                    value: snap.wifi.transmitRateMbps.map { String(format: "%.0f Mbps", $0) } ?? "--",
                    detail: wifiChannelDetail(snap.wifi),
                    symbol: "speedometer",
                    tint: InterfacePalette.accent
                )
                summaryCard(
                    title: "网关 / 公网延迟",
                    value: latencyHeadline(gateway: snap.gatewayLatencyMs, internet: snap.internetLatencyMs),
                    detail: "路由器 \(formatMs(snap.gatewayLatencyMs)) · 1.1.1.1 \(formatMs(snap.internetLatencyMs))",
                    symbol: "waveform.path.ecg",
                    tint: InterfacePalette.download
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

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("网络延迟走势（每 3 秒探测）")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                HStack(spacing: 12) {
                    legendDot("默认网关", color: InterfacePalette.download)
                    legendDot("公网 1.1.1.1", color: InterfacePalette.accent)
                    Text(String(format: "刻度 %.0f ms", peak))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(InterfacePalette.textTertiary)
                }
            }

            GeometryReader { proxy in
                ZStack {
                    Path { path in
                        for step in 1..<4 {
                            let y = proxy.size.height * CGFloat(step) / 4.0
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                        }
                    }
                    .stroke(InterfacePalette.chartGrid, lineWidth: 1)

                    optionalSeriesPath(values: model.gatewayHistory, peak: peak, size: proxy.size)
                        .stroke(InterfacePalette.download, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))

                    optionalSeriesPath(values: model.internetHistory, peak: peak, size: proxy.size)
                        .stroke(InterfacePalette.accent, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(height: 84)
        }
        .padding(16)
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

    private func networkConfigCard(_ config: NetworkConfigSnapshot, wifi: WiFiStatusSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("接口与路由配置")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(config.primaryInterface)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(InterfacePalette.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }

            VStack(spacing: 8) {
                detailRow("Wi-Fi 网络", wifi.available ? "\(wifi.ssidDisplay)（\(wifi.interfaceName)）" : wifi.ssidDisplay)
                Divider().opacity(0.35)
                detailRow("本机 IPv4", config.localIPv4 ?? "--")
                Divider().opacity(0.35)
                detailRow("默认网关", config.routerIP ?? "--")
                Divider().opacity(0.35)
                detailRow("DNS 服务器", config.dnsServers.isEmpty ? "--" : config.dnsServers.joined(separator: ", "))
                Divider().opacity(0.35)
                detailRow("系统代理", config.proxySummary)
            }
        }
        .padding(16)
        .stableDashboardCard()
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(InterfaceTypography.caption)
                .foregroundStyle(InterfacePalette.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func legendDot(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(InterfacePalette.textSecondary)
        }
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
        if rssi >= -67 { return InterfacePalette.download }
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

    private func summaryCard(
        title: String,
        value: String,
        detail: String,
        symbol: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(InterfacePalette.textSecondary)
                Spacer()
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tint)
            }
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(detail)
                .font(InterfaceTypography.microMetadata)
                .foregroundStyle(InterfacePalette.textTertiary)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .stableDashboardCard()
    }
}
