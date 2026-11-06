# 安全反馈

目前维护最新发布版本。Neylu 本身不联网、不上传监控数据，也不要求管理员权限。

请不要在公开 Issue 中提交密钥、证书、完整私人诊断记录或尚未修复的漏洞细节。
启用仓库 Security → Advisories → Private vulnerability reporting 后，请使用该入口私下报告。
若入口尚未启用，请先联系仓库维护者确认私下沟通方式，不要直接公开敏感内容。

正式二进制由 Developer ID 签名并经 Apple 公证；Release 提供 SHA256SUMS。
CI 与 preview draft 仅使用 ad-hoc 签名，不能替代正式分发包。
不提供关闭 Gatekeeper、SIP 或移除隔离属性的安装脚本。
