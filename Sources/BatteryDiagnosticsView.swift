import SwiftUI

struct BatteryDiagnosticsView: View {
    let diagnostics: BatteryDiagnosticsSnapshot
    let inputWatts: Double?
    let batteryChargeWatts: Double?
    let systemLoadWatts: Double?
    let powerSource: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if diagnostics.hasBattery {
                HStack(spacing: 12) {
                    metricCard(
                        title: "电池健康度",
                        value: diagnostics.healthPercent.map { String(format: "%.1f%%", $0) } ?? "--",
                        detail: capacityDetail,
                        symbol: "heart.fill",
                        tint: healthTint
                    )
                    metricCard(
                        title: "循环次数",
                        value: diagnostics.cycleCount.map { "\($0) 次" } ?? "--",
                        detail: chargeStatusDetail,
                        symbol: "arrow.triangle.2.circlepath",
                        tint: InterfacePalette.accent
                    )
                    metricCard(
                        title: "电芯温度与电压",
                        value: diagnostics.temperatureCelsius.map { String(format: "%.1f°C", $0) } ?? "--",
                        detail: electricalDetail,
                        symbol: "thermometer.medium",
                        tint: InterfacePalette.power
                    )
                }

                powerBreakdownCard
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(InterfacePalette.textSecondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("当前设备无内置电池")
                            .font(.system(size: 14, weight: .semibold))
                        Text("桌面端 Mac 仅提供整机供电与阻止休眠进程检测。")
                            .font(InterfaceTypography.caption)
                            .foregroundStyle(InterfacePalette.textSecondary)
                    }
                    Spacer()
                }
                .padding(16)
                .stableDashboardCard()
            }

            sleepAssertionsCard
        }
    }

    private var healthTint: Color {
        guard let health = diagnostics.healthPercent else { return InterfacePalette.textSecondary }
        if health < 80 { return InterfacePalette.temperature }
        if health < 88 { return InterfacePalette.upload }
        return InterfacePalette.battery
    }

    private var capacityDetail: String {
        if let maxCap = diagnostics.maxCapacityMAh, let designCap = diagnostics.designCapacityMAh {
            return "\(maxCap) / \(designCap) mAh"
        }
        return "正在读取电池容量"
    }

    private var chargeStatusDetail: String {
        if let minutes = diagnostics.timeRemainingMinutes {
            let hours = minutes / 60
            let mins = minutes % 60
            let timeText = hours > 0 ? "\(hours)小时\(mins)分" : "\(mins)分钟"
            return diagnostics.isCharging ? "预计 \(timeText) 充满" : "预计续航 \(timeText)"
        }
        if diagnostics.fullyCharged { return "已充满 · \(powerSource)" }
        return diagnostics.externalConnected ? "外接供电 · \(powerSource)" : "电池供电"
    }

    private var electricalDetail: String {
        var parts: [String] = []
        if let volts = diagnostics.voltageVolts {
            parts.append(String(format: "%.2f V", volts))
        }
        if let amps = diagnostics.amperageAmps {
            parts.append(String(format: "%+.2f A", amps))
        }
        return parts.isEmpty ? "正在读取电芯参数" : parts.joined(separator: " · ")
    }

    private var powerBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("实时功耗拆解")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if let adapterWatts = diagnostics.adapterWatts {
                    Text("适配器额定 \(adapterWatts) W")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(InterfacePalette.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
            }

            HStack(spacing: 12) {
                powerItem(
                    title: "外部输入功率",
                    value: inputWatts.map { String(format: "%.1f W", $0) } ?? "未接入",
                    tint: InterfacePalette.power
                )
                powerItem(
                    title: "电池充电功率",
                    value: batteryChargeWatts.map { String(format: "%.1f W", $0) } ?? (diagnostics.isCharging ? "检测中" : "未充电"),
                    tint: InterfacePalette.battery
                )
                powerItem(
                    title: "整机实时负载",
                    value: systemLoadWatts.map { String(format: "%.1f W", $0) } ?? "--",
                    tint: InterfacePalette.accent
                )
                powerItem(
                    title: "当前电量",
                    value: diagnostics.currentChargePercent.map { "\($0)%" } ?? "--",
                    tint: InterfacePalette.textSecondary
                )
            }
        }
        .padding(16)
        .stableDashboardCard()
    }

    private func powerItem(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(InterfacePalette.textTertiary)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint == InterfacePalette.textSecondary ? Color.primary : tint)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var sleepAssertionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(InterfacePalette.accent)
                    Text("阻止休眠进程检测")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                Spacer()
                Text(diagnostics.sleepAssertions.isEmpty ? "无阻止项" : "\(diagnostics.sleepAssertions.count) 个活跃项")
                    .font(InterfaceTypography.microMetadata)
                    .foregroundStyle(diagnostics.sleepAssertions.isEmpty ? InterfacePalette.download : InterfacePalette.upload)
            }

            if diagnostics.sleepAssertions.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(InterfacePalette.download)
                    Text("当前没有进程阻止 Mac 正常休眠或息屏。")
                        .font(InterfaceTypography.caption)
                        .foregroundStyle(InterfacePalette.textSecondary)
                }
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(diagnostics.sleepAssertions.prefix(12).enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 10) {
                            Text(item.processName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .frame(width: 140, alignment: .leading)

                            Text("PID \(item.pid)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(InterfacePalette.textTertiary)
                                .frame(width: 68, alignment: .leading)

                            Text(item.friendlyType)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(InterfacePalette.upload)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(InterfacePalette.upload.opacity(0.11), in: Capsule())

                            Text(item.reason)
                                .font(.system(size: 11))
                                .foregroundStyle(InterfacePalette.textSecondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if index < min(diagnostics.sleepAssertions.count, 12) - 1 {
                            Divider().opacity(0.35)
                        }
                    }
                }
            }
        }
        .padding(16)
        .stableDashboardCard()
    }

    private func metricCard(
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
}
