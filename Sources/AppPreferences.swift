import Foundation
import Combine
import ServiceManagement
import UserNotifications

enum LoginItemStatus: Equatable {
    case enabled
    case requiresApproval
    case disabled
    case unavailable

    var label: String {
        switch self {
        case .enabled: return "已开启"
        case .requiresApproval: return "需在系统设置中允许"
        case .disabled: return "未开启"
        case .unavailable: return "当前运行模式不可用"
        }
    }
}

@MainActor
final class AppPreferences: ObservableObject {
    private enum Keys {
        static let showTemperature = "MRM.MenuBar.ShowTemperature"
        static let showCPU = "MRM.MenuBar.ShowCPU"
        static let showMemory = "MRM.MenuBar.ShowMemory"
        static let showNetwork = "MRM.MenuBar.ShowNetwork"
        static let showPower = "MRM.MenuBar.ShowPower"
        static let alertsEnabled = "MRM.Alerts.Enabled"
        static let highTempThreshold = "MRM.Alerts.HighTempThreshold"
        static let highCPUThreshold = "MRM.Alerts.HighCPUThreshold"
    }

    @Published var showMenuBarTemperature: Bool {
        didSet { userDefaults.set(showMenuBarTemperature, forKey: Keys.showTemperature) }
    }
    @Published var showMenuBarCPU: Bool {
        didSet { userDefaults.set(showMenuBarCPU, forKey: Keys.showCPU) }
    }
    @Published var showMenuBarMemory: Bool {
        didSet { userDefaults.set(showMenuBarMemory, forKey: Keys.showMemory) }
    }
    @Published var showMenuBarNetwork: Bool {
        didSet { userDefaults.set(showMenuBarNetwork, forKey: Keys.showNetwork) }
    }
    @Published var showMenuBarPower: Bool {
        didSet { userDefaults.set(showMenuBarPower, forKey: Keys.showPower) }
    }

    @Published var alertsEnabled: Bool {
        didSet {
            userDefaults.set(alertsEnabled, forKey: Keys.alertsEnabled)
            if alertsEnabled {
                requestNotificationAuthorizationIfNeeded()
            }
        }
    }
    @Published var highTempThreshold: Double {
        didSet { userDefaults.set(highTempThreshold, forKey: Keys.highTempThreshold) }
    }
    @Published var highCPUThreshold: Double {
        didSet { userDefaults.set(highCPUThreshold, forKey: Keys.highCPUThreshold) }
    }

    @Published private(set) var loginItemStatus: LoginItemStatus = .disabled
    @Published private(set) var loginItemError: String? = nil

    private let userDefaults: UserDefaults
    private var lastTempAlertAt: Date? = nil
    private var lastCPUAlertAt: Date? = nil
    private var sustainedHighCPUCount = 0
    private let alertCooldownSeconds: TimeInterval = 300

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.showMenuBarTemperature = userDefaults.object(forKey: Keys.showTemperature) as? Bool ?? true
        self.showMenuBarCPU = userDefaults.object(forKey: Keys.showCPU) as? Bool ?? false
        self.showMenuBarMemory = userDefaults.object(forKey: Keys.showMemory) as? Bool ?? false
        self.showMenuBarNetwork = userDefaults.object(forKey: Keys.showNetwork) as? Bool ?? true
        self.showMenuBarPower = userDefaults.object(forKey: Keys.showPower) as? Bool ?? false

        self.alertsEnabled = userDefaults.object(forKey: Keys.alertsEnabled) as? Bool ?? false
        let storedTemp = userDefaults.object(forKey: Keys.highTempThreshold) as? Double ?? 90.0
        self.highTempThreshold = min(105, max(70, storedTemp))
        let storedCPU = userDefaults.object(forKey: Keys.highCPUThreshold) as? Double ?? 90.0
        self.highCPUThreshold = min(99, max(70, storedCPU))

        refreshLoginItemStatus()
    }

    var isRunningFromAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    func refreshLoginItemStatus() {
        guard isRunningFromAppBundle else {
            loginItemStatus = .unavailable
            return
        }
        switch SMAppService.mainApp.status {
        case .enabled:
            loginItemStatus = .enabled
        case .requiresApproval:
            loginItemStatus = .requiresApproval
        case .notRegistered, .notFound:
            loginItemStatus = .disabled
        @unknown default:
            loginItemStatus = .disabled
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard isRunningFromAppBundle else {
            loginItemStatus = .unavailable
            return
        }
        loginItemError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginItemError = error.localizedDescription
        }
        refreshLoginItemStatus()
    }

    func evaluateAlerts(cpuPercent: Double, cpuTemperature: Double?, now: Date = Date()) {
        guard alertsEnabled, isRunningFromAppBundle else {
            sustainedHighCPUCount = 0
            return
        }

        if let temp = cpuTemperature, temp >= highTempThreshold {
            if lastTempAlertAt.map({ now.timeIntervalSince($0) >= alertCooldownSeconds }) ?? true {
                lastTempAlertAt = now
                postNotification(
                    identifier: "mrm.alert.high-temp",
                    title: "CPU 温度偏高",
                    body: String(format: "当前 CPU 温度 %.1f°C，已达到设定阈值 %.0f°C。", temp, highTempThreshold)
                )
            }
        }

        if cpuPercent >= highCPUThreshold {
            sustainedHighCPUCount += 1
            // Require 3 consecutive samples (~6 seconds) to avoid transient spikes.
            if sustainedHighCPUCount >= 3,
               lastCPUAlertAt.map({ now.timeIntervalSince($0) >= alertCooldownSeconds }) ?? true {
                lastCPUAlertAt = now
                postNotification(
                    identifier: "mrm.alert.high-cpu",
                    title: "CPU 持续高负载",
                    body: String(format: "当前 CPU 占用 %.0f%%，已持续高于 %.0f%%。", cpuPercent, highCPUThreshold)
                )
            }
        } else {
            sustainedHighCPUCount = 0
        }
    }

    private func requestNotificationAuthorizationIfNeeded() {
        guard isRunningFromAppBundle else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func postNotification(identifier: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
