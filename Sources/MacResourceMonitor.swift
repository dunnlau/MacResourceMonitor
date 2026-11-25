import SwiftUI
import Combine
import Darwin
import IOKit
import SystemConfiguration

private struct ProcessRow: Identifiable {
    let id: Int32
    let name: String
    let cpu: Double
    let memoryBytes: UInt64
}

private struct ChargingPowerSnapshot {
    var externalConnected = false
    var isCharging = false
    var inputWatts: Double? = nil
    var batteryChargeWatts: Double? = nil
    var systemLoadWatts: Double? = nil
}

private struct ResourceSnapshot {
    var cpuPercent = 0.0
    var memoryPercent = 0.0
    var memoryUsed: UInt64 = 0
    var memoryTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
    var diskPercent = 0.0
    var diskUsed: UInt64 = 0
    var diskTotal: UInt64 = 0
    var downloadBytesPerSecond = 0.0
    var uploadBytesPerSecond = 0.0
    var networkInterface = "--"
    var batteryText = "检测中"
    var batteryPercent: Double? = nil
    var powerSource = "--"
    var cpuTemperature: Double? = nil
    var hottestCPUTemperature: Double? = nil
    var fanSpeed: Double? = nil
    var fanCount = 0
    var thermalState = "正常"
    var uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    var processes: [ProcessRow] = []
    var cableMonitor = CableMonitorSnapshot()
    var chargingPower = ChargingPowerSnapshot()
    var siliconCompute = SiliconComputeSnapshot()
    var storage = StorageMonitorSnapshot()
    var batteryDiagnostics = BatteryDiagnosticsSnapshot()
    var expandedMetricsUpdatedAt: Date?
    var updatedAt = Date()
}

private final class ChargingPowerReader {
    func read() -> ChargingPowerSnapshot {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != 0 else { return ChargingPowerSnapshot() }
        defer { IOObjectRelease(service) }

        func property(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(
                service,
                key as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue()
        }

        let externalConnected = (property("ExternalConnected") as? NSNumber)?.boolValue ?? false
        let isCharging = (property("IsCharging") as? NSNumber)?.boolValue ?? false
        let telemetry = property("PowerTelemetryData") as? [String: Any] ?? [:]

        func watts(_ key: String) -> Double? {
            guard let milliwatts = (telemetry[key] as? NSNumber)?.doubleValue,
                  milliwatts >= 0, milliwatts < 300_000 else { return nil }
            return milliwatts / 1000
        }

        return ChargingPowerSnapshot(
            externalConnected: externalConnected,
            isCharging: isCharging,
            inputWatts: externalConnected ? watts("SystemPowerIn") : nil,
            batteryChargeWatts: isCharging ? watts("BatteryPower") : nil,
            systemLoadWatts: watts("SystemLoad")
        )
    }
}

private enum SMCDataType: String {
    case ui8 = "ui8 "
    case ui16 = "ui16"
    case ui32 = "ui32"
    case sp78 = "sp78"
    case flt = "flt "
    case fpe2 = "fpe2"
}

private struct SMCKeyData {
    typealias Bytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                       UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                       UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                       UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

    struct Version {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct LimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuLimit: UInt32 = 0
        var gpuLimit: UInt32 = 0
        var memoryLimit: UInt32 = 0
    }

    struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var version = Version()
    var limitData = LimitData()
    var keyInfo = KeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: Bytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

private final class SMCReader {
    private var connection: io_connect_t = 0

    private static let cpuTemperatureKeysByGeneration: [String: [String]] = [
        "m1": [
            "Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D",
            "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"
        ],
        "m2": [
            "Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp01", "Tp05",
            "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"
        ],
        "m3": [
            "Te05", "Te0L", "Te0P", "Te0S", "Tf04", "Tf09",
            "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49",
            "Tf4A", "Tf4B", "Tf4D", "Tf4E"
        ],
        "m4": [
            "Te05", "Te0S", "Te09", "Te0H", "Tp01", "Tp05",
            "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"
        ],
        "m5": [
            "Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K",
            "Tp0O", "Tp0R", "Tp0U", "Tp0X", "Tp0a", "Tp0d",
            "Tp0g", "Tp0j", "Tp0m", "Tp0p", "Tp0u", "Tp0y"
        ]
    ]

    private let cpuTemperatureKeys = SMCReader.detectedCPUTemperatureKeys()
    private var workingCPUTemperatureKeys: [String]?
    private var cpuTemperatureProbeCounter = 0

    private static func detectedCPUTemperatureKeys() -> [String] {
        guard let brand = cpuBrandString()?.lowercased() else { return [] }
        let words = brand.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        for generation in ["m5", "m4", "m3", "m2", "m1"] where words.contains(generation) {
            return cpuTemperatureKeysByGeneration[generation] ?? []
        }
        return []
    }

    private static func cpuBrandString() -> String? {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0,
              size > 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        let result = buffer.withUnsafeMutableBytes { bytes in
            sysctlbyname("machdep.cpu.brand_string", bytes.baseAddress, &size, nil, 0)
        }
        guard result == 0 else { return nil }
        return String(cString: buffer)
    }

    init() {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSMC"), &iterator)
        guard result == kIOReturnSuccess else { return }
        let device = IOIteratorNext(iterator)
        IOObjectRelease(iterator)
        guard device != 0 else { return }
        defer { IOObjectRelease(device) }
        guard IOServiceOpen(device, mach_task_self_, 0, &connection) == kIOReturnSuccess else {
            connection = 0
            return
        }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    func cpuTemperatures() -> (average: Double, hottest: Double)? {
        let shouldProbeAllKeys = workingCPUTemperatureKeys == nil || cpuTemperatureProbeCounter == 0
        let candidates = shouldProbeAllKeys
            ? cpuTemperatureKeys
            : workingCPUTemperatureKeys ?? cpuTemperatureKeys
        cpuTemperatureProbeCounter = (cpuTemperatureProbeCounter + 1) % 30
        let readings = candidates.compactMap { key -> (key: String, value: Double)? in
            guard let value = value(for: key),
                  value.isFinite,
                  (10...120).contains(value) else { return nil }
            return (key, value)
        }
        guard !readings.isEmpty,
              let hottest = readings.map(\.value).max() else {
            workingCPUTemperatureKeys = nil
            return nil
        }
        workingCPUTemperatureKeys = readings.map(\.key)
        let values = readings.map(\.value)
        return (values.reduce(0, +) / Double(values.count), hottest)
    }

    func fanReading() -> (speed: Double?, count: Int) {
        guard let rawCount = value(for: "FNum") else { return (nil, 0) }
        let count = max(0, Int(rawCount.rounded()))
        guard count > 0 else { return (nil, 0) }
        let speeds = (0..<count).compactMap { value(for: "F\($0)Ac") }.filter { $0 >= 0 && $0 < 20_000 }
        return (speeds.max(), count)
    }

    func batteryTemperature() -> Double? {
        let keys = ["TB0T", "TB1T", "TB2T"]
        let readings = keys.compactMap { value(for: $0) }.filter { $0.isFinite && (5...85).contains($0) }
        guard !readings.isEmpty else { return nil }
        return readings.reduce(0, +) / Double(readings.count)
    }

    private func fourCharacterCode(_ string: String) -> UInt32 {
        string.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private func string(from code: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xff), UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff), UInt8(code & 0xff)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }

    private func value(for key: String) -> Double? {
        guard connection != 0, key.utf8.count == 4 else { return nil }
        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = fourCharacterCode(key)
        input.data8 = 9

        guard call(input: &input, output: &output) == kIOReturnSuccess,
              output.result == 0,
              output.status == 0,
              output.keyInfo.dataSize > 0,
              output.keyInfo.dataSize <= 32 else { return nil }
        let dataSize = Int(output.keyInfo.dataSize)
        let dataType = string(from: output.keyInfo.dataType)

        input.keyInfo.dataSize = output.keyInfo.dataSize
        input.data8 = 5
        guard call(input: &input, output: &output) == kIOReturnSuccess,
              output.result == 0,
              output.status == 0 else { return nil }

        let bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(dataSize)) }
        guard !bytes.isEmpty else { return nil }
        switch dataType {
        case SMCDataType.ui8.rawValue:
            return Double(bytes[0])
        case SMCDataType.ui16.rawValue where bytes.count >= 2:
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case SMCDataType.ui32.rawValue where bytes.count >= 4:
            return Double(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
        case SMCDataType.sp78.rawValue where bytes.count >= 2:
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        case SMCDataType.fpe2.rawValue where bytes.count >= 2:
            return Double((Int(bytes[0]) << 6) + (Int(bytes[1]) >> 2))
        case SMCDataType.flt.rawValue where bytes.count >= 4:
            return Double(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
        default:
            return nil
        }
    }

    private func call(input: inout SMCKeyData, output: inout SMCKeyData) -> kern_return_t {
        let inputSize = MemoryLayout<SMCKeyData>.stride
        var outputSize = MemoryLayout<SMCKeyData>.stride
        return IOConnectCallStructMethod(connection, 2, &input, inputSize, &output, &outputSize)
    }
}

private struct ResourceCollectionOptions {
    var includeExpandedMetrics = false
    var includeTopProcesses = false
    var includeCable = false
    var includeSiliconCompute = false
    var includeStorage = false
    var includeBatteryDiagnostics = false
}

private enum ResourceMonitorConsumer: Hashable {
    case expandedMetrics
    case menuBar
    case processTable
    case cable
    case siliconCompute
    case storage
    case batteryDiagnostics
}

/// Accessed exclusively on `MonitorModel`'s serial collector queue.
private final class SystemCollector: @unchecked Sendable {
    private var cachedSnapshot = ResourceSnapshot()
    private var previousCPUTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private var previousNetwork: (interface: String, received: UInt64, sent: UInt64, date: Date)?
    private var cachedBattery: (text: String, percent: Double?, source: String) = ("检测中", nil, "--")
    private var batterySampleCounter = 0
    private var cableSampleCounter = 0
    private var cachedCableMonitor = CableMonitorSnapshot()
    private let smc = SMCReader()
    private let cableCollector = CableCollector()
    private let chargingPowerReader = ChargingPowerReader()
    private let siliconComputeCollector = SiliconComputeCollector()
    private let storageCollector = StorageCollector()
    private let batteryDiagnosticsCollector = BatteryDiagnosticsCollector()

    func collect(
        options: ResourceCollectionOptions,
        forceCableRefresh: Bool = false,
        forceExpandedMetricsRefresh: Bool = false,
        forceStorageRefresh: Bool = false,
        forceBatteryDiagnosticsRefresh: Bool = false
    ) -> ResourceSnapshot {
        var snapshot = cachedSnapshot
        snapshot.cpuPercent = sampleCPU()

        let memory = sampleMemory()
        snapshot.memoryUsed = memory.used
        snapshot.memoryTotal = memory.total
        snapshot.memoryPercent = memory.total > 0 ? Double(memory.used) / Double(memory.total) * 100 : 0

        let network = sampleNetwork()
        snapshot.downloadBytesPerSecond = network.receivedPerSecond
        snapshot.uploadBytesPerSecond = network.sentPerSecond
        snapshot.networkInterface = network.interface

        let temperatures = smc.cpuTemperatures()
        snapshot.cpuTemperature = temperatures?.average
        snapshot.hottestCPUTemperature = temperatures?.hottest
        snapshot.chargingPower = chargingPowerReader.read()

        if options.includeExpandedMetrics {
            let disk = sampleDisk()
            snapshot.diskUsed = disk.used
            snapshot.diskTotal = disk.total
            snapshot.diskPercent = disk.total > 0 ? Double(disk.used) / Double(disk.total) * 100 : 0

            if forceExpandedMetricsRefresh || batterySampleCounter == 0 {
                cachedBattery = sampleBattery()
                batterySampleCounter = 0
                snapshot.expandedMetricsUpdatedAt = Date()
            }
            batterySampleCounter = (batterySampleCounter + 1) % 5
            snapshot.batteryText = cachedBattery.text
            snapshot.batteryPercent = cachedBattery.percent
            snapshot.powerSource = cachedBattery.source

            let fan = smc.fanReading()
            snapshot.fanSpeed = fan.speed
            snapshot.fanCount = fan.count
            snapshot.thermalState = thermalStateText()
            snapshot.uptime = ProcessInfo.processInfo.systemUptime
        } else {
            batterySampleCounter = 0
        }

        if options.includeSiliconCompute {
            snapshot.siliconCompute = siliconComputeCollector.collect()
        }

        if options.includeStorage || forceStorageRefresh {
            snapshot.storage = storageCollector.collect(forceVolumeRefresh: forceStorageRefresh)
        }

        if options.includeBatteryDiagnostics || forceBatteryDiagnosticsRefresh {
            var batteryDiag = batteryDiagnosticsCollector.collect(
                forceRefresh: forceBatteryDiagnosticsRefresh
            )
            if batteryDiag.temperatureCelsius == nil {
                batteryDiag.temperatureCelsius = smc.batteryTemperature()
            }
            snapshot.batteryDiagnostics = batteryDiag
        }

        snapshot.processes = options.includeTopProcesses ? sampleTopProcesses() : []

        if options.includeCable || forceCableRefresh {
            if forceCableRefresh || cableSampleCounter == 0 {
                let reading = cableCollector.collect()
                if reading.errorText == nil || cachedCableMonitor.ports.isEmpty {
                    cachedCableMonitor = reading
                } else {
                    cachedCableMonitor.helperAvailable = reading.helperAvailable
                    cachedCableMonitor.errorText = reading.errorText
                }
            }
            cableSampleCounter = (cableSampleCounter + 1) % 3
        } else {
            cableSampleCounter = 0
        }
        snapshot.cableMonitor = cachedCableMonitor
        snapshot.updatedAt = Date()
        cachedSnapshot = snapshot
        return snapshot
    }

    private func thermalStateText() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "正常"
        case .fair: return "略高"
        case .serious: return "较高"
        case .critical: return "严重"
        @unknown default: return "未知"
        }
    }

    private func sampleCPU() -> Double {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let ticks = (
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
        defer { previousCPUTicks = ticks }
        guard let previous = previousCPUTicks else { return 0 }

        let user = ticks.user >= previous.user ? ticks.user - previous.user : 0
        let system = ticks.system >= previous.system ? ticks.system - previous.system : 0
        let idle = ticks.idle >= previous.idle ? ticks.idle - previous.idle : 0
        let nice = ticks.nice >= previous.nice ? ticks.nice - previous.nice : 0
        let total = user + system + idle + nice
        guard total > 0 else { return 0 }
        return min(100, max(0, Double(user + system + nice) / Double(total) * 100))
    }

    private func sampleMemory() -> (used: UInt64, total: UInt64) {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        let total = ProcessInfo.processInfo.physicalMemory
        guard result == KERN_SUCCESS else { return (0, total) }
        let pageSize = UInt64(vm_kernel_page_size)
        let internalPages = UInt64(stats.internal_page_count)
        let purgeablePages = UInt64(stats.purgeable_count)
        let appPages = internalPages >= purgeablePages ? internalPages - purgeablePages : 0
        let wiredPages = UInt64(stats.wire_count)
        let compressedPages = UInt64(stats.compressor_page_count)
        let used = min(total, (appPages + wiredPages + compressedPages) * pageSize)
        return (used, total)
    }

    private func sampleDisk() -> (used: UInt64, total: UInt64) {
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]) else { return (0, 0) }
        let total = UInt64(max(0, values.volumeTotalCapacity ?? 0))
        let available = UInt64(max(0, values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)))
        return (total >= available ? total - available : 0, total)
    }

    private func primaryInterface() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "MacResourceMonitor" as CFString, nil, nil) else {
            return nil
        }
        for protocolName in ["IPv4", "IPv6"] {
            let key = "State:/Network/Global/\(protocolName)" as CFString
            if let value = SCDynamicStoreCopyValue(store, key) as? [String: Any],
               let interface = value["PrimaryInterface"] as? String,
               !interface.isEmpty {
                return interface
            }
        }
        return nil
    }

    private func interfaceCounters(_ interface: String) -> (received: UInt64, sent: UInt64)? {
        let index = interface.withCString { if_nametoindex($0) }
        guard index > 0 else { return nil }

        var mib = [
            Int32(CTL_NET),
            Int32(PF_LINK),
            Int32(NETLINK_GENERIC),
            Int32(IFMIB_IFDATA),
            Int32(index),
            Int32(IFDATA_GENERAL)
        ]
        var data = ifmibdata()
        var dataSize = MemoryLayout<ifmibdata>.stride
        let result = mib.withUnsafeMutableBufferPointer { pointer in
            sysctl(pointer.baseAddress, u_int(pointer.count), &data, &dataSize, nil, 0)
        }
        guard result == 0 else { return nil }
        return (UInt64(data.ifmd_data.ifi_ibytes), UInt64(data.ifmd_data.ifi_obytes))
    }

    private func sampleNetwork() -> (receivedPerSecond: Double, sentPerSecond: Double, interface: String) {
        guard let interface = primaryInterface(),
              let counters = interfaceCounters(interface) else {
            previousNetwork = nil
            return (0, 0, "--")
        }

        let now = Date()
        defer {
            previousNetwork = (interface, counters.received, counters.sent, now)
        }
        guard let previous = previousNetwork,
              previous.interface == interface,
              counters.received >= previous.received,
              counters.sent >= previous.sent else {
            return (0, 0, interface)
        }

        let elapsed = max(0.2, now.timeIntervalSince(previous.date))
        let receivedDelta = counters.received - previous.received
        let sentDelta = counters.sent - previous.sent
        return (Double(receivedDelta) / elapsed, Double(sentDelta) / elapsed, interface)
    }

    private func run(_ executable: String, _ arguments: [String]) -> String? {
        guard let result = CommandRunner.run(
            executable,
            arguments: arguments,
            timeout: 4
        ), !result.timedOut, result.terminationStatus == 0 else { return nil }
        return result.outputString
    }

    private func sampleBattery() -> (text: String, percent: Double?, source: String) {
        guard let output = run("/usr/bin/pmset", ["-g", "batt"]) else {
            return ("不可用", nil, "未知")
        }
        let lower = output.lowercased()
        let source: String
        if lower.contains("ac power") {
            source = "电源适配器"
        } else if lower.contains("battery power") {
            source = "电池供电"
        } else {
            source = "无电池"
        }

        guard let percentRange = output.range(of: #"\d+%"#, options: .regularExpression) else {
            return (source == "无电池" ? "无内置电池" : "不可用", nil, source)
        }
        let percentString = output[percentRange].dropLast()
        let percent = Double(percentString) ?? 0
        var state = ""
        if lower.contains("discharging") {
            state = " · 使用中"
        } else if lower.contains("charging") && !lower.contains("not charging") {
            state = " · 充电中"
        } else if lower.contains("charged") {
            state = " · 已充满"
        }
        return ("\(Int(percent))%\(state)", percent, source)
    }

    private func sampleTopProcesses() -> [ProcessRow] {
        guard let output = run("/bin/ps", ["-Aceo", "pid=,pcpu=,rss=,comm=", "-r"]) else { return [] }
        var rows: [ProcessRow] = []
        for line in output.split(separator: "\n").prefix(40) {
            let fields = line.split(maxSplits: 3, whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count == 4,
                  let pid = Int32(fields[0]),
                  let cpu = Double(fields[1]),
                  let rssKB = UInt64(fields[2]) else { continue }
            var name = String(fields[3])
            if name.contains("/") {
                name = URL(fileURLWithPath: name).lastPathComponent
            }
            rows.append(ProcessRow(id: pid, name: name, cpu: cpu, memoryBytes: rssKB * 1024))
            if rows.count == 6 { break }
        }
        return rows
    }
}

@MainActor
private final class MonitorModel: ObservableObject {
    private(set) var snapshot = ResourceSnapshot()
    private(set) var cpuHistory = Array(repeating: 0.0, count: 60)
    private(set) var memoryHistory = Array(repeating: 0.0, count: 60)
    private(set) var diskReadHistory = Array(repeating: 0.0, count: 60)
    private(set) var diskWriteHistory = Array(repeating: 0.0, count: 60)
    @Published var isRefreshingCable = false
    @Published var isRefreshingExpandedMetrics = false

    private let collector = SystemCollector()
    private let queue = DispatchQueue(label: "local.mac-resource-monitor.collector", qos: .utility)
    private var pollTask: Task<Void, Never>?
    private var refreshInProgress = false
    private var refreshPending = false
    private var forceCableRefreshPending = false
    private var forceStorageRefreshPending = false
    private var forceBatteryDiagnosticsRefreshPending = false
    private var expandedMetricsRefreshGeneration: UInt64 = 0
    private var activeConsumers: Set<ResourceMonitorConsumer> = []

    init() {
        refresh()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled, let self else { break }
                self.refresh()
            }
        }
    }

    deinit { pollTask?.cancel() }

    func setActive(_ active: Bool, for consumer: ResourceMonitorConsumer) {
        updateActiveConsumers([consumer: active])
    }

    func updateActiveConsumers(_ changes: [ResourceMonitorConsumer: Bool]) {
        let previousConsumers = activeConsumers
        for (consumer, active) in changes {
            if active {
                activeConsumers.insert(consumer)
            } else {
                activeConsumers.remove(consumer)
            }
        }
        guard activeConsumers != previousConsumers else { return }

        let newlyActive = activeConsumers.subtracting(previousConsumers)
        let needsCableRefresh = newlyActive.contains(.cable) || newlyActive.contains(.menuBar)
        let needsStorageRefresh = newlyActive.contains(.storage)
        let needsBatteryRefresh = newlyActive.contains(.batteryDiagnostics)
        let expandedBecameActive = newlyActive.contains(.expandedMetrics) || newlyActive.contains(.menuBar)
        let expandedMetricsAreActive = activeConsumers.contains(.expandedMetrics)
            || activeConsumers.contains(.menuBar)
        let expandedMetricsWereActive = previousConsumers.contains(.expandedMetrics)
            || previousConsumers.contains(.menuBar)
        let expandedMetricsAreStale = snapshot.expandedMetricsUpdatedAt.map {
            Date().timeIntervalSince($0) > 4
        } ?? true
        if expandedBecameActive, expandedMetricsAreStale {
            expandedMetricsRefreshGeneration &+= 1
            isRefreshingExpandedMetrics = true
        } else if expandedMetricsWereActive, !expandedMetricsAreActive {
            expandedMetricsRefreshGeneration &+= 1
            isRefreshingExpandedMetrics = false
        }
        refresh(
            forceCableRefresh: needsCableRefresh,
            forceStorageRefresh: needsStorageRefresh,
            forceBatteryDiagnosticsRefresh: needsBatteryRefresh
        )
    }

    func refresh(
        forceCableRefresh: Bool = false,
        forceStorageRefresh: Bool = false,
        forceBatteryDiagnosticsRefresh: Bool = false
    ) {
        if forceCableRefresh {
            forceCableRefreshPending = true
            isRefreshingCable = true
        }
        if forceStorageRefresh {
            forceStorageRefreshPending = true
        }
        if forceBatteryDiagnosticsRefresh {
            forceBatteryDiagnosticsRefreshPending = true
        }
        guard !refreshInProgress else {
            refreshPending = true
            return
        }
        let shouldForceCableRefresh = forceCableRefreshPending
        let shouldForceStorageRefresh = forceStorageRefreshPending
        let shouldForceBatteryRefresh = forceBatteryDiagnosticsRefreshPending
        let shouldForceExpandedMetricsRefresh = isRefreshingExpandedMetrics
        let options = collectionOptions
        let expandedMetricsGeneration = expandedMetricsRefreshGeneration
        let collector = self.collector
        forceCableRefreshPending = false
        forceStorageRefreshPending = false
        forceBatteryDiagnosticsRefreshPending = false
        refreshPending = false
        refreshInProgress = true
        queue.async { [weak self] in
            let next = collector.collect(
                options: options,
                forceCableRefresh: shouldForceCableRefresh,
                forceExpandedMetricsRefresh: shouldForceExpandedMetricsRefresh,
                forceStorageRefresh: shouldForceStorageRefresh,
                forceBatteryDiagnosticsRefresh: shouldForceBatteryRefresh
            )
            Task { @MainActor [weak self] in
                guard let self else { return }
                let nextCPUHistory = Array(self.cpuHistory.suffix(59)) + [next.cpuPercent]
                let nextMemoryHistory = Array(self.memoryHistory.suffix(59)) + [next.memoryPercent]
                let nextDiskReadHistory = options.includeStorage
                    ? Array(self.diskReadHistory.suffix(59)) + [next.storage.readBytesPerSecond]
                    : self.diskReadHistory
                let nextDiskWriteHistory = options.includeStorage
                    ? Array(self.diskWriteHistory.suffix(59)) + [next.storage.writeBytesPerSecond]
                    : self.diskWriteHistory
                self.objectWillChange.send()
                withTransaction(Transaction(animation: nil)) {
                    self.snapshot = next
                    self.cpuHistory = nextCPUHistory
                    self.memoryHistory = nextMemoryHistory
                    self.diskReadHistory = nextDiskReadHistory
                    self.diskWriteHistory = nextDiskWriteHistory
                    self.refreshInProgress = false
                    if options.includeExpandedMetrics,
                       expandedMetricsGeneration == self.expandedMetricsRefreshGeneration {
                        self.isRefreshingExpandedMetrics = false
                    }
                    if shouldForceCableRefresh {
                        self.isRefreshingCable = self.forceCableRefreshPending
                    }
                }
                if self.refreshPending || self.forceCableRefreshPending
                    || self.forceStorageRefreshPending || self.forceBatteryDiagnosticsRefreshPending {
                    self.refresh()
                }
            }
        }
    }

    func refreshCableMonitor() {
        refresh(forceCableRefresh: true)
    }

    func ejectVolume(_ volume: StorageVolumeSnapshot) {
        let url = URL(fileURLWithPath: volume.mountPath)
        Task.detached(priority: .userInitiated) {
            try? NSWorkspace.shared.unmountAndEjectDevice(at: url)
            await MainActor.run { [weak self] in
                self?.refresh(forceStorageRefresh: true)
            }
        }
    }

    private var collectionOptions: ResourceCollectionOptions {
        ResourceCollectionOptions(
            includeExpandedMetrics: activeConsumers.contains(.expandedMetrics)
                || activeConsumers.contains(.menuBar),
            includeTopProcesses: activeConsumers.contains(.processTable),
            includeCable: activeConsumers.contains(.cable)
                || activeConsumers.contains(.menuBar),
            includeSiliconCompute: activeConsumers.contains(.siliconCompute),
            includeStorage: activeConsumers.contains(.storage),
            includeBatteryDiagnostics: activeConsumers.contains(.batteryDiagnostics)
        )
    }
}

private struct OverviewHeroBento: View {
    let snapshot: ResourceSnapshot
    let isLoadingExpandedMetrics: Bool

    var body: some View {
        HStack(alignment: .top, spacing: InterfaceMetrics.sectionSpacing) {
            cpuHeroCard
            memoryAndGPUHeroCard
            networkPulseCard
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("系统实时遥测")
    }

    private var cpuHeroCard: some View {
        let cpuTint = InterfacePalette.loadTint(for: snapshot.cpuPercent, base: InterfacePalette.cpuSeries)
        let tempTint = InterfacePalette.temperatureTint(for: snapshot.cpuTemperature)
        let cores = snapshot.siliconCompute.cores
        let topologyText: String = cores.hasHybridClusters
            ? "\(cores.performanceCoreCount) P 核 · \(cores.efficiencyCoreCount) E 核"
            : (cores.allCoreLoads.isEmpty ? "处理器核心" : "\(cores.allCoreLoads.count) 逻辑核心")
        let peakText = snapshot.hottestCPUTemperature.map { String(format: "峰值 %.1f°C", $0) } ?? "温控就绪"

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                IconBadge(symbol: "cpu", tint: cpuTint, size: 24, iconSize: 11.5, cornerRadius: 6)
                Text("处理器与核心")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                StatusBadge(
                    text: formatTemperature(snapshot.cpuTemperature),
                    tint: tempTint
                )
            }

            HStack(alignment: .center, spacing: 14) {
                RadialGaugeRing(
                    progress: snapshot.cpuPercent,
                    tint: cpuTint,
                    valueText: "\(Int(snapshot.cpuPercent.rounded()))%",
                    caption: "CPU",
                    size: 74,
                    lineWidth: 6.5
                )

                SiliconCoreMiniMatrix(cores: cores)
            }

            Spacer(minLength: 0)

            HStack {
                Text(topologyText)
                Spacer()
                Text(peakText)
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(InterfacePalette.textTertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .stableDashboardCard()
    }

    private var memoryAndGPUHeroCard: some View {
        let memTint = InterfacePalette.loadTint(for: snapshot.memoryPercent, base: InterfacePalette.memorySeries)
        let gpu = snapshot.siliconCompute.gpu
        let gpuFooter: String = {
            var parts: [String] = []
            if let r = gpu.rendererUtilizationPercent {
                parts.append(String(format: "渲染 %.0f%%", r))
            }
            if let t = gpu.tilerUtilizationPercent {
                parts.append(String(format: "Tiler %.0f%%", t))
            }
            if let maxMem = gpu.recommendedMaxWorkingSetBytes {
                parts.append("上限 \(siliconFormatBytes(maxMem))")
            }
            return parts.isEmpty ? "统一内存架构" : parts.joined(separator: " · ")
        }()

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                IconBadge(symbol: "memorychip", tint: memTint, size: 24, iconSize: 11.5, cornerRadius: 6)
                Text("内存与图形")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                StatusBadge(
                    text: gpu.name,
                    tint: InterfacePalette.memorySeries
                )
            }

            HStack(alignment: .center, spacing: 14) {
                RadialGaugeRing(
                    progress: snapshot.memoryPercent,
                    tint: memTint,
                    valueText: "\(Int(snapshot.memoryPercent.rounded()))%",
                    caption: "MEM",
                    size: 74,
                    lineWidth: 6.5
                )

                GPUComputeInlineStats(
                    gpu: gpu,
                    memoryUsedText: formatBytes(snapshot.memoryUsed)
                )
            }

            Spacer(minLength: 0)

            Text(gpuFooter)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(InterfacePalette.textTertiary)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .stableDashboardCard()
    }

    private var networkPulseCard: some View {
        let thermalTint: Color = snapshot.thermalState.contains("正常")
            ? InterfacePalette.signal
            : InterfacePalette.temperature

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                StatusBadge(
                    text: isLoadingExpandedMetrics ? "同步中" : "LIVE · 2s",
                    tint: isLoadingExpandedMetrics ? InterfacePalette.upload : InterfacePalette.signal,
                    showDot: true
                )
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    Image(systemName: "network")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(InterfacePalette.accent)
                    Text(snapshot.networkInterface)
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(InterfacePalette.textSecondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(InterfacePalette.subtleSurface, in: Capsule())
            }

            VStack(spacing: 8) {
                networkRateRow(
                    label: "网络下行",
                    value: formatRate(snapshot.downloadBytesPerSecond),
                    symbol: "arrow.down",
                    tint: InterfacePalette.download
                )
                networkRateRow(
                    label: "网络上行",
                    value: formatRate(snapshot.uploadBytesPerSecond),
                    symbol: "arrow.up",
                    tint: InterfacePalette.upload
                )
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(InterfacePalette.power)
                    Text(isLoadingExpandedMetrics ? "--" : formatBatteryChargePower(snapshot.chargingPower))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(InterfacePalette.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                StatusBadge(
                    text: isLoadingExpandedMetrics ? "检测中" : "温控 \(snapshot.thermalState)",
                    tint: isLoadingExpandedMetrics ? InterfacePalette.textSecondary : thermalTint
                )
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .stableDashboardCard()
    }

    private func networkRateRow(
        label: String,
        value: String,
        symbol: String,
        tint: Color
    ) -> some View {
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
}

private struct CombinedLoadHistory: View {
    let cpuValues: [Double]
    let memoryValues: [Double]
    let cpuValue: Double
    let memoryValue: Double

    @Environment(\.colorScheme) private var colorScheme
    @State private var hoverIndex: Int?
    @State private var accessibilitySampleOffset = 0

    private var sampleCount: Int {
        min(cpuValues.count, memoryValues.count)
    }

    private var accessibilitySampleIndex: Int? {
        guard sampleCount > 0 else { return nil }
        let offset = min(accessibilitySampleOffset, sampleCount - 1)
        return sampleCount - 1 - offset
    }

    private var accessibilitySampleValue: String {
        guard let index = accessibilitySampleIndex else {
            return "暂无历史采样"
        }
        let secondsAgo = (sampleCount - 1 - index) * 2
        let time = secondsAgo == 0 ? "现在" : "约 \(secondsAgo) 秒前"
        return "\(time)，CPU \(Int(cpuValues[index].rounded()))%，内存 \(Int(memoryValues[index].rounded()))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionCardHeader(
                title: "实时负载趋势",
                subtitle: "近 2 分钟双通道采样",
                symbol: "waveform.path.ecg",
                tint: InterfacePalette.cpuSeries
            ) {
                HStack(spacing: 8) {
                    ChartLegendPill(
                        label: "CPU",
                        value: "\(Int(cpuValue.rounded()))%",
                        color: InterfacePalette.cpuSeries
                    )
                    ChartLegendPill(
                        label: "内存",
                        value: "\(Int(memoryValue.rounded()))%",
                        color: InterfacePalette.memorySeries
                    )
                }
            }

            GeometryReader { geometry in
                let size = geometry.size
                ZStack(alignment: .topLeading) {
                    chartGrid(in: size)

                    areaPath(values: cpuValues, in: size)
                        .fill(
                            LinearGradient(
                                colors: [
                                    InterfacePalette.cpuSeries.opacity(colorScheme == .dark ? 0.28 : 0.20),
                                    InterfacePalette.cpuSeries.opacity(0.01)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    areaPath(values: memoryValues, in: size)
                        .fill(
                            LinearGradient(
                                colors: [
                                    InterfacePalette.memorySeries.opacity(colorScheme == .dark ? 0.20 : 0.14),
                                    InterfacePalette.memorySeries.opacity(0.01)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    linePath(values: memoryValues, in: size)
                        .stroke(
                            InterfacePalette.memorySeries,
                            style: StrokeStyle(
                                lineWidth: 2.0,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )

                    linePath(values: cpuValues, in: size)
                        .stroke(
                            InterfacePalette.cpuSeries,
                            style: StrokeStyle(
                                lineWidth: 2.4,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )

                    if hoverIndex == nil, sampleCount > 1 {
                        liveEndpoints(in: size)
                    }

                    if let hoverIndex, sampleCount > 1 {
                        hoverOverlay(index: hoverIndex, in: size)
                    }

                    Color.clear
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                guard sampleCount > 1 else { return }
                                let ratio = min(1, max(0, location.x / size.width))
                                hoverIndex = min(
                                    sampleCount - 1,
                                    max(0, Int((ratio * CGFloat(sampleCount - 1)).rounded()))
                                )
                            case .ended:
                                hoverIndex = nil
                            }
                        }
                }
            }
            .frame(minHeight: 196, maxHeight: .infinity)
            .clipped()

            HStack {
                Text("2 分钟前")
                Spacer()
                Text(hoverStatusText)
                Spacer()
                Text("现在")
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(InterfacePalette.textTertiary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .stableDashboardCard(cornerRadius: InterfaceMetrics.cardRadius)
        .transaction { transaction in
            transaction.animation = nil
        }
        .onChange(of: sampleCount) { _, newCount in
            accessibilitySampleOffset = min(
                accessibilitySampleOffset,
                max(0, newCount - 1)
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("CPU 与内存负载趋势")
        .accessibilityValue(accessibilitySampleValue)
        .accessibilityHint("向上浏览较新的采样，向下浏览较早的采样")
        .accessibilityAdjustableAction { direction in
            guard sampleCount > 0 else { return }
            switch direction {
            case .increment:
                accessibilitySampleOffset = max(
                    0,
                    accessibilitySampleOffset - 1
                )
            case .decrement:
                accessibilitySampleOffset = min(
                    sampleCount - 1,
                    accessibilitySampleOffset + 1
                )
            @unknown default:
                break
            }
        }
    }

    private var hoverStatusText: String {
        guard let hoverIndex, sampleCount > 1 else { return "悬停查看采样点" }
        let secondsAgo = (sampleCount - 1 - hoverIndex) * 2
        return secondsAgo == 0 ? "最新采样" : "约 \(secondsAgo) 秒前"
    }

    @ViewBuilder
    private func liveEndpoints(in size: CGSize) -> some View {
        let surface = InterfacePalette.stableDashboardSurface(for: colorScheme)
        if let lastCPU = cpuValues.last {
            let y = chartY(lastCPU, height: size.height)
            Circle()
                .fill(InterfacePalette.cpuSeries.opacity(0.26))
                .frame(width: 12, height: 12)
                .position(x: size.width - 3, y: y)
            Circle()
                .fill(InterfacePalette.cpuSeries)
                .overlay(Circle().stroke(surface, lineWidth: 1.5))
                .frame(width: 6.5, height: 6.5)
                .position(x: size.width - 3, y: y)
        }
        if let lastMemory = memoryValues.last {
            let y = chartY(lastMemory, height: size.height)
            Circle()
                .fill(InterfacePalette.memorySeries)
                .overlay(Circle().stroke(surface, lineWidth: 1.5))
                .frame(width: 6, height: 6)
                .position(x: size.width - 3, y: y)
        }
    }

    private func chartGrid(in size: CGSize) -> some View {
        ZStack {
            ForEach(0...4, id: \.self) { step in
                Path { path in
                    let y = size.height * CGFloat(step) / 4
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                .stroke(
                    InterfacePalette.chartGrid,
                    style: StrokeStyle(lineWidth: 1, dash: step == 4 ? [] : [3, 4])
                )
            }
            ForEach([0, 2, 4], id: \.self) { step in
                Text("\(100 - step * 25)%")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(InterfacePalette.textTertiary)
                    .position(x: 18, y: size.height * CGFloat(step) / 4 + (step == 0 ? 9 : -9))
            }
        }
    }

    @ViewBuilder
    private func hoverOverlay(index: Int, in size: CGSize) -> some View {
        let x = size.width * CGFloat(index) / CGFloat(max(1, sampleCount - 1))
        let cpu = cpuValues[index]
        let memory = memoryValues[index]
        let cpuY = chartY(cpu, height: size.height)
        let memoryY = chartY(memory, height: size.height)
        let surface = InterfacePalette.stableDashboardSurface(for: colorScheme)
        let secondsAgo = (sampleCount - 1 - index) * 2
        let timeLabel = secondsAgo == 0 ? "现在" : "-\(secondsAgo)s"

        Path { path in
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
        }
        .stroke(InterfacePalette.crosshair, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

        Circle()
            .fill(InterfacePalette.cpuSeries)
            .overlay(Circle().stroke(surface, lineWidth: 2))
            .frame(width: 8, height: 8)
            .position(x: x, y: cpuY)

        Circle()
            .fill(InterfacePalette.memorySeries)
            .overlay(Circle().stroke(surface, lineWidth: 2))
            .frame(width: 8, height: 8)
            .position(x: x, y: memoryY)

        VStack(alignment: .leading, spacing: 3) {
            Text(timeLabel)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(InterfacePalette.textTertiary)
            HStack(spacing: 5) {
                Circle().fill(InterfacePalette.cpuSeries).frame(width: 5, height: 5)
                Text("CPU \(Int(cpu.rounded()))%")
            }
            HStack(spacing: 5) {
                Circle().fill(InterfacePalette.memorySeries).frame(width: 5, height: 5)
                Text("内存 \(Int(memory.rounded()))%")
            }
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            surface.opacity(0.95),
            in: RoundedRectangle(
                cornerRadius: InterfaceMetrics.controlRadius,
                style: .continuous
            )
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: InterfaceMetrics.controlRadius,
                style: .continuous
            )
            .stroke(InterfacePalette.cardStroke, lineWidth: 0.8)
        )
        .shadow(color: InterfacePalette.cardShadow(for: colorScheme), radius: 6, y: 2)
        .position(
            x: min(max(62, x), max(62, size.width - 62)),
            y: 34
        )
    }

    private func linePath(values: [Double], in size: CGSize) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        for (index, rawValue) in values.enumerated() {
            let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
            let y = chartY(rawValue, height: size.height)
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }

    private func areaPath(values: [Double], in size: CGSize) -> Path {
        var path = linePath(values: values, in: size)
        guard values.count > 1 else { return path }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()
        return path
    }

    private func chartY(_ value: Double, height: CGFloat) -> CGFloat {
        height * (1 - CGFloat(min(100, max(0, value)) / 100))
    }
}

private struct HardwareTelemetryPanel: View {
    let snapshot: ResourceSnapshot
    let isLoadingExpandedMetrics: Bool

    var body: some View {
        let diskTint = InterfacePalette.loadTint(for: snapshot.diskPercent, base: InterfacePalette.storage)

        VStack(alignment: .leading, spacing: 0) {
            SectionCardHeader(
                title: "硬件与主机",
                subtitle: Host.current().localizedName ?? "Mac",
                symbol: "desktopcomputer",
                tint: InterfacePalette.storage
            )
            .padding(.bottom, 10)

            hardwareRow(
                "内置磁盘",
                isLoadingExpandedMetrics
                    ? "--"
                    : "\(Int(snapshot.diskPercent.rounded()))% 已用",
                symbol: "internaldrive",
                tint: diskTint,
                progress: isLoadingExpandedMetrics ? nil : snapshot.diskPercent
            )
            rowDivider
            hardwareRow(
                "散热风扇",
                isLoadingExpandedMetrics ? "--" : formatFanSpeed(snapshot.fanSpeed),
                symbol: "fan",
                tint: InterfacePalette.fan
            )
            rowDivider
            hardwareRow(
                "电池状态",
                isLoadingExpandedMetrics ? "检测中" : snapshot.batteryText,
                symbol: "battery.75percent",
                tint: InterfacePalette.battery
            )
            rowDivider
            hardwareRow(
                "供电方式",
                isLoadingExpandedMetrics ? "检测中" : snapshot.powerSource,
                symbol: "bolt.fill",
                tint: InterfacePalette.power
            )
            rowDivider
            hardwareRow(
                "持续运行",
                isLoadingExpandedMetrics ? "检测中" : formatUptime(snapshot.uptime),
                symbol: "clock",
                tint: InterfacePalette.accent
            )
        }
        .padding(18)
        .frame(width: 320, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .stableDashboardCard(cornerRadius: InterfaceMetrics.cardRadius)
    }

    private func hardwareRow(
        _ label: String,
        _ value: String,
        symbol: String,
        tint: Color = InterfacePalette.accent,
        progress: Double? = nil
    ) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 9) {
                IconBadge(symbol: symbol, tint: tint, size: 24, iconSize: 11, cornerRadius: 6)
                Text(label)
                    .font(InterfaceTypography.caption)
                    .foregroundStyle(InterfacePalette.textSecondary)
                Spacer()
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            if let progress {
                TelemetryProgressBar(progress: progress, tint: tint, height: 4)
                    .padding(.leading, 33)
            }
        }
        .padding(.vertical, 8)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(InterfacePalette.separator)
            .frame(height: 1)
    }
}

private struct ProcessTable: View {
    let rows: [ProcessRow]

    var body: some View {
        let maxCPU = max(10.0, rows.map(\.cpu).max() ?? 10.0)

        VStack(alignment: .leading, spacing: 10) {
            SectionCardHeader(
                title: "高负载进程",
                subtitle: "按实时 CPU 占用排序",
                symbol: "flame.fill",
                tint: InterfacePalette.upload
            ) {
                Text("TOP \(max(rows.count, 5))")
                    .font(InterfaceTypography.eyebrow)
                    .foregroundStyle(InterfacePalette.textTertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(InterfacePalette.subtleSurface, in: Capsule())
            }

            HStack(spacing: 12) {
                Text("#")
                    .frame(width: 24, alignment: .trailing)
                Text("进程名称")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("PID")
                    .frame(width: 72, alignment: .trailing)
                Text("CPU 占用")
                    .frame(width: 140, alignment: .trailing)
                Text("内存占用")
                    .frame(width: 96, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(InterfacePalette.textTertiary)
            .padding(.horizontal, 10)
            .padding(.top, 2)

            Divider().opacity(0.45)

            if rows.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text("正在读取进程…")
                        .font(.system(size: 12))
                        .foregroundStyle(InterfacePalette.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        let ratio = min(1, max(0, row.cpu / maxCPU))
                        let cpuColor = InterfacePalette.loadTint(for: row.cpu, base: InterfacePalette.cpuSeries)

                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(InterfacePalette.textTertiary)
                                .frame(width: 24, alignment: .trailing)

                            Text(row.name)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text("\(row.id)")
                                .foregroundStyle(InterfacePalette.textTertiary)
                                .frame(width: 72, alignment: .trailing)

                            HStack(spacing: 8) {
                                GeometryReader { proxy in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(cpuColor.opacity(0.14))
                                        Capsule()
                                            .fill(cpuColor)
                                            .frame(width: max(3, proxy.size.width * ratio))
                                    }
                                }
                                .frame(width: 68, height: 4.5)

                                Text(String(format: "%.1f%%", row.cpu))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(row.cpu >= 50 ? cpuColor : Color.primary)
                                    .frame(width: 52, alignment: .trailing)
                            }
                            .frame(width: 140, alignment: .trailing)

                            Text(formatBytes(row.memoryBytes))
                                .foregroundStyle(InterfacePalette.textSecondary)
                                .frame(width: 96, alignment: .trailing)
                        }
                        .font(.system(size: 12, design: .monospaced))
                        .monospacedDigit()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .hoverRowHighlight(cornerRadius: 7)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .stableDashboardCard()
    }
}

private struct CableSection: View {
    let monitor: CableMonitorSnapshot
    let chargingPower: ChargingPowerSnapshot
    let isRefreshing: Bool

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    IconBadge(symbol: "cable.connector", tint: InterfacePalette.accent, size: 24, iconSize: 11.5, cornerRadius: 6)
                    Text("USB-C / 雷雳端口状态")
                        .font(InterfaceTypography.cardTitle)
                }
                Spacer()
                if isRefreshing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("正在检测")
                            .font(InterfaceTypography.microMetadata)
                            .foregroundStyle(InterfacePalette.textSecondary)
                    }
                } else if let errorText = monitor.errorText {
                    StatusBadge(text: errorText, tint: InterfacePalette.upload)
                } else {
                    StatusBadge(
                        text: "\(monitor.activePorts.count) / \(monitor.ports.count) 已连接",
                        tint: monitor.activePorts.isEmpty ? InterfacePalette.textSecondary : InterfacePalette.signal,
                        showDot: !monitor.activePorts.isEmpty
                    )
                }
            }

            if isRefreshing {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("正在检测 USB-C 与线缆状态")
                            .font(.system(size: 13, weight: .semibold))
                        Text("检测完成后会更新端口连接与供电速率")
                            .font(InterfaceTypography.caption)
                            .foregroundStyle(InterfacePalette.textSecondary)
                    }
                    Spacer()
                }
                .padding(16)
                .stableDashboardCard()
            } else if monitor.ports.isEmpty {
                HStack(spacing: 12) {
                    IconBadge(symbol: "cable.connector.slash", tint: InterfacePalette.textSecondary, size: 32, iconSize: 15)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(monitor.errorText ?? "未发现可读取的 USB-C 端口")
                            .font(.system(size: 13, weight: .semibold))
                        Text("需要 Apple Silicon 芯片与 macOS 14 及以上系统")
                            .font(InterfaceTypography.caption)
                            .foregroundStyle(InterfacePalette.textSecondary)
                    }
                    Spacer()
                }
                .padding(16)
                .stableDashboardCard()
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(monitor.ports) { port in
                        CablePortCard(
                            port: port,
                            liveInputWatts: liveInputWatts(for: port)
                        )
                    }
                }
            }

            Text("只读检测 · 仅在系统固件暴露 E-Marker 信息时展示线缆标识")
                .font(InterfaceTypography.microMetadata)
                .foregroundStyle(InterfacePalette.textTertiary)
                .padding(.horizontal, 4)
        }
    }

    private func liveInputWatts(for port: CablePortSnapshot) -> Double? {
        let chargingPorts = monitor.activePorts.filter { $0.negotiatedPower != nil }
        guard chargingPorts.count == 1,
              chargingPorts.first?.id == port.id else { return nil }
        return chargingPower.inputWatts
    }
}

private struct PortMonitorView: View {
    let monitor: CableMonitorSnapshot
    let chargingPower: ChargingPowerSnapshot
    let isRefreshing: Bool

    var body: some View {
        CableSection(
            monitor: monitor,
            chargingPower: chargingPower,
            isRefreshing: isRefreshing
        )
    }
}

private struct CablePortCard: View {
    let port: CablePortSnapshot
    let liveInputWatts: Double?

    private var symbol: String {
        if !port.connected { return "cable.connector.slash" }
        if port.activeTransports.contains("Thunderbolt/USB4") { return "bolt.horizontal.fill" }
        if port.activeTransports.contains("DisplayPort") { return "display" }
        return "cable.connector"
    }

    private var portTint: Color {
        if !port.connected { return InterfacePalette.textTertiary }
        if port.negotiatedPower != nil { return InterfacePalette.power }
        return InterfacePalette.accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconBadge(symbol: symbol, tint: portTint, size: 30, iconSize: 13.5, cornerRadius: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(port.displayName)
                        .font(.system(size: 13.5, weight: .semibold))
                    Text(port.stateTitle)
                        .font(InterfaceTypography.microMetadata)
                        .foregroundStyle(port.connected ? InterfacePalette.textSecondary : InterfacePalette.textTertiary)
                }
                Spacer()
                StatusBadge(
                    text: port.connected ? "已连接" : "空闲",
                    tint: port.connected ? InterfacePalette.signal : InterfacePalette.textTertiary,
                    showDot: port.connected
                )
            }

            Text(port.stateDetail)
                .font(InterfaceTypography.caption)
                .foregroundStyle(InterfacePalette.textSecondary)
                .lineLimit(2)

            if port.connected {
                Divider().opacity(0.4)
                VStack(spacing: 7) {
                    if let value = port.negotiatedPower {
                        cableDetail("协商上限", value, "bolt.fill")
                    }
                    if let watts = liveInputWatts {
                        cableDetail("实时输入", String(format: "%.1f W", watts), "gauge.with.dots.needle.50percent")
                    }
                    if let value = port.dataLinkSummary {
                        cableDetail("数据链路", value, "arrow.left.arrow.right")
                    }
                    if let value = port.cableSpeed {
                        cableDetail("线缆速率", value, "speedometer")
                    }
                    if let value = port.cablePower {
                        cableDetail("线缆额定", value, "powerplug")
                    }
                    if let value = port.cableVendor {
                        cableDetail("E-Marker", value, "cpu")
                    }
                    if let value = port.trustText {
                        cableDetail("能力判断", value, "checkmark.shield")
                    }
                    if let value = port.warning {
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(InterfacePalette.upload)
                            Text(value)
                                .font(InterfaceTypography.microMetadata)
                                .foregroundStyle(InterfacePalette.upload)
                            Spacer()
                        }
                        .padding(.top, 2)
                    }
                    if !port.hasCableIdentity {
                        Text("macOS 未读取到线缆 E-Marker 芯片信息。")
                            .font(InterfaceTypography.microMetadata)
                            .foregroundStyle(InterfacePalette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                Text(port.supportedTransports.isEmpty
                     ? (port.type.localizedCaseInsensitiveContains("MagSafe") ? "磁吸充电接口" : "等待设备接入")
                     : "支持：\(port.supportedTransports.joined(separator: " · "))")
                    .font(InterfaceTypography.microMetadata)
                    .foregroundStyle(InterfacePalette.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: port.connected ? 174 : 126, alignment: .topLeading)
        .stableDashboardCard()
    }

    private func cableDetail(_ label: String, _ value: String, _ symbol: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .frame(width: 14)
                .foregroundStyle(InterfacePalette.textTertiary)
            Text(label)
                .font(InterfaceTypography.caption)
                .foregroundStyle(InterfacePalette.textSecondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

private enum DashboardSection: String, CaseIterable, Identifiable {
    case monitor = "系统概览"
    case storage = "磁盘存储"
    case traffic = "网络监控"
    case ports = "电源与接口"
    case peripherals = "显示与外设"
    case settings = "偏好设置"

    static let primaryCases: [DashboardSection] = [.monitor, .storage, .traffic, .ports, .peripherals]

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .monitor: return "gauge.with.dots.needle.50percent"
        case .storage: return "internaldrive"
        case .traffic: return "network"
        case .ports: return "bolt.batteryblock"
        case .peripherals: return "display.2"
        case .settings: return "slider.horizontal.3"
        }
    }

    var tint: Color {
        InterfacePalette.accent
    }

    var subtitle: String {
        switch self {
        case .monitor: return "CPU、GPU 与内存温控"
        case .storage: return "磁盘读写与卷宗健康"
        case .traffic: return "流量、端口与网络诊断"
        case .ports: return "电池能耗与接口线缆"
        case .peripherals: return "显示器与蓝牙外设"
        case .settings: return "菜单栏、通知与启动"
        }
    }

    var eyebrow: String {
        switch self {
        case .monitor: return "SYSTEM / LIVE"
        case .storage: return "DISK / STORAGE"
        case .traffic: return "NETWORK / SERVICE"
        case .ports: return "POWER / PORTS"
        case .peripherals: return "DISPLAY / PERIPHERALS"
        case .settings: return "PREFERENCES"
        }
    }
}

@MainActor
private final class TransparentWindowBridgeView: NSView {
    private weak var configuredWindow: NSWindow?
    private weak var configuredContentView: NSView?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            configuredWindow = nil
            configuredContentView = nil
        } else {
            configureWindowIfNeeded()
        }
    }

    func configureWindowIfNeeded() {
        guard let window else { return }
        let contentView = window.contentView
        guard configuredWindow !== window || configuredContentView !== contentView else { return }

        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        contentView?.wantsLayer = true
        contentView?.layer?.backgroundColor = NSColor.clear.cgColor

        configuredWindow = window
        configuredContentView = contentView
    }
}

private struct WindowTransparencyConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> TransparentWindowBridgeView {
        TransparentWindowBridgeView(frame: .zero)
    }

    func updateNSView(_ nsView: TransparentWindowBridgeView, context: Context) {
        nsView.configureWindowIfNeeded()
    }
}

private struct SidebarNavigationItem: View {
    let section: DashboardSection
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.symbol)
                    .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? InterfacePalette.accent : InterfacePalette.textSecondary)
                    .frame(width: 18)

                Text(section.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.primary : InterfacePalette.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .frame(height: 36)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(
                    cornerRadius: 9,
                    style: .continuous
                )
                .fill(
                    isSelected
                        ? InterfacePalette.accent.opacity(colorScheme == .dark ? 0.16 : 0.11)
                        : (isHovering ? InterfacePalette.hoverFill : Color.clear)
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: 9,
                    style: .continuous
                )
                .stroke(
                    isSelected ? InterfacePalette.accent.opacity(0.24) : Color.clear,
                    lineWidth: 0.7
                )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(section.rawValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct DashboardView: View {
    @ObservedObject var model: MonitorModel
    @ObservedObject var processNetworkModel: ProcessNetworkMonitor
    @ObservedObject var localPortsModel: LocalPortsMonitor
    @ObservedObject var networkDiagnosticsModel: NetworkDiagnosticsMonitor
    @ObservedObject var peripheralsModel: PeripheralsMonitor
    @ObservedObject var preferences: AppPreferences
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selectedSection: DashboardSection

    var body: some View {
        ZStack {
            ZStack {
                InterfacePalette.canvas(for: colorScheme)
                if !reduceTransparency {
                    RadialGradient(
                        colors: [InterfacePalette.accent.opacity(colorScheme == .dark ? 0.14 : 0.08), .clear],
                        center: .topTrailing, startRadius: 0, endRadius: 640
                    )
                    RadialGradient(
                        colors: [InterfacePalette.memorySeries.opacity(colorScheme == .dark ? 0.11 : 0.05), .clear],
                        center: .bottomLeading, startRadius: 0, endRadius: 580
                    )
                }
            }
            .ignoresSafeArea()

            HStack(spacing: 0) {
                sidebar

                Rectangle()
                    .fill(InterfacePalette.separator)
                    .frame(width: 1)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        contentHeader
                        sectionContent
                    }
                    .padding(.top, 26)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 26)
                }
                .scrollClipDisabled(false)
                .scrollEdgeEffectStyle(.soft, for: .bottom)
                .id(selectedSection.rawValue)
            }
        }
        .frame(minWidth: 1060, idealWidth: 1180, minHeight: 720, idealHeight: 830)
        .background(WindowTransparencyConfigurator())
        .onAppear {
            updateResourceConsumers()
        }
        .onChange(of: selectedSection) { _, _ in
            updateResourceConsumers()
        }
        .onDisappear {
            model.updateActiveConsumers([
                .expandedMetrics: false,
                .processTable: false,
                .cable: false,
                .siliconCompute: false,
                .storage: false,
                .batteryDiagnostics: false
            ])
        }
    }

    private func updateResourceConsumers() {
        model.updateActiveConsumers([
            .expandedMetrics: selectedSection == .monitor || selectedSection == .ports,
            .processTable: selectedSection == .monitor,
            .siliconCompute: selectedSection == .monitor,
            .storage: selectedSection == .storage,
            .cable: selectedSection == .ports,
            .batteryDiagnostics: selectedSection == .ports
        ])
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .monitor:
            VStack(spacing: InterfaceMetrics.sectionSpacing) {
                OverviewHeroBento(
                    snapshot: model.snapshot,
                    isLoadingExpandedMetrics: model.isRefreshingExpandedMetrics
                )

                HStack(alignment: .top, spacing: InterfaceMetrics.sectionSpacing) {
                    CombinedLoadHistory(
                        cpuValues: model.cpuHistory,
                        memoryValues: model.memoryHistory,
                        cpuValue: model.snapshot.cpuPercent,
                        memoryValue: model.snapshot.memoryPercent
                    )
                    HardwareTelemetryPanel(
                        snapshot: model.snapshot,
                        isLoadingExpandedMetrics: model.isRefreshingExpandedMetrics
                    )
                }
                .fixedSize(horizontal: false, vertical: true)

                ProcessTable(rows: model.snapshot.processes)
            }
        case .storage:
            StorageView(
                snapshot: model.snapshot.storage,
                readHistory: model.diskReadHistory,
                writeHistory: model.diskWriteHistory,
                onEjectVolume: { volume in
                    model.ejectVolume(volume)
                }
            )
        case .traffic:
            NetworkWorkspaceView(
                processNetworkModel: processNetworkModel,
                localPortsModel: localPortsModel,
                diagnosticsModel: networkDiagnosticsModel
            )
        case .ports:
            VStack(spacing: InterfaceMetrics.sectionSpacing) {
                BatteryDiagnosticsView(
                    diagnostics: model.snapshot.batteryDiagnostics,
                    inputWatts: model.snapshot.chargingPower.inputWatts,
                    batteryChargeWatts: model.snapshot.chargingPower.batteryChargeWatts,
                    systemLoadWatts: model.snapshot.chargingPower.systemLoadWatts,
                    powerSource: model.snapshot.powerSource,
                    showsSleepAssertions: false
                )

                PortMonitorView(
                    monitor: model.snapshot.cableMonitor,
                    chargingPower: model.isRefreshingExpandedMetrics
                        ? ChargingPowerSnapshot()
                        : model.snapshot.chargingPower,
                    isRefreshing: model.isRefreshingCable
                )

                SleepAssertionsCard(
                    assertions: model.snapshot.batteryDiagnostics.sleepAssertions
                )
            }
        case .peripherals:
            PeripheralsView(model: peripheralsModel)
        case .settings:
            SettingsView(preferences: preferences)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(InterfacePalette.cardStroke, lineWidth: 0.6)
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text("Mac 资源监控")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("TELEMETRY")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(InterfacePalette.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.top, 34)
            .padding(.bottom, 18)

            Text("监控模块")
                .font(InterfaceTypography.eyebrow)
                .tracking(0.8)
                .foregroundStyle(InterfacePalette.textTertiary)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)

            VStack(spacing: 3) {
                ForEach(DashboardSection.primaryCases) { section in
                    sidebarItem(section)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                Text("系统")
                    .font(InterfaceTypography.eyebrow)
                    .tracking(0.8)
                    .foregroundStyle(InterfacePalette.textTertiary)
                    .padding(.horizontal, 10)

                sidebarItem(.settings)

                sidebarLiveVitalsCard
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
        .frame(width: InterfaceMetrics.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(InterfacePalette.sidebarSurface(for: colorScheme))
    }

    private var sidebarLiveVitalsCard: some View {
        let cpuTint = InterfacePalette.loadTint(for: model.snapshot.cpuPercent, base: InterfacePalette.cpuSeries)
        let tempTint = InterfacePalette.temperatureTint(for: model.snapshot.cpuTemperature)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(InterfacePalette.signal)
                    .frame(width: 6, height: 6)
                Text("实时状态")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(InterfacePalette.textSecondary)
                Spacer()
                Text(formatTemperature(model.snapshot.cpuTemperature))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tempTint)
            }

            VStack(spacing: 5) {
                HStack {
                    Text("CPU")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(InterfacePalette.textTertiary)
                    Spacer()
                    Text(String(format: "%.0f%%", model.snapshot.cpuPercent))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                }
                TelemetryProgressBar(progress: model.snapshot.cpuPercent, tint: cpuTint, height: 3.5)
            }

            HStack(spacing: 6) {
                Text("MEM \(String(format: "%.0f%%", model.snapshot.memoryPercent))")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(InterfacePalette.textSecondary)
                Spacer()
                Text("↓\(formatMenuBarRate(model.snapshot.downloadBytesPerSecond))")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(InterfacePalette.download)
            }
        }
        .padding(10)
        .background(
            InterfacePalette.subtleSurface,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(InterfacePalette.cardStroke, lineWidth: 0.7)
        )
    }

    private func sidebarItem(_ section: DashboardSection) -> some View {
        SidebarNavigationItem(section: section, isSelected: selectedSection == section) {
            if reduceMotion {
                selectedSection = section
            } else {
                withAnimation(.easeInOut(duration: 0.16)) {
                    selectedSection = section
                }
            }
        }
    }

    private var contentHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedSection.eyebrow)
                    .font(InterfaceTypography.eyebrow)
                    .tracking(1.1)
                    .foregroundStyle(InterfacePalette.accent)

                Text(selectedSection.rawValue)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    Text(headerSubtitle)
                        .foregroundStyle(InterfacePalette.textSecondary)
                    if !heroFootnote.isEmpty {
                        Text("·")
                            .foregroundStyle(InterfacePalette.textTertiary)
                        Text(heroFootnote)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(InterfacePalette.textTertiary)
                    }
                }
                .font(InterfaceTypography.microMetadata)
                .lineLimit(1)
            }

            Spacer(minLength: 14)

            if selectedSection != .settings {
                ActionPillButton(
                    title: heroActionTitle,
                    symbol: "arrow.clockwise",
                    isPrimary: false,
                    isDisabled: isHeroActionDisabled,
                    action: performHeroAction
                )
            }
        }
        .padding(.bottom, 4)
    }

    private var heroFootnote: String {
        switch selectedSection {
        case .monitor:
            if model.isRefreshingExpandedMetrics { return "正在更新传感器" }
            let date = model.snapshot.expandedMetricsUpdatedAt ?? model.snapshot.updatedAt
            return "更新于 \(date.formatted(date: .omitted, time: .standard))"
        case .storage:
            if let date = model.snapshot.storage.updatedAt {
                return "更新于 \(date.formatted(date: .omitted, time: .standard))"
            }
            return "正在读取存储"
        case .traffic:
            if let date = networkDiagnosticsModel.snapshot.updatedAt ?? processNetworkModel.lastUpdatedAt {
                return "采样于 \(date.formatted(date: .omitted, time: .standard))"
            }
            return "正在采样网络"
        case .ports:
            if model.isRefreshingCable { return "正在检测接口" }
            if let date = model.snapshot.batteryDiagnostics.updatedAt ?? model.snapshot.cableMonitor.updatedAt {
                return "检测于 \(date.formatted(date: .omitted, time: .standard))"
            }
            return "只读电池与端口检测"
        case .peripherals:
            if let date = peripheralsModel.snapshot.updatedAt {
                return "更新于 \(date.formatted(date: .omitted, time: .standard))"
            }
            return "正在扫描外设"
        case .settings:
            return ""
        }
    }

    private var heroActionTitle: String {
        switch selectedSection {
        case .monitor: return "刷新"
        case .storage: return "刷新存储"
        case .traffic:
            return networkDiagnosticsModel.isRefreshing ? "探测中" : "刷新诊断"
        case .ports:
            return model.isRefreshingCable ? "检测中" : "刷新全部"
        case .peripherals:
            return peripheralsModel.isRefreshing ? "扫描中" : "刷新外设"
        case .settings:
            return ""
        }
    }

    private var isHeroActionDisabled: Bool {
        switch selectedSection {
        case .monitor, .storage: return false
        case .traffic: return networkDiagnosticsModel.isRefreshing
        case .ports: return model.isRefreshingCable
        case .peripherals: return peripheralsModel.isRefreshing
        case .settings: return true
        }
    }

    private func performHeroAction() {
        switch selectedSection {
        case .monitor:
            model.refresh()
        case .storage:
            model.refresh(forceStorageRefresh: true)
        case .traffic:
            networkDiagnosticsModel.refresh()
            localPortsModel.refresh()
        case .ports:
            model.refresh(forceBatteryDiagnosticsRefresh: true)
            model.refreshCableMonitor()
        case .peripherals:
            peripheralsModel.refresh(forceBluetooth: true)
        case .settings:
            break
        }
    }

    private var headerSubtitle: String {
        switch selectedSection {
        case .monitor:
            return "处理器 P/E 核、GPU、内存与温控实时状态"
        case .storage:
            return "磁盘实时读写速率、NVMe 健康度与挂载卷宗"
        case .traffic:
            return "实时应用流量、Wi-Fi 链路、延迟走势与本机监听端口"
        case .ports:
            return "电池健康、实时功耗拆解、USB-C / 雷雳端口与休眠断言"
        case .peripherals:
            return "显示器分辨率/刷新率/HDR 与蓝牙无线外设电量"
        case .settings:
            return "自定义顶部菜单栏显示项、阈值提醒与开机启动"
        }
    }
}

private struct MenuBarPresentationState {
    var traffic = ProcessTrafficDisplayState()
}

private struct MenuBarPanel: View {
    @ObservedObject var model: MonitorModel
    let processNetworkModel: ProcessNetworkMonitor
    @Binding var selectedSection: DashboardSection
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
    @State private var presentation = MenuBarPresentationState()

    var body: some View {
        VStack(spacing: 10) {
            menuHeader
                .padding(.horizontal, 2)

            heroVitalsGrid

            networkThroughputCard

            processTrafficCard

            hardwareSummaryCard

            menuFooter
                .padding(.horizontal, 2)
                .padding(.top, 2)
        }
        .padding(12)
        .frame(width: 360)
        .background(InterfacePalette.menuSurface(for: colorScheme))
        .background(WindowTransparencyConfigurator())
        .onAppear {
            presentation = MenuBarPresentationState(
                traffic: processNetworkModel.displayState
            )
            model.setActive(true, for: .menuBar)
            processNetworkModel.setActive(true, for: .menuBar)
        }
        .onDisappear {
            model.setActive(false, for: .menuBar)
            processNetworkModel.setActive(false, for: .menuBar)
        }
        .onReceive(processNetworkModel.$displayState) { traffic in
            presentation = MenuBarPresentationState(
                traffic: traffic
            )
        }
    }

    private var snapshot: ResourceSnapshot { model.snapshot }
    private var menuTraffic: ProcessTrafficDisplayState { presentation.traffic }

    private func openDashboard(section: DashboardSection? = nil) {
        if let section {
            selectedSection = section
        }
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "dashboard")
        NSApp.activate(ignoringOtherApps: true)
    }

    private var menuHeader: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5.5, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text("Mac 资源监控")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(
                    model.isRefreshingExpandedMetrics
                        ? "传感器更新中…"
                        : "更新于 \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))"
                )
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(InterfacePalette.textTertiary)
            }

            Spacer()

            StatusBadge(
                text: snapshot.networkInterface,
                tint: InterfacePalette.signal,
                showDot: true
            )

            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(InterfacePalette.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(
                        InterfacePalette.subtleSurface,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(InterfacePalette.cardStroke, lineWidth: 0.6)
                    )
            }
            .buttonStyle(.plain)
            .help("立即刷新遥测数据")
            .accessibilityLabel("刷新")
        }
    }

    private var heroVitalsGrid: some View {
        let cpuTint = InterfacePalette.loadTint(for: snapshot.cpuPercent, base: InterfacePalette.cpuSeries)
        let memTint = InterfacePalette.loadTint(for: snapshot.memoryPercent, base: InterfacePalette.memorySeries)
        let tempTint = InterfacePalette.temperatureTint(for: snapshot.cpuTemperature)

        return HStack(spacing: 10) {
            menuVitalCard(
                title: "CPU",
                value: "\(Int(snapshot.cpuPercent.rounded()))%",
                detail: formatTemperature(snapshot.cpuTemperature),
                detailTint: tempTint,
                symbol: "cpu",
                tint: cpuTint,
                progress: snapshot.cpuPercent,
                history: model.cpuHistory
            )

            menuVitalCard(
                title: "内存",
                value: "\(Int(snapshot.memoryPercent.rounded()))%",
                detail: formatBytes(snapshot.memoryUsed),
                detailTint: InterfacePalette.textSecondary,
                symbol: "memorychip",
                tint: memTint,
                progress: snapshot.memoryPercent,
                history: model.memoryHistory
            )
        }
    }

    private func menuVitalCard(
        title: String,
        value: String,
        detail: String,
        detailTint: Color,
        symbol: String,
        tint: Color,
        progress: Double,
        history: [Double]
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            RadialGaugeRing(
                progress: progress,
                tint: tint,
                valueText: value,
                size: 48,
                lineWidth: 4.5
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                Text(detail)
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(detailTint)
                    .lineLimit(1)

                TelemetrySparkline(values: history, tint: tint)
                    .frame(height: 18)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .stableMenuCard(cornerRadius: 10)
        .accessibilityElement(children: .combine)
    }

    private var networkThroughputCard: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                IconBadge(symbol: "arrow.down", tint: InterfacePalette.download, size: 22, iconSize: 10.5, cornerRadius: 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text("实时下行")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(InterfacePalette.textTertiary)
                    Text(formatRate(snapshot.downloadBytesPerSecond))
                        .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)

            Rectangle()
                .fill(InterfacePalette.separator)
                .frame(width: 1, height: 26)

            HStack(spacing: 8) {
                IconBadge(symbol: "arrow.up", tint: InterfacePalette.upload, size: 22, iconSize: 10.5, cornerRadius: 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text("实时上行")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(InterfacePalette.textTertiary)
                    Text(formatRate(snapshot.uploadBytesPerSecond))
                        .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
        }
        .padding(.vertical, 9)
        .stableMenuCard(cornerRadius: 10)
    }

    private var topTrafficRows: [ProcessTrafficRow] {
        Array(
            menuTraffic.rows
                .filter { $0.currentBytesPerSecond > 0 }
                .sorted { $0.currentBytesPerSecond > $1.currentBytesPerSecond }
                .prefix(3)
        )
    }

    private var processTrafficCard: some View {
        let peakRate = max(1, topTrafficRows.first?.currentBytesPerSecond ?? 1)

        return VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text("活跃进程流量")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                HStack(spacing: 8) {
                    Text("↓ \(formatMenuBarRate(menuTraffic.downloadBytesPerSecond))")
                        .foregroundStyle(InterfacePalette.download)
                    Text("↑ \(formatMenuBarRate(menuTraffic.uploadBytesPerSecond))")
                        .foregroundStyle(InterfacePalette.upload)
                }
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            }

            if let error = menuTraffic.errorText {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(InterfacePalette.upload)
                    Text(error)
                        .font(InterfaceTypography.microMetadata)
                        .foregroundStyle(InterfacePalette.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 22)
            } else if topTrafficRows.isEmpty {
                HStack(spacing: 6) {
                    if menuTraffic.lastUpdatedAt == nil {
                        ProgressView().controlSize(.mini)
                        Text("正在采样进程流量…")
                            .font(InterfaceTypography.microMetadata)
                            .foregroundStyle(InterfacePalette.textTertiary)
                    } else {
                        Text("当前无活跃进程网络活动")
                            .font(InterfaceTypography.microMetadata)
                            .foregroundStyle(InterfacePalette.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 22)
            } else {
                VStack(spacing: 6) {
                    ForEach(topTrafficRows) { row in
                        menuTrafficRow(row, peakRate: peakRate)
                    }
                }
            }
        }
        .padding(11)
        .stableMenuCard(cornerRadius: 10)
    }

    private func menuTrafficRow(_ row: ProcessTrafficRow, peakRate: Double) -> some View {
        let ratio = min(1, max(0, row.currentBytesPerSecond / peakRate))

        return HStack(spacing: 8) {
            menuTrafficIcon(row: row)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(InterfacePalette.subtleSurface)
                        Capsule()
                            .fill(InterfacePalette.accent.opacity(0.75))
                            .frame(width: max(3, proxy.size.width * ratio))
                    }
                }
                .frame(height: 2.5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("↓\(formatMenuBarRate(row.downloadBytesPerSecond))")
                .foregroundStyle(row.downloadBytesPerSecond >= 1 ? InterfacePalette.download : InterfacePalette.textTertiary)
                .frame(width: 58, alignment: .trailing)

            Text("↑\(formatMenuBarRate(row.uploadBytesPerSecond))")
                .foregroundStyle(row.uploadBytesPerSecond >= 1 ? InterfacePalette.upload : InterfacePalette.textTertiary)
                .frame(width: 58, alignment: .trailing)
        }
        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
        .monospacedDigit()
    }

    @ViewBuilder
    private func menuTrafficIcon(row: ProcessTrafficRow) -> some View {
        if let icon = ProcessIconCache.icon(for: row) {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        } else {
            RoundedRectangle(
                cornerRadius: 4.5,
                style: .continuous
            )
            .fill(InterfacePalette.iconSurface)
            .overlay {
                Text(String(row.name.prefix(1)).uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(InterfacePalette.textSecondary)
            }
            .frame(width: 18, height: 18)
        }
    }

    private var hardwareSummaryCard: some View {
        HStack(spacing: 0) {
            menuHardwareMetric(
                title: "风扇",
                value: model.isRefreshingExpandedMetrics
                    ? "--"
                    : compactFanSpeed(snapshot.fanSpeed),
                detail: snapshot.fanCount > 0 ? "\(snapshot.fanCount) 个风扇" : "静音运行",
                symbol: "fan",
                tint: InterfacePalette.fan
            )
            hardwareDivider
            menuHardwareMetric(
                title: "供电",
                value: model.isRefreshingExpandedMetrics
                    ? "--"
                    : formatBatteryChargePower(snapshot.chargingPower),
                detail: model.isRefreshingExpandedMetrics
                    ? "读取中"
                    : snapshot.powerSource,
                symbol: "bolt.fill",
                tint: InterfacePalette.power
            )
            hardwareDivider
            menuHardwareMetric(
                title: "接口",
                value: model.isRefreshingCable
                    ? "--"
                    : "\(snapshot.cableMonitor.activePorts.count) 个已连",
                detail: portStatusDetail,
                symbol: "cable.connector",
                tint: InterfacePalette.storage
            )
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 4)
        .stableMenuCard(cornerRadius: 10)
    }

    private func menuHardwareMetric(
        title: String,
        value: String,
        detail: String,
        symbol: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(InterfacePalette.textTertiary)
            }
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(InterfacePalette.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }

    private var hardwareDivider: some View {
        Rectangle()
            .fill(InterfacePalette.separator)
            .frame(width: 1, height: 36)
    }

    private var menuFooter: some View {
        HStack(spacing: 8) {
            ActionPillButton(
                title: "打开主窗口",
                symbol: "macwindow",
                isPrimary: true
            ) {
                openDashboard()
            }

            Button {
                openDashboard(section: .settings)
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(InterfacePalette.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(
                        InterfacePalette.subtleSurface,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(InterfacePalette.cardStroke, lineWidth: 0.7)
                    )
            }
            .buttonStyle(.plain)
            .help("打开偏好设置")
            .accessibilityLabel("偏好设置")

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "power")
                        .font(.system(size: 11, weight: .medium))
                    Text("退出")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(InterfacePalette.textSecondary)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("退出 Mac 资源监控")
        }
    }

    private var portStatusDetail: String {
        if model.isRefreshingCable { return "检测中" }
        if snapshot.cableMonitor.errorText != nil { return "需刷新" }
        return snapshot.cableMonitor.activePorts.first?.displayName ?? "未连接"
    }
}

private final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    private var windowCloseObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow,
                  isDashboardWindow(window) else { return }
            DispatchQueue.main.async {
                let dashboardStillVisible = NSApp.windows.contains {
                    isDashboardWindow($0) && $0.isVisible
                }
                if !dashboardStillVisible {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    deinit {
        if let windowCloseObserver {
            NotificationCenter.default.removeObserver(windowCloseObserver)
        }
    }
}

private func isDashboardWindow(_ window: NSWindow) -> Bool {
    if window.identifier?.rawValue == "dashboard" { return true }
    return window.level == .normal && window.styleMask.contains(.closable) && window.canBecomeMain
}

@MainActor
private let memoryByteCountFormatter: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .memory
    formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
    formatter.includesUnit = true
    formatter.isAdaptive = true
    return formatter
}()

@MainActor
private func formatBytes(_ bytes: UInt64) -> String {
    memoryByteCountFormatter.string(fromByteCount: Int64(min(bytes, UInt64(Int64.max))))
}

@MainActor
private func formatRate(_ bytesPerSecond: Double) -> String {
    let value = UInt64(max(0, bytesPerSecond))
    return "\(formatBytes(value))/s"
}

private func formatTemperature(_ value: Double?) -> String {
    guard let value else { return "不可用" }
    return String(format: "%.1f°C", value)
}

private func formatFanSpeed(_ value: Double?) -> String {
    guard let value else { return "不可用" }
    return "\(Int(value.rounded())) RPM"
}

private func formatBatteryChargePower(_ power: ChargingPowerSnapshot) -> String {
    guard power.externalConnected else { return "未接电源" }
    guard power.isCharging else { return "未充电" }
    guard let watts = power.batteryChargeWatts else { return "检测中" }
    return String(format: "%.1f W", watts)
}

private func formatUptime(_ interval: TimeInterval) -> String {
    let totalMinutes = Int(interval) / 60
    let days = totalMinutes / 1440
    let hours = (totalMinutes % 1440) / 60
    let minutes = totalMinutes % 60
    if days > 0 { return "\(days)天 \(hours)小时" }
    if hours > 0 { return "\(hours)小时 \(minutes)分" }
    return "\(minutes)分钟"
}

@main
private struct MacResourceMonitorApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var applicationDelegate
    @StateObject private var model = MonitorModel()
    @StateObject private var processNetworkModel = ProcessNetworkMonitor()
    @StateObject private var localPortsModel = LocalPortsMonitor()
    @StateObject private var networkDiagnosticsModel = NetworkDiagnosticsMonitor()
    @StateObject private var peripheralsModel = PeripheralsMonitor()
    @StateObject private var preferences = AppPreferences()
    @State private var selectedSection: DashboardSection = .monitor

    var body: some Scene {
        Window("Mac 资源监控", id: "dashboard") {
            DashboardView(
                model: model,
                processNetworkModel: processNetworkModel,
                localPortsModel: localPortsModel,
                networkDiagnosticsModel: networkDiagnosticsModel,
                peripheralsModel: peripheralsModel,
                preferences: preferences,
                selectedSection: $selectedSection
            )
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        MenuBarExtra {
            MenuBarPanel(
                model: model,
                processNetworkModel: processNetworkModel,
                selectedSection: $selectedSection
            )
        } label: {
            MenuBarStatusLabel(model: model, preferences: preferences)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarStatusLabel: View {
    @ObservedObject var model: MonitorModel
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        let summary = menuBarSummary(model.snapshot, preferences: preferences)
        Text(summary)
            .monospacedDigit()
            .accessibilityLabel("Mac 资源监控 \(summary)")
            .onChange(of: model.snapshot.updatedAt) { _, _ in
                preferences.evaluateAlerts(
                    cpuPercent: model.snapshot.cpuPercent,
                    cpuTemperature: model.snapshot.cpuTemperature
                )
            }
    }
}

@MainActor
private func menuBarSummary(_ snapshot: ResourceSnapshot, preferences: AppPreferences) -> String {
    var parts: [String] = []
    if preferences.showMenuBarTemperature {
        let temperature = snapshot.cpuTemperature.map { "\(Int($0.rounded()))°" } ?? "--°"
        parts.append(temperature)
    }
    if preferences.showMenuBarCPU {
        parts.append("CPU \(Int(snapshot.cpuPercent.rounded()))%")
    }
    if preferences.showMenuBarMemory {
        parts.append("MEM \(Int(snapshot.memoryPercent.rounded()))%")
    }
    if preferences.showMenuBarNetwork {
        parts.append("↓\(formatMenuBarRate(snapshot.downloadBytesPerSecond)) ↑\(formatMenuBarRate(snapshot.uploadBytesPerSecond))")
    }
    if preferences.showMenuBarPower {
        let watts = snapshot.chargingPower.systemLoadWatts.map { String(format: "%.0fW", $0) } ?? "--W"
        parts.append(watts)
    }
    return parts.isEmpty ? "Mac 监控" : parts.joined(separator: "  ")
}

private func formatMenuBarRate(_ bytesPerSecond: Double) -> String {
    let value = max(0, bytesPerSecond)
    if value >= 1_000_000_000 { return String(format: "%.1fG", value / 1_000_000_000) }
    if value >= 10_000_000 { return String(format: "%.0fM", value / 1_000_000) }
    if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
    if value >= 10_000 { return String(format: "%.0fK", value / 1_000) }
    if value >= 1_000 { return String(format: "%.1fK", value / 1_000) }
    return "\(Int(value.rounded()))B"
}

private func compactFanSpeed(_ value: Double?) -> String {
    guard let value else { return "--" }
    return "\(Int(value.rounded())) RPM"
}
