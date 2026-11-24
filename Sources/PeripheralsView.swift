import SwiftUI

struct PeripheralsView: View {
    @ObservedObject var model: PeripheralsMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            displaysCard
            bluetoothBatteriesCard
        }
        .onAppear { model.setActive(true) }
        .onDisappear { model.setActive(false) }
    }

    private var displaysCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "display")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(InterfacePalette.accent)
                    Text("已连接显示器")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                Spacer()
                Text("\(model.snapshot.displays.count) 块屏幕")
                    .font(InterfaceTypography.microMetadata)
                    .foregroundStyle(InterfacePalette.textTertiary)
            }

            if model.snapshot.displays.isEmpty {
                Text("正在读取显示器参数…")
                    .font(InterfaceTypography.caption)
                    .foregroundStyle(InterfacePalette.textTertiary)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(model.snapshot.displays.enumerated()), id: \.element.id) { index, display in
                        displayRow(display)
                        if index < model.snapshot.displays.count - 1 {
                            Divider().opacity(0.4)
                        }
                    }
                }
            }
        }
        .padding(16)
        .stableDashboardCard()
    }

    private func displayRow(_ display: DisplayInfoItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(display.isMain ? InterfacePalette.accent : InterfacePalette.textSecondary)
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(display.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    if display.isMain {
                        badge("主显示器", tint: InterfacePalette.accent)
                    }
                    if display.isBuiltIn {
                        badge("内置", tint: InterfacePalette.textSecondary)
                    }
                    if display.supportsHDR {
                        badge("HDR / EDR", tint: InterfacePalette.power)
                    }
                }
                Text("逻辑 \(display.logicalWidth)×\(display.logicalHeight) · 物理 \(display.pixelWidth)×\(display.pixelHeight) · \(String(format: "%.0fx", display.scaleFactor)) Retina")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(InterfacePalette.textTertiary)
            }

            Spacer()

            Text(display.refreshRateHz.map { String(format: "%.0f Hz", $0) } ?? "60 Hz")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }

    private var bluetoothBatteriesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "wave.3.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(InterfacePalette.battery)
                    Text("蓝牙与无线外设电量")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                Spacer()
                Text(model.snapshot.batteryDevices.isEmpty ? "未发现带电量外设" : "\(model.snapshot.batteryDevices.count) 台设备")
                    .font(InterfaceTypography.microMetadata)
                    .foregroundStyle(InterfacePalette.textTertiary)
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
                VStack(spacing: 10) {
                    ForEach(Array(model.snapshot.batteryDevices.enumerated()), id: \.element.id) { index, device in
                        batteryDeviceRow(device)
                        if index < model.snapshot.batteryDevices.count - 1 {
                            Divider().opacity(0.4)
                        }
                    }
                }
            }
        }
        .padding(16)
        .stableDashboardCard()
    }

    private func batteryDeviceRow(_ device: PeripheralBatteryItem) -> some View {
        let tint: Color = device.batteryPercent <= 15
            ? InterfacePalette.temperature
            : (device.batteryPercent <= 30 ? InterfacePalette.upload : InterfacePalette.battery)

        return HStack(spacing: 12) {
            Image(systemName: iconForCategory(device.category))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Text("\(device.category) · \(device.transport)")
                    .font(InterfaceTypography.microMetadata)
                    .foregroundStyle(InterfacePalette.textTertiary)
            }

            Spacer()

            HStack(spacing: 10) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.07))
                        Capsule()
                            .fill(tint.opacity(0.85))
                            .frame(width: proxy.size.width * min(1, max(0, Double(device.batteryPercent) / 100.0)))
                    }
                }
                .frame(width: 72, height: 5)

                Text("\(device.batteryPercent)%")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tint)
                    .frame(width: 38, alignment: .trailing)
            }
        }
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(tint.opacity(0.12), in: Capsule())
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
