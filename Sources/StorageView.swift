import SwiftUI
import AppKit

struct StorageView: View {
    let snapshot: StorageMonitorSnapshot
    let readHistory: [Double]
    let writeHistory: [Double]
    let onEjectVolume: (StorageVolumeSnapshot) -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var rootVolume: StorageVolumeSnapshot? {
        snapshot.volumes.first(where: \.isRoot) ?? snapshot.volumes.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: InterfaceMetrics.sectionSpacing) {
            storageHeroBento

            ioHistoryCard

            volumesCard
        }
    }

    private var storageHeroBento: some View {
        HStack(alignment: .top, spacing: InterfaceMetrics.sectionSpacing) {
            rootCapacityHeroCard
            driveHealthHeroCard
            ioPulseCard
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var rootCapacityHeroCard: some View {
        let volume = rootVolume
        let usedPercent = volume?.usedPercent ?? 0
        let ringTint = InterfacePalette.loadTint(for: usedPercent, base: InterfacePalette.storage)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                IconBadge(symbol: "internaldrive.fill", tint: ringTint, size: 24, iconSize: 11.5, cornerRadius: 6)
                Text(volume?.name ?? "主系统盘")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let fs = volume?.fileSystemType {
                    StatusBadge(text: fs, tint: InterfacePalette.storage)
                }
            }

            HStack(alignment: .center, spacing: 14) {
                RadialGaugeRing(
                    progress: usedPercent,
                    tint: ringTint,
                    valueText: "\(Int(usedPercent.rounded()))%",
                    caption: "USED",
                    size: 74,
                    lineWidth: 6.5
                )

                VStack(alignment: .leading, spacing: 6) {
                    inlineStat("已用容量", volume.map { storageFormatBytes($0.usedBytes) } ?? "--", tint: .primary)
                    inlineStat("可用空间", volume.map { storageFormatBytes($0.availableBytes) } ?? "--", tint: InterfacePalette.signal)
                    inlineStat(
                        "可清除",
                        volume.map { storageFormatBytes($0.purgeableBytes) } ?? "--",
                        tint: InterfacePalette.textSecondary
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)

            HStack {
                Text(volume?.mountPath ?? "/")
                Spacer()
                Text(volume.map { "总计 \(storageFormatBytes($0.totalBytes))" } ?? "正在读取容量")
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(InterfacePalette.textTertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .stableDashboardCard()
    }

    private var driveHealthHeroCard: some View {
        let drive = snapshot.primaryDrive
        let isHealthy = drive.smartStatus.contains("健康") || drive.smartStatus.contains("已验证")
        let healthTint = isHealthy ? InterfacePalette.signal : InterfacePalette.temperature

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                IconBadge(symbol: "checkmark.shield.fill", tint: healthTint, size: 24, iconSize: 11.5, cornerRadius: 6)
                Text("主磁盘健康")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                StatusBadge(text: drive.smartStatus, tint: healthTint, showDot: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(drive.modelName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(drive.protocolName) · \(drive.isSolidState ? "固态硬盘 (SSD)" : "机械硬盘 (HDD)")")
                    .font(InterfaceTypography.microMetadata)
                    .foregroundStyle(InterfacePalette.textSecondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                compactPill(title: "已挂载卷", value: "\(snapshot.volumes.count) 个")
                compactPill(
                    title: "可移除卷",
                    value: "\(snapshot.volumes.filter { $0.isRemovable && !$0.isRoot }.count) 个"
                )
            }

            Spacer(minLength: 0)

            Text("SMART 只读健康监测")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(InterfacePalette.textTertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .stableDashboardCard()
    }

    private var ioPulseCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                StatusBadge(text: "LIVE I/O", tint: InterfacePalette.storage, showDot: true)
                Spacer(minLength: 4)
                Text("实时吞吐")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(InterfacePalette.textTertiary)
            }

            VStack(spacing: 8) {
                ioRateRow(
                    label: "实时读取",
                    value: storageFormatRate(snapshot.readBytesPerSecond),
                    symbol: "arrow.down",
                    tint: InterfacePalette.storage
                )
                ioRateRow(
                    label: "实时写入",
                    value: storageFormatRate(snapshot.writeBytesPerSecond),
                    symbol: "arrow.up",
                    tint: InterfacePalette.upload
                )
            }

            Spacer(minLength: 0)

            HStack {
                Text("读 \(storageFormatBytes(snapshot.totalReadBytes))")
                Spacer()
                Text("写 \(storageFormatBytes(snapshot.totalWriteBytes))")
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(InterfacePalette.textTertiary)
        }
        .padding(16)
        .frame(width: 320, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .stableDashboardCard()
    }

    private func ioRateRow(label: String, value: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 9) {
            IconBadge(symbol: symbol, tint: tint, size: 24, iconSize: 11, cornerRadius: 6)
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(InterfacePalette.textSecondary)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
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

    private func compactPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(InterfacePalette.textTertiary)
            Text(value)
                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            InterfacePalette.subtleSurface,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
    }

    private var ioHistoryCard: some View {
        let peak = max(1024.0 * 1024.0, (readHistory + writeHistory).max() ?? 0)
        return VStack(alignment: .leading, spacing: 12) {
            SectionCardHeader(
                title: "磁盘读写速率走势",
                subtitle: "近 2 分钟实时吞吐 · 动态峰值 \(storageFormatRate(peak))",
                symbol: "chart.xyaxis.line",
                tint: InterfacePalette.storage
            ) {
                HStack(spacing: 8) {
                    ChartLegendPill(
                        label: "读取",
                        value: storageFormatRate(snapshot.readBytesPerSecond),
                        color: InterfacePalette.storage
                    )
                    ChartLegendPill(
                        label: "写入",
                        value: storageFormatRate(snapshot.writeBytesPerSecond),
                        color: InterfacePalette.upload
                    )
                }
            }

            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    Path { path in
                        for step in 1..<4 {
                            let y = size.height * CGFloat(step) / 4.0
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                        }
                    }
                    .stroke(
                        InterfacePalette.chartGrid,
                        style: StrokeStyle(lineWidth: 1, dash: [3, 4])
                    )

                    areaPath(values: readHistory, peak: peak, size: size)
                        .fill(
                            LinearGradient(
                                colors: [
                                    InterfacePalette.storage.opacity(colorScheme == .dark ? 0.24 : 0.16),
                                    InterfacePalette.storage.opacity(0.01)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    areaPath(values: writeHistory, peak: peak, size: size)
                        .fill(
                            LinearGradient(
                                colors: [
                                    InterfacePalette.upload.opacity(colorScheme == .dark ? 0.20 : 0.14),
                                    InterfacePalette.upload.opacity(0.01)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    seriesPath(values: readHistory, peak: peak, size: size)
                        .stroke(InterfacePalette.storage, style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))

                    seriesPath(values: writeHistory, peak: peak, size: size)
                        .stroke(InterfacePalette.upload, style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(height: 112)
            .clipped()
        }
        .padding(18)
        .stableDashboardCard()
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

    private func areaPath(values: [Double], peak: Double, size: CGSize) -> Path {
        var path = seriesPath(values: values, peak: peak, size: size)
        guard values.count > 1, peak > 0 else { return path }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()
        return path
    }

    private var volumesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionCardHeader(
                title: "已挂载卷宗",
                subtitle: "容量占用、可用空间与可清除缓存",
                symbol: "externaldrive.connected.to.line.below",
                tint: InterfacePalette.storage
            ) {
                StatusBadge(
                    text: "\(snapshot.volumes.count) 个卷宗",
                    tint: InterfacePalette.textSecondary
                )
            }

            if snapshot.volumes.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text("正在扫描已挂载存储卷…")
                        .font(InterfaceTypography.caption)
                        .foregroundStyle(InterfacePalette.textTertiary)
                }
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(snapshot.volumes.enumerated()), id: \.element.id) { index, volume in
                        volumeRow(volume)
                        if index < snapshot.volumes.count - 1 {
                            Divider().opacity(0.35)
                        }
                    }
                }
            }
        }
        .padding(18)
        .stableDashboardCard()
    }

    private func volumeRow(_ volume: StorageVolumeSnapshot) -> some View {
        let barColor = InterfacePalette.loadTint(for: volume.usedPercent, base: InterfacePalette.storage)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                IconBadge(
                    symbol: volume.isInternal ? "internaldrive" : "externaldrive",
                    tint: volume.isRoot ? InterfacePalette.storage : InterfacePalette.textSecondary,
                    size: 28,
                    iconSize: 13,
                    cornerRadius: 7
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(volume.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                        StatusBadge(text: volume.fileSystemType, tint: InterfacePalette.textSecondary)
                        if volume.isRoot {
                            StatusBadge(text: "系统盘", tint: InterfacePalette.storage)
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
                        Image(systemName: "eject.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(InterfacePalette.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(InterfacePalette.subtleSurface, in: RoundedRectangle(cornerRadius: 6.5, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                    .stroke(InterfacePalette.cardStroke, lineWidth: 0.6)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("安全推出 \(volume.name)")
                    .accessibilityLabel("推出 \(volume.name)")
                }
            }

            TelemetryProgressBar(progress: volume.usedPercent, tint: barColor, height: 5)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .hoverRowHighlight(cornerRadius: 8)
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
