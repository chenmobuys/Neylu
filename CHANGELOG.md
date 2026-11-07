# Changelog

## [Unreleased]

- Inspect recorded CPU, GPU, memory, and network samples with synchronized time markers, mouse hover, and Left/Right Arrow navigation.
- Optionally check GitHub once a day in the background; show an update indicator in settings without automatically opening a window or downloading an installer.
- Unmount detail charts and their uptime timeline while hidden; preserve background sampling and the existing batched history writes.
- Add Escape dismissal to utility windows and opaque semantic backgrounds for Reduce Transparency / Increase Contrast; respect Reduce Motion when resizing update windows.
- 图表支持悬浮与左右方向键查看实际采样，CPU、GPU、内存、网络共用时间指示线。
- 后台每天检查一次更新，可关闭；设置按钮提示新版本，不自动弹窗、下载或安装。
- 详情关闭时卸载图表及运行时间视图，保持采样与原有批量历史写入；补充 Escape、减少透明度、提高对比度及减少动态效果的适配。

- Show bundled release notes once after an upgrade, with an always-available Release Notes menu item. First launches establish a version baseline without opening a window; restarts and downgrades do not prompt.
- 升级后首次启动展示本地更新说明，设置菜单可随时打开更新日志；首次运行仅建立版本基线，重复启动和降级不弹窗。

## [0.1.0-alpha.3] - 2026-11-07

<!-- neylu:en -->
### English

- **Formatted release notes:** The software update window now renders Markdown headings, lists, emphasis, code, and links as native rich text instead of displaying Markdown syntax.
- **Native appearance:** Release notes follow the system's light or dark appearance and the selected language. Long notes remain scrollable.

This preview is ad hoc signed and is not notarized by Apple. See the README for first-launch instructions.

<!-- neylu:zh-Hans -->
### 中文

- **更新说明格式修复：** 软件更新窗口使用原生富文本渲染 Markdown，正确显示标题、列表、强调、代码与链接，不再直接展示 Markdown 源码。
- **原生外观适配：** 更新说明跟随系统深浅色外观及所选语言，较长内容可滚动查看。

本预发布版仅 ad-hoc 签名，未经 Apple 公证；首次打开方式见 README。

## [0.1.0-alpha.2] - 2026-11-07

<!-- neylu:en -->
### English

- **Adaptive startup charts:** Expand the available samples across the chart width, then gradually compress them as data accumulates. After two minutes, use a fixed rolling two-minute window.
- **Aligned history:** CPU, GPU, memory, and network charts share the same time range. If a long sampling pause leaves no recent history, restart with the adaptive range. Stored samples are unchanged.
- **First-launch guidance:** Homebrew now prints the `xattr` command with the actual installation path, in English and Chinese. Both READMEs include a combined install-and-approve command and the System Settings alternative. The cask does not execute the command automatically.

This preview is ad hoc signed and is not notarized by Apple. See the README for first-launch instructions.

<!-- neylu:zh-Hans -->
### 中文

- **自适应启动图表：** 初期按已有采样铺满宽度，随数据积累逐渐压缩；满两分钟后使用固定的两分钟滚动窗口。
- **统一时间范围：** CPU、GPU、内存和网络图表共用时间范围；长时间停采、近期数据全部过期后，重新自适应展开。不补写或修改采样数据。
- **首次启动说明：** Homebrew 安装完成后直接以中英文显示适配实际安装路径的 `xattr` 命令。中英文 README 增加安装与手动放行的组合命令，以及通过系统设置允许打开的方式；不会自动执行放行命令。

本预发布版仅 ad-hoc 签名，未经 Apple 公证；首次打开方式见 README。

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
