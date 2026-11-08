# Updating and troubleshooting

[简体中文](UPDATING.md) · English

## Update methods

- Choose **Check for Updates…** in settings, then **Update Now** when a release is available.
- For Homebrew installations, run `brew update && brew upgrade --cask --greedy neylu`; `--greedy` includes apps with built-in updaters.
- Or download the DMG for your Mac from [GitHub Releases](https://github.com/chenmobuys/Neylu/releases), quit Neylu, and replace the app manually.

Automatic checks run once a day by default. An update adds a dot to the settings button and shows the available version in its menu; no window opens and no installer downloads automatically. Disable **Automatically Check for Updates** under **Preferences** to opt out. Stable builds receive stable releases only; Alpha, Beta, and RC builds also receive subsequent previews.

## First-launch or updater warnings

The current Alpha is not notarized by Apple. After confirming that the installer came from this repository and that you trust the release, follow [Apple’s instructions](https://support.apple.com/102445) to allow it through **System Settings → Privacy & Security → Open Anyway**.

You can also remove Neylu’s download-quarantine attribute manually:

```sh
xattr -dr com.apple.quarantine "/Applications/Neylu.app"
```

If the alert names `NeyluUpdater`, choose Done, cancel the update, run the command, and retry. The fix ships in alpha.6; upgrading from an older release still uses the old updater, so that first upgrade may require manual intervention. Use the actual path if the app is installed elsewhere.

This does not disable Gatekeeper or SIP, or repair a damaged signature or incompatible architecture. Do not use it to bypass an explicit malware warning. A new download or manual installation may require approval again; managed Macs may prevent users from adding exceptions.

Homebrew prints first-launch instructions in both languages with the actual installation path, but does not run the command automatically. `brew uninstall --cask neylu` preserves local data; adding `--zap` removes history and preferences.

## Discovery and installer verification

Since alpha.5, the client reads architecture-specific static appcasts, without using the GitHub REST API, an account, or a token. Manual and background checks share in-flight requests and a one-minute cache. Earlier releases use the old endpoint; if they hit its rate limit, update through Homebrew or a DMG.

Installers are hosted on GitHub Releases. The release workflow verifies their digests before writing the appcasts. The updater validates SHA-256, full version, architecture, minimum macOS requirement, app identifier, and code signature. An installation already signed with Developer ID also enforces the Apple signing chain and Team ID. Since alpha.6, the running app and copied helper are verified before quarantine is removed only from the private helper copy; the source app, downloaded candidate, and unrelated metadata remain unchanged.

**Update Now** quits Neylu normally, replaces it, and relaunches it. Replacement failures, failed launch requests, or exit during the short startup observation period restore the previous installation. History and preferences live outside the app bundle and are preserved. When running from a DMG, under App Translocation, or from a location that cannot be replaced safely, Neylu opens the verified DMG for manual installation without requesting administrator privileges.

These checks do not replace Apple notarization. Preview releases still rely on this repository’s GitHub HTTPS distribution channel for publisher trust. To verify a manual download, compare the output below with the SHA-256 digest beside the matching release asset:

```sh
shasum -a 256 ~/Downloads/Neylu-*.dmg
```

The command lists matching installers in Downloads; compare the file you intend to install. No separate checksum files or manifests are published.

## Data and compatibility

Monitoring data stays local; there is no telemetry. CPU, GPU, memory, and network history is retained for 24 hours in `~/Library/Application Support/Neylu/history.sqlite`. The directory uses mode 0700; the database and WAL use 0600. Choose two-minute, fifteen-minute, or one-hour views at the top of the overview. Rendering is reduced, while SQLite retains the original records. See the [metrics reference — Chinese](METRICS.md) for definitions.

Releases from alpha.5 support macOS 12 and later; earlier builds require macOS 13. Both architectures have CI builds and regression checks. Sensors have been tested on an M3 Max; macOS 12 has not been tested on a physical device, and other hardware may lack some readings.

When reporting an issue, include the Neylu version, macOS version, chip, and error text. Redact IP addresses and local paths from diagnostics. Report security issues privately as described in the [security policy](../SECURITY.md).

## Energy saving and diagnostics

**Preferences → Energy Saving** offers Off (the default), Follow System Low Power Mode, and On. When active, sampling runs at intervals of at least five seconds while the overview is closed; opening it restores the configured interval. Background history continues. Detail-only temperature and disk I/O sampling pauses, and reopening establishes fresh baselines.

Choose **Copy Diagnostics** in the settings menu or About window to copy version, system, processor, refresh policy, and metric availability. IP addresses, interface/disk names, paths, logs, and actual monitoring values are excluded; nothing is sent automatically. Some fields normally show “Unavailable or not sampled” while details are closed; that does not establish that the hardware is unsupported.
