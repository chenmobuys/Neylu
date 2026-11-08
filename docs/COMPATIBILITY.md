# 兼容性验收 / Compatibility validation

最低运行要求为 macOS 12；支持 Apple Silicon 和 Intel。构建目标不等同于真机验收。
The deployment target is macOS 12, with Apple Silicon and Intel builds. A deployment target is not evidence of physical-device validation.

| 环境 / Environment | 验证范围 / Validation | 未覆盖项 / Gaps |
| --- | --- | --- |
| Apple M3 Max，macOS 27.2，双显示器 / two displays | 当前开发设备；Swift Testing（含私有测试 App 替换、重启、失败回滚）、双屏窗口定位与局部浅深色外观验证 / Current development device; Swift tests including private fixture replacement, restart and rollback; panel placement and local light/dark appearance on both displays | 本设备不代表其他芯片或系统版本 / Does not establish coverage for other chips or OS versions |
| GitHub macOS 26 ARM / Intel runners | 每次发布原生构建与回归 / Native builds and regression tests on each release | 云端 runner 不等同于用户 Intel 真机 / Hosted runners are not physical-user-device acceptance |
| macOS 12 | 最低部署目标与旧接口编译边界检查 / Deployment-target and legacy API availability checks | 尚无真机，登录项、显示及升级行为未实测 / No physical device; login items, rendering, and upgrades are untested |
| Intel 真机 / Physical Intel Macs | 无设备 / No device available | 尚未实测 / Not tested |
| 其他芯片、外置磁盘 / Other chips and external drives | 可用能力检测与相关回归 / Capability detection and regression coverage | 本机无外置物理磁盘；真实插拔、弹出未实测，也未覆盖所有传感器 / No external physical disk attached; connection/ejection and every sensor remain untested |

当前保留 RC 状态；缺失读数由能力检测隐藏，不能以零值假装支持。DMG 挂载测试不代表外置物理磁盘弹出验收。
The current release remains an RC. Capability detection hides unavailable readings rather than presenting zero as supported data. Mounting a DMG does not validate physical-drive ejection.

发行包仅 ad-hoc 签名，未经 Apple 公证。首次打开见 [中文说明](UPDATING.md) / [English instructions](UPDATING.en.md)。
Installers are ad hoc signed and not notarized by Apple. Follow the first-launch instructions linked above.
