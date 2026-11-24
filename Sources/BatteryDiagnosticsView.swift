import SwiftUI

struct BatteryDiagnosticsView: View {
    let diagnostics: BatteryDiagnosticsSnapshot
    let inputWatts: Double?
    let batteryChargeWatts: Double?
    let systemLoadWatts: Double?
    let powerSource: String

    var body: some View {
        VStack(alignment: .leading, spacing: InterfaceMetrics.sectionSpacing) {
            if diagnostics.hasBattery {
                HStack(spacing: 12) {
                    MetricSummaryCard(
                        title: "电池健康度",
                        value: formattedHealthPercent,
                        detail: capacityDetail,
                        symbol: "heart.fill",
                        tint: healthTint,
                        progress: diagnostics.healthPercent
                    )
                    MetricSummaryCard(
                        title: "循环次数",
                        value: diagnostics.cycleCount.map { "\($0) 次" } ?? "--",
                        detail: chargeStatusDetail,
                        symbol: "arrow.triangle.2.circlepath",
                        tint: InterfacePalette.accent
                    )
                    MetricSummaryCard(
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
                    IconBadge(symbol: "desktopcomputer", tint: InterfacePalette.textSecondary, size: 32, iconSize: 15)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("当前设备无内置电池")
                            .font(.system(size: 14, weight: .semibold))
                        Text("桌面端 Mac 仅提供整机供电与阻止休眠进程检测。")
                            .font(InterfaceTypography.caption)
                            .foregroundStyle(InterfacePalette.textSecondary)
                    }
                    Spacer()
                }
                .padding(InterfaceMetrics.cardPadding)
                .stableDashboardCard()
            }

            sleepAssertionsCard
        }
    }

    private var formattedHealthPercent: String {
        guard let health = diagnostics.healthPercent else { return "--" }
        if abs(health.rounded() - health) < 0.05 {
            return String(format: "%.0f%%", health)
        }
        return String(format: "%.1f%%", health)
    }

    private var healthTint: Color {
        guard let health = diagnostics.healthPercent else { return InterfacePalette.textSecondary }
        if health < 80 { return InterfacePalette.temperature }
        if health < 88 { return InterfacePalette.upload }
        return InterfacePalette.battery
    }

    private var capacityDetail: String {
        if let maxCap = diagnostics.maxCapacityMAh, let designCap = diagnostics.designCapacityMAh {
            let rawSuffix = diagnostics.rawHealthPercent.map { String(format: " (%.1f%%)", $0) } ?? ""
            if let condition = diagnostics.batteryCondition {
                return "\(condition) · 原始 \(maxCap)/\(designCap) mAh\(rawSuffix)"
            }
            return "原始 \(maxCap)/\(designCap) mAh\(rawSuffix)"
        }
        if let condition = diagnostics.batteryCondition {
            return "电池状态：\(condition)"
        }
        return "系统最大容量"
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
        let isDischarging = !diagnostics.isCharging && diagnostics.dischargeWatts != nil
        let batteryFlowTitle = isDischarging ? "电池放电功率" : "电池充电功率"
        let batteryFlowValue: String = {
            if let watts = batteryChargeWatts {
                return String(format: "%.1f W", watts)
            }
            if let discharge = diagnostics.dischargeWatts {
                return String(format: "%.1f W", discharge)
            }
            return diagnostics.isCharging ? "检测中" : "未充电"
        }()

        return VStack(alignment: .leading, spacing: 14) {
            SectionCardHeader(
                title: "实时功耗拆解",
                subtitle: "外部适配器输入、电池充放电与整机负载",
                symbol: "bolt.batteryblock.fill",
                tint: InterfacePalette.power
            ) {
                if let adapterWatts = diagnostics.adapterWatts {
                    StatusBadge(text: "适配器额定 \(adapterWatts) W", tint: InterfacePalette.power)
                }
            }

            HStack(spacing: 10) {
                powerItem(
                    title: "外部输入功率",
                    value: inputWatts.map { String(format: "%.1f W", $0) } ?? "未接入",
                    tint: InterfacePalette.power
                )
                powerItem(
                    title: batteryFlowTitle,
                    value: batteryFlowValue,
                    tint: isDischarging ? InterfacePalette.upload : InterfacePalette.battery
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
        .padding(InterfaceMetrics.cardPadding)
        .stableDashboardCard()
    }

    private func powerItem(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(InterfacePalette.textTertiary)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(tint == InterfacePalette.textSecondary ? Color.primary : tint)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            InterfacePalette.subtleSurface,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(InterfacePalette.cardStroke, lineWidth: 0.65)
        )
    }

    private var sleepAssertionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionCardHeader(
                title: "阻止休眠进程检测",
                subtitle: "检测阻止系统息屏或进入睡眠的电源断言",
                symbol: "moon.zzz.fill",
                tint: InterfacePalette.accent
            ) {
                StatusBadge(
                    text: diagnostics.sleepAssertions.isEmpty ? "无阻止项" : "\(diagnostics.sleepAssertions.count) 个活跃项",
                    tint: diagnostics.sleepAssertions.isEmpty ? InterfacePalette.signal : InterfacePalette.upload,
                    showDot: true
                )
            }

            if diagnostics.sleepAssertions.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(InterfacePalette.signal)
                    Text("当前没有进程阻止 Mac 正常休眠或息屏。")
                        .font(InterfaceTypography.caption)
                        .foregroundStyle(InterfacePalette.textSecondary)
                }
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(diagnostics.sleepAssertions.prefix(12).enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 10) {
                            Text(item.processName)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .frame(width: 140, alignment: .leading)

                            Text("PID \(String(item.pid))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(InterfacePalette.textTertiary)
                                .frame(width: 72, alignment: .leading)

                            StatusBadge(text: item.friendlyType, tint: InterfacePalette.upload)

                            Text(item.reason)
                                .font(.system(size: 11.5))
                                .foregroundStyle(InterfacePalette.textSecondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .hoverRowHighlight(cornerRadius: 6)

                        if index < min(diagnostics.sleepAssertions.count, 12) - 1 {
                            Divider().opacity(0.35)
                        }
                    }
                }
            }
        }
        .padding(InterfaceMetrics.cardPadding)
        .stableDashboardCard()
    }
}
