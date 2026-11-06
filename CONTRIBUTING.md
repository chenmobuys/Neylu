# 参与贡献

欢迎修复、设计与兼容性改进。大功能请先开 Issue 讨论；本项目优先保持紧凑的原生菜单栏体验。

## 开发

需要 Apple Silicon Mac、Xcode 26+（含 macOS 26+ SDK），运行最低 macOS 13。

```sh
./build.sh
./test-history.sh
python3 -m unittest discover -s Tests -p 'test_*.py' -v
build/Neylu.app/Contents/MacOS/Neylu --self-test
```

默认输出为 `build/Neylu.app`，缓存只写入仓库内 `.build/`。
可用 `./build.sh /absolute/path/Neylu.app` 指定输出位置。

## 提交与 PR

提交格式：`english-prefix: 中文描述`。允许 `feat, fix, docs, refactor, test, chore, build, ci, security`。
例如 `fix: 修正网络读数对齐`。说明用户可观察的变化、验证方法和兼容性影响。
用户行为变化应更新 CHANGELOG；发布时同步 VERSION 和递增的 BUILD_NUMBER。

UI 优先使用系统组件、语义颜色和系统材质。保持内部标识 `local.QuietBar`，避免破坏既有偏好、登录项与迁移。
历史数据、证书、私钥和构建输出不得提交。诊断信息可能包含 IP 或本机路径，分享前请脱敏。

默认图标源为 `Assets/AppIcon-v5-vector.svg`，每次构建从矢量直接渲染各个尺寸。
温度与 IOKit 统计需要真机验证；CI 的虚拟机不能证明全部传感器兼容。

提交贡献表示你有权提交相应内容，并同意贡献按仓库 MIT 许可分发；无需签署额外 CLA。
