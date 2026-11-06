# Changelog

本文记录面向用户的变化。版本以 GitHub tag / Release 为准；当前尚未创建公开 Release。
本地开发过程中的 1.0.0–1.0.39 不追溯伪装为公开发行记录。

## [Unreleased]

## [1.0.40]

### 功能

- 单个菜单栏项目显示上传、下载、MEM 与 CPU，可选择十进制或二进制单位。
- 详情并排显示 CPU/GPU、内存/网络，并提供硬盘占用与实时读写速度。
- 本机 SQLite 保存最近 24 小时记录，重启后恢复最近两分钟图表；停采空档连接真实端点。
- 原生系统菜单、关于窗口、开机启动；macOS 26+ 使用系统玻璃，旧版系统回退到原生材质。
- 采用七条淡色参考线的纯矢量应用图标，App 与关于窗口保持一致。

### 发布与维护

- 可移植的源码构建、历史存储与发布工具测试。
- GitHub Actions CI、tag 发布、正式版 Developer ID 签名及 Apple 公证流程。
- 测试 tag 仅创建未经公证的 draft prerelease，正式版校验失败时不降级发布。
- 自动生成版本化 ZIP、SHA-256、Release notes 与 Homebrew Cask 更新 PR。
- MIT 许可、第三方致谢、贡献指南、安全反馈和发布维护说明。

### 已知限制

- 当前仅提供 Apple Silicon 构建，要求 macOS 13+；源码构建需要 Xcode 26+ SDK。
- CPU 温度目前仅支持 M3 已知传感器分组；GPU / 磁盘统计取决于系统和硬件提供的数据。
- 未完成 Apple 签名、公证配置前，不提供正式版 Homebrew 安装包。
