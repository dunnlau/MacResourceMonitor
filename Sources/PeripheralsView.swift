import SwiftUI

struct PeripheralsView: View {
    @ObservedObject var model: PeripheralsMonitor

    private let displayColumns = [
        GridItem(.flexible(), spacing: InterfaceMetrics.sectionSpacing),
        GridItem(.flexible(), spacing: InterfaceMetrics.sectionSpacing)
    ]

    private let batteryColumns = [
        GridItem(.flexible(), spacing: InterfaceMetrics.sectionSpacing),
        GridItem(.flexible(), spacing: InterfaceMetrics.sectionSpacing),
        GridItem(.flexible(), spacing: InterfaceMetrics.sectionSpacing)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: InterfaceMetrics.sectionSpacing) {
            displaysSection
            bluetoothBatteriesSection
        }
        .onAppear { model.setActive(true) }
        .onDisappear { model.setActive(false) }
    }

    private var displaysSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("已连接显示器")
                    .font(InterfaceTypography.cardTitle)
                    .foregroundStyle(.primary)
                Spacer()
                StatusBadge(
                    text: "\(model.snapshot.displays.count) 块屏幕",
                    tint: InterfacePalette.accent,
                    showDot: !model.snapshot.displays.isEmpty
                )
            }

            if model.snapshot.displays.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("正在读取显示器参数…")
                        .font(InterfaceTypography.caption)
                        .foregroundStyle(InterfacePalette.textSecondary)
                    Spacer()
                }
                .padding(18)
                .stableDashboardCard()
            } else if model.snapshot.displays.count == 1, let onlyDisplay = model.snapshot.displays.first {
                displayCard(onlyDisplay)
            } else {
                LazyVGrid(columns: displayColumns, spacing: InterfaceMetrics.sectionSpacing) {
                    ForEach(model.snapshot.displays) { display in
                        displayCard(display)
                    }
                }
            }
        }
    }

    private func displayCard(_ display: DisplayInfoItem) -> some View {
        let accentTint = display.isMain ? InterfacePalette.accent : InterfacePalette.textSecondary
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconBadge(
                    symbol: display.isBuiltIn ? "laptopcomputer" : "display",
                    tint: accentTint,
                    size: 32,
                    iconSize: 15,
                    cornerRadius: 8
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(display.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        if display.isMain {
                            StatusBadge(text: "主显示器", tint: InterfacePalette.accent)
                        }
                        if display.isBuiltIn {
                            StatusBadge(text: "内置", tint: InterfacePalette.textSecondary)
                        }
                        if display.supportsHDR {
                            StatusBadge(text: "HDR / EDR", tint: InterfacePalette.power)
                        }
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(display.refreshRateHz.map { String(format: "%.0f", $0) } ?? "60")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Text("Hz")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(InterfacePalette.textTertiary)
                }
            }

            HStack(spacing: 8) {
                specPill(title: "逻辑分辨率", value: "\(display.logicalWidth) × \(display.logicalHeight)")
                specPill(title: "物理像素", value: "\(display.pixelWidth) × \(display.pixelHeight)")
                specPill(title: "缩放倍率", value: String(format: "%.0fx Retina", display.scaleFactor))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .stableDashboardCard()
    }

    private func specPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(InterfacePalette.textTertiary)
            Text(value)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            InterfacePalette.subtleSurface,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
    }

    private var bluetoothBatteriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("蓝牙与无线外设电量")
                    .font(InterfaceTypography.cardTitle)
                    .foregroundStyle(.primary)
                Spacer()
                StatusBadge(
                    text: model.snapshot.batteryDevices.isEmpty ? "未发现带电量外设" : "\(model.snapshot.batteryDevices.count) 台设备",
                    tint: model.snapshot.batteryDevices.isEmpty ? InterfacePalette.textSecondary : InterfacePalette.battery,
                    showDot: !model.snapshot.batteryDevices.isEmpty
                )
            }

            if model.snapshot.batteryDevices.isEmpty {
                HStack(spacing: 12) {
                    IconBadge(symbol: "wave.3.right", tint: InterfacePalette.textSecondary, size: 32, iconSize: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("暂无上报电量的无线外设")
                            .font(.system(size: 13.5, weight: .semibold))
                        Text("支持妙控键盘、妙控板、鼠标、耳机、游戏手柄等蓝牙 / HID 设备。")
                            .font(InterfaceTypography.caption)
                            .foregroundStyle(InterfacePalette.textSecondary)
                    }
                    Spacer()
                }
                .padding(18)
                .stableDashboardCard()
            } else {
                LazyVGrid(columns: batteryColumns, spacing: InterfaceMetrics.sectionSpacing) {
                    ForEach(model.snapshot.batteryDevices) { device in
                        batteryDeviceCard(device)
                    }
                }
            }
        }
    }

    private func batteryDeviceCard(_ device: PeripheralBatteryItem) -> some View {
        let tint: Color = device.batteryPercent <= 15
            ? InterfacePalette.temperature
            : (device.batteryPercent <= 30 ? InterfacePalette.upload : InterfacePalette.battery)

        return HStack(alignment: .center, spacing: 12) {
            RadialGaugeRing(
                progress: Double(device.batteryPercent),
                tint: tint,
                valueText: "\(device.batteryPercent)%",
                size: 56,
                lineWidth: 5
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: iconForCategory(device.category))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(device.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Text("\(device.category) · \(device.transport)")
                    .font(InterfaceTypography.microMetadata)
                    .foregroundStyle(InterfacePalette.textTertiary)
                    .lineLimit(1)

                TelemetryProgressBar(progress: Double(device.batteryPercent), tint: tint, height: 3.5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .stableDashboardCard()
    }

    private func iconForCategory(_ category: String) -> String {
        switch category {
        case "音频设备": return "airpodspro"
        case "键盘": return "keyboard"
        case "触控板": return "rectangle.and.hand.point.up.left"
        case "鼠标": return "computermouse"
        case "游戏手柄": return "gamecontroller"
        default: return "dot.radiowaves.left.and.right"
        }
    }
}
