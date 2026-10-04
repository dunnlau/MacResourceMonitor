<p align="right">
  简体中文 | <a href="README.md">English</a>
</p>

<p align="center">
  <img src="Assets/AppIcon.png" width="112" height="112" alt="Mac 资源监控图标">
</p>

<h1 align="center">Mac 资源监控</h1>

<p align="center">系统实时遥测、本地代理穿透进程流量、Codex & Antigravity 订阅配额与端口供电监测 — 纯粹、克制的原生 macOS 监控工具。</p>

<p align="center">
  <img alt="macOS 26+" src="https://img.shields.io/badge/macOS-26%2B-111111?logo=apple">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-arm64-0A84FF">
  <img alt="Version" src="https://img.shields.io/badge/version-2.8.0-0A84FF">
  <img alt="CI" src="https://github.com/dunnlau/MacResourceMonitor/actions/workflows/ci.yml/badge.svg">
</p>

> 当前版本：**2.8.0（Build 47）**

基于 SwiftUI 的原生仪表盘与菜单栏监控，集中查看系统资源、进程流量、Codex / Antigravity 订阅额度，以及 USB-C / 雷雳端口状态。支持明暗主题，以不同指标色和清晰文字层级呈现数据。
## 下载与安装

**[下载 MacResourceMonitor-2.8.0.zip](https://github.com/dunnlau/MacResourceMonitor/releases/download/v2.8.0/MacResourceMonitor-2.8.0.zip)** · [发布说明与校验文件](https://github.com/dunnlau/MacResourceMonitor/releases/latest)

需要 **macOS 26 或更高版本，以及 Apple Silicon 芯片**。不支持 Intel Mac 和旧版 macOS。

1. 下载并解压 ZIP。
2. 退出正在运行的旧版，将 **Mac资源监控.app** 拖入“应用程序”；更新时替换旧副本。
3. 从“应用程序”打开。关闭主窗口后菜单栏监控仍会保持运行；需要完全退出时，在菜单弹窗底部点击“退出”。

应用采用 ad-hoc 签名，尚未进行 Apple Developer ID 签名或公证。如果 macOS 阻止打开，请确认来源后，在**系统设置 → 隐私与安全性**中使用对应的允许打开选项，不要关闭系统级安全保护。

如需校验下载完整性，将同名 `.zip.sha256` 文件下载到相同目录，运行：

```zsh
shasum -a 256 -c MacResourceMonitor-2.8.0.zip.sha256
```

## 功能概览

| 模块 | 功能 |
| --- | --- |
| 系统监控 | CPU 负载、物理内存、2 分钟双轴走势图、核心温度、散热风扇、电池与充电功率、高负载进程与系统环境概览 |
| 进程流量 | 穿透 `127.0.0.1` 本地系统代理与 `utun` 虚拟网卡显示可归属的应用流量；自动将 `Helper` 子进程归属回宿主 `.app` 并渲染真实图标；默认剥离代理隧道守护进程的二次汇总流量 |
| AI 用量 | 同时支持 **OpenAI Codex**（5 小时会话 + 7 天每周窗口）与 **Google Antigravity**（Gemini 模型池 + Claude / GPT 模型池的 5 小时与 7 天双窗口）订阅配额监控与一键切换 |
| 接口监测 | 只读检测 USB-C、MagSafe、USB4、Thunderbolt、DisplayPort、USB-PD 协商功率上限与线缆 E-Marker 标识 |

菜单栏弹窗集中展示核心负载指标、**当前活跃进程流量 Top 3**、硬件供电状态以及可快速切换的 **Codex / Antigravity 额度摘要**。

## 刷新策略与低功耗设计

- **轻量系统遥测**：约每 **2 秒**采样一次。关闭主窗口后，菜单栏标题仍实时显示 CPU 温度与网络上下行速率。
- **进程流量极速基线与按需采样**：仅在菜单弹窗或“进程流量”页面可见时调用 `nettop` 采样。首次打开采用 **0.32 秒极速差分基线**快速出数，离开页面 15 秒内切回可直接复用内存基线；主窗口与菜单均隐藏后立即停止后台进程采样。
- **AI 配额按可见性启停**：仅在页面或菜单可见时最多每 **1 分钟**自动同步一次（低电量或高温状态下改为每 **5 分钟**），关闭窗口与菜单后停止配额轮询。

## 隐私、安全与边界

- 所有硬件、进程与端口数据均在本机内存中只读处理，无任何遥测上传，不安装内核扩展、VPN 或特权守护进程。
- 进程流量基于系统原生 `nettop` 快照，仅统计字节收发计数，不解析域名、不解密或检视任何网络通信内容。
- AI 配额集成通过内置只读 **CodexBar CLI v0.56.5** 查询当前已登录会话的剩余额度百分比，不读取对话内容、不导入浏览器 Cookie、不扫描历史账单。

进程归属取决于 macOS 暴露的计数器；短连接及暂停采样期间的流量可能遗漏，过滤后的代理数据不能作为完整流量账单。温度、风扇和线缆字段取决于硬件支持。

## 2.8.0 更新

- 重绘明暗主题：增加卡片层次、改善次要文字对比度，为 CPU、内存、温度与上下行流量设置独立指标色。
- 放大系统指标数值并增加彩色图标，便于快速阅读。
- Codex 与 Antigravity 额度改用圆环展示，菜单栏增加迷你圆环与低额度颜色提示。
- AI 平台切换按钮向辅助功能工具提供选中状态。
- 补充 ChatGPT 内置 CLI 与本地插件 app server 的 Codex CLI 查找路径。

历史版本说明保留在 [GitHub Releases](https://github.com/dunnlau/MacResourceMonitor/releases)。

## 构建与测试

需要 Xcode 26 Command Line Tools 或带 macOS 26 SDK 的 Xcode 26。构建脚本直接调用 Swift 编译器：

```zsh
git clone https://github.com/dunnlau/MacResourceMonitor.git
cd MacResourceMonitor
./build.sh
open "Mac资源监控.app"
```

运行自动化 CI 检查（元数据校验、Swift 严格类型检查、双 Provider 单元测试、应用构建与签名验证）：

```zsh
./Scripts/ci-check.sh
```

## 第三方组件

- [Stats](https://github.com/exelban/stats)：Apple SMC 访问方式参考。
- [WhatCable](https://github.com/darrylmorley/whatcable)：只读接口与线缆检测。
- [CodexBar](https://github.com/steipete/CodexBar)：通过其 CLI 查询 Codex 与 Antigravity 订阅配额。

版权和许可证见[第三方声明](THIRD_PARTY_NOTICES.md)与 [CodexBar 依赖许可证](Assets/CodexBarLicenses)。

## 版本信息

- App 版本：2.8.0
- Build：47
- Bundle ID：`io.github.svsvnm.MacResourceMonitor`
- 构建目标：macOS 26.0+，arm64
