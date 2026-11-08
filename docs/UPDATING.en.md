# Updating and troubleshooting

[简体中文](UPDATING.md) · English

Login items use the legacy system API on macOS 12 and SMAppService on macOS 13 and later. The build-time compatibility wrapper does not change login-item behavior or saved preferences.

## Update methods

- Choose **Check for Updates…** in settings, then **Update Now** when a release is available.
- For Homebrew installations, run `brew update && brew upgrade --cask --greedy neylu`; `--greedy` includes apps with built-in updaters.
- Or download the DMG for your Mac from [GitHub Releases](https://github.com/chenmobuys/Neylu/releases), quit Neylu, and replace the app manually.

Automatic checks run once a day by default. An update adds a dot to the settings button and shows the available version in its menu; no window opens and no installer downloads automatically. Disable **Automatically Check for Updates** under **Preferences** to opt out. All installations check for stable releases by default, including installations running Alpha, Beta, or RC builds. To include pre-releases, explicitly select **Neylu Pre-release** under **Preferences → Beta Updates**; the default is **Off**. The choice persists across restarts and applies to both manual and background checks. Turning it off clears ineligible pre-release notices and cancels pending operations for the previous channel; it does not downgrade the installed app.

## First-launch or updater warnings

Current installers are not notarized by Apple. After confirming that the installer came from this repository and that you trust the release, follow [Apple’s instructions](https://support.apple.com/102445) to allow it through **System Settings → Privacy & Security → Open Anyway**.

You can also remove Neylu’s download-quarantine attribute manually:

```sh
xattr -dr com.apple.quarantine "/Applications/Neylu.app"
```

If the alert names `NeyluUpdater`, choose Done, cancel the update, run the command, and retry. The fix ships in alpha.6; upgrading from an older release still uses the old updater, so that first upgrade may require manual intervention. Use the actual path if the app is installed elsewhere.

This does not disable Gatekeeper or SIP, or repair a damaged signature or incompatible architecture. Do not use it to bypass an explicit malware warning. A new download or manual installation may require approval again; managed Macs may prevent users from adding exceptions.

Homebrew prints first-launch instructions in both languages with the actual installation path, but does not run the command automatically. `brew uninstall --cask neylu` preserves local data; adding `--zap` removes history and preferences.

## Discovery and installer verification

Since alpha.5, the client reads architecture-specific static appcasts, without using the GitHub REST API, an account, or a token. Through Alpha 7, manual and background checks share in-flight requests and a one-minute cache; static CDN caching can delay discovery. Starting with alpha.8, manual checks bypass completed cached results, and each feed transfer uses a fresh cache key and requests revalidation. Background checks retain their one-minute cache, and concurrent requests still coalesce. This fix takes effect after alpha.8 or later is installed. Earlier releases use the old endpoint; if they hit its rate limit, update through Homebrew or a DMG.

Installers are hosted on GitHub Releases. The release workflow verifies their digests before writing the appcasts. The updater validates SHA-256, full version, architecture, minimum macOS requirement, app identifier, and code signature. An installation already signed with Developer ID also enforces the Apple signing chain and Team ID. Since alpha.6, the running app and copied helper are verified before quarantine is removed only from the private helper copy; the source app, downloaded candidate, and unrelated metadata remain unchanged.

**Update Now** quits Neylu normally, replaces it, and relaunches it. Replacement failures, failed launch requests, or exit during the short startup observation period restore the previous installation. History and preferences live outside the app bundle and are preserved. When running from a DMG, under App Translocation, or from a location that cannot be replaced safely, Neylu opens the verified DMG for manual installation without requesting administrator privileges.

These checks do not replace Apple notarization. Ad hoc releases, including any explicitly disclosed stable release, rely on this repository’s GitHub HTTPS distribution channel for publisher trust. To verify a manual download, compare the output below with the SHA-256 digest beside the matching release asset:

```sh
shasum -a 256 ~/Downloads/Neylu-*.dmg
```

The command lists matching installers in Downloads; compare the file you intend to install. No separate checksum files or manifests are published.

## Data and compatibility

Monitoring data stays local; there is no telemetry. CPU, GPU, memory, and network history is retained for 24 hours in `~/Library/Application Support/Neylu/history.sqlite`. The directory uses mode 0700; the database and WAL use 0600. Choose two-minute, fifteen-minute, or one-hour views in Preferences → Chart Time Range. Rendering is reduced, while SQLite retains the original records. See the [metrics reference — Chinese](METRICS.md) for definitions.

Releases from alpha.5 support macOS 12 and later; earlier builds require macOS 13. Both architectures have CI builds and regression checks. Sensors have been tested on an M3 Max; macOS 12 has not been tested on a physical device, and other hardware may lack some readings.

When reporting an issue, include the Neylu version, macOS version, chip, and error text. Redact IP addresses and local paths from diagnostics. Report security issues privately as described in the [security policy](../SECURITY.md).

## Energy saving and diagnostics

**Preferences → Energy Saving** lists Follow System, On, and Off, in that order; Off remains the default. Follow System responds to macOS Low Power Mode. When active, sampling runs at intervals of at least five seconds while the overview is closed; opening it restores the configured interval. Background history continues. Detail-only disk I/O sampling pauses, and reopening establishes fresh baselines. Temperature is sampled when the overview is open or the menu bar temperature item is enabled, at most once every five seconds.

Choose **Copy Diagnostics** in the settings menu or About window to copy version, system, processor, refresh policy, and metric availability. IP addresses, interface/disk names, paths, logs, and actual monitoring values are excluded; nothing is sent automatically. Some fields normally show “Unavailable or not sampled” while details are closed; that does not establish that the hardware is unsupported.

## Display and chart interaction

Menu Bar Items provides a preview and metric visibility/order, with Restore Default Layout beside the metric heading. CPU Temperature is disabled by default and can be enabled and reordered on supported devices; temporary missing readings display “—”. Menu bar memory always shows a percentage with a stable width; used, available, and total capacity remain in the overview. **Preferences → Unit Basis** selects decimal or binary units globally. Network rates always use bytes per second, with no separate bit-rate mode. Restore Default Layout resets only metric order and visibility, preserving history and other preferences.

Click any chart to pin the time range and readouts across all four charts. Background recording and live menu bar values continue. Click again or use the play button at the top to resume live charts. Closing the overview or changing its history range also resumes live charts. Inspection selects actual samples only. Readouts follow the selected time within the plot bounds, and pinned charts display Charts Pinned in the header. Preferences → Chart Time Range offers Last 2 minutes, Last 15 minutes, or Last hour, independently of the refresh interval; the overview header no longer contains a range selector.

The eye button beside the IP address in the overview masks both the address and its tooltip; click it again to reveal them. This preference persists across launches; copied diagnostics always exclude the IP address.

In **Preferences → Global Shortcut…**, click the recording field, press a combination containing Control, Option, or Command–Shift, and click Save to show or hide the overview. Save remains disabled until a valid combination is recorded. No shortcut is assigned by default. You can remove it at any time; registration failures preserve the previous shortcut. Shortcuts use physical key positions; after changing keyboard layouts, remove and re-record the shortcut to update its displayed name. Registration uses the system hotkey API, without Accessibility permission or a global keyboard event monitor.

## Failures and retries

Invalid release information prompts a fresh check. Network interruptions, checksum failures, and app validation failures offer a new download with full verification. Installation or launch failures offer another installation attempt or a DMG from the download page. Failed verification never reuses an untrusted installer.

Closing or cancelling the update window invalidates old callbacks, and reopening it starts a fresh check. Each attempt owns a separate private directory with mode 0700; failure or cancellation cleans only that attempt after background preparation stops. Files handed to the verified updater are owned by the helper; a verified DMG opened in Finder remains available for manual installation. A still-mounted image is neither recursively deleted nor forcibly detached.

The [download page](https://github.com/chenmobuys/Neylu/blob/updates/downloads.md) selects the latest published installer pair by semantic version and shows each architecture's system requirement, independent of GitHub list order.

## Preparation timeouts and cancellation

A completed manual check takes precedence over older background requests. Preparation commands have a default 120-second timeout; copying the app allows up to 300 seconds. Commands stop when output exceeds 1 MiB. Cancellation stops and reaps the owned subprocess before its private files are removed. Each image-detach command has a 30-second timeout, with bounded retries only when busy and no forced unmount. If detachment fails, the mounted workspace is preserved to avoid recursive deletion of image contents.

The in-app Beta Updates choice does not configure Homebrew. Once the default cask reaches its first stable release, later previews will not replace it; previews remain available before the first stable release. Opt in through the app or install the corresponding DMG to try pre-releases.
