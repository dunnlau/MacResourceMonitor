import SwiftUI
import AppKit

struct LocalPortsView: View {
    @ObservedObject var model: LocalPortsMonitor
    @State private var searchText = ""
    @State private var loopbackOnly = false
    @State private var copiedPortID: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var filteredEntries: [LocalPortEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.snapshot.entries.filter { entry in
            if loopbackOnly && !entry.isLoopbackOnly { return false }
            guard !query.isEmpty else { return true }
            return String(entry.port).contains(query)
                || entry.processName.localizedCaseInsensitiveContains(query)
                || (entry.subtitle?.localizedCaseInsensitiveContains(query) == true)
                || entry.bindAddress.localizedCaseInsensitiveContains(query)
                || String(entry.pid).contains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: InterfaceMetrics.sectionSpacing) {
            portsHeroBento

            toolbar

            if let error = model.snapshot.errorText {
                statusCard(symbol: "exclamationmark.triangle.fill", tint: InterfacePalette.upload, title: "暂时无法扫描本地端口", detail: error)
            } else if model.snapshot.updatedAt == nil {
                statusCard(symbol: "network", tint: InterfacePalette.accent, title: "正在扫描本机监听端口…", detail: "只读检测当前用户进程")
            } else if filteredEntries.isEmpty {
                statusCard(symbol: "checkmark.circle.fill", tint: InterfacePalette.signal, title: "暂无匹配的监听端口", detail: "尝试清除搜索词或启动本地开发服务")
            } else {
                portsTable
            }
        }
        .onAppear { model.setActive(true) }
        .onDisappear { model.setActive(false) }
    }

    private var portsHeroBento: some View {
        let total = model.snapshot.entries.count
        let loopbackCount = model.snapshot.entries.filter(\.isLoopbackOnly).count
        let externalCount = total - loopbackCount
        let loopbackPercent = total > 0 ? (Double(loopbackCount) / Double(total)) * 100.0 : 100.0
        let ipv4Count = model.snapshot.entries.filter { $0.ipVersion.contains("4") }.count
        let ipv6Count = model.snapshot.entries.filter { $0.ipVersion.contains("6") }.count

        return HStack(alignment: .top, spacing: InterfaceMetrics.sectionSpacing) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    IconBadge(symbol: "lock.shield.fill", tint: InterfacePalette.signal, size: 24, iconSize: 11.5, cornerRadius: 6)
                    Text("端口暴露面分布")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 4)
                    StatusBadge(
                        text: externalCount == 0 ? "全部仅本机回环" : "\(externalCount) 个对外开放",
                        tint: externalCount == 0 ? InterfacePalette.signal : InterfacePalette.upload,
                        showDot: true
                    )
                }

                HStack(alignment: .center, spacing: 16) {
                    RadialGaugeRing(
                        progress: loopbackPercent,
                        tint: externalCount == 0 ? InterfacePalette.signal : InterfacePalette.accent,
                        valueText: "\(total)",
                        caption: "LISTEN",
                        size: 74,
                        lineWidth: 6.5
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            exposurePill(
                                title: "仅本机回环",
                                value: "\(loopbackCount)",
                                detail: "127.0.0.1 / ::1",
                                tint: InterfacePalette.signal
                            )
                            exposurePill(
                                title: "对外网卡开放",
                                value: "\(externalCount)",
                                detail: "0.0.0.0 / * / LAN",
                                tint: InterfacePalette.upload
                            )
                        }

                        GeometryReader { proxy in
                            let ratio = total > 0 ? CGFloat(loopbackCount) / CGFloat(total) : 1
                            HStack(spacing: 2) {
                                if loopbackCount > 0 || total == 0 {
                                    Capsule()
                                        .fill(InterfacePalette.signal)
                                        .frame(width: max(4, proxy.size.width * ratio))
                                }
                                if externalCount > 0 {
                                    Capsule()
                                        .fill(InterfacePalette.upload)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                        }
                        .frame(height: 5)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .stableDashboardCard()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    IconBadge(symbol: "network", tint: InterfacePalette.accent, size: 24, iconSize: 11.5, cornerRadius: 6)
                    Text("协议栈统计")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 4)
                    StatusBadge(text: "TCP LISTEN", tint: InterfacePalette.accent)
                }

                HStack(spacing: 10) {
                    protocolPill(title: "IPv4 服务", value: "\(ipv4Count)", tint: InterfacePalette.accent)
                    protocolPill(title: "IPv6 服务", value: "\(ipv6Count)", tint: InterfacePalette.memorySeries)
                }

                Spacer(minLength: 0)

                Text("支持一键复制、浏览器打开与 SIGTERM")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(InterfacePalette.textTertiary)
                    .lineLimit(1)
            }
            .padding(16)
            .frame(width: 320, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .stableDashboardCard()
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func exposurePill(title: String, value: String, detail: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(InterfacePalette.textSecondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(InterfacePalette.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            InterfacePalette.subtleSurface,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private func protocolPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(InterfacePalette.textTertiary)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            InterfacePalette.subtleSurface,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            SearchToolbarField(placeholder: "搜索端口号、应用名、地址或 PID…", text: $searchText)

            ToolbarToggleChip(
                title: "仅看本机回环",
                activeSymbol: "checkmark.circle.fill",
                inactiveSymbol: "circle",
                isActive: loopbackOnly
            ) {
                if reduceMotion {
                    loopbackOnly.toggle()
                } else {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        loopbackOnly.toggle()
                    }
                }
            }
        }
    }

    private var portsTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("端口")
                    .frame(width: 78, alignment: .leading)
                Text("进程与服务")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("绑定地址")
                    .frame(width: 146, alignment: .leading)
                Text("操作")
                    .frame(width: 96, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(InterfacePalette.textTertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(InterfacePalette.subtleSurface)

            Divider().opacity(0.45)

            LazyVStack(spacing: 0) {
                ForEach(Array(filteredEntries.enumerated()), id: \.element.id) { index, entry in
                    portRow(entry)
                    if index < filteredEntries.count - 1 {
                        Divider()
                            .opacity(0.35)
                            .padding(.leading, 16)
                    }
                }
            }
        }
        .stableDashboardCard()
    }

    private func portRow(_ entry: LocalPortEntry) -> some View {
        HStack(spacing: 12) {
            Text(":\(entry.port)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(InterfacePalette.accent)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(InterfacePalette.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .frame(width: 78, alignment: .leading)

            HStack(spacing: 8) {
                portIcon(entry)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.processName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if let subtitle = entry.subtitle {
                            Text(subtitle)
                                .font(.system(size: 10.5))
                                .foregroundStyle(InterfacePalette.textSecondary)
                                .padding(.horizontal, 5.5)
                                .padding(.vertical, 1.5)
                                .background(InterfacePalette.subtleSurface, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .lineLimit(1)
                        }
                    }
                    Text("PID \(entry.pid) · \(entry.ipVersion)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(InterfacePalette.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Circle()
                    .fill(entry.isLoopbackOnly ? InterfacePalette.signal : InterfacePalette.upload)
                    .frame(width: 5.5, height: 5.5)
                Text(entry.bindAddress)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(InterfacePalette.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 146, alignment: .leading)

            HStack(spacing: 6) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.localURLString, forType: .string)
                    copiedPortID = entry.id
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        if copiedPortID == entry.id { copiedPortID = nil }
                    }
                } label: {
                    Image(systemName: copiedPortID == entry.id ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(copiedPortID == entry.id ? InterfacePalette.signal : InterfacePalette.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(InterfacePalette.subtleSurface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(InterfacePalette.cardStroke, lineWidth: 0.6)
                        )
                }
                .buttonStyle(.plain)
                .help("复制 \(entry.localURLString)")
                .accessibilityLabel("复制端口地址")

                Button {
                    if let url = URL(string: entry.localURLString) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "safari")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(InterfacePalette.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(InterfacePalette.subtleSurface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(InterfacePalette.cardStroke, lineWidth: 0.6)
                        )
                }
                .buttonStyle(.plain)
                .help("在浏览器打开 \(entry.localURLString)")
                .accessibilityLabel("在浏览器打开")

                Button {
                    model.terminateProcess(pid: entry.pid)
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(InterfacePalette.temperature)
                        .frame(width: 26, height: 26)
                        .background(InterfacePalette.temperature.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(InterfacePalette.temperature.opacity(0.22), lineWidth: 0.6)
                        )
                }
                .buttonStyle(.plain)
                .help("发送 SIGTERM 停止进程 \(entry.processName) (PID \(entry.pid))")
                .accessibilityLabel("停止进程 \(entry.processName)")
            }
            .frame(width: 96, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .hoverRowHighlight()
    }

    @ViewBuilder
    private func portIcon(_ entry: LocalPortEntry) -> some View {
        let proxyRow = ProcessTrafficRow(
            pid: entry.pid,
            name: entry.processName,
            subtitle: entry.subtitle,
            bundlePath: entry.bundlePath,
            isProxyTunnel: false,
            downloadBytesPerSecond: 0,
            uploadBytesPerSecond: 0,
            sessionDownloadedBytes: 0,
            sessionUploadedBytes: 0
        )
        if let icon = ProcessIconCache.icon(for: proxyRow) {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
        } else {
            RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                .fill(InterfacePalette.iconSurface)
                .overlay {
                    Text(String(entry.processName.prefix(1)).uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(InterfacePalette.textSecondary)
                }
                .frame(width: 22, height: 22)
        }
    }

    private func statusCard(symbol: String, tint: Color, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol, tint: tint, size: 32, iconSize: 15)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(detail).font(InterfaceTypography.caption).foregroundStyle(InterfacePalette.textSecondary)
            }
            Spacer()
            if model.isRefreshing { ProgressView().controlSize(.small) }
        }
        .padding(18)
        .stableDashboardCard()
    }
}
