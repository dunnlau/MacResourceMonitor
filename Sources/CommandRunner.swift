import Foundation
import Darwin

struct CommandResult {
    let standardOutput: Data
    let standardError: Data
    let terminationStatus: Int32
    let timedOut: Bool

    var outputString: String {
        String(data: standardOutput, encoding: .utf8) ?? ""
    }

    var errorString: String {
        String(data: standardError, encoding: .utf8) ?? ""
    }
}

enum CommandRunner {
    static func run(
        _ executable: String,
        arguments: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval
    ) -> CommandResult? {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        if let environment { process.environment = environment }

        let stdout = outputPipe.fileHandleForReading.fileDescriptor
        let stderr = errorPipe.fileHandleForReading.fileDescriptor
        guard fcntl(stdout, F_SETFL, O_NONBLOCK) != -1,
              fcntl(stderr, F_SETFL, O_NONBLOCK) != -1 else { return nil }
        defer {
            try? outputPipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
        }
        do { try process.run() } catch { return nil }

        let deadline = ProcessInfo.processInfo.systemUptime + max(0.1, timeout)
        var output = Data()
        var errors = Data()
        var timedOut = false
        while true {
            drain(stdout, into: &output)
            drain(stderr, into: &errors)
            if !process.isRunning {
                drain(stdout, into: &output)
                drain(stderr, into: &errors)
                break
            }
            if ProcessInfo.processInfo.systemUptime >= deadline {
                timedOut = true
                stop(process)
                drain(stdout, into: &output)
                drain(stderr, into: &errors)
                break
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        // Never wait for EOF: descendants can retain the pipe after the helper exits.
        guard !process.isRunning else { return nil }
        return CommandResult(
            standardOutput: output,
            standardError: errors,
            terminationStatus: process.terminationStatus,
            timedOut: timedOut
        )
    }

    private static func drain(_ fd: Int32, into data: inout Data) {
        var buffer = [UInt8](repeating: 0, count: 8192)
        // Bound each pass so a continuously writing process cannot starve the deadline.
        for _ in 0..<64 {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { return }
            data.append(contentsOf: buffer.prefix(count))
        }
    }

    private static func stop(_ process: Process) {
        func children(of pid: pid_t) -> [pid_t] {
            var pids = [pid_t](repeating: 0, count: 256)
            guard proc_listchildpids(pid, &pids, Int32(pids.count * MemoryLayout<pid_t>.size)) > 0 else {
                return []
            }
            return pids.filter { $0 > 0 }
        }
        var descendants = Set<pid_t>()
        var pending = children(of: process.processIdentifier)
        while let pid = pending.popLast(), descendants.count < 256 {
            guard descendants.insert(pid).inserted else { continue }
            pending.append(contentsOf: children(of: pid))
        }
        for pid in descendants { kill(pid, SIGKILL) }
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
