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
}

private enum ResourceMonitorConsumer: Hashable {
    case expandedMetrics
    case menuBar
    case processTable
    case cable
}

private final class SystemCollector {
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

    func collect(
        options: ResourceCollectionOptions,
        forceCableRefresh: Bool = false,
        forceExpandedMetricsRefresh: Bool = false
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
            snapshot.chargingPower = chargingPowerReader.read()
        } else {
            batterySampleCounter = 0
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
        let availablePages = UInt64(stats.free_count) + UInt64(stats.inactive_count)
        let available = min(total, availablePages * pageSize)
        return (total - available, total)
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

private final class MonitorModel: ObservableObject {
    private(set) var snapshot = ResourceSnapshot()
    private(set) var cpuHistory = Array(repeating: 0.0, count: 60)
    private(set) var memoryHistory = Array(repeating: 0.0, count: 60)
    @Published var isRefreshingCable = false
    @Published var isRefreshingExpandedMetrics = false

    private let collector = SystemCollector()
    private let queue = DispatchQueue(label: "local.mac-resource-monitor.collector", qos: .utility)
    private var timer: Timer?
    private var refreshInProgress = false
    private var refreshPending = false
    private var forceCableRefreshPending = false
    private var expandedMetricsRefreshGeneration: UInt64 = 0
    private var activeConsumers: Set<ResourceMonitorConsumer> = []

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit { timer?.invalidate() }

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
        refresh(forceCableRefresh: needsCableRefresh)
    }

    func refresh(forceCableRefresh: Bool = false) {
        if forceCableRefresh {
            forceCableRefreshPending = true
            isRefreshingCable = true
        }
        guard !refreshInProgress else {
            refreshPending = true
            return
        }
        let shouldForceCableRefresh = forceCableRefreshPending
        let shouldForceExpandedMetricsRefresh = isRefreshingExpandedMetrics
        let options = collectionOptions
        let expandedMetricsGeneration = expandedMetricsRefreshGeneration
        forceCableRefreshPending = false
        refreshPending = false
        refreshInProgress = true
        queue.async { [weak self] in
            guard let self else { return }
            let next = self.collector.collect(
                options: options,
                forceCableRefresh: shouldForceCableRefresh,
                forceExpandedMetricsRefresh: shouldForceExpandedMetricsRefresh
            )
            DispatchQueue.main.async {
                let nextCPUHistory = Array(self.cpuHistory.suffix(59)) + [next.cpuPercent]
                let nextMemoryHistory = Array(self.memoryHistory.suffix(59)) + [next.memoryPercent]
                self.objectWillChange.send()
                withTransaction(Transaction(animation: nil)) {
                    self.snapshot = next
                    self.cpuHistory = nextCPUHistory
                    self.memoryHistory = nextMemoryHistory
                    self.refreshInProgress = false
                    if options.includeExpandedMetrics,
                       expandedMetricsGeneration == self.expandedMetricsRefreshGeneration {
                        self.isRefreshingExpandedMetrics = false
                    }
                    if shouldForceCableRefresh {
                        self.isRefreshingCable = self.forceCableRefreshPending
                    }
                }
                if self.refreshPending || self.forceCableRefreshPending {
                    self.refresh()
                }
            }
        }
    }

    func refreshCableMonitor() {
        refresh(forceCableRefresh: true)
    }

    private var collectionOptions: ResourceCollectionOptions {
        ResourceCollectionOptions(
            includeExpandedMetrics: activeConsumers.contains(.expandedMetrics)
                || activeConsumers.contains(.menuBar),
            includeTopProcesses: activeConsumers.contains(.processTable),
            includeCable: activeConsumers.contains(.cable)
                || activeConsumers.contains(.menuBar)
        )
    }
}

private struct TelemetryPulseStrip: View {
    let snapshot: ResourceSnapshot
    let isLoadingExpandedMetrics: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(InterfacePalette.accent)
                    .frame(width: 6, height: 6)
                Text("系统实时概览")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(
                    isLoadingExpandedMetrics
                        ? "正在更新硬件传感器"
                        : "每 2 秒采样"
                )
                .font(InterfaceTypography.microMetadata)
                .foregroundStyle(.tertiary)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "network")
                        .font(.system(size: 11))
                    Text(snapshot.networkInterface)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                TelemetryStripMetric(
                    title: "CPU 负载",
                    value: String(format: "%.0f%%", snapshot.cpuPercent),
                    detail: "处理器占用",
                    progress: snapshot.cpuPercent
                )
                stripDivider
                TelemetryStripMetric(
                    title: "物理内存",
                    value: String(format: "%.0f%%", snapshot.memoryPercent),
                    detail: formatBytes(snapshot.memoryUsed),
                    progress: snapshot.memoryPercent
                )
                stripDivider
                TelemetryStripMetric(
                    title: "核心温度",
                    value: formatTemperature(snapshot.cpuTemperature),
                    detail: snapshot.hottestCPUTemperature.map {
                        String(format: "峰值 %.1f°C", $0)
                    } ?? "传感器就绪",
                    progress: nil
                )
                stripDivider
                TelemetryStripMetric(
                    title: "网络下行",
                    value: formatRate(snapshot.downloadBytesPerSecond),
                    detail: "实时接收",
                    progress: nil
                )
                stripDivider
                TelemetryStripMetric(
                    title: "网络上行",
                    value: formatRate(snapshot.uploadBytesPerSecond),
                    detail: "实时发送",
                    progress: nil
                )
            }
        }
        .padding(18)
        .stableDashboardCard(cornerRadius: InterfaceMetrics.cardRadius)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("系统实时遥测")
    }

    private var stripDivider: some View {
        Rectangle()
            .fill(InterfacePalette.separator)
            .frame(width: 1, height: 54)
            .padding(.horizontal, 4)
    }
}

private struct TelemetryStripMetric: View {
    let title: String
    let value: String
    let detail: String
    let progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let progress {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.06))
                        Capsule()
                            .fill(InterfacePalette.accent.opacity(0.78))
                            .frame(
                                width: geometry.size.width
                                    * min(1, max(0, progress / 100))
                            )
                    }
                }
                .frame(height: 3)
            } else {
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 3)
            }
            Text(detail)
                .font(InterfaceTypography.microMetadata)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
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
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("负载走势")
                        .font(.system(size: 14, weight: .semibold))
                    Text("最近约 2 分钟 · 同一百分比刻度")
                        .font(InterfaceTypography.microMetadata)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                chartLegend("CPU", value: cpuValue, color: InterfacePalette.cpuSeries)
                chartLegend("内存", value: memoryValue, color: InterfacePalette.memorySeries)
            }

            GeometryReader { geometry in
                let size = geometry.size
                ZStack(alignment: .topLeading) {
                    chartGrid(in: size)

                    areaPath(values: cpuValues, in: size)
                        .fill(
                            LinearGradient(
                                colors: [
                                    InterfacePalette.cpuSeries.opacity(0.09),
                                    InterfacePalette.cpuSeries.opacity(0.01)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    linePath(values: cpuValues, in: size)
                        .stroke(
                            InterfacePalette.cpuSeries,
                            style: StrokeStyle(
                                lineWidth: 1.8,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                    linePath(values: memoryValues, in: size)
                        .stroke(
                            InterfacePalette.memorySeries,
                            style: StrokeStyle(
                                lineWidth: 1.5,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )

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
            .frame(height: 170)
            .clipped()

            HStack {
                Text("2 分钟前")
                Spacer()
                Text("悬停查看时间点详情")
                Spacer()
                Text("现在")
            }
            .font(InterfaceTypography.microMetadata)
            .foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 268, alignment: .topLeading)
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

    private func chartLegend(_ title: String, value: Double, color: Color) -> some View {
        HStack(spacing: 6) {
            Capsule()
                .fill(color)
                .frame(width: 12, height: 3)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text("\(Int(value.rounded()))%")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
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
                .stroke(InterfacePalette.chartGrid, lineWidth: 1)
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

        Path { path in
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
        }
        .stroke(InterfacePalette.crosshair, lineWidth: 1)

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
            Text("CPU  \(Int(cpu.rounded()))%")
            Text("内存  \(Int(memory.rounded()))%")
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            .regularMaterial,
            in: RoundedRectangle(
                cornerRadius: InterfaceMetrics.controlRadius,
                style: .continuous
            )
        )
        .position(
            x: min(max(58, x), max(58, size.width - 58)),
            y: 27
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
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("硬件与电源")
                    .font(.system(size: 14, weight: .semibold))
                Text(isLoadingExpandedMetrics ? "正在读取传感器" : "传感器状态")
                    .font(InterfaceTypography.microMetadata)
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 13)

            hardwareRow(
                "内置磁盘",
                isLoadingExpandedMetrics
                    ? "--"
                    : "\(Int(snapshot.diskPercent.rounded()))% 已用",
                symbol: "internaldrive",
                progress: isLoadingExpandedMetrics ? nil : snapshot.diskPercent
            )
            rowDivider
            hardwareRow(
                "散热风扇",
                isLoadingExpandedMetrics ? "--" : formatFanSpeed(snapshot.fanSpeed),
                symbol: "fan"
            )
            rowDivider
            hardwareRow(
                "电池电量",
                isLoadingExpandedMetrics ? "检测中" : snapshot.batteryText,
                symbol: "battery.75percent"
            )
            rowDivider
            hardwareRow(
                "充电功率",
                isLoadingExpandedMetrics
                    ? "--"
                    : formatBatteryChargePower(snapshot.chargingPower),
                symbol: "bolt"
            )
            rowDivider
            hardwareRow(
                "系统温控",
                isLoadingExpandedMetrics ? "检测中" : snapshot.thermalState,
                symbol: "thermometer.medium"
            )
        }
        .padding(18)
        .frame(width: 320, alignment: .topLeading)
        .frame(minHeight: 268, alignment: .topLeading)
        .stableDashboardCard(cornerRadius: InterfaceMetrics.cardRadius)
    }

    private func hardwareRow(
        _ label: String,
        _ value: String,
        symbol: String,
        progress: Double? = nil
    ) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 17)
                Text(label)
                    .font(InterfaceTypography.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            if let progress {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.06))
                        Capsule()
                            .fill(InterfacePalette.accent.opacity(0.75))
                            .frame(
                                width: geometry.size.width
                                    * min(1, max(0, progress / 100))
                            )
                    }
                }
                .frame(height: 3)
                .padding(.leading, 26)
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
        VStack(alignment: .leading, spacing: 10) {
            Text("高负载进程")
                .font(.system(size: 14, weight: .semibold))
            HStack {
                Text("进程").frame(maxWidth: .infinity, alignment: .leading)
                Text("PID").frame(width: 64, alignment: .trailing)
                Text("CPU").frame(width: 64, alignment: .trailing)
                Text("内存").frame(width: 78, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.tertiary)

            if rows.isEmpty {
                Spacer()
                Text("正在读取进程…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(rows) { row in
                    HStack(spacing: 8) {
                        Text(row.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(row.id)")
                            .foregroundStyle(.tertiary)
                            .frame(width: 64, alignment: .trailing)
                        Text(String(format: "%.1f%%", row.cpu))
                            .fontWeight(.medium)
                            .frame(width: 64, alignment: .trailing)
                        Text(formatBytes(row.memoryBytes))
                            .foregroundStyle(.secondary)
                            .frame(width: 78, alignment: .trailing)
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .monospacedDigit()
                    if row.id != rows.last?.id { Divider().opacity(0.35) }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 225, alignment: .topLeading)
        .stableDashboardCard()
    }
}

private struct SystemDetails: View {
    let snapshot: ResourceSnapshot
    let isLoadingExpandedMetrics: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("系统环境").font(.system(size: 14, weight: .semibold))
            detail("网络接口", snapshot.networkInterface, "network")
            Divider().opacity(0.35)
            detail("供电方式", isLoadingExpandedMetrics ? "检测中" : snapshot.powerSource, "bolt")
            Divider().opacity(0.35)
            detail("电池状态", isLoadingExpandedMetrics ? "检测中" : snapshot.batteryText, "battery.75percent")
            Divider().opacity(0.35)
            detail("温控状态", isLoadingExpandedMetrics ? "检测中" : snapshot.thermalState, "thermometer.medium")
            Divider().opacity(0.35)
            detail("持续运行", isLoadingExpandedMetrics ? "检测中" : formatUptime(snapshot.uptime), "clock")
            Divider().opacity(0.35)
            detail("主机名称", Host.current().localizedName ?? "Mac", "desktopcomputer")
        }
        .padding(18)
        .frame(width: 320, alignment: .topLeading)
        .frame(minHeight: 225, alignment: .topLeading)
        .stableDashboardCard()
    }

    private func detail(_ label: String, _ value: String, _ symbol: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .frame(width: 16)
                .foregroundStyle(.secondary)
            Text(label)
                .font(InterfaceTypography.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .allowsTightening(true)
        }
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
            HStack(alignment: .firstTextBaseline) {
                Text("USB-C / 雷雳端口状态")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if isRefreshing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("正在检测")
                            .font(InterfaceTypography.microMetadata)
                            .foregroundStyle(.secondary)
                    }
                } else if let errorText = monitor.errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle")
                        .font(InterfaceTypography.microMetadata)
                        .foregroundStyle(.orange)
                } else {
                    Text("共 \(monitor.ports.count) 个端口 · \(monitor.activePorts.count) 个已连接")
                        .font(InterfaceTypography.microMetadata)
                        .foregroundStyle(.secondary)
                }
            }

            if isRefreshing {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("正在检测 USB-C 与线缆状态")
                            .font(.system(size: 13, weight: .medium))
                        Text("检测完成后会更新端口连接与供电速率")
                            .font(InterfaceTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(16)
                .stableDashboardCard()
            } else if monitor.ports.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "cable.connector.slash")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(monitor.errorText ?? "未发现可读取的 USB-C 端口")
                            .font(.system(size: 13, weight: .medium))
                        Text("需要 Apple Silicon 芯片与 macOS 14 及以上系统")
                            .font(InterfaceTypography.caption)
                            .foregroundStyle(.secondary)
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
                .foregroundStyle(.tertiary)
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
        if port.activeTransports.contains("Thunderbolt/USB4") { return "bolt.horizontal" }
        if port.activeTransports.contains("DisplayPort") { return "display" }
        return "cable.connector"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(port.connected ? .primary : .secondary)
                    .frame(width: 30, height: 30)
                    .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(port.displayName)
                        .font(.system(size: 13, weight: .semibold))
                    Text(port.stateTitle)
                        .font(InterfaceTypography.microMetadata)
                        .foregroundStyle(port.connected ? .primary : .tertiary)
                }
                Spacer()
                Circle()
                    .fill(port.connected ? InterfacePalette.accent : Color.primary.opacity(0.18))
                    .frame(width: 6, height: 6)
            }

            Text(port.stateDetail)
                .font(InterfaceTypography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if port.connected {
                Divider().opacity(0.35)
                VStack(spacing: 7) {
                    if let value = port.negotiatedPower {
                        cableDetail("协商上限", value, "bolt")
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
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                            Text(value)
                                .font(InterfaceTypography.microMetadata)
                                .foregroundStyle(.orange)
                            Spacer()
                        }
                        .padding(.top, 2)
                    }
                    if !port.hasCableIdentity {
                        Text("macOS 未读取到线缆 E-Marker 芯片信息。")
                            .font(InterfaceTypography.microMetadata)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                Text(port.supportedTransports.isEmpty
                     ? (port.type.localizedCaseInsensitiveContains("MagSafe") ? "磁吸充电接口" : "等待设备接入")
                     : "支持：\(port.supportedTransports.joined(separator: " · "))")
                    .font(InterfaceTypography.microMetadata)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: port.connected ? 170 : 124, alignment: .topLeading)
        .stableDashboardCard()
    }

    private func cableDetail(_ label: String, _ value: String, _ symbol: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .frame(width: 14)
                .foregroundStyle(.secondary)
            Text(label)
                .font(InterfaceTypography.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

private enum DashboardSection: String, CaseIterable, Identifiable {
    case monitor = "系统监控"
    case traffic = "进程流量"
    case aiUsage = "AI 用量"
    case ports = "接口监测"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .monitor: return "gauge.with.dots.needle.50percent"
        case .traffic: return "point.3.connected.trianglepath.dotted"
        case .aiUsage: return "terminal"
        case .ports: return "cable.connector"
        }
    }

    var tint: Color {
        InterfacePalette.accent
    }

    var subtitle: String {
        switch self {
        case .monitor: return "性能与硬件状态"
        case .traffic: return "实时进程上下行"
        case .aiUsage: return "Codex 与 Antigravity 额度"
        case .ports: return "USB-C、雷雳与供电"
        }
    }

    var eyebrow: String {
        switch self {
        case .monitor: return "SYSTEM / LIVE"
        case .traffic: return "NETWORK / PROCESS"
        case .aiUsage: return "AI / QUOTA"
        case .ports: return "PORTS / POWER"
        }
    }
}

enum InterfaceMetrics {
    static let shellRadius: CGFloat = 14
    static let panelRadius: CGFloat = 12
    static let cardRadius: CGFloat = 11
    static let controlRadius: CGFloat = 8
    static let compactRadius: CGFloat = 5
    static let shellInset: CGFloat = 12
    static let sidebarWidth: CGFloat = 196
}

enum InterfaceTypography {
    static let microMetadata = Font.system(size: 11, weight: .regular)
    static let microEmphasized = Font.system(size: 11, weight: .medium)
    static let caption = Font.system(size: 12)
    static let captionMedium = Font.system(size: 12, weight: .medium)
    static let captionEmphasized = Font.system(size: 12, weight: .semibold)
    static let body = Font.system(size: 13)
    static let bodyEmphasized = Font.system(size: 13, weight: .semibold)
    static let compactValue = Font.system(size: 12, weight: .semibold, design: .monospaced)
}

enum InterfacePalette {
    // Modern minimalist macOS palette: monochromatic surfaces & typography
    // with a single calm system blue accent.
    static let accent = Color(red: 0.039, green: 0.518, blue: 1.000)
    static let signal = Color(red: 0.039, green: 0.518, blue: 1.000)
    static let cpuSeries = Color(red: 0.039, green: 0.518, blue: 1.000)
    static let memorySeries = Color.primary.opacity(0.40)
    static let temperature = Color(red: 0.92, green: 0.34, blue: 0.28)
    static let download = Color.primary.opacity(0.82)
    static let upload = Color.secondary
    static let storage = Color.secondary
    static let fan = Color.secondary
    static let battery = Color.secondary
    static let power = Color.secondary

    static let iconSurface = Color.primary.opacity(0.055)
    static let cardStroke = Color.primary.opacity(0.075)
    static let separator = Color.primary.opacity(0.070)
    static let chartGrid = Color.primary.opacity(0.055)
    static let crosshair = Color.primary.opacity(0.24)

    static func canvas(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.075, green: 0.078, blue: 0.086)
            : Color(red: 0.955, green: 0.958, blue: 0.966)
    }

    static func sidebarSurface(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.098, green: 0.102, blue: 0.112)
            : Color(red: 0.978, green: 0.980, blue: 0.986)
    }

    static func glassSurface(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.042)
            : Color.white.opacity(0.75)
    }

    static func stableSurface(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.042)
            : Color.white.opacity(0.80)
    }

    static func stableDashboardSurface(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.045)
            : Color.white.opacity(0.88)
    }

    static func menuSurface(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.095, green: 0.098, blue: 0.108)
            : Color(red: 0.972, green: 0.975, blue: 0.982)
    }
}

struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(InterfacePalette.glassSurface(for: colorScheme), in: shape)
            .overlay(shape.stroke(InterfacePalette.cardStroke, lineWidth: 0.6))
            .clipShape(shape)
    }
}

struct LiquidGlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    let isDense: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(
                isDense
                    ? InterfacePalette.sidebarSurface(for: colorScheme)
                    : InterfacePalette.stableDashboardSurface(for: colorScheme),
                in: shape
            )
            .overlay(
                shape.stroke(
                    InterfacePalette.cardStroke,
                    lineWidth: 0.6
                )
            )
            .clipShape(shape)
    }
}

struct StableListCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(
                InterfacePalette.stableSurface(for: colorScheme),
                in: shape
            )
            .overlay(shape.stroke(InterfacePalette.cardStroke, lineWidth: 0.6))
            .clipShape(shape)
    }
}

struct StableDashboardCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(InterfacePalette.stableDashboardSurface(for: colorScheme), in: shape)
            .overlay(shape.stroke(InterfacePalette.cardStroke, lineWidth: 0.6))
            .clipShape(shape)
    }
}

struct StableMenuCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(
                Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.035),
                in: shape
            )
            .overlay(shape.stroke(InterfacePalette.cardStroke, lineWidth: 0.6))
            .clipShape(shape)
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

extension View {
    func glassCard(cornerRadius: CGFloat = InterfaceMetrics.cardRadius) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }

    func liquidGlassPanel(
        cornerRadius: CGFloat = InterfaceMetrics.panelRadius,
        isDense: Bool = false
    ) -> some View {
        modifier(
            LiquidGlassPanelModifier(
                cornerRadius: cornerRadius,
                isDense: isDense
            )
        )
    }

    func stableListCard(
        cornerRadius: CGFloat = InterfaceMetrics.cardRadius
    ) -> some View {
        modifier(StableListCardModifier(cornerRadius: cornerRadius))
    }

    func stableDashboardCard(
        cornerRadius: CGFloat = InterfaceMetrics.cardRadius
    ) -> some View {
        modifier(StableDashboardCardModifier(cornerRadius: cornerRadius))
    }

    func stableMenuCard(
        cornerRadius: CGFloat = InterfaceMetrics.cardRadius
    ) -> some View {
        modifier(StableMenuCardModifier(cornerRadius: cornerRadius))
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
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? InterfacePalette.accent : Color.secondary)
                    .frame(width: 20)

                Text(section.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.82))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(
                    cornerRadius: 8,
                    style: .continuous
                )
                .fill(
                    isSelected
                        ? Color.primary.opacity(colorScheme == .dark ? 0.11 : 0.075)
                        : Color.primary.opacity(isHovering ? 0.04 : 0)
                )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct DashboardView: View {
    @ObservedObject var model: MonitorModel
    @ObservedObject var processNetworkModel: ProcessNetworkMonitor
    @ObservedObject var codexQuotaModel: CodexQuotaMonitor
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Binding var selectedSection: DashboardSection

    var body: some View {
        ZStack {
            InterfacePalette.canvas(for: colorScheme)
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
                    .padding(.bottom, 24)
                }
                .scrollClipDisabled(false)
                .scrollEdgeEffectStyle(.soft, for: .bottom)
                .id(selectedSection.id)
            }
        }
        .frame(minWidth: 1040, idealWidth: 1160, minHeight: 700, idealHeight: 820)
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
                .cable: false
            ])
        }
    }

    private func updateResourceConsumers() {
        model.updateActiveConsumers([
            .expandedMetrics: selectedSection == .monitor || selectedSection == .ports,
            .processTable: selectedSection == .monitor,
            .cable: selectedSection == .ports
        ])
    }

    @ViewBuilder
    private var sectionContent: some View {
        if selectedSection == .monitor {
            VStack(spacing: 14) {
                TelemetryPulseStrip(
                    snapshot: model.snapshot,
                    isLoadingExpandedMetrics: model.isRefreshingExpandedMetrics
                )

                HStack(alignment: .top, spacing: 14) {
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

                HStack(alignment: .top, spacing: 14) {
                    ProcessTable(rows: model.snapshot.processes)
                    SystemDetails(
                        snapshot: model.snapshot,
                        isLoadingExpandedMetrics: model.isRefreshingExpandedMetrics
                    )
                }
            }
        } else if selectedSection == .traffic {
            ProcessTrafficView(model: processNetworkModel)
        } else if selectedSection == .aiUsage {
            CodexQuotaView(model: codexQuotaModel)
        } else {
            PortMonitorView(
                monitor: model.snapshot.cableMonitor,
                chargingPower: model.isRefreshingExpandedMetrics
                    ? ChargingPowerSnapshot()
                    : model.snapshot.chargingPower,
                isRefreshing: model.isRefreshingCable
            )
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                Text("Mac 资源监控")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 8)
            .padding(.top, 34)
            .padding(.bottom, 18)

            VStack(spacing: 3) {
                ForEach(DashboardSection.allCases) { section in
                    sidebarItem(section)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Divider().opacity(0.45)

                HStack(spacing: 6) {
                    Circle()
                        .fill(InterfacePalette.accent)
                        .frame(width: 5, height: 5)
                    Text("CPU \(String(format: "%.0f%%", model.snapshot.cpuPercent))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatTemperature(model.snapshot.cpuTemperature))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
        .frame(width: InterfaceMetrics.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(InterfacePalette.sidebarSurface(for: colorScheme))
    }

    private func sidebarItem(_ section: DashboardSection) -> some View {
        SidebarNavigationItem(section: section, isSelected: selectedSection == section) {
            withAnimation(.easeInOut(duration: 0.16)) {
                selectedSection = section
            }
        }
    }

    private var contentHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(selectedSection.rawValue)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    Text(headerSubtitle)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(heroFootnote)
                        .foregroundStyle(.tertiary)
                }
                .font(InterfaceTypography.microMetadata)
                .lineLimit(1)
            }

            Spacer(minLength: 14)

            if selectedSection == .aiUsage {
                AIProviderSegmentedControl(selectedProvider: $codexQuotaModel.selectedProvider)
            }

            Button(action: performHeroAction) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                    Text(heroActionTitle)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.055))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(InterfacePalette.cardStroke, lineWidth: 0.6)
                )
            }
            .buttonStyle(.plain)
            .disabled(isHeroActionDisabled)
        }
        .padding(.bottom, 4)
    }

    private var heroFootnote: String {
        switch selectedSection {
        case .aiUsage:
            if let date = codexQuotaModel.state.snapshot?.updatedAt {
                let account = codexQuotaModel.state.snapshot?.accountEmail ?? "已连接账号"
                return "\(account) · 更新于 \(date.formatted(date: .omitted, time: .standard))"
            }
            return codexQuotaModel.state.isRefreshing ? "正在同步最新订阅额度…" : "每分钟自动更新"
        case .monitor:
            if model.isRefreshingExpandedMetrics { return "正在更新传感器" }
            let date = model.snapshot.expandedMetricsUpdatedAt ?? model.snapshot.updatedAt
            return "更新于 \(date.formatted(date: .omitted, time: .standard))"
        case .traffic:
            if let date = processNetworkModel.lastUpdatedAt {
                return "采样于 \(date.formatted(date: .omitted, time: .standard))"
            }
            return processNetworkModel.errorText ?? "正在采样"
        case .ports:
            if model.isRefreshingCable { return "正在检测" }
            if let error = model.snapshot.cableMonitor.errorText {
                return error
            }
            if let date = model.snapshot.cableMonitor.updatedAt {
                return "检测于 \(date.formatted(date: .omitted, time: .standard))"
            }
            return "只读检测"
        }
    }

    private var heroActionTitle: String {
        switch selectedSection {
        case .aiUsage: return codexQuotaModel.state.isRefreshing ? "同步中" : "刷新配额"
        case .monitor: return "刷新"
        case .traffic: return "清零累计"
        case .ports: return model.isRefreshingCable ? "检测中" : "重新检测"
        }
    }

    private var isHeroActionDisabled: Bool {
        switch selectedSection {
        case .aiUsage: return codexQuotaModel.state.isRefreshing
        case .monitor: return false
        case .traffic: return false
        case .ports: return model.isRefreshingCable
        }
    }

    private func performHeroAction() {
        switch selectedSection {
        case .aiUsage:
            codexQuotaModel.refresh(force: true)
        case .monitor:
            model.refresh()
        case .traffic:
            processNetworkModel.resetSessionTotals()
        case .ports:
            model.refreshCableMonitor()
        }
    }

    private var headerSubtitle: String {
        switch selectedSection {
        case .monitor: return "处理器、内存、温控与硬件实时状态"
        case .traffic: return "按应用进程实时统计上下行速率与累计流量"
        case .aiUsage:
            return codexQuotaModel.selectedProvider == .antigravity
                ? "Gemini 与 Claude / GPT 模型池订阅配额"
                : "Codex 5 小时会话与 7 天每周订阅额度"
        case .ports: return "USB-C、雷雳接口连接与充电功率协商"
        }
    }
}

private struct MenuBarPresentationState {
    var traffic = ProcessTrafficDisplayState()
}

private struct MenuBarPanel: View {
    @ObservedObject var model: MonitorModel
    let processNetworkModel: ProcessNetworkMonitor
    let codexQuotaModel: CodexQuotaMonitor
    @Binding var selectedSection: DashboardSection
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
    @State private var presentation = MenuBarPresentationState()

    var body: some View {
        VStack(spacing: 10) {
            menuHeader
                .padding(.horizontal, 4)

            primaryVitalsCard

            processTrafficCard

            hardwareSummaryCard

            CodexQuotaMenuSummary(model: codexQuotaModel) {
                selectedSection = .aiUsage
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "dashboard")
            }
            .padding(11)
            .stableMenuCard(cornerRadius: 10)

            menuFooter
                .padding(.horizontal, 2)
                .padding(.top, 2)
        }
        .padding(12)
        .frame(width: 344)
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

    private var menuHeader: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)

            Text("Mac 资源监控")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            HStack(spacing: 5) {
                Text(snapshot.networkInterface)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06), in: Capsule())

                Text(
                    model.isRefreshingExpandedMetrics
                        ? "更新中"
                        : snapshot.updatedAt.formatted(date: .omitted, time: .shortened)
                )
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
            }
        }
    }

    private var primaryVitalsCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                menuLoadMetric("CPU", value: snapshot.cpuPercent, detail: formatTemperature(snapshot.cpuTemperature))
                Rectangle()
                    .fill(InterfacePalette.separator)
                    .frame(width: 1, height: 34)
                menuLoadMetric("内存", value: snapshot.memoryPercent, detail: formatBytes(snapshot.memoryUsed))
            }

            Divider().opacity(0.4)

            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    Text("下行")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text(formatRate(snapshot.downloadBytesPerSecond))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(InterfacePalette.separator)
                    .frame(width: 1, height: 14)

                HStack(spacing: 5) {
                    Text("上行")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text(formatRate(snapshot.uploadBytesPerSecond))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(11)
        .stableMenuCard(cornerRadius: 10)
    }

    private func menuLoadMetric(
        _ title: String,
        value: Double,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Text("\(Int(value.rounded()))%")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.07))
                    Capsule()
                        .fill(InterfacePalette.accent.opacity(0.80))
                        .frame(
                            width: geometry.size.width
                                * min(1, max(0, value / 100))
                        )
                }
            }
            .frame(height: 3)
        }
        .frame(maxWidth: .infinity)
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
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text("活跃进程流量")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(
                    "↓ \(formatMenuBarRate(menuTraffic.downloadBytesPerSecond))  "
                        + "↑ \(formatMenuBarRate(menuTraffic.uploadBytesPerSecond))"
                )
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            }

            if let error = menuTraffic.errorText {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(InterfaceTypography.microMetadata)
                        .foregroundStyle(.secondary)
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
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("当前无活跃进程网络活动")
                            .font(InterfaceTypography.microMetadata)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 22)
            } else {
                ForEach(topTrafficRows) { row in
                    menuTrafficRow(row)
                }
            }
        }
        .padding(11)
        .stableMenuCard(cornerRadius: 10)
    }

    private func menuTrafficRow(_ row: ProcessTrafficRow) -> some View {
        HStack(spacing: 8) {
            menuTrafficIcon(row: row)

            Text(row.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("↓ \(formatMenuBarRate(row.downloadBytesPerSecond))")
                .foregroundStyle(row.downloadBytesPerSecond >= 1 ? .primary : .tertiary)
                .frame(width: 62, alignment: .trailing)

            Text("↑ \(formatMenuBarRate(row.uploadBytesPerSecond))")
                .foregroundStyle(row.uploadBytesPerSecond >= 1 ? .secondary : .tertiary)
                .frame(width: 62, alignment: .trailing)
        }
        .font(.system(size: 11, design: .monospaced))
    }

    @ViewBuilder
    private func menuTrafficIcon(row: ProcessTrafficRow) -> some View {
        if let icon = NSRunningApplication(processIdentifier: pid_t(row.pid))?.icon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        } else if let bundlePath = row.bundlePath {
            Image(nsImage: NSWorkspace.shared.icon(forFile: bundlePath))
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        } else {
            RoundedRectangle(
                cornerRadius: 4,
                style: .continuous
            )
            .fill(Color.primary.opacity(0.06))
            .overlay {
                Text(String(row.name.prefix(1)).uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
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
                detail: snapshot.fanCount > 0 ? "\(snapshot.fanCount) 个风扇" : "静音"
            )
            hardwareDivider
            menuHardwareMetric(
                title: "供电",
                value: model.isRefreshingExpandedMetrics
                    ? "--"
                    : formatBatteryChargePower(snapshot.chargingPower),
                detail: model.isRefreshingExpandedMetrics
                    ? "读取中"
                    : snapshot.powerSource
            )
            hardwareDivider
            menuHardwareMetric(
                title: "接口",
                value: model.isRefreshingCable
                    ? "--"
                    : "\(snapshot.cableMonitor.activePorts.count) 个已连",
                detail: portStatusDetail
            )
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 4)
        .stableMenuCard(cornerRadius: 10)
    }

    private func menuHardwareMetric(
        title: String,
        value: String,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }

    private var hardwareDivider: some View {
        Rectangle()
            .fill(InterfacePalette.separator)
            .frame(width: 1, height: 34)
    }

    private var menuFooter: some View {
        HStack(spacing: 10) {
            Button {
                NSApp.setActivationPolicy(.regular)
                openWindow(id: "dashboard")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 11, weight: .medium))
                    Text("打开主窗口")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                )
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "power")
                        .font(.system(size: 11))
                    Text("退出")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
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

private func formatBytes(_ bytes: UInt64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .memory
    formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
    formatter.includesUnit = true
    formatter.isAdaptive = true
    return formatter.string(fromByteCount: Int64(min(bytes, UInt64(Int64.max))))
}

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
    @State private var model = MonitorModel()
    @State private var processNetworkModel = ProcessNetworkMonitor()
    @State private var codexQuotaModel = CodexQuotaMonitor()
    @State private var selectedSection: DashboardSection = .monitor

    var body: some Scene {
        Window("Mac 资源监控", id: "dashboard") {
            DashboardView(model: model, processNetworkModel: processNetworkModel,
                          codexQuotaModel: codexQuotaModel, selectedSection: $selectedSection)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        MenuBarExtra {
            MenuBarPanel(model: model, processNetworkModel: processNetworkModel,
                         codexQuotaModel: codexQuotaModel, selectedSection: $selectedSection)
        } label: {
            MenuBarStatusLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarStatusLabel: View {
    @ObservedObject var model: MonitorModel

    var body: some View {
        Text(menuBarSummary(model.snapshot))
            .monospacedDigit()
            .accessibilityLabel("Mac 资源监控 \(menuBarSummary(model.snapshot))")
    }
}

private func menuBarSummary(_ snapshot: ResourceSnapshot) -> String {
    let temperature = snapshot.cpuTemperature.map { "\(Int($0.rounded()))°" } ?? "--°"
    return "\(temperature)  ↓\(formatMenuBarRate(snapshot.downloadBytesPerSecond)) ↑\(formatMenuBarRate(snapshot.uploadBytesPerSecond))"
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
