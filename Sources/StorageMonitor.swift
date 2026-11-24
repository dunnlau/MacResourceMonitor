import Foundation
import IOKit

struct StorageVolumeSnapshot: Identifiable, Equatable {
    let id: String
    let name: String
    let mountPath: String
    let fileSystemType: String
    let totalBytes: UInt64
    let usedBytes: UInt64
    let availableBytes: UInt64
    let purgeableBytes: UInt64
    let isInternal: Bool
    let isRemovable: Bool
    let isRoot: Bool

    var usedPercent: Double {
        guard totalBytes > 0 else { return 0 }
        return min(100, max(0, Double(usedBytes) / Double(totalBytes) * 100))
    }
}

struct StorageDriveHealthSnapshot: Equatable {
    var modelName: String = "Apple SSD"
    var protocolName: String = "NVMe"
    var smartStatus: String = "已验证"
    var isSolidState = true
}

struct StorageMonitorSnapshot: Equatable {
    var readBytesPerSecond = 0.0
    var writeBytesPerSecond = 0.0
    var totalReadBytes: UInt64 = 0
    var totalWriteBytes: UInt64 = 0
    var volumes: [StorageVolumeSnapshot] = []
    var primaryDrive = StorageDriveHealthSnapshot()
    var updatedAt: Date?
}

enum StorageMetricsMath {
    static func rate(
        previousBytes: UInt64,
        currentBytes: UInt64,
        elapsedSeconds: TimeInterval
    ) -> Double {
        guard currentBytes >= previousBytes else { return 0 }
        let safeElapsed = max(0.2, elapsedSeconds)
        return Double(currentBytes - previousBytes) / safeElapsed
    }

    static func purgeableBytes(
        importantAvailable: Int64?,
        standardAvailable: Int?
    ) -> UInt64 {
        guard let important = importantAvailable,
              let standard = standardAvailable,
              important > Int64(standard) else { return 0 }
        return UInt64(important - Int64(standard))
    }
}

/// Accessed exclusively on `MonitorModel`'s serial collector queue.
final class StorageCollector: @unchecked Sendable {
    private var previousIO: (read: UInt64, write: UInt64, date: Date)?
    private var cachedDriveHealth: StorageDriveHealthSnapshot?
    private var volumeRefreshCounter = 0
    private var cachedVolumes: [StorageVolumeSnapshot] = []

    func collect(forceVolumeRefresh: Bool = false) -> StorageMonitorSnapshot {
        let now = Date()
        let counters = sampleDiskIOBytes()
        var readRate = 0.0
        var writeRate = 0.0

        if let prev = previousIO {
            let elapsed = now.timeIntervalSince(prev.date)
            readRate = StorageMetricsMath.rate(
                previousBytes: prev.read,
                currentBytes: counters.read,
                elapsedSeconds: elapsed
            )
            writeRate = StorageMetricsMath.rate(
                previousBytes: prev.write,
                currentBytes: counters.write,
                elapsedSeconds: elapsed
            )
        }
        previousIO = (counters.read, counters.write, now)

        if forceVolumeRefresh || cachedVolumes.isEmpty || volumeRefreshCounter == 0 {
            cachedVolumes = sampleVolumes()
            volumeRefreshCounter = 0
        }
        volumeRefreshCounter = (volumeRefreshCounter + 1) % 5

        if cachedDriveHealth == nil || forceVolumeRefresh {
            cachedDriveHealth = samplePrimaryDriveHealth()
        }

        return StorageMonitorSnapshot(
            readBytesPerSecond: readRate,
            writeBytesPerSecond: writeRate,
            totalReadBytes: counters.read,
            totalWriteBytes: counters.write,
            volumes: cachedVolumes,
            primaryDrive: cachedDriveHealth ?? StorageDriveHealthSnapshot(),
            updatedAt: now
        )
    }

    private func sampleDiskIOBytes() -> (read: UInt64, write: UInt64) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOBlockStorageDriver"),
            &iterator
        ) == kIOReturnSuccess else {
            return (0, 0)
        }
        defer { IOObjectRelease(iterator) }

        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            guard let stats = IORegistryEntryCreateCFProperty(
                service,
                "Statistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any] else { continue }

            if let read = (stats["Bytes (Read)"] as? NSNumber)?.uint64Value {
                totalRead &+= read
            }
            if let write = (stats["Bytes (Write)"] as? NSNumber)?.uint64Value {
                totalWrite &+= write
            }
        }
        return (totalRead, totalWrite)
    }

    private func sampleVolumes() -> [StorageVolumeSnapshot] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeLocalizedFormatDescriptionKey,
            .volumeIsInternalKey,
            .volumeIsRemovableKey,
            .volumeIsBrowsableKey
        ]

        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else {
            return []
        }

        var results: [StorageVolumeSnapshot] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let path = url.path
            if path.hasPrefix("/System/Volumes/") && path != "/System/Volumes/Data" {
                continue
            }
            let total = UInt64(max(0, values.volumeTotalCapacity ?? 0))
            guard total > 0 else { continue }
            let availableImportant = values.volumeAvailableCapacityForImportantUsage
            let availableStandard = values.volumeAvailableCapacity
            let available = UInt64(max(0, availableImportant ?? Int64(availableStandard ?? 0)))
            let used = total >= available ? total - available : 0
            let purgeable = StorageMetricsMath.purgeableBytes(
                importantAvailable: availableImportant,
                standardAvailable: availableStandard
            )
            let name = values.volumeName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = (name?.isEmpty == false ? name! : url.lastPathComponent)
            let isRoot = path == "/"
            let isInternal = values.volumeIsInternal ?? isRoot
            let isRemovable = (values.volumeIsRemovable ?? false) || (!isInternal && !isRoot)

            results.append(StorageVolumeSnapshot(
                id: path,
                name: displayName,
                mountPath: path,
                fileSystemType: values.volumeLocalizedFormatDescription ?? "APFS",
                totalBytes: total,
                usedBytes: used,
                availableBytes: available,
                purgeableBytes: purgeable,
                isInternal: isInternal,
                isRemovable: isRemovable,
                isRoot: isRoot
            ))
        }

        return results.sorted { lhs, rhs in
            if lhs.isRoot != rhs.isRoot { return lhs.isRoot }
            if lhs.isInternal != rhs.isInternal { return lhs.isInternal }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func samplePrimaryDriveHealth() -> StorageDriveHealthSnapshot {
        guard let result = CommandRunner.run(
            "/usr/sbin/diskutil",
            arguments: ["info", "-plist", "disk0"],
            timeout: 3
        ), !result.timedOut, result.terminationStatus == 0,
              let plist = try? PropertyListSerialization.propertyList(
                  from: result.standardOutput,
                  options: [],
                  format: nil
              ) as? [String: Any] else {
            return StorageDriveHealthSnapshot()
        }

        let model = (plist["MediaName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let proto = (plist["BusProtocol"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let smartRaw = (plist["SMARTStatus"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let solidState = (plist["SolidState"] as? Bool) ?? true

        let smartLocalized: String = {
            guard let smartRaw, !smartRaw.isEmpty else { return "未知" }
            switch smartRaw.lowercased() {
            case "verified": return "健康（已验证）"
            case "failing": return "存在风险"
            case "not supported": return "不支持 SMART"
            default: return smartRaw
            }
        }()

        return StorageDriveHealthSnapshot(
            modelName: (model?.isEmpty == false ? model! : "Apple SSD"),
            protocolName: (proto?.isEmpty == false ? proto! : "Apple Fabric / NVMe"),
            smartStatus: smartLocalized,
            isSolidState: solidState
        )
    }
}
