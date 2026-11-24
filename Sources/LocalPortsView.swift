import SwiftUI
import AppKit

struct LocalPortsView: View {
    @ObservedObject var model: LocalPortsMonitor
    @State private var searchText = ""
    @State private var loopbackOnly = false
    @State private var copiedPortID: String? = nil
    @Environment(\.colorScheme) private var colorScheme

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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                summaryCard(
                    title: "监听端口总数",
                    value: "\(model.snapshot.entries.count)",
                    detail: "当前用户 TCP LISTEN 端口",
                    symbol: "network",
                    tint: InterfacePalette.accent
                )
                summaryCard(
                    title: "仅本机回环",
                    value: "\(model.snapshot.entries.filter(\.isLoopbackOnly).count)",
                    detail: "127.0.0.1 / ::1 本地服务",
                    symbol: "lock.shield",
                    tint: InterfacePalette.download
                )
                summaryCard(
                    title: "对外网卡开放",
                    value: "\(model.snapshot.entries.filter { !$0.isLoopbackOnly }.count)",
                    detail: "监听 0.0.0.0 / * / 局域网地址",
                    symbol: "globe",
                    tint: InterfacePalette.upload
                )
            }

            toolbar

            if let error = model.snapshot.errorText {
                statusCard(symbol: "exclamationmark.triangle", title: "暂时无法扫描本地端口", detail: error)
            } else if model.snapshot.updatedAt == nil {
                statusCard(symbol: "network", title: "正在扫描本机监听端口…", detail: "只读检测当前用户进程")
            } else if filteredEntries.isEmpty {
                statusCard(symbol: "checkmark.circle", title: "暂无匹配的监听端口", detail: "尝试清除搜索词或启动本地开发服务")
            } else {
                portsTable
            }
        }
        .onAppear { model.setActive(true) }
        .onDisappear { model.setActive(false) }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(InterfacePalette.textSecondary)
                TextField("搜索端口号、应用名、地址或 PID…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(InterfacePalette.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.045))
            )

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    loopbackOnly.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: loopbackOnly ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12, weight: .medium))
                    Text("仅看本机回环")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(loopbackOnly ? Color.primary : InterfacePalette.textSecondary)
                .padding(.horizontal, 11)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(loopbackOnly ? (colorScheme == .dark ? 0.11 : 0.08) : 0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(InterfacePalette.cardStroke, lineWidth: 0.6)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var portsTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("端口")
                    .frame(width: 72, alignment: .leading)
                Text("进程与服务")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("绑定地址")
                    .frame(width: 140, alignment: .leading)
                Text("操作")
                    .frame(width: 96, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(InterfacePalette.textTertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.02))

            Divider().opacity(0.5)

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
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(InterfacePalette.accent)
                .frame(width: 72, alignment: .leading)

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
                                .font(.system(size: 11))
                                .foregroundStyle(InterfacePalette.textSecondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .lineLimit(1)
                        }
                    }
                    Text("PID \(entry.pid) · \(entry.ipVersion)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(InterfacePalette.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 5) {
                Circle()
                    .fill(entry.isLoopbackOnly ? InterfacePalette.download : InterfacePalette.upload)
                    .frame(width: 5, height: 5)
                Text(entry.bindAddress)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(InterfacePalette.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 140, alignment: .leading)

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
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(copiedPortID == entry.id ? InterfacePalette.download : InterfacePalette.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("复制 \(entry.localURLString)")

                Button {
                    if let url = URL(string: entry.localURLString) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "safari")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(InterfacePalette.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("在浏览器打开 \(entry.localURLString)")

                Button {
                    model.terminateProcess(pid: entry.pid)
                } label: {
                    Image(systemName: "stop.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(InterfacePalette.temperature)
                        .frame(width: 26, height: 26)
                        .background(InterfacePalette.temperature.opacity(0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("发送 SIGTERM 停止进程 \(entry.processName) (PID \(entry.pid))")
            }
            .frame(width: 96, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .overlay {
                    Text(String(entry.processName.prefix(1)).uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(InterfacePalette.textSecondary)
                }
                .frame(width: 22, height: 22)
        }
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
            Text(detail)
                .font(InterfaceTypography.microMetadata)
                .foregroundStyle(InterfacePalette.textTertiary)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .stableDashboardCard()
    }

    private func statusCard(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(InterfacePalette.textSecondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(InterfaceTypography.caption).foregroundStyle(InterfacePalette.textSecondary)
            }
            Spacer()
            if model.isRefreshing { ProgressView().controlSize(.small) }
        }
        .padding(18)
        .stableDashboardCard()
    }
}
