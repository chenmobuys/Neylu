# 参与贡献

欢迎修复、设计与兼容性改进。大功能请先开 Issue 讨论；本项目优先保持紧凑的原生菜单栏体验。

## 开发

构建需要能运行 Xcode 26+ 的 Apple Silicon 或 Intel Mac，以及 macOS 26+ SDK；App 的最低运行版本为 macOS 12，两者是不同要求。CI 分别在两种架构的 macOS 26 runner 原生构建与测试。

```sh
./build.sh
swift test --configuration release
```

默认输出为 `build/Neylu.app`，缓存只写入仓库内 `.build/`。也可用 `./test.sh` 一次完成 App 构建与 Swift Testing。`Package.swift` 的 `NeyluCore` 仅供测试直接访问原生逻辑，发布仍由 `build.sh` 编译；Testing、测试目标与夹具不会进入 App。

测试用例与断言统一位于 `Tests/Swift`，使用 `@Test`、`#expect` 和 `#require`。历史、原生界面与更新安全回归直接测试 Swift 源码；AppKit 测试在主线程通过 async/await 等待回调，并串行执行，避免全局偏好与窗口相互干扰。现有发布工具仍以 Python 实现，Swift 测试通过 Process 调用其 CLI 或函数，夹具、模拟 API 与结果断言在 Swift 中；无需 unittest 或额外 Python 测试依赖。
可用 `./build.sh /absolute/path/Neylu.app` 指定输出位置。

## 提交与 PR

提交格式：`english-prefix: 中文描述`。允许 `feat, fix, docs, refactor, test, chore, build, ci, security`。
例如 `fix: 修正网络读数对齐`。说明用户可观察的变化、验证方法和兼容性影响。
用户行为变化应更新 CHANGELOG；发布时同步 VERSION 和递增的 BUILD_NUMBER。

UI 优先使用系统组件、语义颜色和系统材质。应用标识统一为 `io.github.chenmobuys.Neylu`，不添加旧品牌的偏好、登录项或历史迁移兼容。
历史数据、证书、私钥和构建输出不得提交。诊断信息可能包含 IP 或本机路径，分享前请脱敏。

能耗代理指标可运行 `./test-performance.sh --idle-process --warmup 10 --duration 60 --history`，使用私有临时数据库，不读取用户历史；`--energy-mode on` 测省电模式，`--interval 1|2|5|10` 选择设定间隔，`--show-details` 可人工验证真实展开状态。输出含 CPU、内存、进程唤醒和磁盘 I/O，不等于功率或电池续航；同口径多次比较后再报告结论。

默认图标源为 `Assets/AppIcon-v5-vector.svg`，每次构建从矢量直接渲染各个尺寸。
温度与 IOKit 统计需要真机验证；CI 的虚拟机不能证明全部传感器兼容。

macOS 12 的登录项状态查询通过 `Sources/LegacyServiceManagement` 中仅含头文件的系统兼容模块导入；仅对无法替代的单次旧 API 调用局部处理弃用诊断，不全局关闭警告。macOS 13+ 仍用 SMAppService。Swift Testing 以 `-warnings-as-errors` 检查 ARM / Intel 的 macOS 12 目标，并确认 macOS 13 目标拒绝旧接口调用。原生编译入口共用 `scripts/swift-sources.sh` 中的源文件与模块搜索参数。

提交贡献表示你有权提交相应内容，并同意贡献按仓库 MIT 许可分发；无需签署额外 CLA。

## 多语言

用户可见文案统一维护在 `Resources/en.lproj/Localizable.strings` 与 `Resources/zh-Hans.lproj/Localizable.strings`，语言代码使用 BCP 47 标签。使用稳定的语义键（例如 `menu.check_for_updates`、`update.error.integrity_check_failed`），不要用原文句子作键，也不要在窗口或辅助程序中自行分支拼写翻译。

通过 `L("menu.check_for_updates")` 或 `L10n.text` 读取；主程序、关于窗口、更新窗口与辅助程序共用同一资源来源。修改文案后运行本地化测试，校验键集合、命名、格式占位符及全部原生入口。英文应使用 macOS 与系统监控领域的常用术语，并验证切换语言后的实际窗口布局。

## 文档同步

中英文 README 保持相同的信息、功能顺序、安装命令和文档入口；首页面向用户，详细原理放入 docs。最新版本通过 Release 徽标和 VERSION 获取，不在首页写固定版本号。修改运行要求、网络访问、数据保存、安装或更新行为时，同时核对 README、docs/METRICS.md、docs/UPDATING.md、docs/UPDATING.en.md、SECURITY.md 与 docs/RELEASING.md。

Swift Testing 包含文档检查：本地链接和图片、中英文 README 命令与入口、源码最低系统要求及过期版本声明。历史 CHANGELOG 保留各版本当时的行为，不以当前实现覆盖旧记录。未发布改动只写入 Unreleased。

文档预览使用 `./scripts/render-docs.sh /private/tmp/neylu-preview --language zh-Hans`，英文使用 `--language en`。演示夹具位于 `Tests/Support`，仅预览编译启用 `NEYLU_PREVIEW`；发布 App 不提供截图模式、调试报告或自动展开窗口等开发参数。依赖注入接口保留，以便隔离临时数据库、登录服务、网络和快捷键注册边界。

CI 通过 `scripts/test-ci.sh --compile-only` 和 `--run-only` 两个独立步骤分别计时、写入步骤摘要，再运行纯 Swift Testing（不启动空的 XCTest 测试阶段）。执行阶段每 30 秒输出进展，超过 90 秒采集测试子进程堆栈，180 秒仍未完成则失败；此限制不计编译时间、不跳过测试。原生初始化及工具调用进展通过专用临时文件提供，不依赖 SwiftPM 的输出缓冲。

## 可选集成检查

普通 `swift test` 不访问 GitHub，也不替换已安装应用。以下检查必须显式开启：

```sh
NEYLU_LIVE_CHECK=1 swift test --configuration release --filter NeyluTests/updateSafety
NEYLU_LIVE_UPDATE=1 swift test --configuration release --filter NeyluTests/updateSafety
NEYLU_HELPER_INTEGRATION=1 swift test --configuration release --filter NeyluTests/nativeUpdaterReplacementAndRollback
```

前两项分别检查真实更新源和安装包下载／校验。最后一项需要原生 GUI 会话，只操作一次性临时 App，验证退出、替换、重启与启动失败回滚，不触碰已安装 Neylu。
