import AppKit
import Foundation
import CryptoKit
import Darwin

L10n.useResources(at: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources"))

func expect(_ value: @autoclosure () throws -> Bool, _ message: String) {
    guard (try? value()) == true else { fatalError(message) }
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

let fixtureRoot = URL(fileURLWithPath: ProcessInfo.processInfo.environment["NEYLU_APPCAST_FIXTURES"]!)
let armFeed = try Data(contentsOf: fixtureRoot.appendingPathComponent("appcast-arm64.xml"))
let intelFeed = try Data(contentsOf: fixtureRoot.appendingPathComponent("appcast-x86_64.xml"))
let testSystem = OperatingSystemVersion(majorVersion: 12, minorVersion: 0, patchVersion: 0)
let parsedFeed = try Appcast.releases(from: armFeed, architecture: "arm64", system: testSystem)
expect(parsedFeed.count == 3, "Publisher/client appcast contract lost versions")
expect(parsedFeed.first!.body!.contains("**Fix** & <data>") && parsedFeed.first!.body!.contains("中文"), "XML escaping or Unicode release notes changed")
expect(try AvailableUpdate.check(in: parsedFeed, current: ReleaseVersion("0.1.0-alpha.4")!, architecture: "arm64")?.version.text == "0.2.0-alpha.10", "Static preview selection or SemVer ordering")
expect(try AvailableUpdate.check(in: parsedFeed, current: ReleaseVersion("0.0.1")!, architecture: "arm64")?.version.text == "0.1.0", "Static feed offered a preview to stable users")
let parsedIntel = try Appcast.releases(from: intelFeed, architecture: "x86_64", system: testSystem)
expect(parsedIntel.first!.assets.first!.name.hasSuffix("x86_64.dmg"), "Intel enclosure selection")
rejects("Cross-architecture feed accepted") { _ = try Appcast.releases(from: armFeed, architecture: "x86_64", system: testSystem) }
let xml = String(decoding: armFeed, as: UTF8.self)
for bad in ["", xml.replacingOccurrences(of: "<rss ", with: "<!DOCTYPE rss [<!ENTITY x 'bad'>]><rss "),
            xml.replacingOccurrences(of: Appcast.neylu, with: "https://evil.example"),
            xml.replacingOccurrences(of: "<sparkle:channel>alpha", with: "<sparkle:channel>stable"),
            xml.replacingOccurrences(of: "length=\"5\"", with: "length=\"0\""),
            xml.replacingOccurrences(of: "https://github.com/chenmobuys/Neylu/releases/download/", with: "https://evil.example/"),
            xml.replacingOccurrences(of: "12.0.0", with: "13.bad.0.0"),
            xml.replacingOccurrences(of: "<sparkle:version>3", with: "<sparkle:version>0") ] {
    rejects("Unsafe or malformed appcast accepted") { _ = try Appcast.releases(from: Data(bad.utf8), architecture: "arm64", system: testSystem) }
}
rejects("Oversized XML accepted") { _ = try Appcast.releases(from: Data(repeating: 65, count: Appcast.limit + 1), architecture: "arm64") }
let alias = xml.replacingOccurrences(of: "xmlns:neylu=", with: "xmlns:n=").replacingOccurrences(of: "neylu:", with: "n:")
expect(try Appcast.releases(from: Data(alias.utf8), architecture: "arm64", system: testSystem).count == 3, "Namespace identity was confused with a hardcoded prefix")
let futureOS = xml.replacingOccurrences(of: "12.0.0", with: "99.0.0")
expect(try Appcast.releases(from: Data(futureOS.utf8), architecture: "arm64", system: testSystem).isEmpty, "Unsupported macOS requirement was ignored")
for arch in ["arm64", "x86_64"] { expect(UpdateDownload.allowed(Appcast.url(for: arch)!), "Static feed URL rejected") }
for bad in ["https://api.github.com/repos/chenmobuys/Neylu/releases", "https://raw.githubusercontent.com/other/repo/updates/appcast-arm64.xml", "https://raw.githubusercontent.com/chenmobuys/Neylu/main/appcast-arm64.xml", Appcast.url(for: "arm64")!.absoluteString + "?other=1"] {
    expect(!UpdateDownload.allowed(URL(string: bad)!), "REST fallback or foreign static feed allowed")
}
let nonce = UUID(uuidString: "4D18119E-D07B-4C27-95DC-A83678EF0044")!
for arch in ["arm64", "x86_64"] {
    let fresh = Appcast.downloadURL(for: arch, nonce: nonce)!
    expect(UpdateDownload.allowed(fresh), "Fresh feed URL rejected")
    expect(fresh.query == "neylu_check=" + nonce.uuidString, "Cache-isolating feed query missing")
    expect(Appcast.downloadURL(for: arch) != Appcast.downloadURL(for: arch), "New checks reuse the same CDN cache key")
    let base = Appcast.url(for: arch)!.absoluteString
    for suffix in ["?neylu_check=invalid", "?neylu_check=", "?neylu_check=" + nonce.uuidString + "&other=1",
                   "?neylu_check=" + nonce.uuidString + "&neylu_check=" + nonce.uuidString,
                   "?neylu_check=" + nonce.uuidString + "#fragment", "#fragment"] {
        expect(!UpdateDownload.allowed(URL(string: base + suffix)!), "Feed URL validation was weakened")
    }
}
print("PASS real publisher XML/client contract, both architectures, stable/preview channels, XML safety, namespaced checksums and minimum macOS")

final class AppcastTestClock {
    private let lock = NSLock()
    private var date = Date()
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return date }
    func advance(_ seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; date += seconds }
}
actor AppcastFetchProbe {
    var calls = 0
    var cancellations = 0
    func begin() -> Int { calls += 1; return calls }
    func cancelled() { cancellations += 1 }
    private var released = false
    private var gate: CheckedContinuation<Void, Never>?
    func waitForRelease() async {
        guard !released else { return }
        await withCheckedContinuation { gate = $0 }
    }
    func release() { released = true; gate?.resume(); gate = nil }
}
func asyncUpdatesTest(_ body: @escaping () async throws -> Void) throws {
    let done = DispatchSemaphore(value: 0)
    var result: Result<Void, Error>?
    Task.detached {
        do { try await body(); result = .success(()) } catch { result = .failure(error) }
        done.signal()
    }
    expect(done.wait(timeout: .now() + 10) == .success, "Async update tests timed out")
    try result!.get()
}
func waitForProbe(_ condition: () async -> Bool) async throws {
    let deadline = Date().addingTimeInterval(2)
    while !(await condition()) && Date() < deadline { try await Task.sleep(nanoseconds: 1_000_000) }
    let ready = await condition()
    expect(ready, "Asynchronous fetch did not reach expected state")
}
try asyncUpdatesTest {
    let clock = AppcastTestClock()
    let probe = AppcastFetchProbe()
    let store = AppcastStore(clock: clock.now) {
        _ = await probe.begin()
        try await Task.sleep(nanoseconds: 30_000_000)
        return parsedFeed
    }
    let one = Task { try await store.load() }
    let two = Task { try await store.load() }
    let a = try await one.value, b = try await two.value
    expect(a.count == 3 && b.count == 3, "Concurrent consumers lost release metadata")
    var calls = await probe.calls
    expect(calls == 1, "Manual/background checks did not share the fetch")
    _ = try await store.load()
    calls = await probe.calls
    expect(calls == 1, "Fresh cache did not suppress redundant download")
    _ = try await store.load(forceRefresh: true)
    calls = await probe.calls
    expect(calls == 2, "Manual refresh reused a completed cached result")
    clock.advance(61)
    _ = try await store.load()
    calls = await probe.calls
    expect(calls == 3, "Expired cache did not refresh")

    let staleProbe = AppcastFetchProbe()
    let changing = AppcastStore {
        let call = await staleProbe.begin()
        return call == 1 ? [] : parsedFeed
    }
    let oldFeed = try await changing.load()
    let oldResult = try AvailableUpdate.check(in: oldFeed, current: ReleaseVersion("0.1.0-alpha.6")!, architecture: "arm64")
    expect(oldResult == nil, "Old feed fixture already has an update")
    let freshFeed = try await changing.load(forceRefresh: true)
    let freshResult = try AvailableUpdate.check(in: freshFeed, current: ReleaseVersion("0.1.0-alpha.6")!, architecture: "arm64")
    expect(freshResult != nil, "Manual check stayed up to date after the publisher added a new release")
    let sharedProbe = AppcastFetchProbe()
    let shared = AppcastStore {
        _ = await sharedProbe.begin()
        do {
            await sharedProbe.waitForRelease()
            try Task.checkCancellation()
        } catch { await sharedProbe.cancelled(); throw error }
        return parsedFeed
    }
    // Keep the first consumer registered while cancelling another. A controlled
    // response cannot finish before cancellation when the test runner is busy.
    let remaining = Task { try await shared.load() }
    try await waitForProbe { await sharedProbe.calls == 1 }
    let cancelled = Task { try await shared.load() }
    try await Task.sleep(nanoseconds: 10_000_000)
    cancelled.cancel()
    do { _ = try await cancelled.value; fatalError("Cancelled consumer received an update") } catch is CancellationError { }
    await sharedProbe.release()
    let surviving = try await remaining.value
    let sharedCalls = await sharedProbe.calls, sharedCancellations = await sharedProbe.cancellations
    expect(surviving.count == 3 && sharedCalls == 1 && sharedCancellations == 0, "One cancellation interrupted another consumer")

    let lastProbe = AppcastFetchProbe()
    let last = AppcastStore {
        let call = await lastProbe.begin()
        if call == 1 {
            do { try await Task.sleep(nanoseconds: 30_000_000_000) }
            catch { await lastProbe.cancelled(); throw error }
        }
        return parsedFeed
    }
    let request = Task { try await last.load() }
    try await waitForProbe { await lastProbe.calls == 1 }
    request.cancel()
    do { _ = try await request.value; fatalError("Last consumer cancellation failed") } catch is CancellationError { }
    try await waitForProbe { await lastProbe.cancellations == 1 }
    let retry = try await last.load()
    let retryCalls = await lastProbe.calls
    expect(retry.count == 3 && retryCalls == 2, "Cancelled generation poisoned the next request")
}
print("PASS shared static-feed request, short cache, expiry, isolated consumer cancellation and final-consumer download cancellation")

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
    let quarantined = root.appendingPathComponent("Quarantined.app")
    try fm.copyItem(at: app, to: quarantined)
    let sourceHelper = quarantined.appendingPathComponent("Contents/Helpers/NeyluUpdater")
    func setAttribute(_ url: URL, _ name: String, _ text: String) throws {
        let data = Data(text.utf8)
        let result = data.withUnsafeBytes { setxattr(url.path, name, $0.baseAddress, data.count, 0, XATTR_NOFOLLOW) }
        guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }
    func hasAttribute(_ url: URL, _ name: String) -> Bool {
        getxattr(url.path, name, nil, 0, 0, XATTR_NOFOLLOW) >= 0
    }
    try setAttribute(sourceHelper, "com.apple.quarantine", "0181;00000000;NeyluUpdateTest;")
    try setAttribute(sourceHelper, "io.github.chenmobuys.Neylu.test", "preserve")
    let helperStage = root.appendingPathComponent(".Neylu-update-quarantine")
    try fm.createDirectory(at: helperStage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    let unpreparedHelper = helperStage.appendingPathComponent("UnpreparedUpdater")
    try fm.copyItem(at: sourceHelper, to: unpreparedHelper)
    expect(hasAttribute(unpreparedHelper, "com.apple.quarantine"), "Regression fixture did not reproduce inherited quarantine")
    try fm.removeItem(at: unpreparedHelper)
    let stagedHelper = try UpdateFiles.stageUpdater(from: quarantined, in: helperStage)
    expect(!hasAttribute(stagedHelper, "com.apple.quarantine"), "Copied helper retained quarantine")
    expect(hasAttribute(sourceHelper, "com.apple.quarantine"), "Source helper quarantine was modified")
    expect(hasAttribute(stagedHelper, "io.github.chenmobuys.Neylu.test"), "Unrelated metadata was removed")
    expect(try Data(contentsOf: stagedHelper) == Data(contentsOf: sourceHelper), "Helper bytes changed")
    let helperProcess = Process()
    helperProcess.executableURL = stagedHelper
    try helperProcess.run()
    helperProcess.waitUntilExit()
    expect(helperProcess.terminationReason == .exit && helperProcess.terminationStatus == 1, "Verified staged helper could not execute its argument guard")
    rejects("Existing staged helper was overwritten") { _ = try UpdateFiles.stageUpdater(from: quarantined, in: helperStage) }
    try fm.removeItem(at: stagedHelper)
    _ = try UpdateFiles.run("/usr/bin/xattr", ["-d", "com.apple.quarantine", sourceHelper.path])
    _ = try UpdateFiles.stageUpdater(from: quarantined, in: helperStage)
    try fm.removeItem(at: stagedHelper)
    let sourceLink = root.appendingPathComponent("Helper-link")
    try fm.moveItem(at: sourceHelper, to: sourceLink)
    try fm.createSymbolicLink(at: sourceHelper, withDestinationURL: sourceLink)
    rejects("Symlink helper accepted") { _ = try UpdateFiles.stageUpdater(from: quarantined, in: helperStage) }
    try fm.removeItem(at: sourceHelper)
    try fm.moveItem(at: sourceLink, to: sourceHelper)
    try Data("tampered".utf8).write(to: quarantined.appendingPathComponent("Contents/Resources/LICENSE"))
    rejects("Tampered source app supplied an updater") { _ = try UpdateFiles.stageUpdater(from: quarantined, in: helperStage) }
    expect(!fm.fileExists(atPath: stagedHelper.path), "Rejected helper was left executable")
    print("PASS quarantined updater staging verifies source signatures, preserves original/other metadata, rejects tampering/symlinks and launches the clean copy")
    let broken = root.appendingPathComponent("Broken.app")
    try fm.copyItem(at: app, to: broken)
    try Data("tampered".utf8).write(to: broken.appendingPathComponent("Contents/Resources/LICENSE"))
    rejects("Tampered signature accepted") { try UpdateFiles.validate(broken, version: version, architecture: arch, requiredTeam: nil) }
    print("PASS real app signature, version, signing identity and resource tampering checks")
}

if CommandLine.arguments.contains("--live-update") {
    let done = DispatchSemaphore(value: 0)
    var failure: Error?
    Task.detached {
        do {
            #if arch(arm64)
            let arch = "arm64"
            #else
            let arch = "x86_64"
            #endif
            guard let update = try await UpdateDiscovery.find(current: ReleaseVersion("0.0.0-alpha.1")!, architecture: arch) else { throw UpdateFailure.metadata }
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
            do { try await cancelled.fetch(Appcast.url(for: arch)!); throw UpdateFailure.operation }
            catch let error as URLError { expect(error.code == .cancelled, "Cancellation failed") }
            print("PASS live static appcast, streamed DMG, SHA-256, mounted app validation and cancellation")
        } catch { failure = error }
        done.signal()
    }
    done.wait()
    if let failure { throw failure }
}

if CommandLine.arguments.contains("--live-check") {
    MainActor.assumeIsolated {
        var response: Result<[String], Error>?
        Task { @MainActor in
            do {
                var found: [String] = []
                for arch in ["arm64", "x86_64"] {
                    for _ in 0..<2 {
                        guard let update = try await UpdateDiscovery.find(current: ReleaseVersion("0.1.0-alpha.6")!, architecture: arch, forceRefresh: true),
                              update.version >= ReleaseVersion("0.1.0-alpha.7")! else { throw UpdateFailure.metadata }
                        found.append(arch + ": " + update.version.text)
                    }
                }
                response = .success(found)
            } catch { response = .failure(error) }
        }
        let deadline = Date().addingTimeInterval(45)
        while response == nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        guard let response else { fatalError("Live appcast discovery timed out") }
        switch response {
        case .success(let updates): print("PASS repeated live discovery from Alpha 6: " + updates.joined(separator: ", "))
        case .failure(let error): fatalError("Live appcast discovery failed: \(error)")
        }
    }
}
