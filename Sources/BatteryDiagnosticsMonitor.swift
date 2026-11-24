import Foundation
import IOKit

struct SleepAssertionItem: Identifiable, Equatable {
    let id: String
    let pid: Int32
    let processName: String
    let assertionType: String
    let reason: String

    var friendlyType: String {
        switch assertionType {
        case "PreventUserIdleSystemSleep": return "阻止系统休眠"
        case "PreventUserIdleDisplaySleep": return "阻止屏幕关闭"
        case "PreventSystemSleep": return "强制系统唤醒"
        case "NoIdleSleepAssertion": return "阻止空闲休眠"
        case "NoDisplaySleepAssertion": return "阻止屏幕休眠"
        default: return assertionType
        }
    }
}

struct BatteryDiagnosticsSnapshot: Equatable {
    var hasBattery = false
    var currentChargePercent: Int? = nil
    var cycleCount: Int? = nil
    var designCapacityMAh: Int? = nil
    var maxCapacityMAh: Int? = nil
    var currentCapacityMAh: Int? = nil
    var healthPercent: Double? = nil
    var batteryCondition: String? = nil
    var temperatureCelsius: Double? = nil
    var voltageVolts: Double? = nil
    var amperageAmps: Double? = nil
    var adapterWatts: Int? = nil
    var externalConnected = false
    var isCharging = false
    var fullyCharged = false
    var timeRemainingMinutes: Int? = nil
    var sleepAssertions: [SleepAssertionItem] = []
    var updatedAt: Date?

    var dischargeWatts: Double? {
        guard !isCharging, let v = voltageVolts, let a = amperageAmps, a < -0.01 else { return nil }
        return abs(v * a)
    }
}

enum BatteryDiagnosticsParser {
    static func computeHealthPercent(maxCapacityMAh: Int?, designCapacityMAh: Int?) -> Double? {
        guard let maxCap = maxCapacityMAh,
              let designCap = designCapacityMAh,
              maxCap > 0, designCap > 0 else { return nil }
        return min(100.0, max(0.0, Double(maxCap) / Double(designCap) * 100.0))
    }

    /// Normalizes AppleSmartBattery temperature readings across centikelvin (e.g. 30150),
    /// centidegrees Celsius (e.g. 2985), and whole degrees Celsius (e.g. 30).
    static func normalizeTemperatureCelsius(_ raw: Int) -> Double? {
        let celsius: Double
        if (20_000...37_000).contains(raw) {
            celsius = Double(raw) / 100.0 - 273.15
        } else if (500...9_500).contains(raw) {
            celsius = Double(raw) / 100.0
        } else if (1...95).contains(raw) {
            celsius = Double(raw)
        } else {
            return nil
        }
        return (0.0...90.0).contains(celsius) ? celsius : nil
    }

    static func parseSystemProfilerPowerJSON(
        _ data: Data
    ) -> (healthPercent: Double?, condition: String?, cycleCount: Int?, maxCapacityMAh: Int?) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["SPPowerDataType"] as? [[String: Any]] else {
            return (nil, nil, nil, nil)
        }
        var healthPercent: Double? = nil
        var condition: String? = nil
        var cycleCount: Int? = nil
        var maxCapMAh: Int? = nil

        for item in items {
            if let healthInfo = item["sppower_battery_health_info"] as? [String: Any] {
                if let maxCapStr = healthInfo["sppower_battery_health_maximum_capacity"] as? String {
                    let digits = maxCapStr.replacingOccurrences(of: "%", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if let parsed = Double(digits), parsed > 0, parsed <= 100 {
                        healthPercent = parsed
                    }
                }
                if let rawCond = healthInfo["sppower_battery_health"] as? String {
                    switch rawCond.lowercased() {
                    case "good", "normal": condition = "正常"
                    case "fair": condition = "一般"
                    case "poor", "check battery", "replace soon", "replace now", "service recommended":
                        condition = "建议维修"
                    default:
                        if !rawCond.isEmpty { condition = rawCond }
                    }
                }
                if let cycles = (healthInfo["sppower_battery_cycle_count"] as? NSNumber)?.intValue {
                    cycleCount = cycles
                }
            }
            if let chargeInfo = item["sppower_battery_charge_info"] as? [String: Any] {
                if let maxCap = (chargeInfo["sppower_battery_max_capacity"] as? NSNumber)?.intValue, maxCap > 100 {
                    maxCapMAh = maxCap
                }
            }
        }
        return (healthPercent, condition, cycleCount, maxCapMAh)
    }

    static func parseSleepAssertions(_ output: String) -> [SleepAssertionItem] {
        var items: [SleepAssertionItem] = []
        var seenKeys = Set<String>()
        let interestingTypes: Set<String> = [
            "PreventUserIdleSystemSleep",
            "PreventUserIdleDisplaySleep",
            "PreventSystemSleep",
            "NoIdleSleepAssertion",
            "NoDisplaySleepAssertion"
        ]

        // Format example:
        //    pid 412(powerd): [0x00000123000180ab] 00:12:34 PreventUserIdleSystemSleep named: "Reason text"
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("pid ") else { continue }
            guard let openParen = line.firstIndex(of: "("),
                  let closeParen = line.firstIndex(of: ")"),
                  openParen < closeParen else { continue }

            let pidString = line[line.index(line.startIndex, offsetBy: 4)..<openParen]
                .trimmingCharacters(in: .whitespaces)
            guard let pid = Int32(pidString) else { continue }

            let processName = String(line[line.index(after: openParen)..<closeParen])
                .trimmingCharacters(in: .whitespaces)
            let remainder = String(line[line.index(after: closeParen)...])

            guard let matchedType = interestingTypes.first(where: { remainder.contains($0) }) else {
                continue
            }

            let reason: String = {
                if let range = remainder.range(of: "named: \"") {
                    let after = remainder[range.upperBound...]
                    if let endQuote = after.firstIndex(of: "\"") {
                        return String(after[..<endQuote])
                    }
                }
                return "正在保持活跃"
            }()

            let key = "\(pid)-\(matchedType)-\(reason)"
            guard seenKeys.insert(key).inserted else { continue }

            items.append(SleepAssertionItem(
                id: key,
                pid: pid,
                processName: processName.isEmpty ? "PID \(pid)" : processName,
                assertionType: matchedType,
                reason: reason
            ))
        }

        return items
    }
}

/// Accessed exclusively on `MonitorModel`'s serial collector queue.
final class BatteryDiagnosticsCollector: @unchecked Sendable {
    private var assertionsCounter = 0
    private var cachedAssertions: [SleepAssertionItem] = []
    private var cachedProfilerInfo: (healthPercent: Double?, condition: String?, cycleCount: Int?, maxCapacityMAh: Int?)? = nil

    func collect(forceRefresh: Bool = false) -> BatteryDiagnosticsSnapshot {
        var snapshot = readSmartBattery()
        if snapshot.hasBattery && (cachedProfilerInfo == nil || forceRefresh || snapshot.healthPercent == nil) {
            cachedProfilerInfo = readSystemProfilerPower()
        }
        if let profiler = cachedProfilerInfo {
            if snapshot.healthPercent == nil {
                snapshot.healthPercent = profiler.healthPercent
            }
            if snapshot.batteryCondition == nil {
                snapshot.batteryCondition = profiler.condition
            }
            if snapshot.cycleCount == nil {
                snapshot.cycleCount = profiler.cycleCount
            }
            if snapshot.maxCapacityMAh == nil {
                snapshot.maxCapacityMAh = profiler.maxCapacityMAh
            }
        }
        if forceRefresh || assertionsCounter == 0 {
            cachedAssertions = sampleSleepAssertions()
            assertionsCounter = 0
        }
        assertionsCounter = (assertionsCounter + 1) % 3
        snapshot.sleepAssertions = cachedAssertions
        snapshot.updatedAt = Date()
        return snapshot
    }

    private func readSmartBattery() -> BatteryDiagnosticsSnapshot {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != 0 else {
            return BatteryDiagnosticsSnapshot(hasBattery: false)
        }
        defer { IOObjectRelease(service) }

        func property(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(
                service,
                key as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue()
        }

        let batteryData = property("BatteryData") as? [String: Any] ?? [:]

        func intProp(_ key: String) -> Int? {
            if let num = property(key) as? NSNumber {
                return num.intValue
            }
            if let num = batteryData[key] as? NSNumber {
                return num.intValue
            }
            return nil
        }

        let designCap = intProp("DesignCapacity")
        let rawMaxCap = intProp("AppleRawMaxCapacity")
            ?? intProp("NominalChargeCapacity")
            ?? (batteryData["MaxCapacity"] as? NSNumber)?.intValue
        let rawCurrentCap = intProp("AppleRawCurrentCapacity")
        let currentPercent = intProp("CurrentCapacity")
        let cycleCount = intProp("CycleCount")
        let externalConnected = (property("ExternalConnected") as? NSNumber)?.boolValue ?? false
        let isCharging = (property("IsCharging") as? NSNumber)?.boolValue ?? false
        let fullyCharged = (property("FullyCharged") as? NSNumber)?.boolValue ?? false

        let temperature: Double? = {
            let candidates: [Int?] = [
                intProp("VirtualTemperature"),
                intProp("Temperature"),
                (batteryData["VirtualTemperature"] as? NSNumber)?.intValue,
                (batteryData["Temperature"] as? NSNumber)?.intValue,
                (batteryData["BatteryTemperature"] as? NSNumber)?.intValue
            ]
            for raw in candidates.compactMap({ $0 }) {
                if let normalized = BatteryDiagnosticsParser.normalizeTemperatureCelsius(raw) {
                    return normalized
                }
            }
            return nil
        }()

        let voltage: Double? = intProp("Voltage").flatMap { raw in
            let volts = Double(raw) / 1000.0
            return (5...30).contains(volts) ? volts : nil
        }

        let amperage: Double? = (intProp("InstantAmperage") ?? intProp("Amperage")).map { raw in
            Double(raw) / 1000.0
        }

        let adapterWatts: Int? = {
            guard let adapter = property("AdapterDetails") as? [String: Any],
                  let watts = (adapter["Watts"] as? NSNumber)?.intValue,
                  watts > 0 else { return nil }
            return watts
        }()

        let timeRemaining: Int? = {
            let candidate = isCharging ? intProp("AvgTimeToFull") : intProp("AvgTimeToEmpty")
            let fallback = intProp("TimeRemaining")
            let raw = candidate ?? fallback
            guard let raw, raw > 0, raw < 10_000 else { return nil }
            return raw
        }()

        return BatteryDiagnosticsSnapshot(
            hasBattery: designCap != nil || cycleCount != nil || currentPercent != nil,
            currentChargePercent: currentPercent,
            cycleCount: cycleCount,
            designCapacityMAh: designCap,
            maxCapacityMAh: rawMaxCap,
            currentCapacityMAh: rawCurrentCap,
            healthPercent: BatteryDiagnosticsParser.computeHealthPercent(
                maxCapacityMAh: rawMaxCap,
                designCapacityMAh: designCap
            ),
            batteryCondition: nil,
            temperatureCelsius: temperature,
            voltageVolts: voltage,
            amperageAmps: amperage,
            adapterWatts: adapterWatts,
            externalConnected: externalConnected,
            isCharging: isCharging,
            fullyCharged: fullyCharged,
            timeRemainingMinutes: timeRemaining
        )
    }

    private func readSystemProfilerPower() -> (healthPercent: Double?, condition: String?, cycleCount: Int?, maxCapacityMAh: Int?) {
        guard let result = CommandRunner.run(
            "/usr/sbin/system_profiler",
            arguments: ["SPPowerDataType", "-json"],
            timeout: 4
        ), !result.timedOut, result.terminationStatus == 0 else {
            return (nil, nil, nil, nil)
        }
        return BatteryDiagnosticsParser.parseSystemProfilerPowerJSON(result.standardOutput)
    }

    private func sampleSleepAssertions() -> [SleepAssertionItem] {
        guard let result = CommandRunner.run(
            "/usr/bin/pmset",
            arguments: ["-g", "assertions"],
            timeout: 3
        ), !result.timedOut, result.terminationStatus == 0 else {
            return []
        }
        return BatteryDiagnosticsParser.parseSleepAssertions(result.outputString)
    }
}
