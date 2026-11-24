import SwiftUI

struct NetworkDiagnosticsView: View {
    @ObservedObject var model: NetworkDiagnosticsMonitor
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let snap = model.snapshot
        VStack(alignment: .leading, spacing: InterfaceMetrics.sectionSpacing) {
            diagnosticsHeroBento(snap)

            HStack(alignment: .top, spacing: InterfaceMetrics.sectionSpacing) {
                latencyChartCard
                networkConfigCard(snap.config, wifi: snap.wifi)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { model.setActive(true) }
        .onDisappear { model.setActive(false) }
    }

    private func diagnosticsHeroBento(_ snap: NetworkDiagnosticsSnapshot) -> some View {
        HStack(alignment: .top, spacing: InterfaceMetrics.sectionSpacing) {
            wifiSignalHeroCard(snap.wifi)
            wifiLinkHeroCard(snap.wifi, primaryInterface: snap.config.primaryInterface)
            latencyPulseCard(snap)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func wifiSignalHeroCard(_ wifi: WiFiStatusSnapshot) -> some View {
        let tint = wifiTint(wifi.rssiDbm)
        let signalProgress: Double = {
            guard let rssi = wifi.rssiDbm else { return 0 }
            return min(100, max(0, (Double(rssi) + 95.0) / 55.0 * 100.0))
        }()

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                IconBadge(symbol: "wifi", tint: tint, size: 24, iconSize: 11.5, cornerRadius: 6)
                Text("Wi-Fi 信号")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                StatusBadge(
                    text: wifi.available ? wifi.signalQualityText : "未连接",
                    tint: tint,
                    showDot: wifi.available
                )
            }

            HStack(alignment: .center, spacing: 14) {
                RadialGaugeRing(
                    progress: signalProgress,
                    tint: tint,
                    valueText: wifi.rssiDbm.map { "\($0)" } ?? "--",
                    caption: "dBm",
                    size: 74,
                    lineWidth: 6.5
                )

                VStack(alignment: .leading, spacing: 6) {
                    inlineStat("信噪比 SNR", wifi.snrDb.map { "\($0) dB" } ?? "--", tint: .primary)
                    inlineStat("背景噪声", wifi.noiseDbm.map { "\($0) dBm" } ?? "--", tint: InterfacePalette.textSecondary)
                    inlineStat("接口网卡", wifi.available ? wifi.interfaceName : "--", tint: InterfacePalette.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)

            Text(wifi.available ? wifi.ssidDisplay : "当前使用有线网卡或未连 Wi-Fi")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(InterfacePalette.textTertiary)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .stableDashboardCard()
    }

    private func wifiLinkHeroCard(_ wifi: WiFiStatusSnapshot, primaryInterface: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                IconBadge(symbol: "speedometer", tint: InterfacePalette.accent, size: 24, iconSize: 11.5, cornerRadius: 6)
                Text("物理协商速率")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                StatusBadge(text: primaryInterface, tint: InterfacePalette.accent)
            }

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(wifi.transmitRateMbps.map { String(format: "%.0f", $0) } ?? "--")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text("Mbps")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(InterfacePalette.textSecondary)
            }

            HStack(spacing: 8) {
                compactPill(title: "频段", value: wifi.bandLabel ?? "--")
                compactPill(title: "信道", value: wifi.channelNumber.map { "CH \($0)" } ?? "--")
                compactPill(title: "频宽", value: wifi.channelWidthLabel ?? "--")
            }

            Spacer(minLength: 0)

            Text(wifi.available ? "无线物理层实时协商参数" : "无无线协商信息")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(InterfacePalette.textTertiary)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .stableDashboardCard()
    }

    private func latencyPulseCard(_ snap: NetworkDiagnosticsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                StatusBadge(text: "PING · 3s", tint: InterfacePalette.signal, showDot: true)
                Spacer(minLength: 4)
                Text("实时延迟")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(InterfacePalette.textTertiary)
            }

            VStack(spacing: 8) {
                latencyRow(
                    label: "默认网关",
                    value: formatMs(snap.gatewayLatencyMs),
                    symbol: "wifi.router.fill",
                    tint: latencyTint(snap.gatewayLatencyMs)
                )
                latencyRow(
                    label: "公网 1.1.1.1",
                    value: formatMs(snap.internetLatencyMs),
                    symbol: "globe",
                    tint: latencyTint(snap.internetLatencyMs)
                )
            }

            Spacer(minLength: 0)

            Text(snap.config.routerIP.map { "网关 \($0)" } ?? "等待路由探测")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(InterfacePalette.textTertiary)
                .lineLimit(1)
        }
        .padding(16)
        .frame(width: 320, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .stableDashboardCard()
    }

    private func latencyRow(label: String, value: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 9) {
            IconBadge(symbol: symbol, tint: tint, size: 24, iconSize: 11, cornerRadius: 6)
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(InterfacePalette.textSecondary)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(value == "--" ? InterfacePalette.textSecondary : tint)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            InterfacePalette.subtleSurface,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private func inlineStat(_ title: String, _ value: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(InterfacePalette.textTertiary)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
    }

    private func compactPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(InterfacePalette.textTertiary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            InterfacePalette.subtleSurface,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
    }

    private var latencyChartCard: some View {
        let allValues = (model.gatewayHistory + model.internetHistory).compactMap { $0 }
        let peak = max(20.0, (allValues.max() ?? 20.0) * 1.15)

        return VStack(alignment: .leading, spacing: 14) {
            SectionCardHeader(
                title: "网络延迟走势",
                subtitle: "每 3 秒探测 · 上限 \(String(format: "%.0f ms", peak))",
                symbol: "waveform.path.ecg",
                tint: InterfacePalette.signal
            ) {
                HStack(spacing: 8) {
                    ChartLegendPill(label: "网关", color: InterfacePalette.signal)
                    ChartLegendPill(label: "1.1.1.1", color: InterfacePalette.accent)
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
            .frame(minHeight: 184, maxHeight: .infinity)
            .clipped()
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        VStack(alignment: .leading, spacing: 10) {
            SectionCardHeader(
                title: "路由与配置",
                subtitle: wifi.available ? wifi.ssidDisplay : config.primaryInterface,
                symbol: "point.3.connected.trianglepath.dotted",
                tint: InterfacePalette.accent
            )

            VStack(spacing: 0) {
                detailRow("本机 IPv4", config.localIPv4 ?? "--")
                rowDivider
                detailRow("本机 IPv6", config.localIPv6 ?? "未分配")
                rowDivider
                detailRow("默认网关", config.routerIP ?? "--")
                if let routerIPv6 = config.routerIPv6, !routerIPv6.isEmpty {
                    rowDivider
                    detailRow("IPv6 网关", routerIPv6)
                }
                rowDivider
                detailRow("DNS 服务器", config.dnsServers.isEmpty ? "--" : config.dnsServers.joined(separator: ", "))
                rowDivider
                detailRow("系统代理", config.proxySummary)
            }
        }
        .padding(18)
        .frame(width: 320, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .stableDashboardCard()
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(InterfaceTypography.caption)
                .foregroundStyle(InterfacePalette.textSecondary)
            Spacer(minLength: 10)
            Text(value)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(.vertical, 7)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(InterfacePalette.separator)
            .frame(height: 1)
    }

    private func wifiTint(_ rssi: Int?) -> Color {
        guard let rssi else { return InterfacePalette.textSecondary }
        if rssi >= -67 { return InterfacePalette.signal }
        if rssi >= -75 { return InterfacePalette.upload }
        return InterfacePalette.temperature
    }

    private func latencyTint(_ ms: Double?) -> Color {
        guard let ms else { return InterfacePalette.textSecondary }
        if ms < 25 { return InterfacePalette.signal }
        if ms < 80 { return InterfacePalette.upload }
        return InterfacePalette.temperature
    }

    private func formatMs(_ value: Double?) -> String {
        guard let value else { return "--" }
        return value < 10 ? String(format: "%.1f ms", value) : String(format: "%.0f ms", value)
    }
}
