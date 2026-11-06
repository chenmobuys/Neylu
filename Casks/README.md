# Homebrew Cask

首个已签名、公证的 stable Release 发布后，工作流会生成真实 SHA-256 的
`Casks/neylu.rb` 并创建更新 PR。合并该 PR 后才能通过 tap 安装。

不预置虚假下载地址、占位校验和或 `sha256 :no_check`。
Preview / 未公证构建不会进入此目录的稳定 Cask。

首次安装使用 README 中包含仓库 URL 的 `brew tap` 命令。
本仓库作为自有 tap；不是 Homebrew 官方 Cask 仓库。
