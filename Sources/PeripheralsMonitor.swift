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
    static func inferCategory(for name: String) -> String {
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

/// Collects HID/Bluetooth battery info via IOKit and display modes via AppKit/CoreGraphics.
enum PeripheralsCollector {
    static func collectBatteryDevices() -> [PeripheralBatteryItem] {
        var devices: [PeripheralBatteryItem] = []
        var seen = Set<String>()

        let matchingClasses = [
            "AppleDeviceManagementHIDEventService",
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

                let serial = (prop("SerialNumber") as? String)
                    ?? (prop("DeviceAddress") as? String)
                    ?? name
                let key = "\(name)-\(serial)"
                guard seen.insert(key).inserted else { continue }

                let transport = (prop("Transport") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? "Bluetooth"

                devices.append(PeripheralBatteryItem(
                    id: key,
                    name: name,
                    category: PeripheralClassifier.inferCategory(for: name),
                    batteryPercent: battery,
                    transport: transport
                ))
            }
        }

        return devices.sorted { lhs, rhs in
            if lhs.batteryPercent != rhs.batteryPercent {
                return lhs.batteryPercent < rhs.batteryPercent
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
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

    deinit { pollTask?.cancel() }

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        generation &+= 1
        pollTask?.cancel()
        pollTask = nil

        if active {
            refresh()
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

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let displays = PeripheralsCollector.collectDisplays()
        let currentGen = generation
        queue.async { [weak self] in
            let batteryDevices = PeripheralsCollector.collectBatteryDevices()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isRefreshing = false
                guard self.generation == currentGen else { return }
                self.snapshot = PeripheralsSnapshot(
                    batteryDevices: batteryDevices,
                    displays: displays,
                    updatedAt: Date()
                )
            }
        }
    }
}
