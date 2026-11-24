import SwiftUI
import AppKit

struct LocalPortsTableSection: View {
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
        let total = model.snapshot.entries.count
        let loopbackCount = model.snapshot.entries.filter(\.isLoopbackOnly).count
        let externalCount = total - loopbackCount

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SearchToolbarField(placeholder: "搜索端口号、应用名、地址或 PID…", text: $searchText)

                ToolbarToggleChip(
                    title: "仅本机回环 (\(loopbackCount))",
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

                if externalCount > 0 {
                    StatusBadge(text: "对外开放 \(externalCount)", tint: InterfacePalette.upload, showDot: true)
                }

                ActionPillButton(
                    title: model.isRefreshing ? "扫描中" : "重新扫描",
                    symbol: "arrow.clockwise",
                    isDisabled: model.isRefreshing
                ) {
                    model.refresh()
                }
            }

            if let error = model.snapshot.errorText {
                statusRow(symbol: "exclamationmark.triangle.fill", tint: InterfacePalette.upload, title: "暂时无法扫描本地端口", detail: error)
            } else if model.snapshot.updatedAt == nil {
                statusRow(symbol: "network", tint: InterfacePalette.accent, title: "正在扫描本机监听端口…", detail: "只读检测当前用户进程")
            } else if filteredEntries.isEmpty {
                statusRow(symbol: "checkmark.circle.fill", tint: InterfacePalette.signal, title: "暂无匹配的监听端口", detail: "尝试清除搜索词或启动本地开发服务")
            } else {
                portsTable
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
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                InterfacePalette.subtleSurface,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )

            LazyVStack(spacing: 0) {
                ForEach(Array(filteredEntries.enumerated()), id: \.element.id) { index, entry in
                    portRow(entry)
                    if index < filteredEntries.count - 1 {
                        Divider()
                            .opacity(0.32)
                            .padding(.leading, 12)
                    }
                }
            }
        }
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
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .hoverRowHighlight(cornerRadius: 7)
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

    private func statusRow(symbol: String, tint: Color, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol, tint: tint, size: 30, iconSize: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(InterfaceTypography.caption).foregroundStyle(InterfacePalette.textSecondary)
            }
            Spacer()
            if model.isRefreshing { ProgressView().controlSize(.small) }
        }
        .padding(14)
        .background(
            InterfacePalette.subtleSurface,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
    }
}
