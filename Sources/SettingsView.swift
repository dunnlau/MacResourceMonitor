import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            menuBarSettingsCard
            alertsSettingsCard
            startupSettingsCard
        }
        .onAppear {
            preferences.refreshLoginItemStatus()
        }
    }

    private var menuBarSettingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(InterfacePalette.accent)
                Text("顶部菜单栏显示项")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("实时生效")
                    .font(InterfaceTypography.microMetadata)
                    .foregroundStyle(InterfacePalette.textTertiary)
            }

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
        }
        .padding(16)
        .stableDashboardCard()
    }

    private var alertsSettingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(InterfacePalette.temperature)
                Text("高温与高负载通知提醒")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Toggle("", isOn: $preferences.alertsEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            Text("达到阈值时发送 macOS 本地通知（同一项 5 分钟内最多提醒一次，CPU 负载需连续 6 秒超标才触发）。")
                .font(InterfaceTypography.microMetadata)
                .foregroundStyle(InterfacePalette.textTertiary)

            VStack(spacing: 12) {
                HStack {
                    Text("CPU 温度告警阈值")
                        .font(InterfaceTypography.caption)
                        .foregroundStyle(InterfacePalette.textSecondary)
                    Spacer()
                    Slider(value: $preferences.highTempThreshold, in: 75...100, step: 1)
                        .frame(width: 200)
                        .disabled(!preferences.alertsEnabled)
                    Text(String(format: "%.0f°C", preferences.highTempThreshold))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .frame(width: 46, alignment: .trailing)
                }

                HStack {
                    Text("CPU 持续高负载阈值")
                        .font(InterfaceTypography.caption)
                        .foregroundStyle(InterfacePalette.textSecondary)
                    Spacer()
                    Slider(value: $preferences.highCPUThreshold, in: 75...98, step: 1)
                        .frame(width: 200)
                        .disabled(!preferences.alertsEnabled)
                    Text(String(format: "%.0f%%", preferences.highCPUThreshold))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .frame(width: 46, alignment: .trailing)
                }
            }
            .opacity(preferences.alertsEnabled ? 1 : 0.5)
        }
        .padding(16)
        .stableDashboardCard()
    }

    private var startupSettingsCard: some View {
        let isEnabled = preferences.loginItemStatus == .enabled
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "power.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(InterfacePalette.download)
                VStack(alignment: .leading, spacing: 2) {
                    Text("开机自动启动")
                        .font(.system(size: 14, weight: .semibold))
                    Text("状态：\(preferences.loginItemStatus.label)")
                        .font(InterfaceTypography.microMetadata)
                        .foregroundStyle(InterfacePalette.textTertiary)
                }
                Spacer()
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
            }

            if let error = preferences.loginItemError {
                Text(error)
                    .font(InterfaceTypography.microMetadata)
                    .foregroundStyle(InterfacePalette.temperature)
            }
        }
        .padding(16)
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
        }
    }
}
