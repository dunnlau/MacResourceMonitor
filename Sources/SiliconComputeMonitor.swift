import Foundation
import Darwin
import IOKit
import Metal

struct CoreClusterSnapshot: Equatable {
    var performanceCoreCount = 0
    var efficiencyCoreCount = 0
    var performanceAveragePercent = 0.0
    var efficiencyAveragePercent = 0.0
    var performanceCoreLoads: [Double] = []
    var efficiencyCoreLoads: [Double] = []
    var allCoreLoads: [Double] = []

    var hasHybridClusters: Bool {
        performanceCoreCount > 0 && efficiencyCoreCount > 0
            && performanceCoreCount + efficiencyCoreCount == allCoreLoads.count
    }
}

struct GPUComputeSnapshot: Equatable {
    var name = "Apple GPU"
    var deviceUtilizationPercent: Double? = nil
    var rendererUtilizationPercent: Double? = nil
    var tilerUtilizationPercent: Double? = nil
    var inUseMemoryBytes: UInt64? = nil
    var allocatedMemoryBytes: UInt64? = nil
    var recommendedMaxWorkingSetBytes: UInt64? = nil
}

struct SiliconComputeSnapshot: Equatable {
    var cores = CoreClusterSnapshot()
    var gpu = GPUComputeSnapshot()
}

/// Accessed exclusively on `MonitorModel`'s serial collector queue.
final class SiliconComputeCollector: @unchecked Sendable {
    private struct CoreTicks {
        let user: UInt64
        let system: UInt64
        let idle: UInt64
        let nice: UInt64
    }

    private var previousCoreTicks: [CoreTicks] = []
    private let performanceCoreCount: Int
    private let efficiencyCoreCount: Int
    private let gpuDeviceName: String
    private let recommendedMaxWorkingSetBytes: UInt64?

    init() {
        self.performanceCoreCount = Self.sysctlInt("hw.perflevel0.logicalcpu") ?? 0
        self.efficiencyCoreCount = Self.sysctlInt("hw.perflevel1.logicalcpu") ?? 0
        if let device = MTLCreateSystemDefaultDevice() {
            self.gpuDeviceName = device.name
            let maxBytes = device.recommendedMaxWorkingSetSize
            self.recommendedMaxWorkingSetBytes = maxBytes > 0 ? maxBytes : nil
        } else {
            self.gpuDeviceName = "Apple GPU"
            self.recommendedMaxWorkingSetBytes = nil
        }
    }

    func collect() -> SiliconComputeSnapshot {
        SiliconComputeSnapshot(
            cores: sampleCores(),
            gpu: sampleGPU()
        )
    }

    private func sampleCores() -> CoreClusterSnapshot {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCPUInfo
        )
        guard result == KERN_SUCCESS, let cpuInfo else {
            return CoreClusterSnapshot(
                performanceCoreCount: performanceCoreCount,
                efficiencyCoreCount: efficiencyCoreCount
            )
        }
        defer {
            let byteCount = vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), byteCount)
        }

        let coreCount = Int(numCPUs)
        let stride = Int(CPU_STATE_MAX)
        var currentTicks: [CoreTicks] = []
        currentTicks.reserveCapacity(coreCount)

        for index in 0..<coreCount {
            let base = index * stride
            guard base + Int(CPU_STATE_NICE) < Int(numCPUInfo) else { break }
            currentTicks.append(CoreTicks(
                user: UInt64(UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_USER)])),
                system: UInt64(UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_SYSTEM)])),
                idle: UInt64(UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_IDLE)])),
                nice: UInt64(UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_NICE)]))
            ))
        }

        defer { previousCoreTicks = currentTicks }
        guard previousCoreTicks.count == currentTicks.count else {
            return CoreClusterSnapshot(
                performanceCoreCount: performanceCoreCount,
                efficiencyCoreCount: efficiencyCoreCount,
                allCoreLoads: Array(repeating: 0.0, count: currentTicks.count)
            )
        }

        var loads: [Double] = []
        loads.reserveCapacity(currentTicks.count)
        for index in 0..<currentTicks.count {
            let prev = previousCoreTicks[index]
            let curr = currentTicks[index]
            let user = curr.user >= prev.user ? curr.user - prev.user : 0
            let system = curr.system >= prev.system ? curr.system - prev.system : 0
            let idle = curr.idle >= prev.idle ? curr.idle - prev.idle : 0
            let nice = curr.nice >= prev.nice ? curr.nice - prev.nice : 0
            let total = user + system + idle + nice
            let usage = total > 0 ? min(100, max(0, Double(user + system + nice) / Double(total) * 100)) : 0
            loads.append(usage)
        }

        var snapshot = CoreClusterSnapshot(
            performanceCoreCount: performanceCoreCount,
            efficiencyCoreCount: efficiencyCoreCount,
            allCoreLoads: loads
        )

        if snapshot.hasHybridClusters {
            // On Apple Silicon, efficiency cores are typically enumerated first, followed by performance cores.
            let eLoads = Array(loads.prefix(efficiencyCoreCount))
            let pLoads = Array(loads.suffix(performanceCoreCount))
            snapshot.efficiencyCoreLoads = eLoads
            snapshot.performanceCoreLoads = pLoads
            snapshot.efficiencyAveragePercent = eLoads.isEmpty ? 0 : eLoads.reduce(0, +) / Double(eLoads.count)
            snapshot.performanceAveragePercent = pLoads.isEmpty ? 0 : pLoads.reduce(0, +) / Double(pLoads.count)
        }

        return snapshot
    }

    private func sampleGPU() -> GPUComputeSnapshot {
        var snapshot = GPUComputeSnapshot(
            name: gpuDeviceName,
            recommendedMaxWorkingSetBytes: recommendedMaxWorkingSetBytes
        )

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOAccelerator"),
            &iterator
        ) == kIOReturnSuccess else {
            return snapshot
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            if let stats = IORegistryEntryCreateCFProperty(
                service,
                "PerformanceStatistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any] {
                if let deviceUtil = doubleValue(stats["Device Utilization %"]) ?? doubleValue(stats["GPU Activity(%)"]) {
                    snapshot.deviceUtilizationPercent = min(100, max(0, deviceUtil))
                }
                if let rendererUtil = doubleValue(stats["Renderer Utilization %"]) {
                    snapshot.rendererUtilizationPercent = min(100, max(0, rendererUtil))
                }
                if let tilerUtil = doubleValue(stats["Tiler Utilization %"]) {
                    snapshot.tilerUtilizationPercent = min(100, max(0, tilerUtil))
                }
                if let inUse = uint64Value(stats["In use system memory"]) {
                    snapshot.inUseMemoryBytes = inUse
                }
                if let alloc = uint64Value(stats["Alloc system memory"]) {
                    snapshot.allocatedMemoryBytes = alloc
                }
                if snapshot.deviceUtilizationPercent != nil || snapshot.inUseMemoryBytes != nil {
                    break
                }
            }
        }

        return snapshot
    }

    private func doubleValue(_ raw: Any?) -> Double? {
        if let number = raw as? NSNumber {
            let value = number.doubleValue
            return value.isFinite ? value : nil
        }
        return nil
    }

    private func uint64Value(_ raw: Any?) -> UInt64? {
        guard let number = raw as? NSNumber else { return nil }
        let value = number.int64Value
        return value >= 0 ? UInt64(value) : nil
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }
}
