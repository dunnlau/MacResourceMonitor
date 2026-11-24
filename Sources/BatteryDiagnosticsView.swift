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
                batteryHeroBento
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
                .padding(18)
                .stableDashboardCard()
            }

            sleepAssertionsCard
        }
    }

    private var batteryHeroBento: some View {
        HStack(alignment: .top, spacing: InterfaceMetrics.sectionSpacing) {
            batteryHealthHeroCard
            batteryChargeHeroCard
            powerFlowPulseCard
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var batteryHealthHeroCard: some View {
        let healthValue = diagnostics.healthPercent ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                IconBadge(symbol: "heart.fill", tint: healthTint, size: 24, iconSize: 11.5, cornerRadius: 6)
                Text("电池健康")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                if let condition = diagnostics.batteryCondition {
                    StatusBadge(text: condition, tint: healthTint)
                }
            }

            HStack(alignment: .center, spacing: 14) {
                RadialGaugeRing(
                    progress: healthValue,
                    tint: healthTint,
                    valueText: formattedHealthPercent,
                    caption: "HEALTH",
                    size: 74,
                    lineWidth: 6.5
                )

                VStack(alignment: .leading, spacing: 6) {
                    inlineStat("循环次数", diagnostics.cycleCount.map { "\($0) 次" } ?? "--", tint: .primary)
                    inlineStat(
                        "满充容量",
                        diagnostics.maxCapacityMAh.map { "\($0) mAh" } ?? "--",
                        tint: InterfacePalette.textSecondary
                    )
                    inlineStat(
                        "设计容量",
                        diagnostics.designCapacityMAh.map { "\($0) mAh" } ?? "--",
                        tint: InterfacePalette.textTertiary
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)

            Text(rawHealthFootnote)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(InterfacePalette.textTertiary)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .stableDashboardCard()
    }

    private var batteryChargeHeroCard: some View {
        let chargePercent = Double(diagnostics.currentChargePercent ?? 0)
        let chargeTint: Color = chargePercent <= 15
            ? InterfacePalette.temperature
            : (chargePercent <= 30 ? InterfacePalette.upload : InterfacePalette.battery)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                IconBadge(symbol: "battery.75percent", tint: chargeTint, size: 24, iconSize: 11.5, cornerRadius: 6)
                Text("电量与电芯")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                StatusBadge(
                    text: diagnostics.isCharging ? "充电中" : (diagnostics.fullyCharged ? "已充满" : "使用中"),
                    tint: diagnostics.isCharging ? InterfacePalette.power : chargeTint,
                    showDot: diagnostics.isCharging
                )
            }

            HStack(alignment: .center, spacing: 14) {
                RadialGaugeRing(
                    progress: chargePercent,
                    tint: chargeTint,
                    valueText: diagnostics.currentChargePercent.map { "\($0)%" } ?? "--",
                    caption: "LEVEL",
                    size: 74,
                    lineWidth: 6.5
                )

                VStack(alignment: .leading, spacing: 6) {
                    inlineStat(
                        "电芯温度",
                        diagnostics.temperatureCelsius.map { String(format: "%.1f°C", $0) } ?? "--",
                        tint: InterfacePalette.temperatureTint(for: diagnostics.temperatureCelsius)
                    )
                    inlineStat(
                        "实时电压",
                        diagnostics.voltageVolts.map { String(format: "%.2f V", $0) } ?? "--",
                        tint: .primary
                    )
                    inlineStat(
                        "实时电流",
                        diagnostics.amperageAmps.map { String(format: "%+.2f A", $0) } ?? "--",
                        tint: InterfacePalette.textSecondary
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)

            Text(chargeStatusDetail)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(InterfacePalette.textTertiary)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .stableDashboardCard()
    }

    private var powerFlowPulseCard: some View {
        let isDischarging = !diagnostics.isCharging && diagnostics.dischargeWatts != nil
        let batteryFlowTitle = isDischarging ? "电池放电" : "电池充电"
        let batteryFlowValue: String = {
            if let watts = batteryChargeWatts {
                return String(format: "%.1f W", watts)
            }
            if let discharge = diagnostics.dischargeWatts {
                return String(format: "%.1f W", discharge)
            }
            return diagnostics.isCharging ? "检测中" : "未充电"
        }()

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                StatusBadge(text: "实时功耗", tint: InterfacePalette.power, showDot: true)
                Spacer(minLength: 4)
                if let adapterWatts = diagnostics.adapterWatts {
                    StatusBadge(text: "适配器 \(adapterWatts) W", tint: InterfacePalette.textSecondary)
                } else {
                    Text(powerSource)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(InterfacePalette.textTertiary)
                        .lineLimit(1)
                }
            }

            VStack(spacing: 7) {
                powerRow(
                    title: "外部输入",
                    value: inputWatts.map { String(format: "%.1f W", $0) } ?? "未接入",
                    symbol: "powerplug.fill",
                    tint: InterfacePalette.power
                )
                powerRow(
                    title: batteryFlowTitle,
                    value: batteryFlowValue,
                    symbol: isDischarging ? "arrow.down.circle.fill" : "bolt.fill",
                    tint: isDischarging ? InterfacePalette.upload : InterfacePalette.battery
                )
                powerRow(
                    title: "整机负载",
                    value: systemLoadWatts.map { String(format: "%.1f W", $0) } ?? "--",
                    symbol: "gauge.with.dots.needle.50percent",
                    tint: InterfacePalette.accent
                )
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 320, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .stableDashboardCard()
    }

    private func powerRow(title: String, value: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 9) {
            IconBadge(symbol: symbol, tint: tint, size: 22, iconSize: 10.5, cornerRadius: 5.5)
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(InterfacePalette.textSecondary)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 13.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            InterfacePalette.subtleSurface,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private func inlineStat(_ title: String, _ value: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(InterfacePalette.textTertiary)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
                .lineLimit(1)
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

    private var rawHealthFootnote: String {
        if let raw = diagnostics.rawHealthPercent {
            return String(format: "系统最大容量 · 化学容量占比 %.1f%%", raw)
        }
        return "系统最大容量（对齐 macOS 设置）"
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
        .padding(18)
        .stableDashboardCard()
    }
}
