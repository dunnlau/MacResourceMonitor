import Foundation
import Combine
import Darwin

enum AIUsageProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case antigravity = "antigravity"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .antigravity: return "Antigravity"
        }
    }

    var symbol: String {
        switch self {
        case .antigravity: return "atom"
        }
    }

    var subtitle: String {
        switch self {
        case .antigravity: return "Antigravity 配额与模型用量"
        }
    }

    var defaultSource: String {
        switch self {
        case .antigravity: return "auto"
        }
    }
}

struct AIUsageWindow: Decodable, Equatable, Sendable {
    let usedPercent: Double?
    let windowMinutes: Int?
    let resetsAt: Date?
    let isSyntheticPlaceholder: Bool?

    var remainingPercent: Double? {
        guard isSyntheticPlaceholder != true, let usedPercent, usedPercent.isFinite else { return nil }
        return min(100, max(0, 100 - usedPercent))
    }

    var periodTitle: String {
        guard let minutes = windowMinutes, minutes > 0 else { return "额度窗口" }
        if minutes % 1440 == 0 { return "\(minutes / 1440) 天额度" }
        if minutes % 60 == 0 { return "\(minutes / 60) 小时额度" }
        return "\(minutes) 分钟额度"
    }
}

typealias CodexQuotaWindow = AIUsageWindow

struct AIUsageNamedWindow: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let window: AIUsageWindow
}

struct AIUsageSnapshot: Equatable, Sendable {
    let provider: AIUsageProvider
    let primary: AIUsageWindow?
    let secondary: AIUsageWindow?
    let extraWindows: [AIUsageNamedWindow]
    let plan: String?
    let accountEmail: String?
    let updatedAt: Date

    init(
        provider: AIUsageProvider = .antigravity,
        primary: AIUsageWindow?,
        secondary: AIUsageWindow?,
        extraWindows: [AIUsageNamedWindow] = [],
        plan: String?,
        accountEmail: String? = nil,
        updatedAt: Date
    ) {
        self.provider = provider
        self.primary = primary
        self.secondary = secondary
        self.extraWindows = extraWindows
        self.plan = plan
        self.accountEmail = accountEmail
        self.updatedAt = updatedAt
    }

    func extraWindow(matching idSubstring: String) -> AIUsageWindow? {
        extraWindows.first { $0.id.localizedCaseInsensitiveContains(idSubstring) }?.window
    }
}

typealias CodexQuotaSnapshot = AIUsageSnapshot

enum AIUsageError: Error, Equatable, LocalizedError {
    case missingHelper
    case loginRequired(AIUsageProvider = .antigravity)
    case notRunning(AIUsageProvider = .antigravity)
    case unavailable(AIUsageProvider = .antigravity)
    case timedOut(AIUsageProvider = .antigravity)
    case invalidResponse(AIUsageProvider = .antigravity)

    static var loginRequired: AIUsageError { .loginRequired(.antigravity) }
    static var unavailable: AIUsageError { .unavailable(.antigravity) }
    static var timedOut: AIUsageError { .timedOut(.antigravity) }
    static var invalidResponse: AIUsageError { .invalidResponse(.antigravity) }

    var errorDescription: String? {
        switch self {
        case .missingHelper:
            return "额度组件缺失，请重新安装应用。"
        case .loginRequired(let provider):
            return "需要 \(provider.displayName) 登录授权。请在 \(provider.displayName) 中完成登录，再点击刷新。"
        case .notRunning(let provider):
            return "未检测到 \(provider.displayName) 运行。请启动 \(provider.displayName) IDE 或运行 agy。"
        case .unavailable(let provider):
            return "暂时无法读取 \(provider.displayName) 订阅额度，请检查网络及登录状态后重试。"
        case .timedOut(let provider):
            return "\(provider.displayName) 额度查询超时，请稍后重试。"
        case .invalidResponse(let provider):
            return "当前账号未返回可识别的 \(provider.displayName) 订阅额度。"
        }
    }
}

typealias CodexQuotaError = AIUsageError

enum CodexQuotaParser {
    private struct Payload: Decodable {
        let provider: String
        let source: String?
        let usage: Usage?
        let error: Failure?
    }
    private struct ExtraRateWindowPayload: Decodable {
        let id: String?
        let title: String?
        let window: AIUsageWindow?
    }
    private struct Usage: Decodable {
        let primary: AIUsageWindow?
        let secondary: AIUsageWindow?
        let extraRateWindows: [ExtraRateWindowPayload]?
        let accountEmail: String?
        let loginMethod: String?
        let identity: Identity?
    }
    private struct Identity: Decodable {
        let loginMethod: String?
        let accountEmail: String?
    }
    private struct Failure: Decodable { let message: String? }

    private static let knownAntigravityWindowKeys = [
        "gemini-5h",
        "gemini-weekly",
        "3p-5h",
        "3p-weekly"
    ]

    static func parse(
        _ data: Data,
        expectedProvider: AIUsageProvider = .antigravity,
        receivedAt: Date = Date()
    ) throws -> AIUsageSnapshot {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plainFormatter = ISO8601DateFormatter()
        plainFormatter.formatOptions = [.withInternetDateTime]

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            if let date = fractionalFormatter.date(from: value) { return date }
            guard let date = plainFormatter.date(from: value) else {
                throw CodexQuotaError.invalidResponse(expectedProvider)
            }
            return date
        }
        let payloads: [Payload]
        do { payloads = try decoder.decode([Payload].self, from: data) }
        catch { throw CodexQuotaError.invalidResponse(expectedProvider) }
        guard let payload = payloads.first(where: { $0.provider == expectedProvider.rawValue }) else {
            throw CodexQuotaError.invalidResponse(expectedProvider)
        }
        if let failure = payload.error {
            let message = (failure.message ?? "").lowercased()
            if message.contains("not detected") || message.contains("language server") || message.contains("launch") {
                throw CodexQuotaError.notRunning(expectedProvider)
            }
            if ["login", "sign in", "sign-in", "unauthorized", "credential", "auth", "401"]
                .contains(where: message.contains) {
                throw CodexQuotaError.loginRequired(expectedProvider)
            }
            throw CodexQuotaError.unavailable(expectedProvider)
        }
        guard let usage = payload.usage else {
            throw CodexQuotaError.invalidResponse(expectedProvider)
        }
        let rawPlan = usage.identity?.loginMethod ?? usage.loginMethod
        let normalizedPlan: String? = {
            guard let trimmed = rawPlan?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                return nil
            }
            return trimmed
        }()
        let isOfflineSource = payload.source?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "offline"
            || normalizedPlan?.lowercased() == "offline"
        let extraWindows: [AIUsageNamedWindow] = (usage.extraRateWindows ?? []).compactMap { item in
            guard let window = item.window, window.remainingPercent != nil else { return nil }
            let id = item.id ?? item.title ?? UUID().uuidString
            let title = item.title ?? window.periodTitle
            return AIUsageNamedWindow(id: id, title: title, window: window)
        }
        let hasKnownExtraWindow = extraWindows.contains { item in
            knownAntigravityWindowKeys.contains { key in
                item.id.localizedCaseInsensitiveContains(key)
            }
        }
        let hasRenderableQuota = usage.primary?.remainingPercent != nil
            || usage.secondary?.remainingPercent != nil
            || hasKnownExtraWindow
        if isOfflineSource || !hasRenderableQuota {
            throw isOfflineSource
                ? CodexQuotaError.notRunning(expectedProvider)
                : CodexQuotaError.invalidResponse(expectedProvider)
        }
        let email = usage.accountEmail ?? usage.identity?.accountEmail
        return AIUsageSnapshot(
            provider: expectedProvider,
            primary: usage.primary,
            secondary: usage.secondary,
            extraWindows: extraWindows,
            plan: normalizedPlan,
            accountEmail: email,
            updatedAt: receivedAt
        )
    }
}

private final class QuotaCancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

/// A bounded subprocess reader dedicated to the quota helper. Delegates to CommandRunner.
enum CodexQuotaProcess {
    static let maxOutputBytes = 2_000_000

    static func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval = 25,
        provider: AIUsageProvider = .antigravity,
        isCancelled: (() -> Bool)? = nil
    ) throws -> Data {
        if isCancelled?() == true || Task.isCancelled {
            throw CancellationError()
        }
        guard let result = CommandRunner.run(
            executable.path,
            arguments: arguments,
            environment: environment,
            currentDirectoryURL: FileManager.default.homeDirectoryForCurrentUser,
            timeout: timeout,
            maxOutputBytes: maxOutputBytes,
            isCancelled: { (isCancelled?() == true) || Task.isCancelled }
        ) else {
            throw CodexQuotaError.missingHelper
        }
        if result.cancelled {
            throw CancellationError()
        }
        if result.timedOut {
            throw CodexQuotaError.timedOut(provider)
        }
        if result.exceededOutputLimit {
            throw CodexQuotaError.invalidResponse(provider)
        }
        guard !result.standardOutput.isEmpty else {
            throw CodexQuotaError.unavailable(provider)
        }
        return result.standardOutput
    }
}

struct CodexQuotaProvider: Sendable {
    private static let workerQueue = DispatchQueue(
        label: "local.mac-resource-monitor.quota-worker",
        qos: .utility,
        attributes: .concurrent
    )

    let helperURL: URL
    let configURL: URL

    static var bundled: CodexQuotaProvider {
        let resources = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        return CodexQuotaProvider(
            helperURL: resources.appendingPathComponent("Helpers/CodexBar/CodexBarCLI"),
            configURL: resources.appendingPathComponent("CodexQuotaConfig.json")
        )
    }

    func fetch(provider: AIUsageProvider = .antigravity) async throws -> AIUsageSnapshot {
        let helperURL = self.helperURL
        let configURL = self.configURL
        let cancellation = QuotaCancellationFlag()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                Self.workerQueue.async {
                    do {
                        if cancellation.isCancelled {
                            throw CancellationError()
                        }
                        guard FileManager.default.isExecutableFile(atPath: helperURL.path),
                              FileManager.default.fileExists(atPath: configURL.path) else {
                            throw CodexQuotaError.missingHelper
                        }
                        var environment = ProcessInfo.processInfo.environment
                        let home = FileManager.default.homeDirectoryForCurrentUser.path
                        let paths = [
                            "/usr/sbin",
                            "/opt/homebrew/bin",
                            "/usr/local/bin",
                            "\(home)/.local/bin",
                            "/usr/bin",
                            "/bin"
                        ]
                        environment["PATH"] = paths.joined(separator: ":") + ":" + (environment["PATH"] ?? "")
                        environment["CODEXBAR_CONFIG"] = configURL.path
                        let arguments = [
                            "usage",
                            "--provider", provider.rawValue,
                            "--format", "json",
                            "--json-only",
                            "--source", "auto"
                        ]
                        let data = try CodexQuotaProcess.run(
                            executable: helperURL,
                            arguments: arguments,
                            environment: environment,
                            provider: provider,
                            isCancelled: { cancellation.isCancelled }
                        )
                        let snapshot = try CodexQuotaParser.parse(data, expectedProvider: provider)
                        continuation.resume(returning: snapshot)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }
}

enum CodexQuotaConsumer: Hashable { case dashboard, menuBar }

struct CodexQuotaState: Equatable {
    var snapshot: CodexQuotaSnapshot?
    var isRefreshing = false
    var error: CodexQuotaError?
}

@MainActor
final class CodexQuotaMonitor: ObservableObject {
    static let selectedProviderDefaultsKey = "MacResourceMonitor.SelectedAIProvider"

    @Published var selectedProvider: AIUsageProvider {
        didSet {
            guard selectedProvider != oldValue else { return }
            userDefaults?.set(selectedProvider.rawValue, forKey: Self.selectedProviderDefaultsKey)
            deactivate(provider: oldValue)
            if !consumers.isEmpty { refreshCurrent(force: false) }
        }
    }

    @Published private(set) var states: [AIUsageProvider: CodexQuotaState] = [
        .antigravity: CodexQuotaState()
    ]

    var state: CodexQuotaState {
        states[selectedProvider] ?? CodexQuotaState()
    }

    func state(for provider: AIUsageProvider) -> CodexQuotaState {
        states[provider] ?? CodexQuotaState()
    }

    private var consumers: Set<CodexQuotaConsumer> = []
    private var refreshTasks: [AIUsageProvider: Task<Void, Never>] = [:]
    private var scheduledTasks: [AIUsageProvider: Task<Void, Never>] = [:]
    private var generations: [AIUsageProvider: UInt64] = [.antigravity: 0]
    private var lastAttempts: [AIUsageProvider: TimeInterval] = [:]
    private let fetchProvider: @Sendable (AIUsageProvider) async throws -> AIUsageSnapshot
    private let interval: @Sendable () -> TimeInterval
    private let userDefaults: UserDefaults?

    init(
        defaultProvider: AIUsageProvider = .antigravity,
        fetchProvider: @escaping @Sendable (AIUsageProvider) async throws -> AIUsageSnapshot = { provider in
            try await CodexQuotaProvider.bundled.fetch(provider: provider)
        },
        interval: @escaping @Sendable () -> TimeInterval = {
            let info = ProcessInfo.processInfo
            return info.isLowPowerModeEnabled || info.thermalState == .serious || info.thermalState == .critical ? 300 : 60
        },
        userDefaults: UserDefaults? = nil
    ) {
        self.fetchProvider = fetchProvider
        self.interval = interval
        self.userDefaults = userDefaults
        if let stored = userDefaults?.string(forKey: Self.selectedProviderDefaultsKey),
           let provider = AIUsageProvider(rawValue: stored) {
            self.selectedProvider = provider
        } else {
            self.selectedProvider = defaultProvider
        }
    }

    convenience init(
        fetch: @escaping @Sendable () async throws -> AIUsageSnapshot,
        interval: @escaping @Sendable () -> TimeInterval = { 60 }
    ) {
        self.init(defaultProvider: .antigravity, fetchProvider: { _ in try await fetch() }, interval: interval, userDefaults: nil)
    }

    deinit {
        for (_, task) in refreshTasks { task.cancel() }
        for (_, task) in scheduledTasks { task.cancel() }
    }

    func setActive(_ active: Bool, for consumer: CodexQuotaConsumer) {
        if active { consumers.insert(consumer) } else { consumers.remove(consumer) }
        if consumers.isEmpty {
            for provider in AIUsageProvider.allCases {
                deactivate(provider: provider)
            }
        } else {
            refreshCurrent()
        }
    }

    private func deactivate(provider: AIUsageProvider) {
        generations[provider, default: 0] &+= 1
        refreshTasks[provider]?.cancel()
        refreshTasks[provider] = nil
        scheduledTasks[provider]?.cancel()
        scheduledTasks[provider] = nil
        if states[provider]?.isRefreshing == true {
            lastAttempts[provider] = nil
            var next = states[provider] ?? CodexQuotaState()
            next.isRefreshing = false
            states[provider] = next
        }
    }

    func refresh(force: Bool = false) {
        refreshCurrent(force: force)
    }

    func refreshCurrent(force: Bool = false) {
        refresh(provider: selectedProvider, force: force)
    }

    func refresh(provider: AIUsageProvider, force: Bool = false) {
        guard !consumers.isEmpty, provider == selectedProvider else { return }
        let currentState = states[provider] ?? CodexQuotaState()
        guard !currentState.isRefreshing else { return }

        let now = ProcessInfo.processInfo.systemUptime
        let shouldThrottle = !force && currentState.snapshot != nil && currentState.error == nil
        let remaining = interval() - (now - (lastAttempts[provider] ?? -1_000_000))
        if shouldThrottle, remaining > 0 {
            schedule(provider: provider, after: remaining)
            return
        }

        scheduledTasks[provider]?.cancel()
        lastAttempts[provider] = now
        generations[provider, default: 0] &+= 1
        let token = generations[provider, default: 0]

        var pending = currentState
        pending.isRefreshing = true
        states[provider] = pending

        let fetch = self.fetchProvider
        refreshTasks[provider] = Task { [weak self] in
            let result: Result<AIUsageSnapshot, Error>
            do {
                result = .success(try await fetch(provider))
            } catch {
                result = .failure(error)
            }

            guard !Task.isCancelled,
                  let self,
                  self.generations[provider] == token,
                  !self.consumers.isEmpty else { return }

            var next = self.states[provider] ?? CodexQuotaState()
            next.isRefreshing = false
            switch result {
            case let .success(snapshot):
                next.snapshot = snapshot
                next.error = nil
            case let .failure(error):
                let classified = error as? CodexQuotaError ?? .unavailable(provider)
                next.error = classified
                if case .loginRequired = classified {
                    next.snapshot = nil
                }
            }
            self.states[provider] = next
            self.refreshTasks[provider] = nil
            self.schedule(provider: provider, after: self.interval())
        }
    }

    private func schedule(provider: AIUsageProvider, after delay: TimeInterval) {
        guard !consumers.isEmpty, provider == selectedProvider else { return }
        scheduledTasks[provider]?.cancel()
        scheduledTasks[provider] = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(max(0.05, delay) * 1_000_000_000))
            } catch { return }
            guard !Task.isCancelled else { return }
            self?.refresh(provider: provider)
        }
    }
}
