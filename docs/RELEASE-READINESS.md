# 正式版验收 / Release readiness

验收日期 / Review date: 2026-11-08。发行日期 / Release date: 2026-11-09。
此记录用于首个正式版 0.1.0（构建 12）；发行模式为明确披露的未公证版本。
This record covers the first stable release, 0.1.0 (build 12), distributed with explicit unnotarized-release disclosures.

## 本轮收尾 / Stabilization

- 默认只检查正式版；用户在「测试版更新」主动选择后才接收预发布。手动、后台、缓存与进行中的操作遵循同一偏好。Homebrew 的默认 Cask 首次进入正式版后不会被预发布覆盖。
  Check only stable releases by default. Pre-releases require an explicit Beta Updates selection, shared across manual checks, background checks, caches and pending operations. After its first stable release, the default Homebrew cask is not replaced by previews.

- 修正手动和后台更新检查的结果乱序，旧后台结果不能覆盖已完成的手动检查。
  Fix manual/background update ordering so stale background results cannot replace a completed manual result.
- 更新准备命令限时执行、检查输出大小，取消后回收本次子进程；卸载保持独立限时且不强制执行。
  Bound preparation commands, check output size, reap the owned subprocess on cancellation, and retain independent, non-forced image cleanup.
- 两种语言共用专用超时文案；不引入新的框架、遥测或自动安装行为。
  Share a dedicated localized timeout message, without adding frameworks, telemetry, or automatic installation.

## 验证 / Validation

| 项目 / Item | 证据与边界 / Evidence and limits |
| --- | --- |
| 本机 / Local | 完整 52 项 Swift Testing 套件通过，开启私有测试 App 的替换、重启和失败回滚；专用双屏测试本轮未重跑，RC 验收已记录 / The full 52-test Swift suite passes with private-app replacement, restart and rollback enabled; the opt-in display test was not rerun this round and remains covered by RC acceptance |
| 云端 / Hosted CI | main 的 ARM / Intel 原生构建、测试与 DMG 打包均须通过；查看仓库 CI / Native ARM and Intel builds, tests and DMG packaging on main must pass; see repository CI |
| 安装包 / Installer | 本机 ARM 试打包 432,065 字节（约 422 KiB），通过签名、映像和卷图标检查；公开 RC 1 的云端 ARM DMG 为 436,916 字节（约 427 KiB），环境不同，不能据此宣称优化了体积 / Local ARM test package: 432,065 bytes (about 422 KiB), with signature, image and volume-icon validation. Public RC 1 ARM DMG: 436,916 bytes (about 427 KiB). Different build environments prevent a size-reduction claim |
| 运行开销 / Runtime overhead | 日常采样与定时调度未改动；命令监控仅在更新准备时启用。本轮没有新的功率、续航或能耗测量结论 / Normal sampling and timer scheduling are unchanged; command monitoring runs only during update preparation. No new power, battery-life or energy-measurement claim is made |

## 仍需明确披露 / Disclosures

macOS 12 和 Intel 真机未实测；云端构建不能替代用户设备验收。其他芯片传感器和外置物理磁盘的真实插拔、弹出也未全部覆盖。详见 [兼容性说明](COMPATIBILITY.md)。
macOS 12 and physical Intel Macs remain untested. Hosted builds do not establish physical-device acceptance. Other chip sensors and physical-drive connection/ejection are not fully covered. See the compatibility matrix linked above.

发行模式为 `adhoc`：未经 Apple 公证，首次启动仍可能需要系统确认或 README 中的手动命令。正式版标签不代表通过公证。
Distribution remains `adhoc`: not notarized by Apple. First launch may require system approval or the manual command in the README. A stable version label does not imply notarization.

## 正式发布边界 / Stable-release boundary

在上述验收范围内发布明确标注未公证的 `0.1.0`。版本、构建号和双语更新说明统一由仓库维护，tag 触发自动发行；发布结果以 Release 工作流为准，并核对双架构附件、Homebrew、静态订阅与下载页，不覆盖已公开 RC 附件。
Release the explicitly unnotarized `0.1.0` within these documented limits. The repository maintains matching version, build number and bilingual notes; a tag triggers automated distribution. The Release workflow records the publication result. Verify both installers, Homebrew, static feeds and the download page, without replacing public RC assets.
