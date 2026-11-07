import AppKit
import Foundation
import CryptoKit

L10n.useResources(at: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources"))

func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    guard value() else { fatalError(message) }
}
func rejects(_ message: String, _ operation: () throws -> Void) {
    do { try operation(); fatalError(message) } catch { }
}
let fm = FileManager.default
let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("Neylu-update-tests-" + UUID().uuidString)
try fm.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
defer { try? fm.removeItem(at: root) }

for failure in UpdateFailure.allCases {
    let english = failure.message(language: .english)
    let chinese = failure.message(language: .simplifiedChinese)
    expect(english != chinese && english.range(of: #"[\u4e00-\u9fff]"#, options: .regularExpression) == nil, "Update/helper error was not translated")
}
expect(UpdateFailure.describe(URLError(.notConnectedToInternet), language: .english).contains("GitHub"), "Network guidance missing")
expect(UpdateFailure.describe(CancellationError(), language: .english) == "Update cancelled", "Cancellation was not localized")
expect(L10n.cores(1, language: .english) == "1 core" && L10n.cores(40, language: .english) == "40 cores", "Core pluralization")
print("PASS update and helper errors use shared professional English/Chinese messages")

let ordered = ["0.1.0-alpha.2", "0.1.0-alpha.10", "0.1.0-beta.1", "0.1.0-rc.1", "0.1.0", "0.1.1-alpha.1", "0.2.0", "1.0.0"]
expect(ordered.compactMap(ReleaseVersion.init).sorted().map(\.text) == ordered, "SemVer ordering")
for bad in ["v0.1.0", "01.0.0", "1.0", "1.0.0-alpha.0", "1.0.0-rc.1/../../", "9999999999999999999999.0.0"] {
    expect(ReleaseVersion(bad) == nil, "Unsafe or unsupported version accepted")
}

func release(_ version: String, arch: String = "arm64", urlOverride: String? = nil, draft: Bool = false) -> GitHubRelease {
    let file = "Neylu-\(version)-\(arch).dmg"
    let base = AvailableUpdate.repository + "/releases/download/v\(version)/"
    let digest = "sha256:" + SHA256.hash(data: Data([1, 2, 3, 4])).map { String(format: "%02x", $0) }.joined()
    return GitHubRelease(tag_name: "v" + version, html_url: AvailableUpdate.repository + "/releases/tag/v" + version,
                         body: "Release notes", draft: draft, prerelease: version.contains("-"), assets: [
                            .init(name: file, browser_download_url: urlOverride ?? base + file, size: 4, state: "uploaded", digest: digest)])
}
let bilingual = AvailableUpdate(version: ReleaseVersion("0.2.0")!, notes: "<!-- neylu:en -->\nRelease highlights\n<!-- neylu:zh-Hans -->\n更新摘要", page: URL(string: AvailableUpdate.repository)!, package: URL(string: AvailableUpdate.repository)!, digest: "", size: 0, filename: "")
expect(bilingual.releaseNotes(language: .english) == "Release highlights", "English release notes leaked another language")
expect(bilingual.releaseNotes(language: .simplifiedChinese) == "更新摘要", "Chinese release notes selection")
let markdown = ReleaseNotesRenderer.render("### 中文 更新\n\n- **重点：** 内容与 `xattr`。\n- [GitHub](https://github.com/chenmobuys/Neylu)\n\nEnglish *notes* with ~~removed~~ text.")
expect(markdown.string == "中文 更新\n•\t重点： 内容与 xattr。\n•\tGitHub\nEnglish notes with removed text.", "Markdown blocks or inline syntax rendered incorrectly")
func attrs(_ text: String) -> [NSAttributedString.Key: Any] {
    markdown.attributes(at: (markdown.string as NSString).range(of: text).location, effectiveRange: nil)
}
expect((attrs("中文")[.font] as! NSFont).pointSize > 12, "Heading typography missing")
expect(NSFontManager.shared.traits(of: attrs("重点")[.font] as! NSFont).contains(.boldFontMask), "Strong emphasis missing")
expect(NSFontManager.shared.traits(of: attrs("notes")[.font] as! NSFont).contains(.italicFontMask), "Italic emphasis missing")
expect((attrs("xattr")[.font] as! NSFont).isFixedPitch, "Inline code is not monospaced")
expect(attrs("GitHub")[.link] as? URL == URL(string: "https://github.com/chenmobuys/Neylu"), "Release link lost")
expect(attrs("removed")[.strikethroughStyle] != nil, "Strikethrough missing")
let unsafe = ReleaseNotesRenderer.render("[local](file:///tmp/test) [script](javascript:alert) ![image](https://example.com/image.png)")
unsafe.enumerateAttributes(in: NSRange(location: 0, length: unsafe.length)) { values, _, _ in
    expect(values[.link] == nil && values[.attachment] == nil, "External content or unsafe link enabled")
}
let numbered = ReleaseNotesRenderer.render("1. First\n2. Second\n\n```sh\necho Neylu\n```")
expect(numbered.string.contains("1.\tFirst\n2.\tSecond"), "Ordered list separators missing")
let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 372, height: 150))
view.isVerticallyResizable = true
view.textContainer?.containerSize = NSSize(width: 372, height: CGFloat.greatestFiniteMagnitude)
let longNotes = ReleaseNotesRenderer.render(Array(repeating: "- **Update:** A native Markdown release note with enough text to wrap onto another line.", count: 20).joined(separator: "\n"))
view.textStorage?.setAttributedString(longNotes)
view.layoutManager?.ensureLayout(for: view.textContainer!)
expect(view.layoutManager!.usedRect(for: view.textContainer!).height > 150, "Long release notes do not produce scrollable content")
print("PASS native Markdown headings, lists, emphasis, code, safe links and long-note layout")

let notesSuite = "Neylu-release-notes-test-" + UUID().uuidString
let notesDefaults = UserDefaults(suiteName: notesSuite)!
defer { notesDefaults.removePersistentDomain(forName: notesSuite) }
expect(!ReleaseNotesHistory.shouldPresent(current: "invalid", defaults: notesDefaults), "Invalid launch version prompted")
expect(!ReleaseNotesHistory.shouldPresent(current: "0.1.0-alpha.3", defaults: notesDefaults), "First launch must stay silent")
expect(!ReleaseNotesHistory.shouldPresent(current: "0.1.0-alpha.3", defaults: notesDefaults), "Restart prompted")
expect(ReleaseNotesHistory.shouldPresent(current: "0.1.0-alpha.4", defaults: UserDefaults(suiteName: notesSuite)!), "Upgrade did not prompt using persisted state")
expect(!ReleaseNotesHistory.shouldPresent(current: "0.1.0-alpha.4", defaults: notesDefaults), "Upgrade prompted twice")
expect(!ReleaseNotesHistory.shouldPresent(current: "0.1.0-alpha.3", defaults: notesDefaults), "Downgrade prompted")
expect(!ReleaseNotesHistory.shouldPresent(current: "0.1.0-alpha.4", defaults: notesDefaults), "Reinstall of an already-seen version prompted")
expect(ReleaseNotesHistory.shouldPresent(current: "0.1.0-alpha.10", defaults: notesDefaults), "Alpha iteration compared lexically")
expect(ReleaseNotesHistory.shouldPresent(current: "0.1.0", defaults: notesDefaults), "Stable upgrade did not prompt")
expect(!ReleaseNotesHistory.shouldPresent(current: "0.1.0-alpha.11", defaults: notesDefaults), "Preview downgrade prompted after stable")
print("PASS release notes first-launch baseline, persistent once-per-upgrade prompts, restarts, reinstalls and downgrades")

let current = ReleaseVersion("0.1.0-alpha.3")!
let releases = [release("0.1.0-alpha.2"), release("0.2.0-alpha.1"), release("0.1.0"), release("1.0.0", draft: true)]
expect(AvailableUpdate.newest(in: releases, current: current, architecture: "arm64")?.version.text == "0.2.0-alpha.1", "Preview selection")
expect(AvailableUpdate.newest(in: releases, current: ReleaseVersion("0.0.1")!, architecture: "arm64")?.version.text == "0.1.0", "Stable must not receive previews")
expect(AvailableUpdate.newest(in: releases, current: current, architecture: "x86_64") == nil, "Wrong architecture")
expect(AvailableUpdate.newest(in: [release("0.2.0", urlOverride: "https://evil.example/payload.dmg")], current: current, architecture: "arm64") == nil, "Foreign download URL")
expect(AvailableUpdate.newest(in: [release("0.2.0", urlOverride: "https://github.com/another/repo/releases/download/v0.2.0/Neylu-0.2.0-arm64.dmg")], current: current, architecture: "arm64") == nil, "Foreign repository")
for bad in ["http://github.com/a", "https://github.com.evil.example/a", "https://github.com:8443/a", "https://user:password@github.com/a", "file:///tmp/a"] {
    expect(!UpdateDownload.allowed(URL(string: bad)!), "Unsafe redirect accepted")
}
expect(UpdateDownload.allowed(URL(string: "https://release-assets.githubusercontent.com/github-production-release-asset/a?token=example")!), "GitHub CDN rejected")
let checked = try AvailableUpdate.check(in: releases, current: current, architecture: "arm64")
expect(checked?.version.text == "0.2.0-alpha.1", "Newest valid release was missed")
let noUpdate = try AvailableUpdate.check(in: [release("0.1.0-alpha.2")], current: current, architecture: "arm64")
expect(noUpdate == nil, "Older release reported as an update")
let incomplete = GitHubRelease(tag_name: "v0.3.0", html_url: AvailableUpdate.repository + "/releases/tag/v0.3.0",
                               body: nil, draft: false, prerelease: false, assets: [])
rejects("Incomplete newest release was treated as current or silently skipped") {
    _ = try AvailableUpdate.check(in: releases + [incomplete], current: current, architecture: "arm64")
}
rejects("Missing architecture must not report up to date") {
    _ = try AvailableUpdate.check(in: [release("0.3.0", arch: "x86_64")], current: current, architecture: "arm64")
}
print("PASS version ordering, channels, architecture, metadata and redirect allowlist")

let update = AvailableUpdate.newest(in: [release("0.2.0")], current: current, architecture: "arm64")!
let package = root.appendingPathComponent("package.dmg")
let bytes = Data([1, 2, 3, 4])
try bytes.write(to: package)
try update.verify(package: package)
try Data([4, 3, 2, 1]).write(to: package)
rejects("Wrong digest accepted") { try update.verify(package: package) }
try Data([1, 2, 3]).write(to: package)
rejects("Truncated package accepted") { try update.verify(package: package) }
print("PASS GitHub asset digest, streaming checksum and truncation detection")

let target = root.appendingPathComponent("Neylu.app")
let stage = root.appendingPathComponent(".Neylu-update-fixture")
let candidate = stage.appendingPathComponent("Neylu.app")
let backup = stage.appendingPathComponent("Previous.app")
func fixture(_ directory: URL, _ text: String) throws {
    try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try Data(text.utf8).write(to: directory.appendingPathComponent("marker"))
}
func marker(_ directory: URL) -> String? { try? String(contentsOf: directory.appendingPathComponent("marker"), encoding: .utf8) }
try fixture(target, "old"); try fixture(candidate, "new")
rejects("Launch failure should roll back") {
    try UpdateFiles.install(candidate: candidate, target: target, backup: backup) { _ in throw UpdateFailure.operation }
}
expect(marker(target) == "old" && marker(candidate) == "new" && !fm.fileExists(atPath: backup.path), "Rollback lost original")
var launched = false
try UpdateFiles.install(candidate: candidate, target: target, backup: backup) { app in
    expect(marker(app) == "new", "Launch before replacement")
    launched = true
}
expect(launched && marker(target) == "new" && !fm.fileExists(atPath: backup.path), "Replacement failed")
let link = root.appendingPathComponent("Linked.app")
try fm.createSymbolicLink(at: link, withDestinationURL: target)
expect(!UpdateFiles.canReplace(link), "Symlink target accepted")
expect(!UpdateFiles.canReplace(root.appendingPathComponent("Missing.app")), "Missing app accepted")
var launchChecks = 0
rejects("Startup exit was ignored") {
    try UpdateFiles.confirmLaunch(isRunning: { launchChecks += 1; return launchChecks == 1 }, pause: {})
}
expect(launchChecks == 2, "Launch was not checked after the startup interval")
try UpdateFiles.confirmLaunch(isRunning: { true }, pause: {})
rejects("Already exited application was accepted") { try UpdateFiles.confirmLaunch(isRunning: { false }, pause: {}) }
print("PASS same-volume replacement, launch-failure rollback and symlink rejection")

if let appPath = CommandLine.arguments.dropFirst().first {
    let app = URL(fileURLWithPath: appPath).standardizedFileURL
    let version = ReleaseVersion(try String(contentsOf: URL(fileURLWithPath: "VERSION"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
    #if arch(arm64)
    let arch = "arm64"
    #else
    let arch = "x86_64"
    #endif
    try UpdateFiles.validate(app, version: version, architecture: arch, requiredTeam: nil)
    let upgrade = try UpdateFiles.isUpgrade(ReleaseVersion("0.2.0")!, from: app)
    let same = try UpdateFiles.isUpgrade(version, from: app)
    let downgrade = try UpdateFiles.isUpgrade(ReleaseVersion("0.0.1")!, from: app)
    expect(upgrade && !same && !downgrade, "Installed version comparison failed")
    rejects("Wrong version accepted") { try UpdateFiles.validate(app, version: ReleaseVersion("99.0.0")!, architecture: arch, requiredTeam: nil) }
    rejects("Signed identity change accepted") { try UpdateFiles.validate(app, version: version, architecture: arch, requiredTeam: "UNTRUSTEDTEAM") }
    let broken = root.appendingPathComponent("Broken.app")
    try fm.copyItem(at: app, to: broken)
    try Data("tampered".utf8).write(to: broken.appendingPathComponent("Contents/Resources/LICENSE"))
    rejects("Tampered signature accepted") { try UpdateFiles.validate(broken, version: version, architecture: arch, requiredTeam: nil) }
    print("PASS real app signature, version, signing identity and resource tampering checks")
}

if CommandLine.arguments.contains("--live-github") {
    let done = DispatchSemaphore(value: 0)
    var failure: Error?
    Task.detached {
        do {
            let metadata = root.appendingPathComponent("releases.json")
            try await UpdateDownload(destination: metadata, limit: 2 * 1024 * 1024, progress: { _ in }).fetch(
                URL(string: "https://api.github.com/repos/chenmobuys/Neylu/releases?per_page=100")!)
            let releases = try JSONDecoder().decode([GitHubRelease].self, from: Data(contentsOf: metadata))
            #if arch(arm64)
            let arch = "arm64"
            #else
            let arch = "x86_64"
            #endif
            guard let update = try AvailableUpdate.check(in: releases, current: ReleaseVersion("0.0.0-alpha.1")!, architecture: arch) else {
                throw UpdateFailure.metadata
            }
            let package = root.appendingPathComponent("live.dmg")
            try await UpdateDownload(destination: package, limit: update.size, progress: { _ in }).fetch(update.package)
            try update.verify(package: package)
            let mount = root.appendingPathComponent("mount")
            try fm.createDirectory(at: mount, withIntermediateDirectories: false)
            try UpdateFiles.run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-mountpoint", mount.path, package.path])
            defer { _ = try? UpdateFiles.run("/usr/bin/hdiutil", ["detach", mount.path]) }
            try UpdateFiles.validate(mount.appendingPathComponent("Neylu.app"), version: update.version, architecture: arch, requiredTeam: nil)
            let cancelled = UpdateDownload(destination: root.appendingPathComponent("cancelled"), limit: 1024, progress: { _ in })
            cancelled.cancel()
            do { try await cancelled.fetch(URL(string: "https://api.github.com/repos/chenmobuys/Neylu/releases?per_page=1")!); throw UpdateFailure.operation }
            catch let error as URLError { expect(error.code == .cancelled, "Cancellation failed") }
            print("PASS live GitHub metadata, streamed DMG, SHA-256, mounted app validation and cancellation")
        } catch { failure = error }
        done.signal()
    }
    done.wait()
    if let failure { throw failure }
}
