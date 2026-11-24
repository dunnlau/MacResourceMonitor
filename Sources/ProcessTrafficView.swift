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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ProcessTrafficSort.allCases) { option in
                let isSelected = selection == option
                Button {
                    if reduceMotion {
                        selection = option
                    } else {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selection = option
                        }
                    }
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
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
                                    color: isSelected ? Color.black.opacity(colorScheme == .dark ? 0.28 : 0.08) : .clear,
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
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(InterfacePalette.subtleSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(InterfacePalette.cardStroke, lineWidth: 0.65)
        )
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct ProcessTrafficView: View {
    @ObservedObject var model: ProcessNetworkMonitor
    @State private var searchText = ""
    @State private var sort: ProcessTrafficSort = .current
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        VStack(alignment: .leading, spacing: InterfaceMetrics.sectionSpacing) {
            HStack(spacing: 12) {
                let trafficScopeDetail = model.filterProxyTunnels
                    ? "已剥离代理隧道二次汇总"
                    : "净应用流量（不含代理转发）"
                MetricSummaryCard(
                    title: "实时应用下载",
                    value: processTrafficRate(model.downloadBytesPerSecond),
                    detail: trafficScopeDetail,
                    symbol: "arrow.down",
                    tint: InterfacePalette.download
                )
                MetricSummaryCard(
                    title: "实时应用上传",
                    value: processTrafficRate(model.uploadBytesPerSecond),
                    detail: trafficScopeDetail,
                    symbol: "arrow.up",
                    tint: InterfacePalette.upload
                )
                MetricSummaryCard(
                    title: "本次监控累计",
                    value: processTrafficBytes(model.sessionDownloadedBytes + model.sessionUploadedBytes),
                    detail: "↓ \(processTrafficBytes(model.sessionDownloadedBytes)) · ↑ \(processTrafficBytes(model.sessionUploadedBytes))",
                    symbol: "sum",
                    tint: InterfacePalette.accent
                )
            }

            if !model.displayState.proxyTunnelNames.isEmpty {
                proxyTunnelBanner
            }

            toolbarPanel

            if let error = model.errorText {
                statusCard(symbol: "exclamationmark.triangle.fill", tint: InterfacePalette.upload, title: "暂时无法读取进程流量", detail: error)
            } else if model.lastUpdatedAt == nil {
                statusCard(symbol: "network", tint: InterfacePalette.accent, title: "正在采样进程流量", detail: "首次差分采样中（约 0.3 秒）…")
            } else if visibleRows.isEmpty {
                statusCard(symbol: "checkmark.circle.fill", tint: InterfacePalette.signal, title: "暂无匹配的进程流量", detail: "尝试清除搜索词或产生一些网络请求")
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
            SearchToolbarField(placeholder: "搜索应用、子进程或 PID…", text: $searchText)

            ToolbarToggleChip(
                title: model.filterProxyTunnels ? "已剥离 TUN 代理" : "显示全部进程",
                activeSymbol: "line.3.horizontal.decrease.circle.fill",
                inactiveSymbol: "line.3.horizontal.decrease.circle",
                isActive: model.filterProxyTunnels
            ) {
                if reduceMotion {
                    model.filterProxyTunnels.toggle()
                } else {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        model.filterProxyTunnels.toggle()
                    }
                }
            }

            TrafficSortSegmentedControl(selection: $sort)
        }
    }

    private var proxyTunnelBanner: some View {
        let names = model.displayState.proxyTunnelNames.joined(separator: " / ")
        let down = processTrafficRate(model.displayState.proxyTunnelDownloadBytesPerSecond)
        let up = processTrafficRate(model.displayState.proxyTunnelUploadBytesPerSecond)
        let totalSession = processTrafficBytes(model.displayState.proxyTunnelSessionBytes)

        return HStack(spacing: 10) {
            IconBadge(symbol: "arrow.triangle.branch", tint: InterfacePalette.accent, size: 26, iconSize: 11.5, cornerRadius: 6.5)

            HStack(spacing: 6) {
                Text("代理隧道：\(names)")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("·")
                    .foregroundStyle(InterfacePalette.textTertiary)
                Text("总转发 ↓ \(down)  ↑ \(up)  累计 \(totalSession)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(InterfacePalette.textSecondary)
            }
            .lineLimit(1)

            Spacer()

            StatusBadge(
                text: model.filterProxyTunnels ? "已从列表剥离" : "已包含在列表中",
                tint: model.filterProxyTunnels ? InterfacePalette.signal : InterfacePalette.textSecondary
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
            .background(InterfacePalette.subtleSurface)

            Divider().opacity(0.45)

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
                .font(.system(size: 11, weight: .medium, design: .monospaced))
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
                            .font(.system(size: 10.5))
                            .foregroundStyle(InterfacePalette.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(InterfacePalette.subtleSurface, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .lineLimit(1)
                    }

                    if row.isProxyTunnel {
                        StatusBadge(text: "TUN", tint: InterfacePalette.accent)
                    }

                    Text("PID \(row.pid)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(InterfacePalette.textTertiary)
                }

                GeometryReader { proxy in
                    Capsule()
                        .fill(InterfacePalette.subtleSurface)
                        .overlay(alignment: .leading) {
                            if ratio > 0 {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [InterfacePalette.accent.opacity(0.65), InterfacePalette.accent],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(3, proxy.size.width * ratio))
                            }
                        }
                }
                .frame(height: 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(processTrafficRate(row.downloadBytesPerSecond))
                .font(.system(size: 12, weight: isActiveDown ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(isActiveDown ? InterfacePalette.download : InterfacePalette.textTertiary)
                .frame(width: 104, alignment: .trailing)

            Text(processTrafficRate(row.uploadBytesPerSecond))
                .font(.system(size: 12, weight: isActiveUp ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(isActiveUp ? InterfacePalette.upload : InterfacePalette.textTertiary)
                .frame(width: 104, alignment: .trailing)

            Text(processTrafficBytes(row.sessionBytes))
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(InterfacePalette.textSecondary)
                .frame(width: 100, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .hoverRowHighlight()
    }

    @ViewBuilder
    private func processIcon(row: ProcessTrafficRow) -> some View {
        if let icon = ProcessIconCache.icon(for: row) {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
        } else {
            RoundedRectangle(
                cornerRadius: 6,
                style: .continuous
            )
            .fill(InterfacePalette.iconSurface)
            .overlay {
                Text(String(row.name.prefix(1)).uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(InterfacePalette.textSecondary)
            }
            .frame(width: 24, height: 24)
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
            if model.isCollecting { ProgressView().controlSize(.small) }
        }
        .padding(18)
        .stableDashboardCard()
    }
}

@MainActor
private let processTrafficByteFormatter: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
    formatter.includesUnit = true
    formatter.isAdaptive = true
    return formatter
}()

@MainActor
private func processTrafficRate(_ bytesPerSecond: Double) -> String {
    "\(processTrafficBytes(UInt64(max(0, bytesPerSecond))))/s"
}

@MainActor
private func processTrafficBytes(_ bytes: UInt64) -> String {
    processTrafficByteFormatter.string(fromByteCount: Int64(min(bytes, UInt64(Int64.max))))
}
