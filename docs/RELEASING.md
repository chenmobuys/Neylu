# 发布维护

目标仓库：`chenmobuys/Neylu`。当前无 Developer ID 证书，先使用 preview 流程。
首发版本为 0.1.0-alpha.1，当前版本以仓库 VERSION 为准。Alpha / Beta / RC 创建 GitHub 预发布；自有 Homebrew tap 也支持这些测试版，不以 Developer ID 为前提。

## 一次性配置

1. 创建公开 GitHub 仓库 `chenmobuys/Neylu`，默认分支 `main`，把本目录作为仓库根目录。
2. Settings → Actions → General：允许 Actions；Workflow permissions 保持 read-only，无需开启 Actions 创建 PR；当前发布直接同步专用 tap，未使用自动 PR。各工作流按 job 单独申请写权限。
3. 创建名为 `release` 的 Environment。未来的签名 Secrets 放在此环境，不提交进仓库。可以按需要设置 required reviewers。
4. 启用 Issues、Security → Private vulnerability reporting。可给 main 设置要求 CI 通过的分支保护。
5. 查看 Actions 的首次 CI，确认 macOS 26 runner / Xcode 26+ 可用。工作流使用固定提交 SHA，Dependabot 每周检查 Actions 更新。

## 测试版：目前可用

```sh
git tag v$(cat VERSION)
git push origin v$(cat VERSION)
```

也可在 Actions → Release → Run workflow 输入已存在的 预发布 tag。
Tag 去掉 v 后必须完整等于 VERSION（包括预发布后缀），alpha / beta / rc 序号从 1 开始。
预发布版编译、测试和打包后创建 **prerelease**，明确标为早期测试版本，随后调用 Homebrew 工作流直接更新独立 tap，无需合并 PR。
两种架构分别在 macos-26（arm64）和 macos-26-intel（x86_64）原生 runner 上构建、运行测试。
CI 通过 `--ci-build` 生成仅用于开发验证的 ad-hoc 安装映像；公开 Release 不使用此选项，正式版仍强制检查 Developer ID 与公证。
图标保留 Apple 标准的 16、32、128、256、512 点及各自 2x 槽位（最高 1024 像素），从同一 SVG 生成一个 `AppIcon.icns`；渲染时将 RGB 按 8 级步长量化、保留完整 8 位透明度，再无损重编码 PNG，以减少细微渐变噪声；图案与轮廓不变，颜色精度略有降低。
DMG 挂载卷通过硬链接将 App 图标作为 `.VolumeIcon.icns`，不复制第二份数据，再写入 Finder 自定图标标记并转换为只读压缩映像；打包检查会验证两者共享同一 inode。
macOS 12 登录项查询由 `Sources/LegacyServiceManagement` 的头文件兼容模块提供，只在单次必需旧调用处局部处理弃用诊断，macOS 13+ 使用 SMAppService。应用、截图预览及性能构建共用 `scripts/swift-sources.sh` 的模块搜索参数；不全局关闭编译警告，也不打包新的运行时库。Swift Testing 以警告视为错误验证两种架构的 macOS 12 目标和 macOS 13 禁用边界。
CI 的 `scripts/test-ci.sh` 将测试编译与执行分开计时，执行时每 30 秒显示进度，90 秒采集进程堆栈，180 秒仍未完成则失败；不跳过任何 Swift Testing 用例，不运行空的 XCTest 阶段。所有回归由 `swift test --configuration release` 通过 Swift Testing 执行，测试目标不编入发布 App；截图夹具仅由 `scripts/render-docs.sh` 从 `Tests/Support` 编译，预览固定开机时长通过专用编译标记隔离，发布构建不包含演示模式、自动展开窗口或调试报告入口；主程序及更新辅助程序使用 `-Osize -whole-module-optimization`，在签名前通过 `strip -S -x` 清理调试与局部符号表，保留全局符号和运行时元数据。
最终 DMG 采用系统原生 ULMO / LZMA 压缩；系统工具说明其支持 macOS 10.15+，低于本项目 macOS 12 的最低要求。构建后校验映像，并只读挂载检查卷图标及共享存储。
后续公开附件只有两份 DMG 安装映像；不上传独立 SHA-256 文件或 manifest。GitHub 自动生成附件摘要，发布后工作流将其与本地最终 DMG 的大小和 SHA-256 逐一核对。Release notes 来自 CHANGELOG 中与完整版本精确匹配的章节。
Preview 只有 ad-hoc 签名，未经 Apple 公证。可先验证 CI 与附件；首次打开的手动确认方式见 README；安装脚本和 Cask 不自动删除隔离标记。更新器仅处理已验证辅助程序的私有副本，边界见 SECURITY.md。

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
先签名 `Contents/Helpers/NeyluUpdater` 和 `Contents/Library/LoginItems/NeyluLoginHelper.app`，再对 App 完成签名、公证、staple 和 Gatekeeper 检查，再制作 DMG；随后对 DMG 本身签名、公证和 staple，最后计算校验和。
任何一步失败都会停止正式发布，不会回退到未签名包。

1. 修改 VERSION、递增 BUILD_NUMBER；更新 CHANGELOG 对应版本段落。
2. 合并 CI 通过的发布准备改动。
3. 创建 `v版本号` tag 并 push。工作流创建正式 GitHub Release。
4. 工作流根据 **已签名、公证后的最终 DMG** 计算 SHA-256，再自动提交到独立 tap。
5. tap 自身执行 Ruby 语法与 Homebrew 风格检查；无需手动合并 PR。

工作流不覆盖已发布的附件：重跑时会下载既有附件并核对 GitHub 记录的 SHA-256 摘要；Cask 使用既有安装包的真实校验和。
若上传中途失败导致缺失附件，先检查 Release，不要替换已被下载的 DMG；必要时撤回不完整版本，用新版本号发布。
已公开版本不要移动 tag 或替换 DMG，否则会破坏已有校验和与安装。

## 静态 appcast

发布成功后，Release 工作流自动调用 `.github/workflows/appcast.yml`，与 Homebrew 同步独立运行：

1. 使用本仓库临时 `GITHUB_TOKEN` 读取已公开 Release，下载 ARM / Intel 两份最终 DMG，并复核 GitHub SHA-256、实际大小和仓库下载地址。
2. 从对应 tag 的 `BUILD_NUMBER` 读取构建号、`build.sh` 读取最低系统要求，`scripts/appcast.py` 生成 RSS/Sparkle 命名空间的架构独立订阅，保留各最近十个正式版及测试版。
3. `scripts/publish-appcast.py` 仅更新 `updates` 分支中的 `appcast-arm64.xml`、`appcast-x86_64.xml`，不修改源码分支或 Release 附件。同版本校验值、大小、构建号或最低系统要求变化会被拒绝；重跑旧版本保留更新版本，重复同步不产生提交。
4. 客户端通过 GitHub 静态内容服务读取固定 HTTPS 地址，不访问 REST API：
   - https://raw.githubusercontent.com/chenmobuys/Neylu/updates/appcast-arm64.xml
   - https://raw.githubusercontent.com/chenmobuys/Neylu/updates/appcast-x86_64.xml

无需额外服务器、个人 PAT、Apple Developer ID 或新的仓库 Secret。客户端使用系统 XMLParser，不捆绑 Sparkle 框架；`neylu:sha256` 扩展承载已核对的安装包摘要，继续执行已有的下载完整性、版本、架构和应用代码签名验证。这不是 Sparkle 的 EdDSA 更新签名，不能替代 Apple 签名、公证或独立的发布者身份认证；信任边界仍是本仓库的 HTTPS 发布渠道。

客户端拒绝 DTD、实体声明、外部实体、超限 XML、重复版本及不符合约束的安装包地址或摘要；不会退回未登录 GitHub API。正式版不接收测试版，最低 macOS 要求不满足的版本不会安装。

修改 appcast 发布脚本后，推送 main 会同步当前已公开版本，便于首次初始化。也可在 Actions → Appcast 手动输入已公开 tag 重跑；无需移动 tag、重新构建或替换既有 DMG。原 Homebrew 自动同步保持不变。

## Homebrew

安装定义独立存放在 [`chenmobuys/homebrew-tap`](https://github.com/chenmobuys/homebrew-tap)，应用源码与 Release 安装包留在 Neylu 仓库：

```sh
brew install --cask chenmobuys/tap/neylu
```

发布成功后，Release 工作流自动调用 `.github/workflows/homebrew.yml`：

1. 读取已公开 Release，下载 ARM / Intel 两份 DMG，验证完整版本、附件大小、实际 SHA-256 与 GitHub 摘要及下载地址归属。
2. 用专用部署密钥检出独立 tap；密钥只对该仓库有效。
3. `scripts/update-tap.py` 比较已有版本：拒绝降级，拒绝同版本校验和变化；重复同步不产生空提交。最低系统要求从发布 tag 的 `build.sh` 读取，不能用当前源码的要求覆盖历史安装包。
4. 仅提交 `Casks/neylu.rb` 并直接推送 main；tap 的 CI 自动检查 Ruby 与 Homebrew 风格。无需手动 PR。

### 一次性凭据配置

为 `chenmobuys/homebrew-tap` 添加独立的可写 Deploy key，私钥保存在 Neylu 的 `release` Environment Secret `HOMEBREW_TAP_DEPLOY_KEY`。不得复用个人 SSH 私钥；不需要个人 PAT。
使用固定 SHA 的 checkout action 管理临时 SSH 凭据与 GitHub 主机校验，结束时清理；源码检出不保存默认 token，工作流不输出私钥。
Homebrew 工作流的 `GITHUB_TOKEN` 仅具有读取权限，无法跨仓库写入；部署密钥负责限定仓库的推送。
后续轮换时先替换 tap 公钥与对应 Secret，再运行一次同步验证。

### 失败与重试

若同步失败，GitHub Release 已存在且附件不会被修改。修复后在 Neylu → Actions → Homebrew → Run workflow 输入已公开 tag，单独重试；不重新构建、不修改 VERSION、不覆盖安装包。
同步全局串行；过期 tag 不会覆盖较新版本。tap main 若启用必须 PR 的分支规则，需为发布自动化明确配置允许直接更新的规则，否则推送会失败。


不要在 Homebrew Cask 或安装自动化中添加 `sha256 :no_check`、自动删除 quarantine 或关闭 Gatekeeper 的步骤；这与已验证更新辅助程序私有副本的处理是两个不同范围。
自有 tap 不等于官方收录；未公证 Alpha 首次打开仍按 README 的系统确认步骤操作。

## 发布前文档核对

README.md 与 README.en.md 保持相同的功能和命令，不写固定的“当前版本”号；版本以 VERSION、Release 徽标和实际公开安装包为准。核对 CONTRIBUTING.md 的构建 SDK/运行要求、SECURITY.md 的网络与信任边界、docs/METRICS.md 的采样定义、两份 UPDATING 文档的安装和排错步骤。更新中英文 CHANGELOG 对应版本，保留历史章节原貌。Swift Testing 会验证本地链接、首页命令与入口一致性及最低系统要求。

## 本地检查

```sh
bash -n build.sh test.sh scripts/sign-and-notarize.sh
./build.sh
swift test --configuration release
python3 scripts/release.py validate --tag v$(cat VERSION)
python3 scripts/release.py package --app build/Neylu.app --output dist \
  --arch "$(uname -m)" --tag v$(cat VERSION)
```

本地打包后运行 `python3 scripts/release.py verify-assets --tag v$(cat VERSION) --output dist --arch "$(uname -m)"` 检查附件范围。发布后使用 `verify-github-assets --metadata 发布接口返回的JSON文件` 对比 GitHub 摘要，不生成额外附件。

更新器的真实 GitHub 下载回归可运行 `NEYLU_LIVE_UPDATE=1 swift test --configuration release --filter NeyluTests/updateSafety`；在有 GUI 会话的 Mac 上运行 `NEYLU_HELPER_INTEGRATION=1 swift test --configuration release --filter NeyluTests/nativeUpdaterReplacementAndRollback`，使用一次性测试 App 验证退出、替换和重启，不触碰已安装应用。

发布脚本拒绝覆盖同名附件。重新做本地实验时换一个输出目录即可，不必碰运行中的 App。
源码不包含本机 SQLite、缓存、证书或生成的应用。

## 参考

- [GitHub Actions 权限与安全](https://docs.github.com/en/actions/reference/security/secure-use)
- [macOS 26 runner](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)
- [Apple 公证](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Homebrew Cask Cookbook](https://docs.brew.sh/Cask-Cookbook)
- [官方 Cask 收录要求](https://docs.brew.sh/Acceptable-Casks)
