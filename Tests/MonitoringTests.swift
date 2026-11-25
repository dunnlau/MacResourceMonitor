import Foundation

@main
struct MonitoringTests {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    @MainActor static func main() throws {
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

        let largeOutput = CommandRunner.run(
            "/bin/sh",
            arguments: ["-c", "dd if=/dev/zero bs=1024 count=700 2>/dev/null | tr '\\0' 'a'"],
            timeout: 5
        )
        expect(largeOutput?.standardOutput.count == 700 * 1024, "large output >512KB must not be truncated")
        expect(largeOutput?.exceededOutputLimit == false && largeOutput?.timedOut == false, "large output within limit succeeds")

        expect(CommandRunner.run("/does/not/exist", arguments: [], timeout: 0.1) == nil, "launch failure")
        print("CommandRunner: timeout, inherited pipes, dual-stream output, >512KB drain, exit status passed")

        expect(ProcessTrafficClassifier.isProxyTunnel(leafName: "Surge-Helper", topAppName: "Surge", isAppExtension: false), "Surge recognized as proxy")
        expect(ProcessTrafficClassifier.isProxyTunnel(leafName: "Stash", topAppName: "Stash", isAppExtension: false), "Stash recognized as proxy")
        expect(ProcessTrafficClassifier.isProxyTunnel(leafName: "mihomo", topAppName: nil, isAppExtension: false), "mihomo recognized as proxy")
        expect(!ProcessTrafficClassifier.isProxyTunnel(leafName: "Balloon", topAppName: "Balloon", isAppExtension: false), "Balloon must not match loon")
        expect(!ProcessTrafficClassifier.isProxyTunnel(leafName: "MyTool", topAppName: "MyStashHelper", isAppExtension: false), "substring stash in unrelated name must not match")
        print("ProcessTrafficClassifier: exact token and substring rules passed")

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

        expect(StorageMetricsMath.rate(previousBytes: 1000, currentBytes: 3000, elapsedSeconds: 2.0) == 1000.0, "storage rate diff")
        expect(StorageMetricsMath.rate(previousBytes: 3000, currentBytes: 1000, elapsedSeconds: 2.0) == 0.0, "storage rate underflow guard")
        expect(StorageMetricsMath.purgeableBytes(importantAvailable: 10_000, standardAvailable: 6_000) == 4_000, "purgeable space diff")
        expect(StorageMetricsMath.purgeableBytes(importantAvailable: 5_000, standardAvailable: 6_000) == 0, "purgeable non-negative")

        let health = BatteryDiagnosticsParser.computeHealthPercent(maxCapacityMAh: 4500, designCapacityMAh: 5000)
        expect(health == 90.0, "battery health percentage")
        expect(BatteryDiagnosticsParser.computeHealthPercent(maxCapacityMAh: 5200, designCapacityMAh: 5000) == 100.0, "battery health clamped to 100")

        let sampleAssertions = """
        Assertion status system-wide:
           PreventUserIdleSystemSleep             1
        Listed by owning process:
           pid 412(caffeinate): [0x00000123000180ab] 00:12:34 PreventUserIdleSystemSleep named: "caffeinate command-line tool"
           pid 901(Chrome): [0x00000123000180ac] 00:05:10 PreventUserIdleDisplaySleep named: "Playing video"
           pid 100(powerd): [0x00000123000180ad] 00:01:00 BackgroundTask named: "Ignore me"
        """
        let parsedAssertions = BatteryDiagnosticsParser.parseSleepAssertions(sampleAssertions)
        expect(parsedAssertions.count == 2, "only sleep-preventing assertions parsed")
        expect(parsedAssertions[0].pid == 412 && parsedAssertions[0].processName == "caffeinate", "first assertion parsed")
        expect(parsedAssertions[1].pid == 901 && parsedAssertions[1].reason == "Playing video", "second assertion reason parsed")
        print("Storage & Battery diagnostics: rate math, purgeable bytes, health, sleep assertions passed")

        let lsofSample = """
        p1234
        cnode
        PTCP
        n127.0.0.1:3000
        n[::1]:3000
        p5678
        cpython3
        PTCP
        n*:8080
        """
        let ports = LocalPortsParser.parseLsofFieldOutput(lsofSample)
        expect(ports.count == 3, "lsof parsed three TCP listeners")
        expect(ports[0].port == 3000 && ports[0].isLoopbackOnly, "loopback IPv4 listener detected")
        expect(ports[1].ipVersion == "IPv6" && ports[1].isLoopbackOnly, "loopback IPv6 listener detected")
        expect(ports[2].port == 8080 && !ports[2].isLoopbackOnly, "wildcard listener detected")

        let pingSample = "64 bytes from 1.1.1.1: icmp_seq=0 ttl=57 time=14.823 ms\n"
        expect(NetworkDiagnosticsParser.parsePingLatencyMs(pingSample) == 14.823, "ping RTT parsed")
        expect(NetworkDiagnosticsParser.parsePingLatencyMs("Request timeout for icmp_seq 0") == nil, "timeout returns nil")

        expect(PeripheralClassifier.inferCategory(for: "AirPods Pro") == "音频设备", "AirPods category")
        expect(PeripheralClassifier.inferCategory(for: "Magic Keyboard") == "键盘", "Keyboard category")
        expect(PeripheralClassifier.inferCategory(for: "Magic Trackpad") == "触控板", "Trackpad category")

        let kelvinTemp = BatteryDiagnosticsParser.normalizeTemperatureCelsius(30150)
        expect(kelvinTemp != nil && abs(kelvinTemp! - 28.35) < 0.05, "centikelvin battery temp normalized")
        expect(BatteryDiagnosticsParser.normalizeTemperatureCelsius(2985) == 29.85, "centidegrees battery temp normalized")
        expect(BatteryDiagnosticsParser.normalizeTemperatureCelsius(31) == 31.0, "whole-degree battery temp normalized")

        let spPowerJSON = Data(#"{"SPPowerDataType":[{"sppower_battery_health_info":{"sppower_battery_health":"Good","sppower_battery_health_maximum_capacity":"96%","sppower_battery_cycle_count":107}}]}"#.utf8)
        let spPower = BatteryDiagnosticsParser.parseSystemProfilerPowerJSON(spPowerJSON)
        expect(spPower.healthPercent == 96.0 && spPower.condition == "正常" && spPower.cycleCount == 107, "system_profiler battery health parsed")

        let preferredV6 = NetworkDiagnosticsParser.preferredIPv6(from: ["fe80::1%en0", "240e:1234::88", "::1"])
        expect(preferredV6 == "240e:1234::88", "global IPv6 preferred over link-local")
        expect(NetworkDiagnosticsParser.preferredIPv6(from: ["fe80::abcd%en0"]) == "fe80::abcd", "link-local IPv6 fallback strips scope")

        let spBluetoothJSON = Data(#"""
        {
          "SPBluetoothDataType": [
            {
              "device_connected": [
                {
                  "Keychron M6 8K": {
                    "device_address": "AA:BB:CC:DD:EE:FF",
                    "device_batteryLevelMain": "81%",
                    "device_minorType": "Mouse"
                  }
                },
                {
                  "AirPods Pro": {
                    "device_address": "11:22:33:44:55:66",
                    "device_batteryLevelLeft": "95%",
                    "device_batteryLevelRight": "90%",
                    "device_batteryLevelCase": "72%",
                    "device_minorType": "Headphones"
                  }
                }
              ]
            }
          ]
        }
        """#.utf8)
        let btDevices = PeripheralsBluetoothParser.parseSystemProfilerBluetoothJSON(spBluetoothJSON)
        expect(btDevices.count == 4, "Bluetooth profiler parsed main mouse + AirPods L/R/Case")
        let keychron = btDevices.first { $0.name == "Keychron M6 8K" }
        expect(keychron?.batteryPercent == 81 && keychron?.category == "鼠标", "Keychron M6 8K parsed as mouse with 81%")
        let iokitDup = [
            PeripheralBatteryItem(id: "aabbccddeeff", name: "Keychron M6 8K", category: "无线外设", batteryPercent: 81, transport: "Bluetooth"),
            PeripheralBatteryItem(id: "dongle-1", name: "USB Wireless Keyboard", category: "键盘", batteryPercent: 55, transport: "USB")
        ]
        let mergedDevices = PeripheralsBluetoothParser.mergeBatteryDevices(iokit: iokitDup, bluetooth: btDevices)
        expect(mergedDevices.count == 5, "deduplicates overlapping Bluetooth/IOKit device while keeping unique IOKit device")
        expect(mergedDevices.first?.name == "USB Wireless Keyboard", "merged devices sorted by battery percent ascending")
        print("LocalPorts, NetworkDiagnostics, Peripherals & Battery profiler parsers passed")
    }
}
