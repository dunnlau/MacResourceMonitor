import Foundation

@main
struct MonitoringTests {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    static func main() throws {
        let start = ProcessInfo.processInfo.systemUptime
        let timeout = CommandRunner.run(
            "/bin/sh",
            arguments: ["-c", "trap '' TERM; /bin/sleep 30 & wait"],
            timeout: 0.1
        )
        expect(timeout?.timedOut == true, "timeout must be reported")
        expect(ProcessInfo.processInfo.systemUptime - start < 1.5, "descendant pipe must not block timeout")

        let exitedStart = ProcessInfo.processInfo.systemUptime
        let exited = CommandRunner.run(
            "/bin/sh",
            arguments: ["-c", "trap '' TERM; /bin/sleep 1 & printf ready; exit 0"],
            timeout: 0.2
        )
        expect(exited?.outputString == "ready", "output retained after parent exit")
        expect(exited?.timedOut == false, "exited parent must not time out")
        expect(ProcessInfo.processInfo.systemUptime - exitedStart < 0.7, "inherited pipe must not block parent exit")

        let data = CommandRunner.run(
            "/bin/sh",
            arguments: ["-c", "i=0; while [ $i -lt 3000 ]; do printf 'output1234567890\\n'; printf 'error1234567890\\n' >&2; i=$((i+1)); done; exit 7"],
            timeout: 5
        )
        expect(data?.standardOutput.count == 17 * 3000, "stdout fully drained")
        expect(data?.standardError.count == 16 * 3000, "stderr fully drained")
        expect(data?.terminationStatus == 7 && data?.timedOut == false, "nonzero exit status preserved")
        expect(CommandRunner.run("/does/not/exist", arguments: [], timeout: 0.1) == nil, "launch failure")
        print("CommandRunner: timeout, inherited pipes, dual-stream output, exit status passed")

        let model = ProcessNetworkMonitor()
        func sample(_ bytes: UInt64) -> ProcessTrafficCollectionResult {
            .success(rows: [
                ProcessTrafficSnapshot(pid: 123, name: "Example", subtitle: nil, bundlePath: nil, isProxyTunnel: false,
                                       processStartedAt: 1, downloadedBytes: bytes, uploadedBytes: bytes),
                ProcessTrafficSnapshot(pid: 124, name: "Tunnel", subtitle: nil, bundlePath: nil, isProxyTunnel: true,
                                       processStartedAt: 1, downloadedBytes: bytes, uploadedBytes: bytes)
            ])
        }
        model.apply(sample(0))
        Thread.sleep(forTimeInterval: 0.12)
        model.apply(sample(12000))
        expect(model.rows.first!.currentBytesPerSecond > 0, "live rates available")
        let cumulative = model.sessionDownloadedBytes
        model.apply(.failure("test failure"))
        expect(model.downloadBytesPerSecond == 0 && model.uploadBytesPerSecond == 0, "totals cleared on failure")
        expect(model.displayState.proxyTunnelDownloadBytesPerSecond == 0, "proxy live rates cleared")
        expect(model.displayState.allRows.allSatisfy { $0.currentBytesPerSecond == 0 }, "all row rates cleared")
        model.filterProxyTunnels = false
        expect(model.errorText == "test failure", "filter must retain sampling error")
        expect(model.rows.count == 2 && model.rows.allSatisfy { $0.currentBytesPerSecond == 0 }, "filter cannot revive stale rates")
        expect(model.sessionDownloadedBytes == cumulative, "failure retains accumulated bytes")
        model.filterProxyTunnels = true
        expect(model.errorText == "test failure", "both filter directions retain error")
        Thread.sleep(forTimeInterval: 0.12)
        model.apply(sample(24000))
        expect(model.errorText == nil && model.rows.first!.currentBytesPerSecond > 0, "successful sample recovers")
        print("Process traffic: failure, filter changes, cumulative retention, recovery passed")
    }
}
