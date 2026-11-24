<p align="right">
  简体中文 | <a href="README.md">English</a>
</p>

<p align="center">
  <img src="Assets/AppIcon.png" width="112" height="112" alt="Mac 资源监控图标">
</p>

<h1 align="center">Mac 资源监控</h1>

<p align="center">系统实时遥测、本地代理穿透进程流量与端口供电监测 — 纯粹、克制的原生 macOS 监控工具。</p>

<p align="center">
  <img alt="macOS 26+" src="https://img.shields.io/badge/macOS-26%2B-111111?logo=apple">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-arm64-0A84FF">
  <img alt="Version" src="https://img.shields.io/badge/version-2.9.0-0A84FF">
  <img alt="CI" src="https://github.com/dunnlau/MacResourceMonitor/actions/workflows/ci.yml/badge.svg">
</p>

> 当前版本：**2.9.0（Build 53）**

基于 SwiftUI 的原生仪表盘与菜单栏监控，集中查看系统资源、进程流量，以及 USB-C / 雷雳端口状态。支持明暗主题，以不同指标色和清晰文字层级呈现数据。
## 下载与安装

**[下载 MacResourceMonitor-2.9.0.zip](https://github.com/dunnlau/MacResourceMonitor/releases/download/v2.9.0/MacResourceMonitor-2.9.0.zip)** · [发布说明与校验文件](https://github.com/dunnlau/MacResourceMonitor/releases/latest)

需要 **macOS 26 或更高版本，以及 Apple Silicon 芯片**。不支持 Intel Mac 和旧版 macOS。

1. 下载并解压 ZIP。
2. 退出正在运行的旧版，将 **Mac资源监控.app** 拖入“应用程序”；更新时替换旧副本。
3. 从“应用程序”打开。关闭主窗口后菜单栏监控仍会保持运行；需要完全退出时，在菜单弹窗底部点击“退出”。

应用采用 ad-hoc 签名，尚未进行 Apple Developer ID 签名或公证。如果 macOS 阻止打开，请确认来源后，在**系统设置 → 隐私与安全性**中使用对应的允许打开选项，不要关闭系统级安全保护。

如需校验下载完整性，将同名 `.zip.sha256` 文件下载到相同目录，运行：

```zsh
shasum -a 256 -c MacResourceMonitor-2.9.0.zip.sha256
```

## 功能概览

| 模块 | 功能 |
| --- | --- |
| 系统监控 | **性能概览**：CPU/内存负载、2 分钟双轴走势、Apple Silicon **P/E 核分核负载**与 **GPU 利用率/显存**、温控风扇与高负载进程。<br>**磁盘存储**：实时磁盘读写速率与 2 分钟走势、主磁盘 NVMe SMART 健康度、挂载卷宗容量、可清除空间与外接卷一键安全推出 |
| 进程流量 | 穿透 `127.0.0.1` 本地系统代理与 `utun` 虚拟网卡显示可归属的应用流量；自动将 `Helper` 子进程归属回宿主 `.app` 并渲染真实图标；默认剥离代理隧道守护进程的二次汇总流量 |
| 硬件与供电 | **接口线缆**：只读检测 USB-C、MagSafe、USB4、Thunderbolt、DisplayPort、USB-PD 协商功率上限与线缆 E-Marker 标识。<br>**电池能耗**：电池健康度、循环次数、电芯温度/电压/电流、实时功耗拆解与**阻止休眠进程检测** |

菜单栏弹窗集中展示核心负载指标、**当前活跃进程流量 Top 3** 与硬件供电状态。

## 刷新策略与低功耗设计

- **轻量系统遥测**：约每 **2 秒**采样一次。关闭主窗口后，菜单栏标题仍实时显示 CPU 温度与网络上下行速率。
- **进程流量极速基线与按需采样**：仅在菜单弹窗或“进程流量”页面可见时调用 `nettop` 采样。首次打开采用 **0.32 秒极速差分基线**快速出数，离开页面 15 秒内切回可直接复用内存基线；主窗口与菜单均隐藏后立即停止后台进程采样。

## 隐私、安全与边界

- 所有硬件、进程与端口数据均在本机内存中只读处理，无任何遥测上传，不安装内核扩展、VPN 或特权守护进程。
- 进程流量基于系统原生 `nettop` 快照，仅统计字节收发计数，不解析域名、不解密或检视任何网络通信内容。

进程归属取决于 macOS 暴露的计数器；短连接及暂停采样期间的流量可能遗漏，过滤后的代理数据不能作为完整流量账单。温度、风扇和线缆字段取决于硬件支持。

## 2.9.0 更新

- **Apple Silicon 细粒度算力监控**：在「系统监控 → 性能概览」中新增 P-Core（性能核）/ E-Core（能效核）实时分核负载柱状图与 GPU 利用率/活跃显存遥测。
- **磁盘存储与实时 I/O**：在「系统监控」页内新增「磁盘存储」分段，提供实时读写速率、2 分钟双线走势图、主磁盘 NVMe SMART 健康度、挂载卷宗容量与可清除空间统计及外接卷安全推出。
- **电池健康与阻止休眠检测**：将侧边栏升级为「硬件与供电」，页内新增「电池能耗」分段，提供电池健康度、循环次数、电芯温压电流、实时功耗拆解及阻止休眠进程排查（`pmset -g assertions`）。

历史版本说明保留在 [GitHub Releases](https://github.com/dunnlau/MacResourceMonitor/releases)。

## 构建与测试

需要 Xcode 26 Command Line Tools 或带 macOS 26 SDK 的 Xcode 26。构建脚本直接调用 Swift 编译器：

```zsh
git clone https://github.com/dunnlau/MacResourceMonitor.git
cd MacResourceMonitor
./build.sh
open "Mac资源监控.app"
```

运行自动化 CI 检查（元数据校验、Swift 严格类型检查、单元测试、应用构建与签名验证）：

```zsh
./Scripts/ci-check.sh
```

## 第三方组件

- [Stats](https://github.com/exelban/stats)：Apple SMC 访问方式参考。
- [WhatCable](https://github.com/darrylmorley/whatcable)：只读接口与线缆检测。

版权和许可证见[第三方声明](THIRD_PARTY_NOTICES.md)。

## 版本信息

- App 版本：2.9.0
- Build：53
- Bundle ID：`io.github.svsvnm.MacResourceMonitor`
- 构建目标：macOS 26.0+，arm64
