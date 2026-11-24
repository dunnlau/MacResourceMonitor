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
  <img alt="Version" src="https://img.shields.io/badge/version-3.1.1-0A84FF">
  <img alt="CI" src="https://github.com/dunnlau/MacResourceMonitor/actions/workflows/ci.yml/badge.svg">
</p>

> 当前版本：**3.1.1（Build 58）**

基于 SwiftUI 的原生仪表盘与菜单栏监控，集中查看系统概览、磁盘存储、网络监控、电源与接口以及显示与外设状态。支持明暗主题，以不同指标色和清晰文字层级呈现数据。
## 下载与安装

**[下载 MacResourceMonitor-3.1.1.zip](https://github.com/dunnlau/MacResourceMonitor/releases/download/v3.1.1/MacResourceMonitor-3.1.1.zip)** · [发布说明与校验文件](https://github.com/dunnlau/MacResourceMonitor/releases/latest)

需要 **macOS 26 或更高版本，以及 Apple Silicon 芯片**。不支持 Intel Mac 和旧版 macOS。

1. 下载并解压 ZIP。
2. 退出正在运行的旧版，将 **Mac资源监控.app** 拖入“应用程序”；更新时替换旧副本。
3. 从“应用程序”打开。关闭主窗口后菜单栏监控仍会保持运行；需要完全退出时，在菜单弹窗底部点击“退出”。

应用采用 ad-hoc 签名，尚未进行 Apple Developer ID 签名或公证。如果 macOS 阻止打开，请确认来源后，在**系统设置 → 隐私与安全性**中使用对应的允许打开选项，不要关闭系统级安全保护。

如需校验下载完整性，将同名 `.zip.sha256` 文件下载到相同目录，运行：

```zsh
shasum -a 256 -c MacResourceMonitor-3.1.1.zip.sha256
```

## 功能概览

| 模块 | 功能 |
| --- | --- |
| 系统概览 | CPU/内存负载、2 分钟双轴走势、Apple Silicon **P/E 核分核负载**与 **GPU 利用率/显存**、温控风扇与高负载进程 |
| 磁盘存储 | 实时磁盘读写速率与 2 分钟走势、主磁盘 NVMe SMART 健康度、挂载卷宗容量、可清除空间与外接卷一键安全推出 |
| 网络监控 | **进程流量**：本地代理穿透、宿主 `.app` 归属与重复隧道流量剥离。<br>**本地端口**：监听中 TCP 端口列表、应用归属、一键复制/打开 `localhost` 与安全停止进程。<br>**网络诊断**：Wi-Fi 信号/信噪比/速率/频段信道、IP/网关/DNS/代理配置与网关/公网延迟走势 |
| 电源与接口 | **电池能耗**：电池健康度、官方电池状态、循环次数、电芯温度/电压/电流、实时充/放电功耗拆解与阻止休眠进程检测。<br>**接口线缆**：只读检测 USB-C、MagSafe、USB4、Thunderbolt、DisplayPort、USB-PD 协商功率上限与线缆 E-Marker 标识 |
| 显示与外设 | 已连显示器分辨率/刷新率/HDR 与蓝牙/HID 无线外设电量 |
| 偏好设置 | 顶部菜单栏显示项自由开关（温度/CPU/内存/网速/功耗）、高温与持续高负载本地通知提醒、开机自动启动（`SMAppService`） |

菜单栏弹窗集中展示核心负载指标、**当前活跃进程流量 Top 3** 与硬件供电状态。

## 刷新策略与低功耗设计

- **轻量系统遥测**：约每 **2 秒**采样一次。关闭主窗口后，菜单栏标题按你的自定义配置实时刷新。
- **按可见性启停的子监控**：进程流量（`nettop`）、本地端口（`lsof`）、网络延迟探测（`ping`）、磁盘 I/O 与外设扫描仅在对应页面可见时运行，离开或隐藏后立即停止。

## 隐私、安全与边界

- 所有硬件、进程、网络与端口数据均在本机内存中只读处理，无任何遥测上传，不安装内核扩展、VPN 或特权守护进程。
- 进程流量基于系统原生 `nettop` 快照，仅统计字节收发计数，不解析域名、不解密或检视任何网络通信内容。

进程归属取决于 macOS 暴露的计数器；短连接及暂停采样期间的流量可能遗漏，过滤后的代理数据不能作为完整流量账单。温度、风扇和线缆字段取决于硬件支持。

## 3.1.1 更新

- **严格对齐的 3 行 Bento Grid 概览布局**：移除原先高低错位、与上下列不对齐的 50/50 核心与 GPU 卡片以及重复的「系统环境」卡片，改为等高三卡英雄区 + 等高趋势与硬件区 + 全宽进程表。
- **全新环形仪表盘组件（`RadialGaugeRing`）**：桌面概览与菜单栏统一引入 280° 圆弧仪表盘，将 Apple Silicon P/E 核柱状矩阵与 GPU/显存统计自然融合进 CPU 与内存主卡。
- **侧边栏与图表细节打磨**：优化侧边栏选中态胶囊、修复走势图副标题截断，并将硬件与主机环境信息合并去重。

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

- App 版本：3.1.1
- Build：58
- Bundle ID：`io.github.svsvnm.MacResourceMonitor`
- 构建目标：macOS 26.0+，arm64
