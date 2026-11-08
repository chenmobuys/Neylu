# 安全反馈 / Security policy

## 简体中文

维护最新发布版本。监控读数保存在本机，无遥测，不上传数据，不要求管理员权限。默认每天检查一次静态 appcast，可关闭；手动检查与下载安装包也会访问 GitHub 静态内容及 HTTPS 附件服务。客户端不请求 GitHub REST API，不需要账号或 Token。

更新器验证 SHA-256、代码签名、应用标识、完整版本、架构和最低系统要求；已有 Developer ID 的安装还约束 Apple 签名链与 Team ID。当前发行包仅 ad-hoc 签名、未经 Apple 公证，更新来源信任依赖本仓库的 GitHub HTTPS 渠道；摘要不替代发布者身份认证。发行通道与公证状态独立：DISTRIBUTION=adhoc 允许明确标注的未公证正式版；DISTRIBUTION=notarized 强制 Developer ID、公证与 Gatekeeper 验证，失败即中止，不降级。

安装包、Homebrew 和发布自动化不关闭 Gatekeeper/SIP、不自动删除安装 App 的隔离标记。alpha.6 起，用户确认更新后，验证已安装 App 及其复制后的辅助程序，只处理私有暂存辅助程序副本的隔离标记，不修改来源 App、下载候选应用或其他元数据。首次打开是否允许未经公证的软件由用户决定，见[更新与排错](docs/UPDATING.md)。

请勿公开密钥、证书、私人诊断或尚未修复的漏洞细节。优先使用仓库 **Security → Advisories → Private vulnerability reporting** 私下报告；若入口不可用，请先联系维护者取得私下沟通方式。

诊断复制采用字段白名单，不序列化监控对象、偏好集合或错误日志；不含 IP、网卡/磁盘名、路径或实际读数，只在用户点击时写入剪贴板，不自动发送。

IP 隐藏同时应用于详情文字和悬浮提示，辅助功能不会额外暴露地址。全局快捷键默认关闭，使用系统热键注册，仅在设置录入框聚焦时接收本地按键；不使用全局键盘监听或申请辅助功能权限。注册失败保留已有快捷键。

## English

The latest published release is maintained. Monitoring data stays local, with no telemetry, uploads, or administrator privileges. Static appcast checks run daily by default and can be disabled. Manual checks and installer downloads also use GitHub’s static content and HTTPS asset services. The client does not use the GitHub REST API or require an account or token.

The updater validates SHA-256, code signatures, app identifier, full version, architecture, and minimum macOS requirement. An existing Developer ID installation also enforces the Apple signing chain and Team ID. Current installers are ad hoc signed and not notarized. Publisher trust relies on this repository’s GitHub HTTPS channel; digests do not establish publisher identity. Release channels and notarization are independent: DISTRIBUTION=adhoc permits explicitly disclosed unnotarized stable releases; DISTRIBUTION=notarized requires Developer ID signing, notarization, and Gatekeeper verification. Failure aborts distribution without a fallback.

Installers, Homebrew, and release automation do not disable Gatekeeper/SIP or automatically clear quarantine on the installed app. Since alpha.6, after the user requests an update, the installed app and copied helper are verified before quarantine is removed only from that private helper copy. The source app, downloaded candidate, and unrelated metadata remain unchanged. Users decide whether to allow an unnotarized first launch; see [updating and troubleshooting](docs/UPDATING.en.md).

Do not disclose credentials, certificates, private diagnostics, or details of unfixed vulnerabilities publicly. Prefer **Security → Advisories → Private vulnerability reporting** in this repository. If it is unavailable, contact the maintainer to establish a private reporting channel first.

Diagnostics use an explicit field allowlist, never serialization of monitoring objects, preference collections, or error logs. IP addresses, interface/disk names, paths, and actual readings are excluded. The clipboard is written only on user action; nothing is transmitted automatically.

IP masking covers detail text and tooltips, with no separate address exposed through accessibility. Global shortcuts are disabled by default and use system hotkey registration. Local keystrokes are captured only while the settings recorder has focus; there is no global keyboard monitor or Accessibility permission request. Registration failures preserve the existing shortcut.


## 更新子进程 / Update subprocesses

更新命令只使用固定系统可执行文件及独立参数，不经过 shell。标准输入关闭，输出写入本次私有目录的 0600 文件并检查大小，命令有单独时限；取消后先停止本次持有的 Process，再清理目录。卸载映像保持独立的超时，且不传入强制卸载参数。
Update commands use fixed system executables and separate arguments, without a shell. Standard input is closed; output is written to an owner-only file in a private per-command directory and checked for size. Commands have individual deadlines. Cancellation stops the owned Process before directory cleanup. Image detachment retains its own timeout and never uses force-unmount flags.
