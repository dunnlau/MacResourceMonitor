import SwiftUI

private enum NetworkListMode: String, CaseIterable, Identifiable {
    case traffic = "进程流量"
    case ports = "本地端口"

    var id: String { rawValue }
}

/// Unified Network Monitor workspace combining Live Traffic, Wi-Fi/Latency Diagnostics,
/// Routing Config, and an inline-switchable Process Traffic / Local Ports table.
struct NetworkWorkspaceView: View {
    @ObservedObject var processNetworkModel: ProcessNetworkMonitor
    @ObservedObject var localPortsModel: LocalPortsMonitor
    @ObservedObject var diagnosticsModel: NetworkDiagnosticsMonitor
    @State private var listMode: NetworkListMode = .traffic
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let snap = diagnosticsModel.snapshot
        VStack(alignment: .leading, spacing: InterfaceMetrics.sectionSpacing) {
            unifiedHeroBento(snap)

            HStack(alignment: .top, spacing: InterfaceMetrics.sectionSpacing) {
                latencyChartCard
                networkConfigCard(snap.config, wifi: snap.wifi)
            }
            .fixedSize(horizontal: false, vertical: true)

            unifiedListCard
        }
        .onAppear {
            diagnosticsModel.setActive(true)
            processNetworkModel.setActive(true, for: .dashboard)
            localPortsModel.setActive(true)
        }
        .onDisappear {
            diagnosticsModel.setActive(false)
            processNetworkModel.setActive(false, for: .dashboard)
            localPortsModel.setActive(false)
        }
    }

    private func unifiedHeroBento(_ snap: NetworkDiagnosticsSnapshot) -> some View {
        HStack(alignment: .top, spacing: InterfaceMetrics.sectionSpacing) {
            liveTrafficHeroCard
            wifiSignalHeroCard(snap.wifi, primaryInterface: snap.config.primaryInterface)
            latencyPulseCard(snap)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var liveTrafficHeroCard: some View {
        let down = processNetworkModel.sessionDownloadedBytes
        let up = processNetworkModel.sessionUploadedBytes
        let total = down + up
        let downRatio = total > 0 ? Double(down) / Double(total) : 0.5

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                IconBadge(symbol: "arrow.up.arrow.down", tint: InterfacePalette.download, size: 24, iconSize: 11.5, cornerRadius: 6)
                Text("应用实时速率")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                StatusBadge(text: "累计 \(processTrafficBytes(total))", tint: InterfacePalette.accent)
            }

            HStack(spacing: 8) {
                compactRateTile(
                    title: "下载",
                    value: processTrafficRate(processNetworkModel.downloadBytesPerSecond),
                    symbol: "arrow.down",
                    tint: InterfacePalette.download
                )
                compactRateTile(
                    title: "上传",
                    value: processTrafficRate(processNetworkModel.uploadBytesPerSecond),
                    symbol: "arrow.up",
                    tint: InterfacePalette.upload
                )
            }

            GeometryReader { proxy in
                HStack(spacing: 2) {
                    Capsule()
                        .fill(InterfacePalette.download)
                        .frame(width: max(4, proxy.size.width * downRatio))
                    Capsule()
                        .fill(InterfacePalette.upload)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 4.5)

            HStack {
                Text("↓ \(processTrafficBytes(down))")
                Spacer()
                Text("↑ \(processTrafficBytes(up))")
            }
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(InterfacePalette.textTertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .stableDashboardCard()
    }

    private func compactRateTile(title: String, value: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(InterfacePalette.textSecondary)
            }
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            InterfacePalette.subtleSurface,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private func wifiSignalHeroCard(_ wifi: WiFiStatusSnapshot, primaryInterface: String) -> some View {
        let tint = wifiTint(wifi.rssiDbm)
        let signalProgress: Double = {
            guard let rssi = wifi.rssiDbm else { return 0 }
            return min(100, max(0, (Double(rssi) + 95.0) / 55.0 * 100.0))
        }()

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                IconBadge(symbol: "wifi", tint: tint, size: 24, iconSize: 11.5, cornerRadius: 6)
                Text("Wi-Fi 与链路")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                StatusBadge(
                    text: wifi.available ? wifi.signalQualityText : primaryInterface,
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
                    inlineStat(
                        "协商速率",
                        wifi.transmitRateMbps.map { String(format: "%.0f Mbps", $0) } ?? "--",
                        tint: .primary
                    )
                    inlineStat(
                        "频段信道",
                        wifiChannelCompact(wifi),
                        tint: InterfacePalette.textSecondary
                    )
                    inlineStat(
                        "信噪比",
                        wifi.snrDb.map { "\($0) dB" } ?? "--",
                        tint: InterfacePalette.textTertiary
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)

            Text(wifi.available ? wifi.ssidDisplay : "有线网卡 · \(primaryInterface)")
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

    private var latencyChartCard: some View {
        let allValues = (diagnosticsModel.gatewayHistory + diagnosticsModel.internetHistory).compactMap { $0 }
        let peak = max(20.0, (allValues.max() ?? 20.0) * 1.15)

        return VStack(alignment: .leading, spacing: 12) {
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

                    optionalAreaPath(values: diagnosticsModel.internetHistory, peak: peak, size: size)
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

                    optionalSeriesPath(values: diagnosticsModel.gatewayHistory, peak: peak, size: size)
                        .stroke(InterfacePalette.signal, style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))

                    optionalSeriesPath(values: diagnosticsModel.internetHistory, peak: peak, size: size)
                        .stroke(InterfacePalette.accent, style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(minHeight: 164, maxHeight: .infinity)
            .clipped()
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .stableDashboardCard()
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

    private var unifiedListCard: some View {
        let activeTrafficCount = processNetworkModel.rows.count
        let listeningPortsCount = localPortsModel.snapshot.entries.count

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                IconBadge(
                    symbol: listMode == .traffic ? "arrow.up.arrow.down.circle.fill" : "network",
                    tint: InterfacePalette.accent,
                    size: 28,
                    iconSize: 13,
                    cornerRadius: 7
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(listMode == .traffic ? "应用进程网络流量" : "本机 TCP 监听端口")
                        .font(InterfaceTypography.cardTitle)
                        .foregroundStyle(.primary)
                    Text(listMode == .traffic ? "按实时流速或累计流量排行" : "当前用户监听端口、归属应用与快捷管理")
                        .font(InterfaceTypography.microMetadata)
                        .foregroundStyle(InterfacePalette.textTertiary)
                }

                Spacer(minLength: 10)

                HStack(spacing: 2) {
                    listSwitchButton(mode: .traffic, count: activeTrafficCount)
                    listSwitchButton(mode: .ports, count: listeningPortsCount)
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(InterfacePalette.subtleSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(InterfacePalette.cardStroke, lineWidth: 0.65)
                )
            }

            switch listMode {
            case .traffic:
                ProcessTrafficTableSection(model: processNetworkModel)
            case .ports:
                LocalPortsTableSection(model: localPortsModel)
            }
        }
        .padding(18)
        .stableDashboardCard()
    }

    private func listSwitchButton(mode: NetworkListMode, count: Int) -> some View {
        let isSelected = listMode == mode
        return Button {
            if reduceMotion {
                listMode = mode
            } else {
                withAnimation(.easeInOut(duration: 0.16)) {
                    listMode = mode
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(mode.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                Text("\(count)")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isSelected ? InterfacePalette.accent : InterfacePalette.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        (isSelected ? InterfacePalette.accent.opacity(0.12) : InterfacePalette.subtleSurface),
                        in: Capsule()
                    )
            }
            .foregroundStyle(isSelected ? Color.primary : InterfacePalette.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                    .fill(
                        isSelected
                            ? (colorScheme == .dark ? Color.white.opacity(0.13) : Color.white)
                            : Color.clear
                    )
                    .shadow(
                        color: isSelected ? Color.black.opacity(colorScheme == .dark ? 0.25 : 0.08) : .clear,
                        radius: 2,
                        y: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        .padding(.vertical, 6.5)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(InterfacePalette.separator)
            .frame(height: 1)
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

    private func wifiChannelCompact(_ wifi: WiFiStatusSnapshot) -> String {
        guard wifi.available else { return "--" }
        var parts: [String] = []
        if let band = wifi.bandLabel { parts.append(band) }
        if let ch = wifi.channelNumber { parts.append("CH \(ch)") }
        return parts.isEmpty ? wifi.interfaceName : parts.joined(separator: " · ")
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
