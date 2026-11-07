# 安全反馈

目前维护最新发布版本。监控数据只保存在本机，不上传，不要求管理员权限。手动检查更新或下载安装包时，Neylu 会访问 GitHub API 及 GitHub 的 HTTPS 附件下载域名，不需要登录 GitHub，也不发送监控读数。更新器核对 GitHub 提供的 SHA-256、代码签名、应用标识、版本与架构；已使用 Developer ID 签名的应用同时约束 Apple 签名链和 Team ID。当前 Alpha 没有 Developer ID 与公证，其更新来源信任依赖本仓库 GitHub 发布渠道，摘要用于发现损坏，不替代开发者身份认证。

请不要在公开 Issue 中提交密钥、证书、完整私人诊断记录或尚未修复的漏洞细节。
启用仓库 Security → Advisories → Private vulnerability reporting 后，请使用该入口私下报告。
若入口尚未启用，请先联系仓库维护者确认私下沟通方式，不要直接公开敏感内容。

正式二进制由 Developer ID 签名并经 Apple 公证；后续 Release 只附带 DMG，使用 GitHub 自动生成的 SHA-256 摘要。
CI 与 alpha / beta / rc 仅使用 ad-hoc 签名，不能替代正式分发包。
安装包和自动化流程不会关闭 Gatekeeper、SIP 或自动移除隔离属性。README 提供仅针对 Neylu 的手动首次打开说明，是否允许未经公证的测试版由用户决定。
