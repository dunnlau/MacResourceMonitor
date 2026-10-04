import SwiftUI
import AppKit

private enum ProcessTrafficSort: String, CaseIterable, Identifiable {
    case current = "当前流速"
    case download = "下载"
    case upload = "上传"
    case session = "累计"

    var id: String { rawValue }
}

private struct TrafficSortSegmentedControl: View {
    @Binding var selection: ProcessTrafficSort
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ProcessTrafficSort.allCases) { option in
                let isSelected = selection == option
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection = option
                    }
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.primary : InterfacePalette.textSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(
                                    isSelected
                                        ? (colorScheme == .dark ? Color.white.opacity(0.14) : Color.white)
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
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.055))
        )
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct ProcessTrafficView: View {
    @ObservedObject var model: ProcessNetworkMonitor
    @State private var searchText = ""
    @State private var sort: ProcessTrafficSort = .current
    @Environment(\.colorScheme) private var colorScheme

    private var visibleRows: [ProcessTrafficRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = model.rows.filter { row in
            query.isEmpty
                || row.name.localizedCaseInsensitiveContains(query)
                || (row.subtitle?.localizedCaseInsensitiveContains(query) == true)
                || String(row.pid).contains(query)
        }
        return filtered.sorted { lhs, rhs in
            switch sort {
            case .current: return lhs.currentBytesPerSecond > rhs.currentBytesPerSecond
            case .download: return lhs.downloadBytesPerSecond > rhs.downloadBytesPerSecond
            case .upload: return lhs.uploadBytesPerSecond > rhs.uploadBytesPerSecond
            case .session: return lhs.sessionBytes > rhs.sessionBytes
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                summaryCard(
                    title: "实时应用下载",
                    value: processTrafficRate(model.downloadBytesPerSecond),
                    detail: "已剥离代理隧道二次汇总",
                    symbol: "arrow.down"
                )
                summaryCard(
                    title: "实时应用上传",
                    value: processTrafficRate(model.uploadBytesPerSecond),
                    detail: "已剥离代理隧道二次汇总",
                    symbol: "arrow.up"
                )
                summaryCard(
                    title: "本次监控累计",
                    value: processTrafficBytes(model.sessionDownloadedBytes + model.sessionUploadedBytes),
                    detail: "↓ \(processTrafficBytes(model.sessionDownloadedBytes)) · ↑ \(processTrafficBytes(model.sessionUploadedBytes))",
                    symbol: "sum"
                )
            }

            if !model.displayState.proxyTunnelNames.isEmpty {
                proxyTunnelBanner
            }

            toolbarPanel

            if let error = model.errorText {
                statusCard(symbol: "exclamationmark.triangle", title: "暂时无法读取进程流量", detail: error)
            } else if model.lastUpdatedAt == nil {
                statusCard(symbol: "network", title: "正在采样进程流量", detail: "首次差分采样中（约 0.3 秒）…")
            } else if visibleRows.isEmpty {
                statusCard(symbol: "checkmark.circle", title: "暂无匹配的进程流量", detail: "尝试清除搜索词或产生一些网络请求")
            } else {
                processTable
            }

            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 11))
                    .foregroundStyle(InterfacePalette.textTertiary)
                Text("支持穿透 127.0.0.1 本地系统代理与 utun 虚拟网卡，自动剥离代理守护进程的重复转发流量。")
                    .font(InterfaceTypography.microMetadata)
                    .foregroundStyle(InterfacePalette.textTertiary)
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
        }
        .onAppear { model.setActive(true, for: .dashboard) }
        .onDisappear { model.setActive(false, for: .dashboard) }
    }

    private var toolbarPanel: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(InterfacePalette.textSecondary)
                TextField("搜索应用、子进程或 PID…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
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
                    model.filterProxyTunnels.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: model.filterProxyTunnels ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 12, weight: .medium))
                    Text(model.filterProxyTunnels ? "已剥离 TUN 代理" : "显示全部进程")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(model.filterProxyTunnels ? Color.primary : InterfacePalette.textSecondary)
                .padding(.horizontal, 11)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(model.filterProxyTunnels ? (colorScheme == .dark ? 0.11 : 0.08) : 0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(InterfacePalette.cardStroke, lineWidth: 0.6)
                )
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)

            TrafficSortSegmentedControl(selection: $sort)
        }
    }

    private var proxyTunnelBanner: some View {
        let names = model.displayState.proxyTunnelNames.joined(separator: " / ")
        let down = processTrafficRate(model.displayState.proxyTunnelDownloadBytesPerSecond)
        let up = processTrafficRate(model.displayState.proxyTunnelUploadBytesPerSecond)
        let totalSession = processTrafficBytes(model.displayState.proxyTunnelSessionBytes)

        return HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(InterfacePalette.textSecondary)
                .frame(width: 24, height: 24)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            HStack(spacing: 6) {
                Text("代理隧道：\(names)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                Text("·")
                    .foregroundStyle(InterfacePalette.textTertiary)
                Text("总转发 ↓ \(down)  ↑ \(up)  累计 \(totalSession)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(InterfacePalette.textSecondary)
            }
            .lineLimit(1)

            Spacer()

            Text(model.filterProxyTunnels ? "已从列表剥离" : "已包含在列表中")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(InterfacePalette.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .stableDashboardCard()
    }

    private var processTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("#")
                    .frame(width: 24, alignment: .trailing)
                Text("应用与进程")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("下载")
                    .frame(width: 104, alignment: .trailing)
                Text("上传")
                    .frame(width: 104, alignment: .trailing)
                Text("累计流量")
                    .frame(width: 100, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(InterfacePalette.textTertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.02))

            Divider().opacity(0.5)

            LazyVStack(spacing: 0) {
                let rows = Array(visibleRows.prefix(80))
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    processRow(row, rank: index + 1)
                    if index < rows.count - 1 {
                        Divider()
                            .opacity(0.35)
                            .padding(.leading, 52)
                    }
                }
            }
        }
        .stableDashboardCard()
    }

    private func processRow(_ row: ProcessTrafficRow, rank: Int) -> some View {
        let maxRate = max(1, visibleRows.first?.currentBytesPerSecond ?? 1)
        let ratio = min(1, max(0, row.currentBytesPerSecond / maxRate))
        let isActiveDown = row.downloadBytesPerSecond >= 1
        let isActiveUp = row.uploadBytesPerSecond >= 1

        return HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(InterfacePalette.textTertiary)
                .frame(width: 24, alignment: .trailing)

            processIcon(row: row)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(row.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let subtitle = row.subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(InterfacePalette.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .lineLimit(1)
                    }

                    if row.isProxyTunnel {
                        Text("TUN")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(InterfacePalette.textSecondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }

                    Text("PID \(row.pid)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(InterfacePalette.textTertiary)
                }

                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.primary.opacity(0.05))
                        .overlay(alignment: .leading) {
                            if ratio > 0 {
                                Capsule()
                                    .fill(InterfacePalette.accent.opacity(0.65))
                                    .frame(width: max(3, proxy.size.width * ratio))
                            }
                        }
                }
                .frame(height: 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(processTrafficRate(row.downloadBytesPerSecond))
                .font(.system(size: 12, weight: isActiveDown ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(isActiveDown ? .primary : .tertiary)
                .frame(width: 104, alignment: .trailing)

            Text(processTrafficRate(row.uploadBytesPerSecond))
                .font(.system(size: 12, weight: isActiveUp ? .medium : .regular, design: .monospaced))
                .foregroundStyle(isActiveUp ? .primary : .tertiary)
                .frame(width: 104, alignment: .trailing)

            Text(processTrafficBytes(row.sessionBytes))
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(InterfacePalette.textSecondary)
                .frame(width: 100, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func processIcon(row: ProcessTrafficRow) -> some View {
        if let icon = NSRunningApplication(processIdentifier: pid_t(row.pid))?.icon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
        } else if let bundlePath = row.bundlePath {
            Image(nsImage: NSWorkspace.shared.icon(forFile: bundlePath))
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
        } else {
            RoundedRectangle(
                cornerRadius: 6,
                style: .continuous
            )
            .fill(Color.primary.opacity(0.06))
            .overlay {
                Text(String(row.name.prefix(1)).uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(InterfacePalette.textSecondary)
            }
            .frame(width: 24, height: 24)
        }
    }

    private func summaryCard(title: String, value: String, detail: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(InterfacePalette.textSecondary)
                Spacer()
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(InterfacePalette.textTertiary)
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
            if model.isCollecting { ProgressView().controlSize(.small) }
        }
        .padding(18)
        .stableDashboardCard()
    }
}

private func processTrafficRate(_ bytesPerSecond: Double) -> String {
    "\(processTrafficBytes(UInt64(max(0, bytesPerSecond))))/s"
}

private func processTrafficBytes(_ bytes: UInt64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
    formatter.includesUnit = true
    formatter.isAdaptive = true
    return formatter.string(fromByteCount: Int64(min(bytes, UInt64(Int64.max))))
}
