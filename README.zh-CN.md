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
  <img alt="Version" src="https://img.shields.io/badge/version-2.7.0-0A84FF">
  <img alt="CI" src="https://github.com/svsvnm/MacResourceMonitor/actions/workflows/ci.yml/badge.svg">
</p>

> 当前版本：**2.7.0（Build 46）**

基于 SwiftUI 构建，采用现代简约的原生 macOS 视觉语言（单主色 + 中性灰阶体系）与紧凑菜单栏弹窗。专注于零副作用的只读硬件遥测、可穿透本地代理与 TUN 虚拟网卡的真实应用流量排行、双 AI 平台（Codex 与 Antigravity）订阅额度追踪，以及 USB-C / 雷雳接口协商状态检测。

## 下载与安装

**[下载 MacResourceMonitor-2.7.0.zip](https://github.com/svsvnm/MacResourceMonitor/releases/download/v2.7.0/MacResourceMonitor-2.7.0.zip)** · [发布说明与校验文件](https://github.com/svsvnm/MacResourceMonitor/releases/latest)

需要 **macOS 26 或更高版本，以及 Apple Silicon 芯片**。不支持 Intel Mac 和旧版 macOS。

1. 下载并解压 ZIP。
2. 退出正在运行的旧版，将 **Mac资源监控.app** 拖入“应用程序”；更新时替换旧副本。
3. 从“应用程序”打开。关闭主窗口后菜单栏监控仍会保持运行；需要完全退出时，在菜单弹窗底部点击“退出”。

应用采用 ad-hoc 签名，尚未进行 Apple Developer ID 签名或公证。如果 macOS 阻止打开，请确认来源后，在**系统设置 → 隐私与安全性**中使用对应的允许打开选项，不要关闭系统级安全保护。

如需校验下载完整性，将同名 `.zip.sha256` 文件下载到相同目录，运行：

```zsh
shasum -a 256 -c MacResourceMonitor-2.7.0.zip.sha256
```

## 功能概览

| 模块 | 功能 |
| --- | --- |
| 系统监控 | CPU 负载、物理内存、2 分钟双轴走势图、核心温度、散热风扇、电池与充电功率、高负载进程与系统环境概览 |
| 进程流量 | 穿透 `127.0.0.1` 本地系统代理与 `utun` 虚拟网卡捕获真实耗流应用；自动将 `Helper` 子进程归属回宿主 `.app` 并渲染真实图标；默认剥离代理隧道守护进程的二次汇总流量 |
| AI 用量 | 同时支持 **OpenAI Codex**（5 小时会话 + 7 天每周窗口）与 **Google Antigravity**（Gemini 模型池 + Claude / GPT 模型池的 5 小时与 7 天双窗口）订阅配额监控与一键切换 |
| 接口监测 | 只读检测 USB-C、MagSafe、USB4、Thunderbolt、DisplayPort、USB-PD 协商功率上限与线缆 E-Marker 标识 |

菜单栏弹窗集中展示核心负载指标、**当前活跃进程流量 Top 3**、硬件供电状态以及可快速切换的 **Codex / Antigravity 额度摘要**。

## 刷新策略与低功耗设计

- **轻量系统遥测**：约每 **2 秒**采样一次。关闭主窗口后，菜单栏标题仍实时显示 CPU 温度与网络上下行速率。
- **进程流量极速基线与按需采样**：仅在菜单弹窗或“进程流量”页面可见时调用 `nettop` 采样。首次打开采用 **0.32 秒极速差分基线**快速出数，离开页面 15 秒内切回可直接复用内存基线；主窗口与菜单均隐藏后立即停止后台进程采样。
- **AI 配额按可见性启停**：仅在页面或菜单可见时最多每 **1 分钟**自动同步一次（低电量或高温状态下改为每 **5 分钟**），关闭窗口与菜单后零后台空转开销。

## 隐私、安全与边界

- 所有硬件、进程与端口数据均在本机内存中只读处理，无任何遥测上传，不安装内核扩展、VPN 或特权守护进程。
- 进程流量基于系统原生 `nettop` 快照，仅统计字节收发计数，不解析域名、不解密或检视任何网络通信内容。
- AI 配额集成通过内置只读 **CodexBar CLI v0.56.5** 查询当前已登录会话的剩余额度百分比，不读取对话内容、不导入浏览器 Cookie、不扫描历史账单。

## 2.7.0 更新

- **全新现代简约 macOS 界面重绘**：采用单主色（系统静谧蓝）+ 中性灰阶视觉体系，移除高饱和度杂乱色块；将左侧导航栏合并为统一单层列表，重绘紧凑型菜单栏弹窗与统一表格容器。
- **进程流量本地代理与 TUN 穿透**：支持捕获通过 `127.0.0.1` 系统代理与 `utun` 虚拟网卡发包的真实应用，自动识别并剥离 Quantumult X / Surge / Clash / Mihomo / sing-box 等隧道守护进程的重复汇总流量（支持一键切换显示），新增 `.app` 宿主应用归属解析与 `0.32s` 极速首屏差分采样。
- **新增 Antigravity 订阅配额监控**：AI 用量模块与菜单栏摘要升级为 **Codex + Antigravity 双平台架构**，支持按 Gemini 模型池与 Claude / GPT 模型池分别查看 5 小时短时限额与 7 天每周限额。
- **精简纯只读架构**：移除旧版存储清理与应用卸载模块，聚焦轻量、零副作用的系统与 AI 遥测体验。

历史版本说明保留在 [GitHub Releases](https://github.com/svsvnm/MacResourceMonitor/releases)。

## 构建与测试

需要 Xcode 26 Command Line Tools 或带 macOS 26 SDK 的 Xcode 26。构建脚本直接调用 Swift 编译器：

```zsh
git clone https://github.com/svsvnm/MacResourceMonitor.git
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

- App 版本：2.7.0
- Build：46
- Bundle ID：`io.github.svsvnm.MacResourceMonitor`
- 构建目标：macOS 26.0+，arm64
