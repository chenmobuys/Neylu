# Changelog

## [Unreleased]

## [0.1.0-rc.1] - 2026-11-08

<!-- neylu:en -->
### English

- Add compact and standard menu bar spacing with a live preview and saved preferences; preserve stable rate-field widths across unit transitions.
- Show original download and upload samples on separate tooltip lines. Use an adaptive linear network range with explicit markers and a range label for isolated peaks beyond the displayed range; preserve all recorded values.
- Keep existing external drives in a stable session order, append newly connected drives, truncate long names with full-name tooltips, and show native eject recovery guidance.
- Classify update retry actions by failure stage, invalidate callbacks from cancelled attempts, and scope temporary files and updater cleanup to each attempt without following mounted images.
- Separate release channels from signing policy: support explicitly disclosed ad-hoc stable releases and fail closed when notarized distribution is selected.
- Separate CI compilation and execution into distinct timed steps and summaries. Generate a bilingual download index from verified appcasts, select complete installer pairs by semantic version, and sort the release badge by SemVer.

This release candidate is ad hoc signed and **not notarized by Apple**. Stable releases may use the same explicitly disclosed mode; notarized distribution remains a separate strict opt-in. See the README for first-launch instructions. macOS 12 and physical Intel Macs have not been tested; CI verifies native ARM/Intel builds and tests on macOS 26.

<!-- neylu:zh-Hans -->
### 中文

- 增加紧凑／标准菜单栏间距，实时预览并保存设置；单位变化前后保持速率字段宽度稳定。
- 网络提示分行展示原始下载与上传采样；自适应线性量程对超范围的孤立尖峰明确标记并显示量程，不改写记录值。
- 外盘保留会话中已有顺序，新接入磁盘追加到末尾，长名称截断并提示全名，弹出失败提供系统恢复建议。
- 按失败阶段提供更新重试操作，取消后忽略旧回调，各次临时文件与辅助程序分别管理，清理时不递归进入挂载映像。
- 发行通道与签名策略分离：支持明确标注的未公证正式版，选择公证发行时失败即中止。
- CI 编译与执行拆成独立计时步骤并写入摘要；从已验证订阅生成双语下载索引，按语义版本选择架构齐全的安装包，Release 徽标明确按 SemVer 排序。

本候选版仅 ad-hoc 签名，**未经 Apple 公证**。正式版也可使用明确披露的未公证发行模式；公证发行仍需显式选择并完成严格验证。首次打开方式见 README。macOS 12 与 Intel 真机尚未实测；CI 在 macOS 26 上原生构建并测试 ARM／Intel 两种架构。

## [0.1.0-alpha.10] - 2026-11-08

<!-- neylu:en -->
### English

- **Clean compatibility builds:** Isolate the required macOS 12 login-item status query in a header-only system compatibility module. Handle the deprecation diagnostic only around that single legacy call; all other compiler diagnostics remain enabled. Preserve the system-reported state and Core Foundation ownership rules.
- **Enforced version boundaries:** macOS 13 and later continue using SMAppService. Swift Testing verifies that the compatibility query compiles without warnings for both macOS 12 architecture targets and is rejected for macOS 13 targets, with warnings treated as errors.
- **Consistent build entry points:** Share the module search path across app, documentation-preview, and performance builds, and synchronize development and release instructions. No additional framework or runtime dependency is bundled.

This preview supports macOS 12 and later on Apple Silicon and Intel. Login-item behavior and saved preferences are unchanged. It is ad hoc signed and not notarized by Apple; see the README for first-launch instructions. macOS 12 on physical hardware still requires additional validation.

<!-- neylu:zh-Hans -->
### 中文

- **消除兼容接口编译警告：** 将 macOS 12 必需的登录项状态查询隔离到仅含头文件的系统兼容模块，仅在该次旧接口调用处处理弃用诊断，其他编译诊断保持开启；保留系统真实状态查询及 Core Foundation 内存所有权规则。
- **强制检查版本边界：** macOS 13 及以上继续使用 SMAppService。Swift Testing 以警告视为错误验证两种架构的 macOS 12 目标均可无警告编译，并确认 macOS 13 目标拒绝旧查询接口。
- **统一构建入口：** 应用、文档预览和性能构建共用模块搜索路径，同步开发与发布说明；不向安装包增加额外框架或运行时依赖。

本预发布版支持 Apple Silicon 和 Intel 的 macOS 12 及以上系统，开机启动行为及已保存设置不变，仅 ad-hoc 签名，未经 Apple 公证；首次打开方式见 README。macOS 12 真机仍需补充验证。

## [0.1.0-alpha.9] - 2026-11-08

<!-- neylu:en -->
### English

- **In-app licenses:** View the MIT license and third-party notices in a reusable native window with document tabs, selectable text, and a full-text copy action. The About window no longer opens license files in another app.
- **Clearer energy-saving options:** Label automatic energy saving “Follow System” and order the options Follow System, On, Off. The default remains Off; sampling behavior is unchanged.
- **System compatibility:** Restrict legacy login-item APIs to macOS 12 with a compiler-enforced upper availability boundary; macOS 13 and later continue using SMAppService. Review availability checks for native glass and chart focus behavior, and verify both architecture builds against the macOS 12 deployment target.
- **Native regression tests:** Unify regression tests under Swift Testing and `swift test`, migrate Python test cases and custom native assertions, and use async/await for UI callbacks. Preserve updater replacement and rollback coverage, preload the test app icon to avoid IconServices delays, and synchronize CI and development instructions. Testing and fixtures remain outside the shipped app.

This preview supports macOS 12 and later on Apple Silicon and Intel. It is ad hoc signed and not notarized by Apple; see the README for first-launch instructions. macOS 12 on physical hardware and other processor models still require additional validation. The legacy macOS 12 login-item status query still produces an expected deprecation warning; it has no equivalent modern API on that system.

<!-- neylu:zh-Hans -->
### 中文

- **应用内许可证：** 在可复用的原生窗口中查看 MIT 许可证和第三方声明，支持文档页签、文字选择与全文复制；关于窗口不再调用其他应用打开许可文件。
- **省电选项更清晰：** 自动模式简化为「跟随系统」，按「跟随系统、开启、关闭」排列；默认仍为关闭，采样行为不变。
- **系统兼容性：** 用编译器可检查的版本上限将旧登录项接口限制在 macOS 12，macOS 13 及以上继续使用 SMAppService；检查系统玻璃与图表焦点的版本分支，并验证两种架构均可按 macOS 12 最低目标构建。
- **原生回归测试：** 测试统一迁入 Swift Testing 与 `swift test`，迁移 Python 测试用例及原生自定义断言，UI 回调改用 async/await；保留更新器替换与失败回滚覆盖，为原生测试预置应用图标以避免图标服务阻塞，同步 CI 和开发文档。测试框架及夹具不进入发布 App。

本预发布版支持 Apple Silicon 和 Intel 的 macOS 12 及以上系统，仅 ad-hoc 签名，未经 Apple 公证；首次打开方式见 README。macOS 12 真机与其他处理器型号仍需补充验证。macOS 12 的旧登录项状态查询仍有预期的弃用警告，该系统没有等价的新查询接口。

## [0.1.0-alpha.8] - 2026-11-08

<!-- neylu:en -->
### English

- **Reliable update checks:** Fix intermittent false “up to date” results after a release. Manual checks bypass completed cached results; each static-feed transfer uses a fresh cache key and requests HTTP revalidation. Preserve concurrent-request coalescing, background caching, and strict feed URL validation.
- **Hardware-aware metrics:** Hide metrics without a detected supported data source from the menu bar, overview, and selection/reordering list. Show optional GPU counters, core count, temperature, and disk I/O only when supported. Preserve saved visibility, order, and history; temporary read failures remain unavailable rather than becoming zero.
- **Compact menu bar:** Keep memory as a percentage with stable width and add an optional, reorderable CPU temperature item, disabled by default. Remove separate capacity and bit-rate modes; detail capacity values remain available. Temperature sampling respects the refresh and energy-saving policy without enabling unrelated hardware polling.
- **Simpler settings:** Focus Menu Bar Items on preview, visibility, order, and an inline reset action. Keep unit basis only in Preferences and IP masking beside the address in the overview. Move chart range selection to Preferences → Chart Time Range.
- **Chart and shortcut interaction:** Keep chart readouts within plot bounds and aligned with the selected time; clearly label pinned charts. Use an explicit click–record–save flow for global shortcuts, support Command–Shift combinations, and preserve existing bindings on registration conflicts.
- **Documentation:** Synchronize Chinese and English instructions, hardware-availability guidance, and overview screenshots.

This preview supports macOS 12 and later on Apple Silicon and Intel. It is ad hoc signed and not notarized by Apple; see the README for first-launch instructions. macOS 12 on physical hardware and other processor models still require additional validation. When upgrading from Alpha 7 or earlier, the old update checker may temporarily miss this release; retry later or use Homebrew or the DMG.

<!-- neylu:zh-Hans -->
### 中文

- **修复更新检查：** 修复发布后间歇性误报“已是最新版本”。手动检查绕过已完成缓存，每次静态订阅传输使用新的缓存键并请求 HTTP 重新验证；保留并发请求合并、后台缓存与严格地址校验。
- **按硬件能力显示：** 菜单栏、详情和选择／排序列表统一隐藏没有受支持数据源的指标；GPU 子指标、核心数、温度及磁盘读写分别检测。保留勾选、顺序与历史，暂时读取失败显示不可用，不伪装成零。
- **紧凑菜单栏：** 内存统一显示百分比并保持稳定宽度，增加默认关闭、可排序的 CPU 温度指标；移除独立容量和比特速率模式，详情容量读数保留。温度遵循刷新及省电策略，不连带启用其他硬件轮询。
- **精简设置：** 菜单栏设置只保留预览、指标勾选排序和标题行恢复默认；单位进制只保留偏好设置入口，IP 遮挡位于详情地址旁。图表范围移至「偏好设置 → 图表时间范围」。
- **图表与快捷键：** 图表提示跟随选中时间并限制在图内，固定时显示明确状态；全局快捷键改为点击录入、按组合键、保存，支持 Command＋Shift，注册冲突保留原组合。
- **文档同步：** 更新中英文说明、硬件可用性规则与详情截图。

本预发布版支持 Apple Silicon 和 Intel 的 macOS 12 及以上系统，仅 ad-hoc 签名，未经 Apple 公证；首次打开方式见 README。macOS 12 真机与其他处理器型号仍需补充验证。从 Alpha 7 或更早版本升级时，旧更新检查器可能暂时无法发现本版，可稍后重试或通过 Homebrew、DMG 升级。

## [0.1.0-alpha.7] - 2026-11-08

<!-- neylu:en -->
### English

- **Lower background overhead:** Cache display-only network addresses and GPU core counts, pause detail-only hardware polling while the overview is closed, and skip unchanged menu bar images and hidden plot preparation. CPU, GPU, memory, and network history continues recording.
- **Optional energy saving:** Choose Off (the default), Follow System Low Power Mode, or On. When active, closed-overview sampling uses intervals of at least five seconds; opening the overview restores your configured interval.
- **History and pinned charts:** Switch between two-minute, fifteen-minute, and one-hour views. Click a chart to pin the time range and synchronized readouts across all four charts while recording continues; click again or use the play button to resume live charts. History loads asynchronously and rendering preserves actual sample timestamps and extrema.
- **Menu bar display options:** Show memory as a percentage or used capacity, and network rates as bytes or bits per second. Hide the IP address, restore the default metric layout without clearing history or other preferences, and assign an optional global shortcut. Shortcut conflicts preserve the previous binding; no Accessibility permission or global keyboard monitor is required.
- **Diagnostics and native interaction:** Copy a privacy-filtered diagnostic summary from settings or About. Refine chart focus indicators on macOS 14+ and avoid automatically selecting the first control in utility windows, while preserving keyboard navigation and macOS 12/13 behavior.
- **Cleanup and documentation:** Remove obsolete development launch switches and raw diagnostic output. Keep screenshot fixtures in the documentation tool rather than the shipped app, retain compact native packaging, and synchronize English and Chinese documentation and previews.

This preview supports macOS 12 and later on Apple Silicon and Intel. It is ad hoc signed and not notarized by Apple; see the README for first-launch instructions. macOS 12 on physical hardware, other processor models, and real multi-display/VPN transitions still require additional validation. A simulated day of recording is covered by regression tests; it is not a day-long hardware endurance test.

<!-- neylu:zh-Hans -->
### 中文

- **减少后台开销：** 缓存仅用于显示的网络地址和 GPU 核心数，详情关闭时暂停详情专用硬件轮询，跳过不变的菜单栏位图和隐藏图表准备；CPU、GPU、内存和网络历史持续记录。
- **可选省电模式：** 提供默认关闭、跟随系统低电量模式、开启三种选择。生效时详情关闭后的采样间隔至少五秒，打开详情恢复设定间隔。
- **历史范围与图表固定：** 支持两分钟、十五分钟、一小时视图；点击图表固定四图的时间范围和同步读数，后台继续记录，再次点击或使用播放按钮恢复实时。历史异步读取，绘图保留真实采样时间和极值。
- **菜单栏显示选项：** 内存可显示使用率或已用容量，网速可显示字节或比特每秒；支持隐藏 IP、仅恢复默认指标布局而不清除历史和其他偏好，以及默认关闭的全局快捷键。快捷键冲突保留旧组合，无需辅助功能权限或全局键盘监听。
- **诊断与原生交互：** 设置与关于窗口可复制经过隐私过滤的诊断摘要；优化 macOS 14+ 图表焦点提示，工具窗口不再自动选中首个控件，保留键盘导航和 macOS 12/13 原生行为。
- **清理与文档：** 删除闲置开发启动参数和旧的原始诊断输出，将截图夹具移至文档工具，不随 App 分发；保持轻量原生打包，同步中英文文档与预览图。

本预发布版支持 Apple Silicon 和 Intel 的 macOS 12 及以上系统，仅 ad-hoc 签名，未经 Apple 公证；首次打开方式见 README。macOS 12 真机、其他处理器型号及真实多屏／VPN 切换仍需补充验证。回归测试覆盖模拟一天采样，不等同于一天真机耐久测试。

## [0.1.0-alpha.6] - 2026-11-08

<!-- neylu:en -->
### English

- **Update helper launch fix:** Fix Gatekeeper blocking `NeyluUpdater` after it is copied from a previously approved installation to the private staging directory. Verify the installed app’s signature and nested code, confirm the copied helper’s contents and signature, then remove quarantine only from that helper copy. Leave the installed app, downloaded candidate, and unrelated metadata unchanged.
- **Update safety checks:** Preserve installer checksums, version and architecture checks, signing identity checks, and replacement rollback. Add regression coverage for inherited quarantine, helper execution, tampered source apps, symbolic links, and existing staging files; make the shared-request cancellation test independent of response timing.

When upgrading from alpha.5 or earlier, the old updater still runs until this version is installed. If macOS blocks `NeyluUpdater`, cancel the update and follow the README’s quarantine instructions before retrying, or install this release using the DMG or Homebrew.

This preview is ad hoc signed and is not notarized by Apple. First-launch approval may still be required. Requires macOS 12 or later; macOS 12 has not yet been tested on a physical device.

<!-- neylu:zh-Hans -->
### 中文

- **修复更新器启动被拦截：** 修复从已允许运行的安装中，将 `NeyluUpdater` 复制到私有暂存目录后再次被 Gatekeeper 拦截的问题。先验证已安装 App 的签名与内嵌代码，再核对复制后辅助程序的内容与签名，仅处理该辅助程序副本的隔离标记；不修改已安装 App、下载的候选应用或其他元数据。
- **保留更新安全校验：** 继续验证安装包校验值、版本、架构与签名身份，并保留替换失败回滚。补充隔离标记继承、辅助程序执行、来源篡改、符号链接及暂存文件防覆盖测试；共享请求的取消测试不再依赖响应延时。

从 alpha.5 或更早版本升级时，安装本版前仍由旧更新器执行。若系统拦截 `NeyluUpdater`，请取消更新，按 README 的隔离标记处理说明操作后重试；也可通过 DMG 或 Homebrew 安装本版。

本预发布版仅 ad-hoc 签名，未经 Apple 公证，首次运行仍可能需要手动允许。要求 macOS 12 及以上；macOS 12 尚未完成实机验证。

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
