<p align="right">
  <a href="README.zh-CN.md">简体中文</a> | English
</p>

<p align="center">
  <img src="Assets/AppIcon.png" width="112" height="112" alt="Mac Resource Monitor icon">
</p>

<h1 align="center">Mac Resource Monitor</h1>

<p align="center">Live system telemetry, proxy-aware process traffic, and USB-C / Thunderbolt port diagnostics — in a clean, minimalist native macOS app.</p>

<p align="center">
  <img alt="macOS 26+" src="https://img.shields.io/badge/macOS-26%2B-111111?logo=apple">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-arm64-0A84FF">
  <img alt="Version" src="https://img.shields.io/badge/version-3.1.1-0A84FF">
  <img alt="CI" src="https://github.com/dunnlau/MacResourceMonitor/actions/workflows/ci.yml/badge.svg">
</p>

> Current version: **3.1.1 (Build 58)**

A native SwiftUI dashboard and menu bar monitor for system resources, disk storage, per-process network traffic, local listening ports, Wi-Fi diagnostics, battery health, hardware ports, and peripherals. Light and dark appearances use distinct metric colors and clear text hierarchy.
## Download and Install

**[Download MacResourceMonitor-3.1.1.zip](https://github.com/dunnlau/MacResourceMonitor/releases/download/v3.1.1/MacResourceMonitor-3.1.1.zip)** · [Release notes and checksums](https://github.com/dunnlau/MacResourceMonitor/releases/latest)

Requires **macOS 26 or later and Apple Silicon**. Intel Macs and earlier macOS versions are not supported.

1. Download and extract the ZIP.
2. Quit any running copy, then drag **Mac资源监控.app** into Applications, replacing the old copy if updating.
3. Open the app from Applications. Closing the main window keeps the menu bar monitor running; click **退出 (Quit)** at the bottom of the menu popover to exit completely.

The app is ad-hoc signed, not Apple Developer ID signed or notarized. If macOS blocks opening it, review the source and use the approval option in **System Settings → Privacy & Security**. Do not disable system-wide security protections.

For an integrity check, download the matching `.zip.sha256` file into the same directory and run:

```zsh
shasum -a 256 -c MacResourceMonitor-3.1.1.zip.sha256
```

## Features

| Module | What it shows or does |
| --- | --- |
| System Overview | CPU & memory load, 2-minute dual-series trend chart, Apple Silicon **P-Core / E-Core cluster breakdown**, **GPU utilization & memory**, core temperature, fan speed, top processes |
| Disk Storage | Live disk read/write throughput & 2-minute chart, primary NVMe SMART health, mounted volumes, purgeable space, and safe eject |
| Network Monitor | **Process Traffic**: Proxy-aware client traffic behind `127.0.0.1` & `utun`, `.app` host attribution, duplicate proxy tunnel stripping.<br>**Local Ports**: Listening TCP ports with app icons, PID, bind address, copy/open `localhost`, and safe `SIGTERM`.<br>**Network Diagnostics**: Wi-Fi RSSI/SNR/Tx rate/channel, IP/gateway/DNS/proxy config, and live gateway/internet latency chart |
| Power & Ports | **Battery & Power**: Battery health %, official condition, cycle count, cell temperature/voltage/current, charge/discharge power breakdown, and sleep-preventing assertions.<br>**Ports & Cables**: Read-only USB-C, MagSafe, USB4, Thunderbolt, DisplayPort, USB-PD power limits, and cable E-Marker identity |
| Displays & Peripherals | Connected displays (resolution, refresh rate, HDR/EDR) and Bluetooth/HID wireless peripheral batteries |
| Preferences | Customizable menu bar metrics (temperature, CPU, memory, network, power), thermal/CPU local notification thresholds, and launch at login (`SMAppService`) |

The menu bar popover provides an at-a-glance view of core system load, **top three active network processes**, and hardware power state.

## Refresh Policy and Low Power Design

- **Lightweight System Telemetry**: Refreshes every **2 seconds**. Closing the main window leaves the menu bar item displaying your chosen live metrics.
- **Visibility-Scoped Sub-Monitors**: Process traffic (`nettop`), local port scans (`lsof`), latency probes (`ping`), storage I/O, and peripheral scans run only while their respective view is visible and stop immediately when hidden.

## Privacy, Safety, and Limits

- All hardware, process, network, and port metrics are processed locally in memory without uploading app telemetry and no kernel extensions, VPNs, or privileged daemons.
- Process traffic uses read-only byte counters from macOS `nettop` without inspecting domains, packet payloads, or connection contents.

Process attribution depends on the counters macOS exposes. Short-lived connections and traffic while sampling is paused may be missed; filtered proxy totals are not a full accounting of all traffic. Sensor and cable fields depend on hardware support.

## What's New in 3.1.1

- **Aligned 3-Row Bento Grid Overview**: Replaced the uneven 50/50 Silicon/GPU row and duplicate System Details panel with a strictly aligned Bento Grid featuring equal-height paired rows and a full-width High-Load Processes table.
- **Radial Arc Gauges (`RadialGaugeRing`)**: Added 280° radial gauges for CPU and Memory across both the desktop Hero Bento Trio (integrating compact P/E-Core equalizer bars and GPU/VRAM stats) and the menu bar popover.
- **Refined Sidebar & Chart Polish**: Cleaned up active sidebar pills, fixed chart subtitle truncation, and unified hardware & host info into a single non-duplicated panel.

Older release notes remain in [GitHub Releases](https://github.com/dunnlau/MacResourceMonitor/releases).

## Build and Test

Requires Xcode 26 Command Line Tools or Xcode 26 with a macOS 26 SDK:

```zsh
git clone https://github.com/dunnlau/MacResourceMonitor.git
cd MacResourceMonitor
./build.sh
open "Mac资源监控.app"
```

Run the full CI verification suite (metadata validation, strict Swift typecheck, monitoring unit tests, fresh bundle build, and code signature checks):

```zsh
./Scripts/ci-check.sh
```

## Third-Party Components

- [Stats](https://github.com/exelban/stats): reference for Apple SMC access.
- [WhatCable](https://github.com/darrylmorley/whatcable): read-only port and cable diagnostics.

See [third-party notices](THIRD_PARTY_NOTICES.md) for attribution and license texts.

## Version

- App version: 3.1.1
- Build: 58
- Bundle ID: `io.github.svsvnm.MacResourceMonitor`
- Target: macOS 26.0+, arm64
