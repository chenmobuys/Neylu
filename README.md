<p align="center"><img src="Assets/AppIcon-v5-vector.svg" width="112" alt="Neylu icon"></p>
<h1 align="center">Neylu</h1>
<p align="center">安静、紧凑的原生 macOS 菜单栏监控工具。</p>
<p align="center">Apple Silicon · macOS 13+ · MIT</p>

菜单栏显示上传、下载、内存和 CPU；点击展开 CPU、GPU、内存、网络及磁盘详情。
使用系统字体、原生控件和系统材质，保持一页轻览。

## 功能

- **一个菜单栏项目**：三组读数一起移动，数字等宽，上传下载分别显示完整单位。
- **原生外观**：macOS 26+ 系统玻璃；macOS 13–25 原生材质回退，跟随系统外观。
- **实时图表**：CPU/GPU 并排、内存/网络并排，磁盘显示占用和读写速度。
- **本机历史**：SQLite 增量存储 24 小时，打开时恢复最近两分钟；没有遥测与网络上传。
- **简单设置**：十进制/二进制单位、开机启动、活动监视器与关于窗口。

## 安装

目前正在准备首次公开发布。只有正式 Release 标记为已签名、公证的包才适合普通下载和 Homebrew 渠道；CI 附件和 preview draft 是开发测试包。

### GitHub Releases

在仓库右侧 **Releases** 下载 `Neylu-版本-arm64.zip`，解压后将 `Neylu.app` 拖到 `/Applications` 并打开。
默认不在 Dock 显示。点击菜单栏读数展开；再次点击、Esc 或切换到其他应用关闭。

发布会附带 `SHA256SUMS`，可在下载目录验证：

```sh
shasum -a 256 -c SHA256SUMS
```

### Homebrew

首个正式 Release 的 Cask 更新 PR 合并后，使用本仓库作为自有 tap：

```sh
brew tap chenmobuys/neylu https://github.com/chenmobuys/Neylu
brew install --cask chenmobuys/neylu/neylu
```

升级：`brew upgrade --cask chenmobuys/neylu/neylu`。
普通卸载保留历史与偏好：`brew uninstall --cask neylu`。
`brew uninstall --cask --zap neylu` 会额外删除 Neylu 历史和偏好，请按需使用。

这不是 Homebrew 官方仓库收录；正式发布流程会根据下载附件计算真实 SHA-256，不使用 `:no_check`，也不会绕过系统安全检查。

## 系统要求与读数

| 项目 | 支持情况 |
| --- | --- |
| 运行 | Apple Silicon、macOS 13+；暂不提供 Intel 构建 |
| 源码构建 | Xcode 26+，需要 macOS 26+ SDK |
| CPU / 内存 / 网络 | 每 2 秒采样；网络自动使用主接口 |
| CPU 温度 | 仅 M3 已知传感器分组；读取失败显示不可用 |
| GPU | 依赖 IOKit 提供利用率、渲染、Tiler 与核心数；不支持时显示不可用 |
| 磁盘 | 启动盘共享容器容量；读写速度来自其物理磁盘，不显示未采集的温度 |

图表空档会连接前后真实采样点，连接仅用于视觉展示，不补写停采数据。
内存占用按 App、联动与压缩内存统计，不把可回收文件缓存计入使用量。
GPU 三个值各按 1/3 堆叠，总高度表示平均值；图例显示原始百分比，不能视为三种互斥负载之和。
更多指标定义见 [技术说明](docs/METRICS.md)。

## 隐私与历史

应用不请求网络、不收集遥测、不读取进程内容、不要求管理员权限。
CPU/GPU/内存/网络历史保存在 `~/Library/Application Support/Neylu/history.sqlite`，保留 24 小时。
每 30 秒批量写入，退出和睡眠前保存；强制结束或断电最多可能丢失约 30 秒未写入记录。
开机时间来自内核 `kern.boottime`，包括睡眠。

旧版 QuietBar 的历史会通过 SQLite 一致性备份迁移，原数据库保留，已有 Neylu 数据不会覆盖。
内部标识 `local.QuietBar` 暂时保留，避免丢失单位偏好和开机启动登记。

## 开发

```sh
./build.sh
open build/Neylu.app
./test-history.sh
python3 -m unittest discover -s Tests -p 'test_*.py' -v
build/Neylu.app/Contents/MacOS/Neylu --self-test
```

输出位于 `build/`，缓存位于 `.build/`，均不会提交。
使用系统框架与 SQLite，无第三方运行时依赖。
默认图标源是 [纯矢量 SVG](Assets/AppIcon-v5-vector.svg)，构建时直接渲染所有尺寸。

## 发布与贡献

- [更新记录](CHANGELOG.md)
- [发布与 GitHub / Homebrew 配置](docs/RELEASING.md)
- [贡献指南](CONTRIBUTING.md)
- [安全反馈](SECURITY.md)
- [第三方致谢](THIRD_PARTY_NOTICES.md)

## 许可

Neylu 使用 [MIT License](LICENSE)。第三方参考材料的许可保留在 THIRD_PARTY_NOTICES.md 中。
