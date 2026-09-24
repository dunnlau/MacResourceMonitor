import Foundation
import Combine
import Darwin

enum AIUsageProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case codex = "codex"
    case antigravity = "antigravity"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .antigravity: return "Antigravity"
        }
    }

    var symbol: String {
        switch self {
        case .codex: return "bolt.shield"
        case .antigravity: return "atom"
        }
    }

    var subtitle: String {
        switch self {
        case .codex: return "Codex 订阅额度"
        case .antigravity: return "Antigravity 配额与模型用量"
        }
    }

    var defaultSource: String {
        switch self {
        case .codex: return "cli"
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
        provider: AIUsageProvider = .codex,
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
    case loginRequired(AIUsageProvider)
    case notRunning(AIUsageProvider)
    case unavailable(AIUsageProvider)
    case timedOut(AIUsageProvider)
    case invalidResponse(AIUsageProvider)

    static var loginRequired: AIUsageError { .loginRequired(.codex) }
    static var unavailable: AIUsageError { .unavailable(.codex) }
    static var timedOut: AIUsageError { .timedOut(.codex) }
    static var invalidResponse: AIUsageError { .invalidResponse(.codex) }

    var errorDescription: String? {
        switch self {
        case .missingHelper:
            return "额度组件缺失，请重新安装应用。"
        case .loginRequired(let provider):
            switch provider {
            case .codex:
                return "需要 Codex 登录授权。请在 Codex 中完成登录，再点击刷新。"
            case .antigravity:
                return "需要 Antigravity 登录授权。请在 Antigravity 中完成登录，再点击刷新。"
            }
        case .notRunning(let provider):
            switch provider {
            case .antigravity:
                return "未检测到 Antigravity 运行。请启动 Antigravity IDE 或运行 agy。"
            case .codex:
                return "未检测到 Codex 运行环境。"
            }
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

    static func parse(
        _ data: Data,
        expectedProvider: AIUsageProvider = .codex,
        receivedAt: Date = Date()
    ) throws -> AIUsageSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: value) else {
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
        guard let usage = payload.usage,
              usage.primary?.remainingPercent != nil || usage.secondary?.remainingPercent != nil else {
            throw CodexQuotaError.invalidResponse(expectedProvider)
        }
        let extraWindows: [AIUsageNamedWindow] = (usage.extraRateWindows ?? []).compactMap { item in
            guard let window = item.window, window.remainingPercent != nil else { return nil }
            let id = item.id ?? item.title ?? UUID().uuidString
            let title = item.title ?? window.periodTitle
            return AIUsageNamedWindow(id: id, title: title, window: window)
        }
        let rawPlan = usage.identity?.loginMethod ?? usage.loginMethod
        let normalizedPlan: String? = {
            guard let rawPlan = rawPlan?.trimmingCharacters(in: .whitespacesAndNewlines), !rawPlan.isEmpty else {
                return nil
            }
            if rawPlan.lowercased() == "plus" { return "ChatGPT Plus" }
            if rawPlan.lowercased() == "pro" { return "ChatGPT Pro" }
            return rawPlan
        }()
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

/// A bounded subprocess reader dedicated to the optional quota helper. No shell, no unbounded pipe waits.
enum CodexQuotaProcess {
    static func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval = 25
    ) throws -> Data {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = errors
        let stdout = output.fileHandleForReading.fileDescriptor
        let stderr = errors.fileHandleForReading.fileDescriptor
        _ = fcntl(stdout, F_SETFL, O_NONBLOCK)
        _ = fcntl(stderr, F_SETFL, O_NONBLOCK)
        defer {
            try? output.fileHandleForReading.close()
            try? errors.fileHandleForReading.close()
        }
        try Task.checkCancellation()
        do { try process.run() } catch { throw CodexQuotaError.missingHelper }
        defer {
            if process.isRunning { stop(process) }
        }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var data = Data()
        var totalRead = 0
        repeat {
            try Task.checkCancellation()
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw CodexQuotaError.timedOut(.codex) }
            for fd in [stdout, stderr] {
                var buffer = [UInt8](repeating: 0, count: 8192)
                while true {
                    let count = Darwin.read(fd, &buffer, buffer.count)
                    guard count > 0 else { break }
                    totalRead += count
                    guard totalRead <= 2_000_000 else { throw CodexQuotaError.invalidResponse(.codex) }
                    if fd == stdout { data.append(contentsOf: buffer.prefix(count)) }
                }
            }
            if !process.isRunning {
                // Drain once more after exit; descendants retaining a pipe cannot block this reader.
                var buffer = [UInt8](repeating: 0, count: 8192)
                while true {
                    let count = Darwin.read(stdout, &buffer, buffer.count)
                    guard count > 0 else { break }
                    totalRead += count
                    guard totalRead <= 2_000_000 else { throw CodexQuotaError.invalidResponse(.codex) }
                    data.append(contentsOf: buffer.prefix(count))
                }
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        } while true
        guard !data.isEmpty else { throw CodexQuotaError.unavailable(.codex) }
        return data
    }

    private static func stop(_ process: Process) {
        func children(of pid: pid_t) -> [pid_t] {
            var pids = [pid_t](repeating: 0, count: 256)
            let count = proc_listchildpids(pid, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
            guard count > 0 else { return [] }
            return pids.prefix(min(Int(count), pids.count)).filter { $0 > 0 }
        }
        var descendants: [pid_t] = []
        var pending = children(of: process.processIdentifier)
        while !pending.isEmpty, descendants.count < 256 {
            let pid = pending.removeLast()
            guard !descendants.contains(pid) else { continue }
            descendants.append(pid)
            pending.append(contentsOf: children(of: pid))
        }
        // Only signal the children still descended from this live helper, before killing their parent.
        for pid in descendants.reversed() { kill(pid, SIGKILL) }
        if process.isRunning { process.terminate() }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.3
        while process.isRunning, ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
}

struct CodexQuotaProvider: Sendable {
    let helperURL: URL
    let configURL: URL

    static var bundled: CodexQuotaProvider {
        let resources = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        return CodexQuotaProvider(
            helperURL: resources.appendingPathComponent("Helpers/CodexBar/CodexBarCLI"),
            configURL: resources.appendingPathComponent("CodexQuotaConfig.json")
        )
    }

    func fetch(provider: AIUsageProvider = .codex) async throws -> AIUsageSnapshot {
        let worker = Task.detached(priority: .utility) { () throws -> AIUsageSnapshot in
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
                "/Applications/ChatGPT.app/Contents/Resources",
                "/Applications/Codex.app/Contents/Resources",
                "/usr/bin",
                "/bin"
            ]
            environment["PATH"] = paths.joined(separator: ":") + ":" + (environment["PATH"] ?? "")
            environment["CODEXBAR_CONFIG"] = configURL.path
            var arguments = [
                "usage",
                "--provider", provider.rawValue,
                "--format", "json",
                "--json-only"
            ]
            if provider == .codex {
                arguments.append(contentsOf: ["--source", "cli"])
            } else if provider == .antigravity {
                arguments.append(contentsOf: ["--source", "auto"])
            }
            let data: Data
            do {
                data = try CodexQuotaProcess.run(
                    executable: helperURL,
                    arguments: arguments,
                    environment: environment
                )
            } catch let error as CodexQuotaError {
                if case .timedOut = error {
                    throw CodexQuotaError.timedOut(provider)
                }
                throw error
            }
            return try CodexQuotaParser.parse(data, expectedProvider: provider)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
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
    @Published var selectedProvider: AIUsageProvider = .codex {
        didSet {
            if selectedProvider != oldValue, !consumers.isEmpty {
                refreshCurrent(force: false)
            }
        }
    }

    @Published private(set) var states: [AIUsageProvider: CodexQuotaState] = [
        .codex: CodexQuotaState(),
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
    private var generations: [AIUsageProvider: UInt64] = [.codex: 0, .antigravity: 0]
    private var lastAttempts: [AIUsageProvider: TimeInterval] = [:]
    private let fetchProvider: @Sendable (AIUsageProvider) async throws -> AIUsageSnapshot
    private let interval: @Sendable () -> TimeInterval

    init(
        fetchProvider: @escaping @Sendable (AIUsageProvider) async throws -> AIUsageSnapshot = { provider in
            try await CodexQuotaProvider.bundled.fetch(provider: provider)
        },
        interval: @escaping @Sendable () -> TimeInterval = {
            let info = ProcessInfo.processInfo
            return info.isLowPowerModeEnabled || info.thermalState == .serious || info.thermalState == .critical ? 300 : 60
        }
    ) {
        self.fetchProvider = fetchProvider
        self.interval = interval
    }

    convenience init(
        fetch: @escaping @Sendable () async throws -> AIUsageSnapshot,
        interval: @escaping @Sendable () -> TimeInterval = { 60 }
    ) {
        self.init(fetchProvider: { _ in try await fetch() }, interval: interval)
    }

    deinit {
        for (_, task) in refreshTasks { task.cancel() }
        for (_, task) in scheduledTasks { task.cancel() }
    }

    func setActive(_ active: Bool, for consumer: CodexQuotaConsumer) {
        if active { consumers.insert(consumer) } else { consumers.remove(consumer) }
        if consumers.isEmpty {
            for provider in AIUsageProvider.allCases {
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
        } else {
            refreshCurrent()
        }
    }

    func refresh(force: Bool = false) {
        refreshCurrent(force: force)
    }

    func refreshCurrent(force: Bool = false) {
        refresh(provider: selectedProvider, force: force)
    }

    func refresh(provider: AIUsageProvider, force: Bool = false) {
        guard !consumers.isEmpty else { return }
        let currentState = states[provider] ?? CodexQuotaState()
        guard !currentState.isRefreshing else { return }

        let now = ProcessInfo.processInfo.systemUptime
        let remaining = interval() - (now - (lastAttempts[provider] ?? -1_000_000))
        if !force, remaining > 0 {
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
