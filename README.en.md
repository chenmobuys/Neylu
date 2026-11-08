<p align="center"><img src="Assets/AppIcon-v5-vector.svg" width="96" alt="Neylu icon"></p>
<h1 align="center">Neylu</h1>
<p align="center"><a href="README.md">简体中文</a> · English</p>
<p align="center">A compact, native system monitor for the macOS menu bar.</p>

[![CI](https://github.com/chenmobuys/Neylu/actions/workflows/ci.yml/badge.svg)](https://github.com/chenmobuys/Neylu/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/chenmobuys/Neylu?sort=semver)](https://github.com/chenmobuys/Neylu/releases/latest)
[![MIT](https://img.shields.io/github/license/chenmobuys/Neylu)](LICENSE)
![macOS 12+](https://img.shields.io/badge/macOS-12%2B-111827?logo=apple&logoColor=white)
![Apple Silicon and Intel](https://img.shields.io/badge/arch-arm64%20%7C%20x86__64-007AFF)
![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white)
[![Stars](https://img.shields.io/github/stars/chenmobuys/Neylu)](https://github.com/chenmobuys/Neylu/stargazers)

<p align="center"><picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/overview-dark-en@2x.png">
  <img src="docs/images/overview-light-en@2x.png" width="380" alt="Neylu overview">
</picture></p>

The preview uses demonstration readings. Native materials adapt to the system appearance and desktop background.

## Features

- Network, memory, GPU, CPU, and system disk metrics in one menu bar item; choose what to show, reorder metrics, and select compact or standard spacing.
- Live charts, CPU temperature on supported hardware, and disk capacity and read/write rates; monitor and eject external drives.
- Native glass on macOS 26+, system materials on earlier releases, and automatic/light/dark appearance. Login items use SMAppService on macOS 13+ and the legacy system API on macOS 12.
- English and Simplified Chinese; configurable refresh intervals, decimal or binary units, and energy-saving options.
- Local history retained for 24 hours, with two-minute, fifteen-minute, and one-hour chart views and pinned historical readouts. Network charts mark peaks above the displayed range and show original upload/download rates on hover. No telemetry or monitoring-data uploads.
- Built-in update checks, verified installers, cancellable preparation, contextual retry actions, and release notes after upgrades.

## Metric availability

Neylu adapts to the current macOS version, hardware, and accessible data sources. Metrics without a detected supported source are hidden from the menu bar, overview, and selection/reordering list in Menu Bar Items, rather than shown as disabled placeholders.

- CPU temperature requires a readable supported sensor; GPU utilization requires an exposed total-utilization counter. Optional Renderer, Tiler, GPU core-count, and disk I/O fields are also shown only when a source is available. Support varies by device and macOS version.
- Disconnection, post-wake baseline initialization, and temporary read failures do not establish a lack of support. Previously detected metrics remain visible, with missing readings shown as “—”, never a fabricated zero.
- Hiding preserves saved visibility, order, and history. Sources are probed at startup, and temperature sensors are checked again after wake; restored sources can reappear.

## Install

Requires **macOS 12 or later**, on Apple Silicon or Intel. The [download page](https://github.com/chenmobuys/Neylu/blob/updates/downloads.md) selects the latest installers by semantic version; [all releases](https://github.com/chenmobuys/Neylu/releases) remain available.

```sh
brew install --cask chenmobuys/tap/neylu
```

Or download a DMG: choose `arm64` for Apple Silicon or `x86_64` for Intel, open it, and drag **Neylu.app** into **Applications**. Xcode and an Apple Developer membership are not required to use the app.


Beta Updates are Off by default, so all installations check only for stable releases. Choose **Preferences → Beta Updates → Neylu Pre-release** to opt in to Alpha, Beta, and RC releases.

## First launch

Current installers are ad hoc signed and **not notarized by Apple**. If macOS blocks it, follow [Apple’s instructions](https://support.apple.com/102445) to choose **Open Anyway**. If you trust the downloaded Neylu, you can instead run:

```sh
xattr -dr com.apple.quarantine "/Applications/Neylu.app"
```

Use your actual installation path. This affects only Neylu; it does not disable Gatekeeper or SIP. See [update troubleshooting](docs/UPDATING.en.md) if the alert names `NeyluUpdater`.

## Use

- Left-click the menu bar readings to open the overview; right-click, or use **…**, to open settings.
- **Menu Bar Items…** selects and reorders metrics or restores the default layout; **Appearance** changes the theme; **Preferences** contains refresh interval, energy saving, unit basis, a global shortcut, language, login, and automatic update checks.
- Choose a chart time range in **Preferences → Chart Time Range**; hover or use Left/Right Arrow keys to inspect real samples; click a chart to pin it, then click again or use the play button to resume live charts. Press Escape to close details and utility windows.
- View the MIT license and third-party notices in an in-app window from About, or copy their full text. Copy diagnostics without IP addresses or paths from the menu or About window. Choose **Check for Updates…**, or update with `brew update && brew upgrade --cask --greedy neylu`.

## Documentation

- [Updating and troubleshooting](docs/UPDATING.en.md)
- [Metrics and hardware compatibility — Chinese](docs/METRICS.md)
- [Build and contribution guide — Chinese](CONTRIBUTING.md)
- [Release automation — Chinese](docs/RELEASING.md)
- [Changelog](CHANGELOG.md) · [Security](SECURITY.md) · [MIT License](LICENSE) · [Attributions](THIRD_PARTY_NOTICES.md)

[Compatibility validation and untested environments](docs/COMPATIBILITY.md)

[正式版验收记录 / Release readiness](docs/RELEASE-READINESS.md)
