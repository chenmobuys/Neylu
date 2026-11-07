# Changelog

## [Unreleased]

## [0.1.0-alpha.5] - 2026-11-08

<!-- neylu:en -->
### English

- **Clearer menus:** Keep menu bar display and appearance options at the top, group refresh interval, units, language, login, and automatic update checks under Preferences, and separate update and app information actions. Native menu items and submenus retain their identity as titles and states change.
- **macOS Monterey support:** Lower the minimum system requirement to macOS 12 for both Apple Silicon and Intel. Use a small bundled login helper on Monterey and AppKit for chart hover tracking. Preserve SMAppService on macOS 13+ and system glass on macOS 26+. macOS 12 has not yet been tested on a physical device.
- **Reliable update discovery:** Read architecture-specific static appcasts instead of the unauthenticated GitHub REST API, avoiding that API’s shared request limit. Keep the native update interface and existing installer verification without adding the Sparkle framework. Manual and background checks share a short-lived cache and in-flight requests; downloads stop when the last consumer cancels.
- **Automated distribution:** Verify published installers before generating static feeds and synchronizing Homebrew. Retain stable and preview history and each release’s actual minimum macOS requirement.

This preview is ad hoc signed and is not notarized by Apple. See the README for first-launch instructions. Earlier Alphas still use the GitHub API to check for updates; if an older version cannot find this release, download the DMG from the release page.

<!-- neylu:zh-Hans -->
### 中文

- **菜单重新整理：** 菜单栏显示与外观放在顶部，刷新间隔、单位进制、语言、开机启动和自动检查更新归入「偏好设置」，更新与软件信息单独分组。原生菜单和子菜单持续复用，更新文案与状态时不重建。
- **兼容 macOS Monterey：** Apple Silicon 与 Intel 均支持 macOS 12 及以上；Monterey 使用轻量内置登录辅助应用，图表悬浮读数统一采用 AppKit。13+ 保留 SMAppService，26+ 保留系统玻璃效果。macOS 12 尚未完成实机验证。
- **改进更新检查：** 使用架构独立的静态 appcast，避免未登录 GitHub REST API 的共享请求限额；保留原生更新界面与现有安装校验，不额外捆绑 Sparkle。手动与后台检查共用短时缓存和进行中的请求，最后一个调用取消时停止下载。
- **自动发布同步：** 校验已发布安装包后自动生成静态订阅并同步 Homebrew，保留正式版、测试版历史及各版本真实的最低系统要求。

本预发布版仅 ad-hoc 签名，未经 Apple 公证；首次打开方式见 README。更早的 Alpha 仍通过 GitHub API 检查更新，若旧版无法发现本次更新，请前往发布页下载 DMG。

## [0.1.0-alpha.4] - 2026-11-07

<!-- neylu:en -->
### English

- **Chart inspection:** Hover over CPU, GPU, memory, or network charts to inspect recorded samples with synchronized time markers. Use the Left and Right Arrow keys when a chart is focused. Timestamps include seconds; unavailable GPU counters remain unavailable.
- **Quiet update checks:** Check GitHub once a day in the background, with an update indicator on the settings button and the available version in its menu. Automatic checks can be disabled. No installer is downloaded or installed automatically.
- **Release notes after updates:** Bundle the current release notes for offline viewing and show them once after subsequent upgrades. The Release Notes menu item lets you reopen them at any time. First launches establish a version baseline silently; restarts, reinstalls of an already-seen version, and downgrades do not prompt.
- **Lower hidden-view overhead:** Unmount detail charts and their uptime timeline when the overview is closed; pause the menu bar settings preview while its window is hidden. Monitoring and batched history writes continue.
- **Native keyboard and accessibility support:** Add Escape dismissal to utility windows, keyboard chart inspection, and more descriptive accessibility text. Respect Reduce Transparency, Increase Contrast, and Reduce Motion where applicable.

This is the first version to track the last launched release. When upgrading from an earlier Alpha, open Release Notes from settings to view this release; automatic post-update notes begin with the next upgrade.

This preview is ad hoc signed and is not notarized by Apple. See the README for first-launch instructions.

<!-- neylu:zh-Hans -->
### 中文

- **图表读数：** 悬浮查看 CPU、GPU、内存、网络的实际采样，四项图表共用时间指示线；聚焦后可用左右方向键查看。时间精确到秒，GPU 缺失指标仍显示不可用。
- **安静检查更新：** 后台每天检查一次 GitHub，发现新版后在设置按钮显示提示点，菜单显示版本号；可关闭自动检查，不会自动下载安装包或安装更新。
- **升级后的更新说明：** 当前版本说明随 App 打包，支持离线查看；后续升级时只展示一次，设置中的「更新日志」可随时重新打开。首次运行只记录版本，重启、重装已展示版本及降级不重复弹窗。
- **降低隐藏界面开销：** 详情关闭时卸载图表及开机时间视图，菜单栏设置窗口隐藏后暂停预览更新；保持监控采样和批量历史写入。
- **原生键盘与辅助功能：** 工具窗口支持 Escape 关闭，图表支持键盘查看，补充辅助朗读信息，并适配减少透明度、提高对比度和减少动态效果设置。

本版首次开始记录已运行版本。从更早的 Alpha 升级后，可在设置的「更新日志」查看本次说明；下一次升级起会自动展示一次。

本预发布版仅 ad-hoc 签名，未经 Apple 公证；首次打开方式见 README。

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
