import SwiftUI

/// Compact Apple Silicon P-Core / E-Core live equalizer matrix embedded inside the CPU Hero card.
struct SiliconCoreMiniMatrix: View {
    let cores: CoreClusterSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if cores.hasHybridClusters {
                compactClusterRow(
                    label: "P 核",
                    average: cores.performanceAveragePercent,
                    loads: cores.performanceCoreLoads,
                    tint: InterfacePalette.cpuSeries
                )
                compactClusterRow(
                    label: "E 核",
                    average: cores.efficiencyAveragePercent,
                    loads: cores.efficiencyCoreLoads,
                    tint: InterfacePalette.signal
                )
            } else {
                let loads = cores.allCoreLoads
                let avg = loads.isEmpty ? 0 : loads.reduce(0, +) / Double(loads.count)
                compactClusterRow(
                    label: "核心",
                    average: avg,
                    loads: loads,
                    tint: InterfacePalette.cpuSeries
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactClusterRow(
        label: String,
        average: Double,
        loads: [Double],
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(InterfacePalette.textSecondary)
                Spacer(minLength: 4)
                Text(String(format: "%.0f%%", average))
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            if loads.isEmpty {
                Capsule()
                    .fill(InterfacePalette.subtleSurface)
                    .frame(height: 12)
            } else {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(loads.enumerated()), id: \.offset) { index, load in
                        let normalized = min(1, max(0.12, load / 100.0))
                        let barTint = InterfacePalette.loadTint(for: load, base: tint)
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(barTint)
                                .frame(height: max(2.5, 16 * normalized))
                        }
                        .frame(maxWidth: .infinity, maxHeight: 16)
                        .background(
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(tint.opacity(0.10))
                        )
                        .help("\(label) #\(index + 1)：\(Int(load.rounded()))%")
                    }
                }
                .frame(height: 16)
            }
        }
    }
}

/// Compact GPU utilization & VRAM breakdown embedded inside the Memory & GPU Hero card.
struct GPUComputeInlineStats: View {
    let gpu: GPUComputeSnapshot
    let memoryUsedText: String

    var body: some View {
        let utilization = gpu.deviceUtilizationPercent
        let gpuTint = utilization.map { InterfacePalette.loadTint(for: $0, base: InterfacePalette.memorySeries) }
            ?? InterfacePalette.memorySeries

        VStack(alignment: .leading, spacing: 7) {
            statRow(title: "已用内存", value: memoryUsedText, valueTint: .primary)

            VStack(alignment: .leading, spacing: 3.5) {
                statRow(
                    title: "GPU 负载",
                    value: utilization.map { String(format: "%.0f%%", $0) } ?? "--",
                    valueTint: utilization != nil ? gpuTint : InterfacePalette.textSecondary
                )
                TelemetryProgressBar(progress: utilization ?? 0, tint: gpuTint, height: 3.5)
            }

            statRow(
                title: "活跃显存",
                value: gpu.inUseMemoryBytes.map(siliconFormatBytes) ?? "--",
                valueTint: InterfacePalette.textSecondary
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statRow(title: String, value: String, valueTint: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(InterfacePalette.textTertiary)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(valueTint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
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
func siliconFormatBytes(_ bytes: UInt64) -> String {
    siliconByteFormatter.string(fromByteCount: Int64(min(bytes, UInt64(Int64.max))))
}
