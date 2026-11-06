import SwiftUI
import AppKit

/// 圆环额度指示：百分比与“剩余”放在环内。
struct QuotaRing: View {
    let window: CodexQuotaWindow?
    let tint: Color
    var size: CGFloat = 120
    var lineWidth: CGFloat = 11
    var isLoading = false

    var body: some View {
        let remaining = min(100, max(0, window?.remainingPercent ?? 0))
        let hasValue = window?.remainingPercent != nil
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.07), lineWidth: lineWidth)
            if hasValue {
                Circle()
                    .trim(from: 0, to: remaining / 100)
                    .stroke(
                        AngularGradient(
                            colors: [tint.opacity(0.45), tint],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360 * max(remaining, 1) / 100)
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: tint.opacity(0.28), radius: lineWidth * 0.5)
                    .animation(.easeOut(duration: 0.6), value: remaining)
            }
            VStack(spacing: 1) {
                Text(isLoading ? "88%" : (hasValue ? String(format: "%.0f%%", remaining) : "--"))
                    .font(.system(size: size * 0.27, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.4), value: window?.remainingPercent)
                    .foregroundStyle(hasValue ? tint : InterfacePalette.textSecondary)
                    .redacted(reason: isLoading ? .placeholder : [])
                Text("剩余")
                    .font(.system(size: max(9, size * 0.095), weight: .medium))
                    .foregroundStyle(InterfacePalette.textTertiary)
            }
        }
        .frame(width: size, height: size)
        .padding(lineWidth / 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("剩余额度")
        .accessibilityValue(hasValue ? String(format: "%.0f%%", remaining) : "未知")
    }
}

/// 菜单栏面板里的迷你圆环（仅图形，数值由旁边的文字给出）。
private struct MiniQuotaRing: View {
    let window: CodexQuotaWindow?

    var body: some View {
        let remaining = min(100, max(0, window?.remainingPercent ?? 0))
        let color: Color = remaining <= 10 ? InterfacePalette.temperature : (remaining <= 25 ? .orange : InterfacePalette.accent.opacity(0.9))
        ZStack {
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: 3)
            if window?.remainingPercent != nil {
                Circle()
                    .trim(from: 0, to: remaining / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}

struct CodexQuotaView: View {
    @ObservedObject var model: CodexQuotaMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let error = model.state.error {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.orange)
                    Text(error.localizedDescription)
                        .font(InterfaceTypography.captionMedium)
                        .foregroundStyle(InterfacePalette.textSecondary)
                    Spacer()
                    Button("重试") {
                        model.refreshCurrent(force: true)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .stableDashboardCard()
            }

            antigravityPoolGrid

            footerMetadataCard
        }
        .onAppear { model.setActive(true, for: .dashboard) }
        .onDisappear { model.setActive(false, for: .dashboard) }
    }

    // MARK: - Antigravity Dual Model Pool Cards

    private var antigravityPoolGrid: some View {
        let snapshot = model.state.snapshot
        let gemini5h = snapshot?.extraWindow(matching: "gemini-5h")
        let geminiWeekly = snapshot?.extraWindow(matching: "gemini-weekly") ?? snapshot?.primary
        let thirdParty5h = snapshot?.extraWindow(matching: "3p-5h")
        let thirdPartyWeekly = snapshot?.extraWindow(matching: "3p-weekly") ?? snapshot?.secondary

        return HStack(alignment: .top, spacing: 14) {
            antigravityPoolCard(
                title: "Gemini 模型池",
                subtitle: "Gemini Pro / Flash 系列模型",
                symbol: "sparkles",
                shortWindow: gemini5h,
                weeklyWindow: geminiWeekly
            )

            antigravityPoolCard(
                title: "Claude / GPT 模型池",
                subtitle: "Claude Sonnet / Opus 与第三方模型",
                symbol: "cpu",
                shortWindow: thirdParty5h,
                weeklyWindow: thirdPartyWeekly
            )
        }
    }

    private func antigravityPoolCard(
        title: String,
        subtitle: String,
        symbol: String,
        shortWindow: CodexQuotaWindow?,
        weeklyWindow: CodexQuotaWindow?
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(InterfacePalette.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(subtitle)
                        .font(InterfaceTypography.microMetadata)
                        .foregroundStyle(InterfacePalette.textTertiary)
                }

                Spacer()

                if let plan = model.state.snapshot?.plan {
                    Text(plan)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(InterfacePalette.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }

            Divider().opacity(0.45)

            HStack(alignment: .top, spacing: 0) {
                quotaRingTier(badgeTitle: "5 小时短时限额", window: shortWindow)
                Divider().opacity(0.45).frame(height: 150)
                quotaRingTier(badgeTitle: "7 天每周限额", window: weeklyWindow)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(lowQuotaTint([shortWindow, weeklyWindow]))
        .stableDashboardCard()
        .transaction { $0.animation = nil }
    }

    private func quotaRingTier(badgeTitle: String, window: CodexQuotaWindow?) -> some View {
        VStack(spacing: 10) {
            QuotaRing(
                window: window,
                tint: statusColor(for: window, defaultColor: InterfacePalette.accent.opacity(0.9)),
                size: 104,
                lineWidth: 10,
                isLoading: isLoading(window)
            )

            VStack(spacing: 3) {
                Text(badgeTitle)
                    .font(.system(size: 12, weight: .semibold))
                if let remaining = window?.remainingPercent {
                    Text(String(format: "已用 %.1f%%", max(0, 100 - remaining)))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(InterfacePalette.textTertiary)
                }
                if let reset = window?.resetsAt {
                    Text("重置于 \(reset.formatted(date: .abbreviated, time: .shortened))")
                        .foregroundStyle(InterfacePalette.textSecondary)
                    Text(reset > Date() ? "约 \(reset.formatted(.relative(presentation: .numeric)))" : "即将刷新")
                        .foregroundStyle(InterfacePalette.textTertiary)
                } else {
                    Text(model.state.isRefreshing ? "正在读取窗口配额…" : "暂未提供该窗口配额")
                        .foregroundStyle(InterfacePalette.textTertiary)
                }
            }
            .font(InterfaceTypography.microMetadata)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer Account & Policy Card

    private var footerMetadataCard: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 9) {
                Text("账号与会话")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                metadataRow(
                    label: "登录账号",
                    value: model.state.snapshot?.accountEmail ?? "本机已授权会话"
                )
                metadataRow(
                    label: "订阅方案",
                    value: model.state.snapshot?.plan ?? "Google AI Pro"
                )
                metadataRow(
                    label: "最近同步",
                    value: statusText
                )

                HStack(spacing: 12) {
                    Link(destination: URL(string: "https://antigravity.google/docs")!) {
                        Label("Antigravity 文档", systemImage: "arrow.up.right")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .foregroundStyle(InterfacePalette.textSecondary)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().opacity(0.45)

            VStack(alignment: .leading, spacing: 8) {
                Text("说明")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("· 仅在窗口或菜单打开时每分钟按需同步，关闭后零后台消耗。")
                Text("· 通过只读本地接口读取剩余百分比，不接触对话内容或账单。")
                Text("· 若提示未连接，请确认 Antigravity 处于运行状态后点击刷新。")
            }
            .font(InterfaceTypography.microMetadata)
            .foregroundStyle(InterfacePalette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .stableDashboardCard()
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(InterfaceTypography.caption)
                .foregroundStyle(InterfacePalette.textSecondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    private var statusText: String {
        guard let date = model.state.snapshot?.updatedAt else {
            return model.state.isRefreshing ? "正在查询…" : "尚未获取"
        }
        let prefix = model.state.error == nil ? "已同步" : "缓存"
        return "\(prefix) · \(date.formatted(date: .omitted, time: .standard))"
    }

    /// 剩余额度偏低时给整张卡片一层淡淡的警示底色。
    private func lowQuotaTint(_ windows: [CodexQuotaWindow?]) -> Color {
        guard let lowest = windows.compactMap({ $0?.remainingPercent }).min() else { return .clear }
        if lowest <= 10 { return InterfacePalette.temperature.opacity(0.09) }
        if lowest <= 25 { return Color.orange.opacity(0.07) }
        return .clear
    }

    /// 首次加载且尚无数据时，用骨架占位代替“--”。
    private func isLoading(_ window: CodexQuotaWindow?) -> Bool {
        window == nil && model.state.isRefreshing && model.state.snapshot == nil
    }

    private func statusColor(for window: CodexQuotaWindow?, defaultColor: Color) -> Color {
        guard let remaining = window?.remainingPercent else { return defaultColor }
        if remaining <= 10 { return InterfacePalette.temperature }
        if remaining <= 25 { return .orange }
        return defaultColor
    }
}

/// Observes only the low-frequency quota store; quota updates do not invalidate the whole menu.
struct CodexQuotaMenuSummary: View {
    @ObservedObject var model: CodexQuotaMonitor
    let openUsage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Button(action: openUsage) {
                    HStack(spacing: 6) {
                        Text("AI 订阅配额")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Antigravity")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(InterfacePalette.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                if model.state.isRefreshing {
                    ProgressView().controlSize(.mini)
                } else if model.state.error != nil {
                    Button {
                        model.refreshCurrent(force: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(InterfacePalette.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("点击重试")
                }
            }

            Button(action: openUsage) {
                if let error = model.state.error {
                    Text(error.localizedDescription)
                        .foregroundStyle(InterfacePalette.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let snapshot = model.state.snapshot {
                    let left = snapshot.extraWindow(matching: "gemini-weekly") ?? snapshot.primary
                    let right = snapshot.extraWindow(matching: "3p-weekly") ?? snapshot.secondary
                    HStack(spacing: 6) {
                        MiniQuotaRing(window: left)
                        Text("Gemini 周 \(quotaPercent(left))")
                        Spacer(minLength: 4)
                        Text("Claude/GPT 周 \(quotaPercent(right))")
                        MiniQuotaRing(window: right)
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(InterfacePalette.textSecondary)
                } else {
                    Text(model.state.isRefreshing ? "正在同步配额…" : "点击查看订阅配额")
                        .foregroundStyle(InterfacePalette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
        }
        .font(InterfaceTypography.microMetadata)
        .contentShape(Rectangle())
        .onAppear { model.setActive(true, for: .menuBar) }
        .onDisappear { model.setActive(false, for: .menuBar) }
    }
}

private func quotaPercent(_ window: CodexQuotaWindow?) -> String {
    guard let remaining = window?.remainingPercent else { return "--" }
    return String(format: "%.0f%%", remaining)
}
