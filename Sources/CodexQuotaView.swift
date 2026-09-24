import SwiftUI
import AppKit

struct AIProviderSegmentedControl: View {
    @Binding var selectedProvider: AIUsageProvider
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AIUsageProvider.allCases) { provider in
                let isSelected = selectedProvider == provider
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedProvider = provider
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: provider.symbol)
                            .font(.system(size: 11, weight: .medium))
                        Text(provider.displayName)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .padding(.horizontal, 11)
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
                        .foregroundStyle(.secondary)
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

            if model.selectedProvider == .antigravity {
                antigravityPoolGrid
            } else {
                codexWindowGrid
            }

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
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(subtitle)
                        .font(InterfaceTypography.microMetadata)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if let plan = model.state.snapshot?.plan {
                    Text(plan)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }

            Divider().opacity(0.45)

            quotaTierBlock(
                badgeTitle: "5 小时短时限额",
                window: shortWindow,
                isPrimaryHero: false
            )

            Divider().opacity(0.45)

            quotaTierBlock(
                badgeTitle: "7 天每周限额",
                window: weeklyWindow,
                isPrimaryHero: true
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .stableDashboardCard()
        .transaction { $0.animation = nil }
    }

    private func quotaTierBlock(
        badgeTitle: String,
        window: CodexQuotaWindow?,
        isPrimaryHero: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center) {
                Text(badgeTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                if let remaining = window?.remainingPercent {
                    let used = max(0, 100 - remaining)
                    Text(String(format: "已用 %.1f%%", used))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(quotaPercent(window))
                    .font(.system(size: isPrimaryHero ? 30 : 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(statusColor(for: window, defaultColor: .primary))
                Text("剩余")
                    .font(InterfaceTypography.caption)
                    .foregroundStyle(.tertiary)
            }

            GeometryReader { geo in
                let remaining = min(100, max(0, window?.remainingPercent ?? 0))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                    if window?.remainingPercent != nil {
                        Capsule()
                            .fill(statusColor(for: window, defaultColor: InterfacePalette.accent.opacity(0.82)))
                            .frame(width: geo.size.width * (remaining / 100))
                    }
                }
            }
            .frame(height: 5)

            HStack(spacing: 5) {
                if let reset = window?.resetsAt {
                    Text("重置于 \(reset.formatted(date: .abbreviated, time: .shortened))")
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(reset > Date() ? "约 \(reset.formatted(.relative(presentation: .numeric)))" : "即将刷新")
                        .foregroundStyle(.tertiary)
                } else {
                    Text(model.state.isRefreshing ? "正在读取窗口配额…" : "暂未提供该窗口配额")
                        .foregroundStyle(.tertiary)
                }
            }
            .font(InterfaceTypography.microMetadata)
            .lineLimit(1)
        }
    }

    // MARK: - Codex Dual Window Cards

    private var codexWindowGrid: some View {
        HStack(alignment: .top, spacing: 14) {
            codexQuotaCard(
                title: "5 小时会话额度",
                subtitle: "短时高频调用限额 · 滚动刷新",
                badge: "5 小时窗口",
                symbol: "bolt",
                window: model.state.snapshot?.primary
            )

            codexQuotaCard(
                title: "7 天每周额度",
                subtitle: "每周累计额度上限 · 周期重置",
                badge: "7 天窗口",
                symbol: "calendar",
                window: model.state.snapshot?.secondary
            )
        }
    }

    private func codexQuotaCard(
        title: String,
        subtitle: String,
        badge: String,
        symbol: String,
        window: CodexQuotaWindow?
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(subtitle)
                        .font(InterfaceTypography.microMetadata)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Text(badge)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(quotaPercent(window))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(statusColor(for: window, defaultColor: .primary))
                Text("剩余")
                    .font(InterfaceTypography.caption)
                    .foregroundStyle(.tertiary)

                Spacer()

                if let remaining = window?.remainingPercent {
                    Text(String(format: "已用 %.0f%%", max(0, 100 - remaining)))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            GeometryReader { geo in
                let remaining = min(100, max(0, window?.remainingPercent ?? 0))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                    if window?.remainingPercent != nil {
                        Capsule()
                            .fill(statusColor(for: window, defaultColor: InterfacePalette.accent.opacity(0.82)))
                            .frame(width: geo.size.width * (remaining / 100))
                    }
                }
            }
            .frame(height: 5)

            Divider().opacity(0.45)

            HStack(spacing: 6) {
                if let reset = window?.resetsAt {
                    Text("重置于 \(reset.formatted(date: .abbreviated, time: .shortened))")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(reset > Date() ? "约 \(reset.formatted(.relative(presentation: .numeric)))" : "已到重置时间")
                        .foregroundStyle(.tertiary)
                } else {
                    Text(model.state.isRefreshing ? "正在查询订阅额度…" : "重置时间暂不可用")
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }
            .font(InterfaceTypography.microMetadata)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
        .stableDashboardCard()
        .transaction { $0.animation = nil }
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
                    value: model.state.snapshot?.plan ?? (model.selectedProvider == .antigravity ? "Google AI Pro" : "ChatGPT Plus / Pro")
                )
                metadataRow(
                    label: "最近同步",
                    value: statusText
                )

                HStack(spacing: 12) {
                    if model.selectedProvider == .antigravity {
                        Link(destination: URL(string: "https://antigravity.google/docs")!) {
                            Label("Antigravity 文档", systemImage: "arrow.up.right")
                                .font(.system(size: 11, weight: .medium))
                        }
                    } else {
                        Link(destination: URL(string: "https://chatgpt.com/codex/settings/usage")!) {
                            Label("Codex 用量设置", systemImage: "arrow.up.right")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                }
                .foregroundStyle(.secondary)
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
                if model.selectedProvider == .antigravity {
                    Text("· 若提示未连接，请确认 Antigravity 处于运行状态后点击刷新。")
                } else {
                    Text("· 若提示授权失效，请在终端运行 codex 登录后刷新。")
                }
            }
            .font(InterfaceTypography.microMetadata)
            .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
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
                        Text(model.selectedProvider.displayName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    model.selectedProvider = (model.selectedProvider == .codex ? .antigravity : .codex)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 9))
                        Text(model.selectedProvider == .codex ? "切换 Antigravity" : "切换 Codex")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.055), in: Capsule())
                }
                .buttonStyle(.plain)

                if model.state.isRefreshing { ProgressView().controlSize(.mini) }
            }

            Button(action: openUsage) {
                if let error = model.state.error {
                    Text(error.localizedDescription)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let snapshot = model.state.snapshot {
                    HStack {
                        if model.selectedProvider == .antigravity {
                            let geminiWeekly = snapshot.extraWindow(matching: "gemini-weekly") ?? snapshot.primary
                            let thirdPartyWeekly = snapshot.extraWindow(matching: "3p-weekly") ?? snapshot.secondary
                            Text("Gemini 周剩余 \(quotaPercent(geminiWeekly))")
                            Spacer(minLength: 4)
                            Text("Claude/GPT 周剩余 \(quotaPercent(thirdPartyWeekly))")
                        } else {
                            Text("5h 剩余 \(quotaPercent(snapshot.primary))")
                            Spacer(minLength: 4)
                            Text("7d 剩余 \(quotaPercent(snapshot.secondary))")
                        }
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                } else {
                    Text(model.state.isRefreshing ? "正在同步配额…" : "点击查看订阅配额")
                        .foregroundStyle(.tertiary)
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
