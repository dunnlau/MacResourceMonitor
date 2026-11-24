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
}

enum BatteryDiagnosticsParser {
    static func computeHealthPercent(maxCapacityMAh: Int?, designCapacityMAh: Int?) -> Double? {
        guard let maxCap = maxCapacityMAh,
              let designCap = designCapacityMAh,
              maxCap > 0, designCap > 0 else { return nil }
        return min(100.0, max(0.0, Double(maxCap) / Double(designCap) * 100.0))
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

    func collect(forceRefresh: Bool = false) -> BatteryDiagnosticsSnapshot {
        var snapshot = readSmartBattery()
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

        func intProp(_ key: String) -> Int? {
            (property(key) as? NSNumber)?.intValue
        }

        let designCap = intProp("DesignCapacity")
        let rawMaxCap = intProp("AppleRawMaxCapacity") ?? intProp("NominalChargeCapacity")
        let rawCurrentCap = intProp("AppleRawCurrentCapacity")
        let currentPercent = intProp("CurrentCapacity")
        let cycleCount = intProp("CycleCount")
        let externalConnected = (property("ExternalConnected") as? NSNumber)?.boolValue ?? false
        let isCharging = (property("IsCharging") as? NSNumber)?.boolValue ?? false
        let fullyCharged = (property("FullyCharged") as? NSNumber)?.boolValue ?? false

        let temperature: Double? = intProp("Temperature").flatMap { raw in
            let celsius = Double(raw) / 100.0
            return (0...90).contains(celsius) ? celsius : nil
        }

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
