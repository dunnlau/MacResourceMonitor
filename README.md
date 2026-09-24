<p align="right">
  <a href="README.zh-CN.md">简体中文</a> | English
</p>

<p align="center">
  <img src="Assets/AppIcon.png" width="112" height="112" alt="Mac Resource Monitor icon">
</p>

<h1 align="center">Mac Resource Monitor</h1>

<p align="center">Live system telemetry, proxy-aware process traffic, Codex & Antigravity quota tracking, and USB-C / Thunderbolt port diagnostics — in a clean, minimalist native macOS app.</p>

<p align="center">
  <img alt="macOS 26+" src="https://img.shields.io/badge/macOS-26%2B-111111?logo=apple">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-arm64-0A84FF">
  <img alt="Version" src="https://img.shields.io/badge/version-2.7.0-0A84FF">
  <img alt="CI" src="https://github.com/svsvnm/MacResourceMonitor/actions/workflows/ci.yml/badge.svg">
</p>

> Current version: **2.7.0 (Build 46)**

Built with SwiftUI using a restrained, modern minimalist macOS aesthetic (monochrome hierarchy with a single system blue accent) and a compact menu bar popover. Designed for zero-side-effect read-only hardware telemetry, proxy/TUN-penetrating per-process network attribution, dual AI provider quota monitoring (**Codex** & **Antigravity**), and USB-C / Thunderbolt power & cable inspection.

## Download and Install

**[Download MacResourceMonitor-2.7.0.zip](https://github.com/svsvnm/MacResourceMonitor/releases/download/v2.7.0/MacResourceMonitor-2.7.0.zip)** · [Release notes and checksums](https://github.com/svsvnm/MacResourceMonitor/releases/latest)

Requires **macOS 26 or later and Apple Silicon**. Intel Macs and earlier macOS versions are not supported.

1. Download and extract the ZIP.
2. Quit any running copy, then drag **Mac资源监控.app** into Applications, replacing the old copy if updating.
3. Open the app from Applications. Closing the main window keeps the menu bar monitor running; click **退出 (Quit)** at the bottom of the menu popover to exit completely.

The app is ad-hoc signed, not Apple Developer ID signed or notarized. If macOS blocks opening it, review the source and use the approval option in **System Settings → Privacy & Security**. Do not disable system-wide security protections.

For an integrity check, download the matching `.zip.sha256` file into the same directory and run:

```zsh
shasum -a 256 -c MacResourceMonitor-2.7.0.zip.sha256
```

## Features

| Module | What it shows or does |
| --- | --- |
| System | CPU and memory load, 2-minute dual-series trend chart, core temperature, fan speed, battery & charging power, top CPU processes, and system environment |
| Process Traffic | Captures real client apps behind `127.0.0.1` local system proxies and `utun` virtual interfaces; resolves `.app` host bundles and icons for `Helper` subprocesses; strips duplicate proxy/TUN daemon forwarding totals by default |
| AI Usage | Dual-provider subscription quota monitoring for **OpenAI Codex** (5h session + 7d weekly windows) and **Google Antigravity** (Gemini pool + Claude/GPT pool, 5h & 7d windows) with instant switching |
| Ports | Read-only inspection of USB-C, MagSafe, USB4, Thunderbolt, DisplayPort, negotiated USB-PD power limits, and cable E-Marker identity |

The menu bar popover provides an at-a-glance view of core system load, **top three active network processes**, hardware power state, and a switchable **Codex / Antigravity quota summary**.

## Refresh Policy and Low Power Design

- **Lightweight System Telemetry**: Refreshes every **2 seconds**. Closing the main window leaves the menu bar item displaying live CPU temperature and network throughput.
- **Fast Baseline & Visibility-Scoped Process Traffic**: `nettop` sampling runs only while the menu popover or Process Traffic view is open. Cold start uses a **0.32s fast differential baseline** for sub-second initial rates and reuses the in-memory baseline when switching tabs within 15 seconds; closing both views stops sampling immediately.
- **Visibility-Scoped AI Quota Polling**: Queries run at most once per **minute** while visible (or every **5 minutes** in Low Power Mode / elevated thermal pressure), stopping completely when hidden.

## Privacy, Safety, and Limits

- All hardware, process, and port metrics are processed locally in memory with zero telemetry upload and no kernel extensions, VPNs, or privileged daemons.
- Process traffic uses read-only byte counters from macOS `nettop` without inspecting domains, packet payloads, or connection contents.
- AI quota integration queries remaining subscription percentages via the bundled read-only **CodexBar CLI v0.56.5** without reading chat transcripts, importing browser cookies, or scanning billing history.

## What's New in 2.7.0

- **Modern Minimalist macOS Redesign**: Rebuilt the entire dashboard and menu bar popover with a calm monochrome + single system blue accent palette, merged the left sidebar into a single unified navigation list, and unified process rankings into a crisp native table layout.
- **Local Proxy & TUN Penetration in Process Traffic**: Captures real client apps routing through `127.0.0.1` proxies and `utun` interfaces, automatically strips duplicate forwarding totals from proxy daemons (Quantumult X, Surge, Clash, Mihomo, sing-box, etc.) with a one-click filter toggle, resolves parent `.app` bundles/icons for `Helper` processes, and cuts initial sampling latency to ~0.32s.
- **Antigravity Subscription Quota Support**: Upgraded AI Usage and the menu bar summary to support both **Codex** and **Antigravity**, displaying 5-hour and 7-day quota windows across Gemini and Claude/GPT model pools.
- **Streamlined Read-Only Architecture**: Removed legacy storage cleanup and app uninstallation tools to keep the app 100% read-only and lightweight.

Older release notes remain in [GitHub Releases](https://github.com/svsvnm/MacResourceMonitor/releases).

## Build and Test

Requires Xcode 26 Command Line Tools or Xcode 26 with a macOS 26 SDK:

```zsh
git clone https://github.com/svsvnm/MacResourceMonitor.git
cd MacResourceMonitor
./build.sh
open "Mac资源监控.app"
```

Run the full CI verification suite (metadata validation, strict Swift typecheck, multi-provider quota unit tests, fresh bundle build, and code signature checks):

```zsh
./Scripts/ci-check.sh
```

## Third-Party Components

- [Stats](https://github.com/exelban/stats): reference for Apple SMC access.
- [WhatCable](https://github.com/darrylmorley/whatcable): read-only port and cable diagnostics.
- [CodexBar](https://github.com/steipete/CodexBar): Codex and Antigravity subscription quota via its CLI.

See [third-party notices](THIRD_PARTY_NOTICES.md) and [CodexBar dependency licenses](Assets/CodexBarLicenses) for attribution and license texts.

## Version

- App version: 2.7.0
- Build: 46
- Bundle ID: `io.github.svsvnm.MacResourceMonitor`
- Target: macOS 26.0+, arm64
