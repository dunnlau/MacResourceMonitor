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
  <img alt="Version" src="https://img.shields.io/badge/version-2.9.0-0A84FF">
  <img alt="CI" src="https://github.com/dunnlau/MacResourceMonitor/actions/workflows/ci.yml/badge.svg">
</p>

> Current version: **2.9.0 (Build 53)**

A native SwiftUI dashboard and menu bar monitor for system resources, per-process network traffic, and USB-C / Thunderbolt diagnostics. Light and dark appearances use distinct metric colors and clear text hierarchy.
## Download and Install

**[Download MacResourceMonitor-2.9.0.zip](https://github.com/dunnlau/MacResourceMonitor/releases/download/v2.9.0/MacResourceMonitor-2.9.0.zip)** · [Release notes and checksums](https://github.com/dunnlau/MacResourceMonitor/releases/latest)

Requires **macOS 26 or later and Apple Silicon**. Intel Macs and earlier macOS versions are not supported.

1. Download and extract the ZIP.
2. Quit any running copy, then drag **Mac资源监控.app** into Applications, replacing the old copy if updating.
3. Open the app from Applications. Closing the main window keeps the menu bar monitor running; click **退出 (Quit)** at the bottom of the menu popover to exit completely.

The app is ad-hoc signed, not Apple Developer ID signed or notarized. If macOS blocks opening it, review the source and use the approval option in **System Settings → Privacy & Security**. Do not disable system-wide security protections.

For an integrity check, download the matching `.zip.sha256` file into the same directory and run:

```zsh
shasum -a 256 -c MacResourceMonitor-2.9.0.zip.sha256
```

## Features

| Module | What it shows or does |
| --- | --- |
| System | **Overview**: CPU & memory load, 2-minute dual-series trend chart, Apple Silicon **P-Core / E-Core cluster breakdown**, **GPU utilization & memory**, core temperature, fan speed, top processes.<br>**Storage**: Live disk read/write throughput & 2-minute chart, primary NVMe SMART health, mounted volumes, purgeable space, and safe eject |
| Process Traffic | Shows available client counters behind `127.0.0.1` local system proxies and `utun` virtual interfaces; resolves `.app` host bundles and icons for `Helper` subprocesses; strips duplicate proxy/TUN daemon forwarding totals by default |
| Hardware & Power | **Ports & Cables**: Read-only inspection of USB-C, MagSafe, USB4, Thunderbolt, DisplayPort, negotiated USB-PD power limits, and cable E-Marker identity.<br>**Battery & Power**: Battery health %, cycle count, cell temperature/voltage/current, power breakdown, and **sleep-preventing process assertions** |

The menu bar popover provides an at-a-glance view of core system load, **top three active network processes**, and hardware power state.

## Refresh Policy and Low Power Design

- **Lightweight System Telemetry**: Refreshes every **2 seconds**. Closing the main window leaves the menu bar item displaying live CPU temperature and network throughput.
- **Fast Baseline & Visibility-Scoped Process Traffic**: `nettop` sampling runs only while the menu popover or Process Traffic view is open. Cold start uses a **0.32s fast differential baseline** for sub-second initial rates and reuses the in-memory baseline when switching tabs within 15 seconds; closing both views stops sampling immediately.

## Privacy, Safety, and Limits

- All hardware, process, and port metrics are processed locally in memory without uploading app telemetry and no kernel extensions, VPNs, or privileged daemons.
- Process traffic uses read-only byte counters from macOS `nettop` without inspecting domains, packet payloads, or connection contents.

Process attribution depends on the counters macOS exposes. Short-lived connections and traffic while sampling is paused may be missed; filtered proxy totals are not a full accounting of all traffic. Sensor and cable fields depend on hardware support.

## What's New in 2.9.0

- **Apple Silicon Compute Breakdown**: Add real-time P-Core vs E-Core per-core load bars and GPU utilization / active memory telemetry to the System Monitor overview.
- **Disk I/O & Storage Diagnostics**: Add an in-page **Storage** sub-tab under System Monitor with live disk read/write rates, 2-minute I/O trend chart, primary NVMe SMART health, mounted volume breakdown, purgeable space, and one-click safe eject.
- **Battery Health & Sleep Assertions**: Upgrade Ports into **Hardware & Power** with an in-page **Battery & Power** sub-tab showing battery health %, cycle count, cell temperature/voltage/current, power breakdown, and active sleep-preventing processes (`pmset -g assertions`).

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

- App version: 2.9.0
- Build: 53
- Bundle ID: `io.github.svsvnm.MacResourceMonitor`
- Target: macOS 26.0+, arm64
