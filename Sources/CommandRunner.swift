import Foundation
import Darwin

struct CommandResult {
    let standardOutput: Data
    let standardError: Data
    let terminationStatus: Int32
    let timedOut: Bool
    let exceededOutputLimit: Bool
    let cancelled: Bool

    init(
        standardOutput: Data,
        standardError: Data,
        terminationStatus: Int32,
        timedOut: Bool,
        exceededOutputLimit: Bool = false,
        cancelled: Bool = false
    ) {
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.terminationStatus = terminationStatus
        self.timedOut = timedOut
        self.exceededOutputLimit = exceededOutputLimit
        self.cancelled = cancelled
    }

    var outputString: String {
        String(data: standardOutput, encoding: .utf8) ?? ""
    }

    var errorString: String {
        String(data: standardError, encoding: .utf8) ?? ""
    }
}

enum CommandRunner {
    static let defaultMaxOutputBytes = 8_000_000

    static func run(
        _ executable: String,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectoryURL: URL? = nil,
        timeout: TimeInterval,
        maxOutputBytes: Int = defaultMaxOutputBytes,
        isCancelled: (() -> Bool)? = nil
    ) -> CommandResult? {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        var closedWriteEnds = false
        defer {
            try? outputPipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
            if !closedWriteEnds {
                try? outputPipe.fileHandleForWriting.close()
                try? errorPipe.fileHandleForWriting.close()
            }
        }

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        if let environment { process.environment = environment }
        if let currentDirectoryURL { process.currentDirectoryURL = currentDirectoryURL }

        let stdout = outputPipe.fileHandleForReading.fileDescriptor
        let stderr = errorPipe.fileHandleForReading.fileDescriptor
        guard fcntl(stdout, F_SETFL, O_NONBLOCK) != -1,
              fcntl(stderr, F_SETFL, O_NONBLOCK) != -1 else { return nil }

        if isCancelled?() == true {
            return CommandResult(
                standardOutput: Data(),
                standardError: Data(),
                terminationStatus: -1,
                timedOut: false,
                exceededOutputLimit: false,
                cancelled: true
            )
        }

        do { try process.run() } catch { return nil }
        try? outputPipe.fileHandleForWriting.close()
        try? errorPipe.fileHandleForWriting.close()
        closedWriteEnds = true

        let deadline = ProcessInfo.processInfo.systemUptime + max(0.1, timeout)
        let byteLimit = max(1, maxOutputBytes)
        var output = Data()
        var errors = Data()
        var totalRead = 0
        var timedOut = false
        var exceededOutputLimit = false
        var cancelled = false

        while true {
            if drain(stdout, into: &output, totalRead: &totalRead, limit: byteLimit, maxPasses: 64)
                || drain(stderr, into: &errors, totalRead: &totalRead, limit: byteLimit, maxPasses: 64) {
                exceededOutputLimit = true
                stop(process)
                break
            }
            if isCancelled?() == true {
                cancelled = true
                stop(process)
                break
            }
            if !process.isRunning {
                // Drain completely after process exit (still bounded by byteLimit).
                if drain(stdout, into: &output, totalRead: &totalRead, limit: byteLimit, maxPasses: nil)
                    || drain(stderr, into: &errors, totalRead: &totalRead, limit: byteLimit, maxPasses: nil) {
                    exceededOutputLimit = true
                }
                break
            }
            if ProcessInfo.processInfo.systemUptime >= deadline {
                timedOut = true
                stop(process)
                _ = drain(stdout, into: &output, totalRead: &totalRead, limit: byteLimit, maxPasses: 64)
                _ = drain(stderr, into: &errors, totalRead: &totalRead, limit: byteLimit, maxPasses: 64)
                break
            }
            Thread.sleep(forTimeInterval: 0.01)
        }

        let status: Int32 = process.isRunning ? -1 : process.terminationStatus
        if !timedOut && !exceededOutputLimit && !cancelled && process.isRunning {
            return nil
        }
        return CommandResult(
            standardOutput: output,
            standardError: errors,
            terminationStatus: status,
            timedOut: timedOut,
            exceededOutputLimit: exceededOutputLimit,
            cancelled: cancelled
        )
    }

    /// Returns `true` if `limit` was exceeded while draining.
    private static func drain(
        _ fd: Int32,
        into data: inout Data,
        totalRead: inout Int,
        limit: Int,
        maxPasses: Int?
    ) -> Bool {
        var buffer = [UInt8](repeating: 0, count: 8192)
        var pass = 0
        while maxPasses == nil || pass < maxPasses! {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0 {
                if errno == EINTR { continue }
                return false
            }
            guard count > 0 else { return false }
            totalRead += count
            if totalRead > limit {
                return true
            }
            data.append(contentsOf: buffer.prefix(count))
            pass += 1
        }
        return false
    }

    private static func stop(_ process: Process) {
        func children(of pid: pid_t) -> [pid_t] {
            var pids = [pid_t](repeating: 0, count: 256)
            let bytes = proc_listchildpids(pid, &pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
            guard bytes > 0 else { return [] }
            let count = min(Int(bytes) / MemoryLayout<pid_t>.stride, pids.count)
            return pids.prefix(count).filter { $0 > 0 }
        }
        var descendants: [pid_t] = []
        var seen = Set<pid_t>()
        var pending = children(of: process.processIdentifier)
        while let pid = pending.popLast(), descendants.count < 256 {
            guard seen.insert(pid).inserted else { continue }
            descendants.append(pid)
            pending.append(contentsOf: children(of: pid))
        }
        for pid in descendants.reversed() { kill(pid, SIGKILL) }
        if process.isRunning { process.terminate() }
        var deadline = ProcessInfo.processInfo.systemUptime + 0.2
        while process.isRunning, ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        deadline = ProcessInfo.processInfo.systemUptime + 0.2
        while process.isRunning, ProcessInfo.processInfo.systemUptime < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
    }
}
