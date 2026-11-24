import SwiftUI

struct PeripheralsView: View {
    @ObservedObject var model: PeripheralsMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: InterfaceMetrics.sectionSpacing) {
            displaysCard
            bluetoothBatteriesCard
        }
        .onAppear { model.setActive(true) }
        .onDisappear { model.setActive(false) }
    }

    private var displaysCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionCardHeader(
                title: "已连接显示器",
                subtitle: "分辨率、缩放倍率、刷新率与 HDR 状态",
                symbol: "display.2",
                tint: InterfacePalette.accent
            ) {
                StatusBadge(
                    text: "\(model.snapshot.displays.count) 块屏幕",
                    tint: InterfacePalette.accent
                )
            }

            if model.snapshot.displays.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text("正在读取显示器参数…")
                        .font(InterfaceTypography.caption)
                        .foregroundStyle(InterfacePalette.textTertiary)
                }
                .padding(.vertical, 6)
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(model.snapshot.displays.enumerated()), id: \.element.id) { index, display in
                        displayRow(display)
                        if index < model.snapshot.displays.count - 1 {
                            Divider().opacity(0.35)
                        }
                    }
                }
            }
        }
        .padding(InterfaceMetrics.cardPadding)
        .stableDashboardCard()
    }

    private func displayRow(_ display: DisplayInfoItem) -> some View {
        HStack(spacing: 12) {
            IconBadge(
                symbol: display.isBuiltIn ? "laptopcomputer" : "display",
                tint: display.isMain ? InterfacePalette.accent : InterfacePalette.textSecondary,
                size: 32,
                iconSize: 15,
                cornerRadius: 8
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(display.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.primary)
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
                Text("逻辑 \(display.logicalWidth)×\(display.logicalHeight) · 物理 \(display.pixelWidth)×\(display.pixelHeight) · \(String(format: "%.0fx", display.scaleFactor)) Retina")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(InterfacePalette.textTertiary)
            }

            Spacer()

            Text(display.refreshRateHz.map { String(format: "%.0f Hz", $0) } ?? "60 Hz")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(InterfacePalette.subtleSurface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .hoverRowHighlight(cornerRadius: 8)
    }

    private var bluetoothBatteriesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionCardHeader(
                title: "蓝牙与无线外设电量",
                subtitle: "妙控键盘、触控板、鼠标、耳机与游戏手柄",
                symbol: "wave.3.right",
                tint: InterfacePalette.battery
            ) {
                StatusBadge(
                    text: model.snapshot.batteryDevices.isEmpty ? "未发现带电量外设" : "\(model.snapshot.batteryDevices.count) 台设备",
                    tint: model.snapshot.batteryDevices.isEmpty ? InterfacePalette.textSecondary : InterfacePalette.battery,
                    showDot: !model.snapshot.batteryDevices.isEmpty
                )
            }

            if model.snapshot.batteryDevices.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(InterfacePalette.textTertiary)
                    Text("当前未检测到上报电量的无线外设（如妙控键盘、妙控板、鼠标、手柄等）。")
                        .font(InterfaceTypography.caption)
                        .foregroundStyle(InterfacePalette.textSecondary)
                }
                .padding(.vertical, 6)
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(model.snapshot.batteryDevices.enumerated()), id: \.element.id) { index, device in
                        batteryDeviceRow(device)
                        if index < model.snapshot.batteryDevices.count - 1 {
                            Divider().opacity(0.35)
                        }
                    }
                }
            }
        }
        .padding(InterfaceMetrics.cardPadding)
        .stableDashboardCard()
    }

    private func batteryDeviceRow(_ device: PeripheralBatteryItem) -> some View {
        let tint: Color = device.batteryPercent <= 15
            ? InterfacePalette.temperature
            : (device.batteryPercent <= 30 ? InterfacePalette.upload : InterfacePalette.battery)

        return HStack(spacing: 12) {
            IconBadge(
                symbol: iconForCategory(device.category),
                tint: tint,
                size: 30,
                iconSize: 13.5,
                cornerRadius: 7.5
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("\(device.category) · \(device.transport)")
                    .font(InterfaceTypography.microMetadata)
                    .foregroundStyle(InterfacePalette.textTertiary)
            }

            Spacer()

            HStack(spacing: 10) {
                TelemetryProgressBar(progress: Double(device.batteryPercent), tint: tint, height: 5)
                    .frame(width: 78)

                Text("\(device.batteryPercent)%")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(tint)
                    .frame(width: 40, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .hoverRowHighlight(cornerRadius: 8)
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
