# 发布维护

目标仓库：`chenmobuys/Neylu`。当前无 Developer ID 证书，先使用 preview 流程。
以下描述已准备的自动化配置；首次上传前，本地检查不能替代 GitHub 实际运行结果。

## 一次性配置

1. 创建公开 GitHub 仓库 `chenmobuys/Neylu`，默认分支 `main`，把本目录作为仓库根目录。
2. Settings → Actions → General：允许 Actions；Workflow permissions 保持 read-only，勾选允许 GitHub Actions 创建 PR。各工作流按 job 单独申请写权限。
3. 创建名为 `release` 的 Environment。未来的签名 Secrets 放在此环境，不提交进仓库。可以按需要设置 required reviewers。
4. 启用 Issues、Security → Private vulnerability reporting。可给 main 设置要求 CI 通过的分支保护。
5. 查看 Actions 的首次 CI，确认 macOS 26 runner / Xcode 26+ 可用。工作流使用固定提交 SHA，Dependabot 每周检查 Actions 更新。

## 测试版：目前可用

```sh
git tag v1.0.40-preview.1
git push origin v1.0.40-preview.1
```

也可在 Actions → Release → Run workflow 输入已存在的 preview tag。
Tag 的基础版本必须等于 VERSION，preview 序号从 1 开始。
测试版编译、测试和打包后创建 **draft prerelease**，不自动向普通用户发布，也不更新稳定 Cask。
附件包括 arm64 ZIP、SHA256SUMS、release.json；Release notes 来自 CHANGELOG 的版本章节。
Preview 只有 ad-hoc 签名，未经 Apple 公证。可先验证 CI 与附件；不提供绕过 Gatekeeper 的脚本。

## 正式版：有 Developer ID 后启用

在 `release` Environment 配置以下 Secrets：

| Secret | 内容 |
| --- | --- |
| APPLE_CERTIFICATE_BASE64 | Developer ID Application 证书与私钥的 p12，base64 编码 |
| APPLE_CERTIFICATE_PASSWORD | p12 导出密码 |
| APPLE_SIGNING_IDENTITY | 完整 `Developer ID Application: … (…)` 名称 |
| APPLE_API_KEY_BASE64 | App Store Connect API 私钥 .p8 的 base64 内容 |
| APPLE_API_KEY_ID | API Key ID |
| APPLE_API_ISSUER_ID | API Issuer ID |

私钥仅写入 runner 临时目录，权限 0700/0600；独立临时钥匙串在结束时删除，不修改默认钥匙串或输出密钥。
签名、公证提交、Accepted 状态、staple 和 Gatekeeper 检查全部通过后才打包。
任何一步失败都会停止正式发布，不会回退到未签名包。

1. 修改 VERSION、递增 BUILD_NUMBER；更新 CHANGELOG 对应版本段落。
2. 合并 CI 通过的发布准备改动。
3. 创建 `v版本号` tag 并 push。工作流创建正式 GitHub Release。
4. 工作流根据 **已签名、公证后的最终 ZIP** 计算 SHA-256，生成 Cask，自动打开更新 PR。
5. 检查并合并 Cask PR 后 tap 才对外生效。不会自动合并到 main。

工作流不覆盖已发布的附件：重跑时会下载既有附件并校验 manifest、ZIP 与 Cask 一致性。
若上传中途失败导致缺失附件，先检查 Release，不要替换已被下载的 ZIP；必要时撤回不完整版本，用新版本号发布。
已公开版本不要移动 tag 或替换 ZIP，否则会破坏已有校验和与安装。

## Homebrew

Neylu 是 GUI App，使用 Cask 而不是 Formula。本仓库同时作为自有 tap：

```sh
brew tap chenmobuys/neylu https://github.com/chenmobuys/Neylu
brew install --cask chenmobuys/neylu/neylu
```

首次安装前需有正式 Release 及已合并的 `Casks/neylu.rb`。
GitHub 默认 token 无法触发它自己创建的 PR 的普通 CI，这是平台行为；Cask PR只改下载元数据，维护者可手动运行 CI 并核对 Release SHA 后合并。
需要验证 Cask 时，可在 macOS 上运行 `brew style Casks/neylu.rb` 和 `brew audit --cask --online chenmobuys/neylu/neylu`。
后者会访问已发布链接，首次真实 Release 前不可能完成。
不要添加 `sha256 :no_check`、quarantine 删除或 Gatekeeper 绕过步骤。

后续如希望加入 Homebrew 官方 `homebrew/cask`，需另外满足其收录规则并提交 PR；自有 tap 发布不等于官方收录。

## 本地检查

```sh
bash -n build.sh test-history.sh scripts/sign-and-notarize.sh
python3 -m unittest discover -s Tests -p 'test_*.py' -v
./test-history.sh
./build.sh
build/Neylu.app/Contents/MacOS/Neylu --self-test
python3 scripts/release.py validate --tag v1.0.40-preview.1
python3 scripts/release.py package --app build/Neylu.app --output dist \
  --repository chenmobuys/Neylu --tag v1.0.40-preview.1
```

发布脚本拒绝覆盖同名附件。重新做本地实验时换一个输出目录即可，不必碰运行中的 App。
源码不包含本机 SQLite、缓存、证书或生成的应用。

## 参考

- [GitHub Actions 权限与安全](https://docs.github.com/en/actions/reference/security/secure-use)
- [macOS 26 runner](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)
- [Apple 公证](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Homebrew Cask Cookbook](https://docs.brew.sh/Cask-Cookbook)
- [官方 Cask 收录要求](https://docs.brew.sh/Acceptable-Casks)
