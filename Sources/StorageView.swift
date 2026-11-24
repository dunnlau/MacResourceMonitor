import SwiftUI
import AppKit

struct StorageView: View {
    let snapshot: StorageMonitorSnapshot
    let readHistory: [Double]
    let writeHistory: [Double]
    let onEjectVolume: (StorageVolumeSnapshot) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ioSummaryCard(
                    title: "磁盘实时读取",
                    value: storageFormatRate(snapshot.readBytesPerSecond),
                    detail: "系统累计 \(storageFormatBytes(snapshot.totalReadBytes))",
                    symbol: "arrow.down.circle",
                    tint: InterfacePalette.storage
                )
                ioSummaryCard(
                    title: "磁盘实时写入",
                    value: storageFormatRate(snapshot.writeBytesPerSecond),
                    detail: "系统累计 \(storageFormatBytes(snapshot.totalWriteBytes))",
                    symbol: "arrow.up.circle",
                    tint: InterfacePalette.upload
                )
                driveHealthCard
            }

            ioHistoryCard

            volumesCard
        }
    }

    private func ioSummaryCard(
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
                    .font(.system(size: 13, weight: .medium))
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

    private var driveHealthCard: some View {
        let drive = snapshot.primaryDrive
        let isHealthy = drive.smartStatus.contains("健康") || drive.smartStatus.contains("已验证")
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("主磁盘健康")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(InterfacePalette.textSecondary)
                Spacer()
                Text(drive.smartStatus)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isHealthy ? InterfacePalette.download : InterfacePalette.temperature)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        (isHealthy ? InterfacePalette.download : InterfacePalette.temperature).opacity(0.12),
                        in: Capsule()
                    )
            }
            Text(drive.modelName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text("\(drive.protocolName) · \(drive.isSolidState ? "固态硬盘" : "机械硬盘")")
                .font(InterfaceTypography.microMetadata)
                .foregroundStyle(InterfacePalette.textTertiary)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .stableDashboardCard()
    }

    private var ioHistoryCard: some View {
        let peak = max(1024.0 * 1024.0, (readHistory + writeHistory).max() ?? 0)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("磁盘读写速率走势（近 2 分钟）")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                HStack(spacing: 12) {
                    legendDot(label: "读取", color: InterfacePalette.storage)
                    legendDot(label: "写入", color: InterfacePalette.upload)
                    Text("峰值 \(storageFormatRate(peak))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(InterfacePalette.textTertiary)
                }
            }

            GeometryReader { proxy in
                ZStack {
                    Path { path in
                        for step in 1..<4 {
                            let y = proxy.size.height * CGFloat(step) / 4.0
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                        }
                    }
                    .stroke(InterfacePalette.chartGrid, lineWidth: 1)

                    seriesPath(values: readHistory, peak: peak, size: proxy.size)
                        .stroke(InterfacePalette.storage, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))

                    seriesPath(values: writeHistory, peak: peak, size: proxy.size)
                        .stroke(InterfacePalette.upload, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(height: 84)
        }
        .padding(16)
        .stableDashboardCard()
    }

    private func legendDot(label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(InterfacePalette.textSecondary)
        }
    }

    private func seriesPath(values: [Double], peak: Double, size: CGSize) -> Path {
        Path { path in
            guard values.count > 1, peak > 0 else { return }
            let stepX = size.width / CGFloat(values.count - 1)
            for (index, value) in values.enumerated() {
                let x = CGFloat(index) * stepX
                let normalized = min(1, max(0, value / peak))
                let y = size.height * (1 - CGFloat(normalized))
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
    }

    private var volumesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("已挂载卷宗")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(snapshot.volumes.count) 个卷宗")
                    .font(InterfaceTypography.microMetadata)
                    .foregroundStyle(InterfacePalette.textTertiary)
            }

            if snapshot.volumes.isEmpty {
                Text("正在扫描已挂载存储卷…")
                    .font(InterfaceTypography.caption)
                    .foregroundStyle(InterfacePalette.textTertiary)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(snapshot.volumes.enumerated()), id: \.element.id) { index, volume in
                        volumeRow(volume)
                        if index < snapshot.volumes.count - 1 {
                            Divider().opacity(0.4)
                        }
                    }
                }
            }
        }
        .padding(16)
        .stableDashboardCard()
    }

    private func volumeRow(_ volume: StorageVolumeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: volume.isInternal ? "internaldrive" : "externaldrive")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(volume.isRoot ? InterfacePalette.storage : InterfacePalette.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(volume.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(volume.fileSystemType)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(InterfacePalette.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                        if volume.isRoot {
                            Text("系统盘")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(InterfacePalette.storage)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(InterfacePalette.storage.opacity(0.12), in: Capsule())
                        }
                    }
                    Text(volume.mountPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(InterfacePalette.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(storageFormatBytes(volume.usedBytes)) / \(storageFormatBytes(volume.totalBytes))")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Text("可用 \(storageFormatBytes(volume.availableBytes))")
                        if volume.purgeableBytes >= 64 * 1024 * 1024 {
                            Text("· 可清除 \(storageFormatBytes(volume.purgeableBytes))")
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(InterfacePalette.textTertiary)
                }

                if volume.isRemovable && !volume.isRoot {
                    Button {
                        onEjectVolume(volume)
                    } label: {
                        Image(systemName: "eject")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(InterfacePalette.textSecondary)
                            .frame(width: 26, height: 26)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("安全推出 \(volume.name)")
                }
            }

            GeometryReader { proxy in
                let usedRatio = min(1, max(0, volume.usedPercent / 100.0))
                let barColor = volume.usedPercent >= 90 ? InterfacePalette.temperature : InterfacePalette.storage
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06))
                    Capsule()
                        .fill(barColor.opacity(0.82))
                        .frame(width: proxy.size.width * usedRatio)
                }
            }
            .frame(height: 5)
        }
    }
}

@MainActor
private let storageByteFormatter: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
    formatter.includesUnit = true
    formatter.isAdaptive = true
    return formatter
}()

@MainActor
private func storageFormatBytes(_ bytes: UInt64) -> String {
    storageByteFormatter.string(fromByteCount: Int64(min(bytes, UInt64(Int64.max))))
}

@MainActor
private func storageFormatRate(_ bytesPerSecond: Double) -> String {
    "\(storageFormatBytes(UInt64(max(0, bytesPerSecond))))/s"
}
