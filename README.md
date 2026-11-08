<p align="center"><img src="Assets/AppIcon-v5-vector.svg" width="96" alt="Neylu icon"></p>
<h1 align="center">Neylu</h1>
<p align="center">简体中文 · <a href="README.en.md">English</a></p>
<p align="center">安静、紧凑的原生 macOS 菜单栏监控工具。</p>

[![CI](https://github.com/chenmobuys/Neylu/actions/workflows/ci.yml/badge.svg)](https://github.com/chenmobuys/Neylu/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/chenmobuys/Neylu?include_prereleases)](https://github.com/chenmobuys/Neylu/releases)
[![MIT](https://img.shields.io/github/license/chenmobuys/Neylu)](LICENSE)
![macOS 12+](https://img.shields.io/badge/macOS-12%2B-111827?logo=apple&logoColor=white)
![Apple Silicon and Intel](https://img.shields.io/badge/arch-arm64%20%7C%20x86__64-007AFF)
![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white)
[![Stars](https://img.shields.io/github/stars/chenmobuys/Neylu)](https://github.com/chenmobuys/Neylu/stargazers)

<p align="center"><picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/overview-dark@2x.png">
  <img src="docs/images/overview-light@2x.png" width="380" alt="Neylu 系统概览">
</picture></p>

预览采用演示读数；实际运行时，系统材质随外观与桌面背景变化。

## 功能

- 网速、内存、GPU、CPU 与系统盘指标合为一个菜单栏项目，可选择显示内容并排序。
- 实时图表、受支持硬件的 CPU 温度、磁盘容量与读写速度；支持外接磁盘监控和弹出。
- macOS 26+ 使用系统玻璃，更早版本使用系统材质；支持自动、浅色、深色外观。
- 简体中文与英文；可调整刷新间隔、十进制或二进制单位，并选择省电模式。
- 本机保留 24 小时历史，图表可切换两分钟、十五分钟或一小时；无遥测，不上传监控数据。
- 内置更新检查、安装包校验和升级后的更新说明。

## 安装

支持 **macOS 12 及以上**，兼容 Apple Silicon 与 Intel。最新安装包见 [GitHub Releases](https://github.com/chenmobuys/Neylu/releases)。

```sh
brew install --cask chenmobuys/tap/neylu
```

也可下载 DMG：Apple Silicon 选择 `arm64`，Intel 选择 `x86_64`，打开后将 **Neylu.app** 拖入「应用程序」。使用 App 不需要 Xcode 或 Apple Developer 会员。

## 首次打开

当前 Alpha 仅 ad-hoc 签名，**未经 Apple 公证**。若被 macOS 拦截，可按 [Apple 官方步骤](https://support.apple.com/zh-cn/102445)选择「仍要打开」；确认信任下载的 Neylu 后，也可执行：

```sh
xattr -dr com.apple.quarantine "/Applications/Neylu.app"
```

请使用实际安装路径。此命令只针对 Neylu，不会关闭 Gatekeeper 或 SIP。若提示对象为 `NeyluUpdater`，请参阅[更新与排错](docs/UPDATING.md)。

## 使用

- 左键点击菜单栏读数展开详情；右键或点击「…」打开设置。
- 「菜单栏显示…」选择和排列指标；「外观」切换主题；「偏好设置」包含刷新间隔、省电模式、单位、语言、开机启动和自动检查更新。
- 在详情顶部切换历史范围，悬浮或用左右方向键查看真实采样；按 Escape 关闭详情和工具窗口。
- 菜单或关于窗口可复制不含 IP 和路径的诊断信息。选择「检查更新…」，也可执行 `brew update && brew upgrade --cask --greedy neylu` 升级。

## 文档

- [更新与排错](docs/UPDATING.md)
- [指标与硬件兼容性](docs/METRICS.md)
- [构建与贡献指南](CONTRIBUTING.md)
- [发布自动化](docs/RELEASING.md)
- [更新记录](CHANGELOG.md) · [安全反馈](SECURITY.md) · [MIT 许可](LICENSE) · [第三方致谢](THIRD_PARTY_NOTICES.md)
