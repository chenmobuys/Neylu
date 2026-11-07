# Changelog

## [Unreleased]

- 图表启动时按已有数据铺满，随采样积累逐渐压缩，满两分钟后固定滚动；四张图共用时间范围，无近期数据后恢复自适应展示。
- Expand startup charts to fit the available history, then settle into a shared rolling two-minute window as samples accumulate.

- 补充中英文 Homebrew 首次启动说明和一条命令完成安装及手动放行的方式；安装完成后直接显示适配实际安装路径的 `xattr` 提示，不自动执行。
- Document first-launch approval in English and Chinese, with a combined install command. Homebrew now prints the `xattr` instructions using the actual installation path without running them automatically.

## [0.1.0-alpha.1] - 2026-11-07

<!-- neylu:en -->
### English

First public Alpha of Neylu, a compact native system monitor for the macOS menu bar.

- Select and reorder network, memory, GPU, CPU, and system disk readings in one menu bar item.
- View CPU and GPU activity, memory usage, network transfer rates, and disk capacity and I/O in a native overview.
- Support mounted external disks and safe system eject controls.
- Choose automatic, light, or dark appearance; English or Simplified Chinese; refresh interval; and decimal or binary units.
- Keep monitoring history locally for 24 hours, without telemetry or monitoring-data uploads.
- Check GitHub Releases manually and install verified updates with rollback.
- Install from DMGs for Apple Silicon and Intel, or with `brew install --cask chenmobuys/tap/neylu`.

Requires macOS 13 or later. This Alpha is ad hoc signed and is not notarized by Apple. See the README for first-launch instructions. Application identifier: `io.github.chenmobuys.Neylu`.

<!-- neylu:zh-Hans -->
### 中文

Neylu 首个公开 Alpha，紧凑、原生的 macOS 菜单栏监控工具。

- 单个菜单栏项目显示网速、内存、GPU、CPU 和系统盘占用，支持勾选及拖动排序。
- 原生详情展示 CPU/GPU 活动、内存使用量、网络速度、磁盘容量与读写速度。
- 自动展示已挂载外接磁盘，支持系统安全弹出。
- 支持自动/浅色/深色外观、简体中文/英语、刷新间隔与十进制/二进制单位设置。
- 本机保留 24 小时监控历史，不收集遥测、不上传监控数据。
- 手动检查 GitHub 更新，校验安装包后替换并重启，失败时回滚。
- 提供 Apple Silicon 与 Intel 的 DMG，也可一行安装：`brew install --cask chenmobuys/tap/neylu`。

要求 macOS 13 或更新版本。本 Alpha 仅 ad-hoc 签名，未经 Apple 公证；首次打开方式见 README。应用标识统一为 `io.github.chenmobuys.Neylu`。
