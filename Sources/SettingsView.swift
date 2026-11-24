import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        HStack(alignment: .top, spacing: InterfaceMetrics.sectionSpacing) {
            menuBarSettingsCard

            VStack(spacing: InterfaceMetrics.sectionSpacing) {
                alertsSettingsCard
                startupSettingsCard
            }
            .frame(width: 340)
        }
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            preferences.refreshLoginItemStatus()
        }
    }

    private var menuBarPreviewText: String {
        var parts: [String] = []
        if preferences.showMenuBarTemperature { parts.append("48°") }
        if preferences.showMenuBarCPU { parts.append("CPU 18%") }
        if preferences.showMenuBarMemory { parts.append("MEM 62%") }
        if preferences.showMenuBarNetwork { parts.append("↓1.2M ↑320K") }
        if preferences.showMenuBarPower { parts.append("14W") }
        return parts.isEmpty ? "Mac 监控" : parts.joined(separator: "  ")
    }

    private var menuBarSettingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionCardHeader(
                title: "顶部菜单栏显示项",
                subtitle: "自由组合状态栏实时指标，修改后立即生效",
                symbol: "menubar.rectangle",
                tint: InterfacePalette.accent
            ) {
                StatusBadge(text: "实时生效", tint: InterfacePalette.signal, showDot: true)
            }

            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    Circle().fill(InterfacePalette.temperature.opacity(0.75)).frame(width: 7, height: 7)
                    Circle().fill(InterfacePalette.power.opacity(0.75)).frame(width: 7, height: 7)
                    Circle().fill(InterfacePalette.signal.opacity(0.75)).frame(width: 7, height: 7)
                }
                Text("菜单栏预览")
                    .font(InterfaceTypography.eyebrow)
                    .foregroundStyle(InterfacePalette.textTertiary)
                Spacer()
                Text(menuBarPreviewText)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4.5)
                    .background(
                        InterfacePalette.iconSurface,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(InterfacePalette.cardStroke, lineWidth: 0.7)
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                InterfacePalette.subtleSurface,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )

            VStack(spacing: 10) {
                toggleRow("CPU 温度", subtitle: "例如 48°", isOn: $preferences.showMenuBarTemperature)
                Divider().opacity(0.35)
                toggleRow("CPU 使用率", subtitle: "例如 CPU 18%", isOn: $preferences.showMenuBarCPU)
                Divider().opacity(0.35)
                toggleRow("内存使用率", subtitle: "例如 MEM 62%", isOn: $preferences.showMenuBarMemory)
                Divider().opacity(0.35)
                toggleRow("实时网络速率", subtitle: "例如 ↓1.2M ↑320K", isOn: $preferences.showMenuBarNetwork)
                Divider().opacity(0.35)
                toggleRow("整机实时功耗", subtitle: "例如 14W（需硬件支持）", isOn: $preferences.showMenuBarPower)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .stableDashboardCard()
    }

    private var alertsSettingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionCardHeader(
                title: "高温与高负载提醒",
                subtitle: "每项 5 分钟冷却",
                symbol: "bell.badge.fill",
                tint: InterfacePalette.temperature
            ) {
                Toggle("", isOn: $preferences.alertsEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel("启用高温与高负载通知提醒")
            }

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("CPU 温度告警阈值")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        StatusBadge(
                            text: String(format: "%.0f°C", preferences.highTempThreshold),
                            tint: InterfacePalette.temperature
                        )
                    }
                    Slider(value: $preferences.highTempThreshold, in: 75...100, step: 1)
                        .disabled(!preferences.alertsEnabled)
                }

                Divider().opacity(0.35)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("CPU 持续高负载阈值")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        StatusBadge(
                            text: String(format: "%.0f%%", preferences.highCPUThreshold),
                            tint: InterfacePalette.upload
                        )
                    }
                    Slider(value: $preferences.highCPUThreshold, in: 75...98, step: 1)
                        .disabled(!preferences.alertsEnabled)
                    Text("连续 6 秒超标后发送本地通知")
                        .font(InterfaceTypography.microMetadata)
                        .foregroundStyle(InterfacePalette.textTertiary)
                }
            }
            .opacity(preferences.alertsEnabled ? 1 : 0.45)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .stableDashboardCard()
    }

    private var startupSettingsCard: some View {
        let isEnabled = preferences.loginItemStatus == .enabled
        return VStack(alignment: .leading, spacing: 10) {
            SectionCardHeader(
                title: "开机自动启动",
                subtitle: preferences.loginItemStatus.label,
                symbol: "power.circle.fill",
                tint: InterfacePalette.signal
            ) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { isEnabled },
                        set: { preferences.setLaunchAtLogin($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!preferences.isRunningFromAppBundle)
                .accessibilityLabel("开机自动启动")
            }

            if let error = preferences.loginItemError {
                Text(error)
                    .font(InterfaceTypography.microMetadata)
                    .foregroundStyle(InterfacePalette.temperature)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .stableDashboardCard()
    }

    private func toggleRow(_ title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(InterfaceTypography.microMetadata)
                    .foregroundStyle(InterfacePalette.textTertiary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(title)
        }
    }
}
