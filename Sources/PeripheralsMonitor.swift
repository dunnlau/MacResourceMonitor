import Foundation
import AppKit
import CoreGraphics
import IOKit

struct PeripheralBatteryItem: Identifiable, Equatable {
    let id: String
    let name: String
    let category: String
    let batteryPercent: Int
    let transport: String
}

struct DisplayInfoItem: Identifiable, Equatable {
    let id: UInt32
    let name: String
    let logicalWidth: Int
    let logicalHeight: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let scaleFactor: Double
    let refreshRateHz: Double?
    let isBuiltIn: Bool
    let isMain: Bool
    let supportsHDR: Bool
}

struct PeripheralsSnapshot: Equatable {
    var batteryDevices: [PeripheralBatteryItem] = []
    var displays: [DisplayInfoItem] = []
    var updatedAt: Date? = nil
}

enum PeripheralClassifier {
    static func inferCategory(for name: String, minorType: String? = nil) -> String {
        if let minor = minorType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !minor.isEmpty {
            if minor.contains("mouse") {
                return "鼠标"
            }
            if minor.contains("keyboard") {
                return "键盘"
            }
            if minor.contains("trackpad") {
                return "触控板"
            }
            if minor.contains("headphone") || minor.contains("headset") || minor.contains("speaker")
                || minor.contains("audio") || minor.contains("earbud") || minor.contains("loudspeaker") {
                return "音频设备"
            }
            if minor.contains("gamepad") || minor.contains("joystick") || minor.contains("controller") {
                return "游戏手柄"
            }
        }

        let lower = name.lowercased()
        if lower.contains("airpods") || lower.contains("headphone") || lower.contains("beats") || lower.contains("buds") {
            return "音频设备"
        }
        if lower.contains("keyboard") || lower.contains("键盘") {
            return "键盘"
        }
        if lower.contains("trackpad") || lower.contains("触控板") {
            return "触控板"
        }
        if lower.contains("mouse") || lower.contains("鼠标") {
            return "鼠标"
        }
        if lower.contains("controller") || lower.contains("gamepad") || lower.contains("xbox") || lower.contains("dualsense") {
            return "游戏手柄"
        }
        return "无线外设"
    }
}

enum PeripheralsBluetoothParser {
    static func parsePercent(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            let pct = number.intValue
            return (0...100).contains(pct) ? pct : nil
        }
        if let text = value as? String {
            let cleaned = text
                .replacingOccurrences(of: "%", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let pct = Int(cleaned), (0...100).contains(pct) {
                return pct
            }
        }
        return nil
    }

    static func normalizeAddress(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        return normalized.isEmpty ? nil : normalized
    }

    static func parseSystemProfilerBluetoothJSON(_ data: Data) -> [PeripheralBatteryItem] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["SPBluetoothDataType"] as? [[String: Any]] else {
            return []
        }

        var devices: [PeripheralBatteryItem] = []
        var seenIDs = Set<String>()

        for entry in entries {
            guard let connectedList = entry["device_connected"] as? [[String: Any]] else { continue }
            for deviceDict in connectedList {
                for (rawName, rawAttrs) in deviceDict {
                    let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty, let attrs = rawAttrs as? [String: Any] else { continue }

                    let address = normalizeAddress(attrs["device_address"] as? String)
                    let minorType = attrs["device_minorType"] as? String
                    let category = PeripheralClassifier.inferCategory(for: name, minorType: minorType)
                    let baseID = address ?? name.lowercased()

                    if let mainPercent = parsePercent(attrs["device_batteryLevelMain"]) {
                        if seenIDs.insert(baseID).inserted {
                            devices.append(PeripheralBatteryItem(
                                id: baseID,
                                name: name,
                                category: category,
                                batteryPercent: mainPercent,
                                transport: "Bluetooth"
                            ))
                        }
                        continue
                    }

                    let subComponents: [(key: String, suffix: String, label: String)] = [
                        ("device_batteryLevelLeft", "left", "左耳"),
                        ("device_batteryLevelRight", "right", "右耳"),
                        ("device_batteryLevelCase", "case", "充电盒")
                    ]
                    for component in subComponents {
                        if let pct = parsePercent(attrs[component.key]) {
                            let itemID = "\(baseID)-\(component.suffix)"
                            if seenIDs.insert(itemID).inserted {
                                devices.append(PeripheralBatteryItem(
                                    id: itemID,
                                    name: "\(name)（\(component.label)）",
                                    category: category,
                                    batteryPercent: pct,
                                    transport: "Bluetooth"
                                ))
                            }
                        }
                    }
                }
            }
        }

        return devices
    }

    static func mergeBatteryDevices(
        iokit: [PeripheralBatteryItem],
        bluetooth: [PeripheralBatteryItem]
    ) -> [PeripheralBatteryItem] {
        var merged: [PeripheralBatteryItem] = []
        var seenIDs = Set<String>()
        var seenNames = Set<String>()

        for item in bluetooth {
            let normName = item.name.lowercased()
            if seenIDs.insert(item.id).inserted {
                seenNames.insert(normName)
                merged.append(item)
            }
        }

        for item in iokit {
            let normName = item.name.lowercased()
            if seenIDs.contains(item.id) || seenNames.contains(normName) {
                continue
            }
            seenIDs.insert(item.id)
            seenNames.insert(normName)
            merged.append(item)
        }

        return merged.sorted { lhs, rhs in
            if lhs.batteryPercent != rhs.batteryPercent {
                return lhs.batteryPercent < rhs.batteryPercent
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

/// Collects HID/Bluetooth battery info via IOKit + SPBluetoothDataType and display modes via AppKit/CoreGraphics.
enum PeripheralsCollector {
    static func collectIOKitBatteryDevices() -> [PeripheralBatteryItem] {
        var devices: [PeripheralBatteryItem] = []
        var seen = Set<String>()

        let matchingClasses = [
            "AppleDeviceManagementHIDEventService",
            "AppleHSBluetoothDevice",
            "IOBluetoothHIDDriver",
            "BNBMouseDevice",
            "BNBTrackpadDevice",
            "AppleBluetoothHIDKeyboard",
            "IOHIDDevice"
        ]

        for className in matchingClasses {
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(
                kIOMainPortDefault,
                IOServiceMatching(className),
                &iterator
            ) == kIOReturnSuccess else { continue }
            defer { IOObjectRelease(iterator) }

            var service = IOIteratorNext(iterator)
            while service != 0 {
                defer {
                    IOObjectRelease(service)
                    service = IOIteratorNext(iterator)
                }

                func prop(_ key: String) -> Any? {
                    IORegistryEntryCreateCFProperty(
                        service,
                        key as CFString,
                        kCFAllocatorDefault,
                        0
                    )?.takeRetainedValue()
                }

                guard let battery = (prop("BatteryPercent") as? NSNumber)?.intValue,
                      (0...100).contains(battery) else { continue }

                let rawName = (prop("Product") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let name = rawName, !name.isEmpty else { continue }

                let normalizedAddress = PeripheralsBluetoothParser.normalizeAddress(prop("DeviceAddress") as? String)
                let serial = (prop("SerialNumber") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let id = normalizedAddress
                    ?? (serial?.isEmpty == false ? "\(name.lowercased())-\(serial!)" : name.lowercased())
                guard seen.insert(id).inserted else { continue }

                let transport = (prop("Transport") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? "Bluetooth"

                devices.append(PeripheralBatteryItem(
                    id: id,
                    name: name,
                    category: PeripheralClassifier.inferCategory(for: name),
                    batteryPercent: battery,
                    transport: transport
                ))
            }
        }

        return devices
    }

    static func collectBluetoothProfilerDevices() -> [PeripheralBatteryItem] {
        guard let result = CommandRunner.run(
            "/usr/sbin/system_profiler",
            arguments: ["SPBluetoothDataType", "-json"],
            timeout: 4.0
        ),
        !result.timedOut,
        result.terminationStatus == 0 else {
            return []
        }
        return PeripheralsBluetoothParser.parseSystemProfilerBluetoothJSON(result.standardOutput)
    }

    static func collectBatteryDevices(
        cachedBluetooth: [PeripheralBatteryItem]?,
        refreshBluetooth: Bool
    ) -> (devices: [PeripheralBatteryItem], bluetoothCache: [PeripheralBatteryItem]) {
        let iokit = collectIOKitBatteryDevices()
        let bluetooth = (refreshBluetooth || cachedBluetooth == nil)
            ? collectBluetoothProfilerDevices()
            : (cachedBluetooth ?? [])
        let merged = PeripheralsBluetoothParser.mergeBatteryDevices(iokit: iokit, bluetooth: bluetooth)
        return (merged, bluetooth)
    }

    @MainActor
    static func collectDisplays() -> [DisplayInfoItem] {
        let mainDisplayID = CGMainDisplayID()
        return NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let displayID = CGDirectDisplayID(number.uint32Value)
            let logicalWidth = Int(screen.frame.width.rounded())
            let logicalHeight = Int(screen.frame.height.rounded())
            let scale = Double(screen.backingScaleFactor)

            let mode = CGDisplayCopyDisplayMode(displayID)
            let pixelWidth = mode?.pixelWidth ?? Int(Double(logicalWidth) * scale)
            let pixelHeight = mode?.pixelHeight ?? Int(Double(logicalHeight) * scale)
            let rawRate = mode?.refreshRate ?? 0
            let refreshRate: Double? = rawRate > 0 ? rawRate : nil

            let isBuiltIn = CGDisplayIsBuiltin(displayID) != 0
            let supportsHDR = screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.0

            return DisplayInfoItem(
                id: displayID,
                name: screen.localizedName,
                logicalWidth: logicalWidth,
                logicalHeight: logicalHeight,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                scaleFactor: scale,
                refreshRateHz: refreshRate,
                isBuiltIn: isBuiltIn,
                isMain: displayID == mainDisplayID,
                supportsHDR: supportsHDR
            )
        }
    }
}

@MainActor
final class PeripheralsMonitor: ObservableObject {
    @Published private(set) var snapshot = PeripheralsSnapshot()
    @Published private(set) var isRefreshing = false

    private let queue = DispatchQueue(label: "local.mac-resource-monitor.peripherals", qos: .utility)
    private var isActive = false
    private var pollTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var cachedBluetoothDevices: [PeripheralBatteryItem]? = nil
    private var bluetoothPollTick = 0

    deinit { pollTask?.cancel() }

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        generation &+= 1
        pollTask?.cancel()
        pollTask = nil

        if active {
            bluetoothPollTick = 0
            refresh(forceBluetooth: true)
            let currentGen = generation
            pollTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    guard !Task.isCancelled, let self, self.isActive, self.generation == currentGen else { break }
                    self.refresh()
                }
            }
        }
    }

    func refresh(forceBluetooth: Bool = false) {
        guard !isRefreshing else { return }
        isRefreshing = true
        let displays = PeripheralsCollector.collectDisplays()
        let currentGen = generation
        let shouldRefreshBluetooth = forceBluetooth || cachedBluetoothDevices == nil || bluetoothPollTick == 0
        bluetoothPollTick = (bluetoothPollTick + 1) % 3
        let previousBluetooth = cachedBluetoothDevices

        queue.async { [weak self] in
            let collected = PeripheralsCollector.collectBatteryDevices(
                cachedBluetooth: previousBluetooth,
                refreshBluetooth: shouldRefreshBluetooth
            )
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isRefreshing = false
                guard self.generation == currentGen else { return }
                self.cachedBluetoothDevices = collected.bluetoothCache
                self.snapshot = PeripheralsSnapshot(
                    batteryDevices: collected.devices,
                    displays: displays,
                    updatedAt: Date()
                )
            }
        }
    }
}
