import SwiftUI

struct SiliconComputeSection: View {
    let snapshot: SiliconComputeSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            coreClusterCard
            gpuComputeCard
        }
    }

    private var coreClusterCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "cpu")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(InterfacePalette.cpuSeries)
                    .frame(width: 26, height: 26)
                    .background(InterfacePalette.cpuSeries.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Apple Silicon 核心调度")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(clusterSubtitle)
                        .font(InterfaceTypography.microMetadata)
                        .foregroundStyle(InterfacePalette.textTertiary)
                }
                Spacer()
            }

            if snapshot.cores.hasHybridClusters {
                VStack(alignment: .leading, spacing: 10) {
                    clusterBarRow(
                        title: "性能核 (P-Core)",
                        average: snapshot.cores.performanceAveragePercent,
                        loads: snapshot.cores.performanceCoreLoads,
                        tint: InterfacePalette.cpuSeries
                    )
                    Divider().opacity(0.4)
                    clusterBarRow(
                        title: "能效核 (E-Core)",
                        average: snapshot.cores.efficiencyAveragePercent,
                        loads: snapshot.cores.efficiencyCoreLoads,
                        tint: InterfacePalette.download
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
        .padding(16)
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
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 18)
            } else {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(loads.enumerated()), id: \.offset) { _, load in
                        let normalized = min(1, max(0.06, load / 100.0))
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(tint.opacity(0.25 + 0.70 * normalized))
                                .frame(height: max(3, 28 * normalized))
                        }
                        .frame(maxWidth: .infinity, maxHeight: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.primary.opacity(0.045))
                        )
                    }
                }
                .frame(height: 28)
            }
        }
    }

    private var gpuComputeCard: some View {
        let gpu = snapshot.gpu
        let utilization = gpu.deviceUtilizationPercent

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(InterfacePalette.memorySeries)
                    .frame(width: 26, height: 26)
                    .background(InterfacePalette.memorySeries.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text("GPU 与图形显存")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(gpu.name)
                        .font(InterfaceTypography.microMetadata)
                        .foregroundStyle(InterfacePalette.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                Text(utilization.map { String(format: "%.0f%%", $0) } ?? "--")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(utilization != nil ? InterfacePalette.memorySeries : InterfacePalette.textSecondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.07))
                    if let utilization {
                        Capsule()
                            .fill(InterfacePalette.memorySeries.opacity(0.85))
                            .frame(width: proxy.size.width * min(1, max(0, utilization / 100.0)))
                    }
                }
            }
            .frame(height: 6)

            HStack(spacing: 12) {
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
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .stableDashboardCard()
    }

    private func gpuMetricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(InterfacePalette.textTertiary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
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
