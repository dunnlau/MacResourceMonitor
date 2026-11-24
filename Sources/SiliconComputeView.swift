import SwiftUI

struct SiliconComputeSection: View {
    let snapshot: SiliconComputeSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: InterfaceMetrics.sectionSpacing) {
            coreClusterCard
            gpuComputeCard
        }
    }

    private var coreClusterCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionCardHeader(
                title: "Apple Silicon 核心调度",
                subtitle: clusterSubtitle,
                symbol: "cpu",
                tint: InterfacePalette.cpuSeries
            )

            if snapshot.cores.hasHybridClusters {
                VStack(alignment: .leading, spacing: 11) {
                    clusterBarRow(
                        title: "性能核 (P-Core)",
                        average: snapshot.cores.performanceAveragePercent,
                        loads: snapshot.cores.performanceCoreLoads,
                        tint: InterfacePalette.cpuSeries
                    )
                    Rectangle()
                        .fill(InterfacePalette.separator)
                        .frame(height: 1)
                    clusterBarRow(
                        title: "能效核 (E-Core)",
                        average: snapshot.cores.efficiencyAveragePercent,
                        loads: snapshot.cores.efficiencyCoreLoads,
                        tint: InterfacePalette.signal
                    )
                }
            } else {
                let loads = snapshot.cores.allCoreLoads
                let avg = loads.isEmpty ? 0 : loads.reduce(0, +) / Double(loads.count)
                clusterBarRow(
                    title: "逻辑核心负载",
                    average: avg,
                    loads: loads,
                    tint: InterfacePalette.cpuSeries
                )
            }
        }
        .padding(InterfaceMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .stableDashboardCard()
    }

    private var clusterSubtitle: String {
        if snapshot.cores.hasHybridClusters {
            return "\(snapshot.cores.performanceCoreCount) 性能核 · \(snapshot.cores.efficiencyCoreCount) 能效核"
        }
        let total = snapshot.cores.allCoreLoads.count
        return total > 0 ? "\(total) 逻辑核心" : "正在读取核心拓扑"
    }

    private func clusterBarRow(
        title: String,
        average: Double,
        loads: [Double],
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(InterfacePalette.textSecondary)
                Spacer()
                Text(String(format: "%.0f%%", average))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            if loads.isEmpty {
                Capsule()
                    .fill(InterfacePalette.subtleSurface)
                    .frame(height: 20)
            } else {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(loads.enumerated()), id: \.offset) { index, load in
                        let normalized = min(1, max(0.08, load / 100.0))
                        let barTint = InterfacePalette.loadTint(for: load, base: tint)
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [barTint.opacity(0.65), barTint],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                                .frame(height: max(3, 30 * normalized))
                        }
                        .frame(maxWidth: .infinity, maxHeight: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(InterfacePalette.subtleSurface)
                        )
                        .help("核心 #\(index + 1)：\(Int(load.rounded()))%")
                    }
                }
                .frame(height: 30)
            }
        }
    }

    private var gpuComputeCard: some View {
        let gpu = snapshot.gpu
        let utilization = gpu.deviceUtilizationPercent
        let gpuTint = utilization.map { InterfacePalette.loadTint(for: $0, base: InterfacePalette.memorySeries) }
            ?? InterfacePalette.memorySeries

        return VStack(alignment: .leading, spacing: 14) {
            SectionCardHeader(
                title: "GPU 与图形显存",
                subtitle: gpu.name,
                symbol: "square.stack.3d.up",
                tint: InterfacePalette.memorySeries
            ) {
                Text(utilization.map { String(format: "%.0f%%", $0) } ?? "--")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(utilization != nil ? gpuTint : InterfacePalette.textSecondary)
            }

            TelemetryProgressBar(progress: utilization ?? 0, tint: gpuTint, height: 6)

            HStack(spacing: 10) {
                gpuMetricPill(
                    title: "渲染器",
                    value: gpu.rendererUtilizationPercent.map { String(format: "%.0f%%", $0) } ?? "--"
                )
                gpuMetricPill(
                    title: "Tiler",
                    value: gpu.tilerUtilizationPercent.map { String(format: "%.0f%%", $0) } ?? "--"
                )
                gpuMetricPill(
                    title: "活跃显存",
                    value: gpu.inUseMemoryBytes.map(siliconFormatBytes) ?? "--"
                )
                gpuMetricPill(
                    title: "推荐上限",
                    value: gpu.recommendedMaxWorkingSetBytes.map(siliconFormatBytes) ?? "--"
                )
            }
        }
        .padding(InterfaceMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .stableDashboardCard()
    }

    private func gpuMetricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(InterfacePalette.textTertiary)
            Text(value)
                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            InterfacePalette.subtleSurface,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(InterfacePalette.cardStroke, lineWidth: 0.6)
        )
    }
}

@MainActor
private let siliconByteFormatter: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .memory
    formatter.allowedUnits = [.useMB, .useGB, .useTB]
    formatter.includesUnit = true
    formatter.isAdaptive = true
    return formatter
}()

@MainActor
private func siliconFormatBytes(_ bytes: UInt64) -> String {
    siliconByteFormatter.string(fromByteCount: Int64(min(bytes, UInt64(Int64.max))))
}
