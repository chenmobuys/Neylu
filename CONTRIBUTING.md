# 参与贡献

欢迎修复、设计与兼容性改进。大功能请先开 Issue 讨论；本项目优先保持紧凑的原生菜单栏体验。

## 开发

构建需要能运行 Xcode 26+ 的 Apple Silicon 或 Intel Mac，以及 macOS 26+ SDK；App 的最低运行版本为 macOS 12，两者是不同要求。CI 分别在两种架构的 macOS 26 runner 原生构建与测试。

```sh
./build.sh
./test-history.sh
./test-updates.sh
python3 -m unittest discover -s Tests -p 'test_*.py' -v
./test-runtime.sh
```

默认输出为 `build/Neylu.app`，缓存只写入仓库内 `.build/`。`test-runtime.sh` 单独编译原生运行回归，测试代码不会进入发布 App。
可用 `./build.sh /absolute/path/Neylu.app` 指定输出位置。

## 提交与 PR

提交格式：`english-prefix: 中文描述`。允许 `feat, fix, docs, refactor, test, chore, build, ci, security`。
例如 `fix: 修正网络读数对齐`。说明用户可观察的变化、验证方法和兼容性影响。
用户行为变化应更新 CHANGELOG；发布时同步 VERSION 和递增的 BUILD_NUMBER。

UI 优先使用系统组件、语义颜色和系统材质。应用标识统一为 `io.github.chenmobuys.Neylu`，不添加旧品牌的偏好、登录项或历史迁移兼容。
历史数据、证书、私钥和构建输出不得提交。诊断信息可能包含 IP 或本机路径，分享前请脱敏。

默认图标源为 `Assets/AppIcon-v5-vector.svg`，每次构建从矢量直接渲染各个尺寸。
温度与 IOKit 统计需要真机验证；CI 的虚拟机不能证明全部传感器兼容。

提交贡献表示你有权提交相应内容，并同意贡献按仓库 MIT 许可分发；无需签署额外 CLA。

## 多语言

用户可见文案统一维护在 `Resources/en.lproj/Localizable.strings` 与 `Resources/zh-Hans.lproj/Localizable.strings`，语言代码使用 BCP 47 标签。使用稳定的语义键（例如 `menu.check_for_updates`、`update.error.integrity_check_failed`），不要用原文句子作键，也不要在窗口或辅助程序中自行分支拼写翻译。

通过 `L("menu.check_for_updates")` 或 `L10n.text` 读取；主程序、关于窗口、更新窗口与辅助程序共用同一资源来源。修改文案后运行本地化测试，校验键集合、命名、格式占位符及全部原生入口。英文应使用 macOS 与系统监控领域的常用术语，并验证切换语言后的实际窗口布局。

## 文档同步

中英文 README 保持相同的信息、功能顺序、安装命令和文档入口；首页面向用户，详细原理放入 docs。最新版本通过 Release 徽标和 VERSION 获取，不在首页写固定版本号。修改运行要求、网络访问、数据保存、安装或更新行为时，同时核对 README、docs/METRICS.md、docs/UPDATING.md、docs/UPDATING.en.md、SECURITY.md 与 docs/RELEASING.md。

`python3 -m unittest discover -s Tests -p 'test_*.py'` 包含文档检查：本地链接和图片、中英文 README 命令与入口、源码最低系统要求及过期版本声明。历史 CHANGELOG 保留各版本当时的行为，不以当前实现覆盖旧记录。未发布改动只写入 Unreleased。
