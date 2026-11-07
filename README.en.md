<p align="center"><img src="Assets/AppIcon-v5-vector.svg" width="112" alt="Neylu icon"></p>
<h1 align="center">Neylu</h1>
<p align="center"><a href="README.md">简体中文</a> · English</p>

A compact, native system monitor for the macOS menu bar.

[![CI](https://github.com/chenmobuys/Neylu/actions/workflows/ci.yml/badge.svg)](https://github.com/chenmobuys/Neylu/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/chenmobuys/Neylu?include_prereleases)](https://github.com/chenmobuys/Neylu/releases)
[![License: MIT](https://img.shields.io/github/license/chenmobuys/Neylu)](LICENSE)

<p align="center"><img src="docs/images/overview-light-en@2x.png" width="380" alt="Neylu overview: CPU, GPU, memory, network, and disk activity"></p>

The preview uses demonstration readings and a documentation-only IP address. In the running app, native materials adapt to the system appearance and desktop background.

## Features

- One menu bar item with configurable metrics and drag-and-drop ordering.
- CPU and GPU utilization, memory usage, network transfer rates, and disk usage and I/O.
- External disk monitoring with native eject controls.
- Automatic, light, and dark appearance; English and Simplified Chinese.
- Local history retained for 24 hours, with a two-minute chart view. No telemetry or monitoring-data uploads.
- Manual update checks against GitHub Releases, verified downloads, and installation with rollback.

## Install

**Current version: 0.1.0-alpha.2.** Requires macOS 13 or later. This is an early preview, ad hoc signed and not notarized by Apple. You do not need Xcode or an Apple Developer membership to use it.

1. Download a DMG from [GitHub Releases](https://github.com/chenmobuys/Neylu/releases): choose `arm64` for Apple Silicon or `x86_64` for Intel.
2. Open the DMG and drag **Neylu.app** into **Applications**.
3. Open Neylu from Applications. Its readings appear in the menu bar; there is no Dock icon.

GitHub provides a SHA-256 digest for each release asset. To verify a downloaded installer, compare that digest with the output of:

```sh
shasum -a 256 Neylu-0.1.0-alpha.2-arm64.dmg
```

### If macOS prevents the app from opening

First confirm that you downloaded the app from this repository and trust the release. Follow [Apple’s instructions](https://support.apple.com/102445) to allow it in **System Settings → Privacy & Security → Open Anyway**, then confirm the system prompt.

If needed, after moving the app to Applications, you can remove its download-quarantine attribute manually:

```sh
xattr -dr com.apple.quarantine "/Applications/Neylu.app"
```

This command affects only Neylu. It does not sign or notarize the app, disable Gatekeeper or SIP, or repair a damaged or incompatible download. Downloading or updating the app may require approval again. Do not use it to bypass a warning that the app will damage your computer.

## Use

Click the menu bar readings to open the overview. Right-click them, or use the overview’s **…** button, to open settings. Choose **Menu Bar Items…** to select metrics and reorder them. Settings take effect immediately.

Choose **Check for Updates…** to check GitHub. **Update Now** downloads and verifies the installer, quits Neylu normally, replaces the app, and relaunches it. If replacement fails or the new app quits during the startup observation period, the previous installation is restored. History and preferences are kept outside the app bundle and remain intact.

If the current location cannot be safely replaced, Neylu opens the verified DMG for manual installation. It does not request administrator privileges or remove quarantine attributes automatically. Update checks are user-initiated and do not require a GitHub account.

The application identifier is `io.github.chenmobuys.Neylu`. Preview builds check for newer previews and stable releases; stable builds check for stable releases only.

## Homebrew

Install from the independent [homebrew-tap](https://github.com/chenmobuys/homebrew-tap). Homebrew selects the installer for your Mac’s architecture. The current release is an Alpha preview, ad hoc signed and not notarized by Apple; the first-launch instructions above still apply. No Apple Developer membership is required.

```sh
brew install --cask chenmobuys/tap/neylu
```

Homebrew prints first-launch instructions and the `xattr` command after installation. If macOS blocks the app and you trust this release, run the following, then reopen Neylu:

```sh
xattr -dr com.apple.quarantine "/Applications/Neylu.app"
```

To install and explicitly remove the download-quarantine attribute in one step (using the default Applications directory):

```sh
brew install --cask chenmobuys/tap/neylu &&
xattr -dr com.apple.quarantine "/Applications/Neylu.app"
```

This affects only Neylu. You can instead use **System Settings → Privacy & Security → Open Anyway**. If you install with `--appdir`, use the actual installation path; Homebrew’s post-installation message shows that path.

The fully qualified name identifies the account, tap, and cask. Homebrew 6+ trusts that individual cask when you install it by its full name; afterward, the short name `neylu` can be used.
Update with `brew update && brew upgrade --cask --greedy neylu`; `--greedy` includes apps with built-in updaters. Uninstall with `brew uninstall --cask neylu`. Adding `--zap` also deletes local history and preferences.

Successful releases automatically verify and update the cask; no manual pull-request merge is required.

This is a third-party tap, not inclusion in the official Homebrew Cask repository. Downloads are verified against architecture-specific SHA-256 checksums; installation does not remove quarantine attributes automatically.

## Build and contribute

Building requires Xcode 26 or later, including the macOS 26 SDK. The deployment target remains macOS 13.

```sh
./build.sh
./test-history.sh
./test-runtime.sh
./test-updates.sh
python3 -m unittest discover -s Tests -p 'test_*.py' -v
```

The app is written to `build/Neylu.app`; runtime tests are built separately. See [contribution guidelines](CONTRIBUTING.md), [release maintenance](docs/RELEASING.md), and the [changelog](CHANGELOG.md).

Temperature readings have been tested on an M3 Max. Other sensor mappings and older macOS versions need further hardware testing. Missing metrics are shown as unavailable rather than zero.

Licensed under the [MIT License](LICENSE). Third-party attributions are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Report security issues privately as described in [SECURITY.md](SECURITY.md).
