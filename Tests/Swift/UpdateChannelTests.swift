import AppKit
import Foundation
import Testing

@testable import NeyluCore

extension NeyluTests {
  private func channelRelease(_ value: String, missingInstaller: Bool = false) -> GitHubRelease {
    let filename = "Neylu-\(value)-arm64.dmg"
    return GitHubRelease(
      tag_name: "v" + value, html_url: AvailableUpdate.repository + "/releases/tag/v" + value,
      body: "", draft: false, prerelease: value.contains("-"),
      assets: missingInstaller
        ? []
        : [
          .init(
            name: filename,
            browser_download_url: AvailableUpdate.repository + "/releases/download/v\(value)/"
              + filename, size: 1, state: "uploaded",
            digest: "sha256:" + String(repeating: "a", count: 64))
        ])
  }
  @Test func stableUpdatesAreDefaultEvenForInstalledPreviews() throws {
    let suite = "Neylu-update-channel-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    #expect(UpdateChannel.load(from: defaults) == .stable)
    defaults.set("unknown", forKey: "updateChannel")
    #expect(UpdateChannel.load(from: defaults) == .stable)
    UpdateChannel.development.save(to: defaults)
    #expect(UpdateChannel.load(from: try #require(UserDefaults(suiteName: suite))) == .development)
    UpdateChannel.stable.save(to: defaults)
    #expect(UpdateChannel.load(from: defaults) == .stable)
    let releases = [
      channelRelease("0.1.0"), channelRelease("0.2.0-alpha.2"), channelRelease("0.2.0-beta.1"),
      channelRelease("0.2.0-rc.1"),
    ]
    for installed in ["0.0.1", "0.1.0-alpha.9", "0.1.0-beta.1", "0.1.0-rc.1"] {
      let current = try #require(ReleaseVersion(installed))
      #expect(
        try AvailableUpdate.check(in: releases, current: current, architecture: "arm64")?.version
          .text == "0.1.0")
      #expect(
        try AvailableUpdate.check(
          in: releases, current: current, architecture: "arm64", channel: .development)?.version
          .text == "0.2.0-rc.1")
    }
    let stable = try #require(ReleaseVersion("0.1.0"))
    #expect(try AvailableUpdate.check(in: releases, current: stable, architecture: "arm64") == nil)
    #expect(
      try AvailableUpdate.check(
        in: releases, current: stable, architecture: "arm64", channel: .development)?.version.text
        == "0.2.0-rc.1")
    // An incomplete test release must not block the stable channel.
    #expect(
      try AvailableUpdate.check(
        in: releases + [channelRelease("0.3.0-alpha.1", missingInstaller: true)],
        current: ReleaseVersion("0.0.1")!, architecture: "arm64")?.version.text == "0.1.0")
    #expect(throws: UpdateFailure.incomplete) {
      try AvailableUpdate.check(
        in: releases + [channelRelease("0.3.0-alpha.1", missingInstaller: true)], current: stable,
        architecture: "arm64", channel: .development)
    }
    #expect(
      try AvailableUpdate.check(
        in: [channelRelease("0.1.0")], current: ReleaseVersion("0.2.0-alpha.1")!,
        architecture: "arm64") == nil)
  }

  @Test @MainActor func betaUpdateMenuAndCacheRespectExplicitChoice() async throws {
    try TestSupport.prepareNativeTests()
    let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
    let previous = UserDefaults.standard.object(forKey: "updateChannel")
    defer {
      if let previous {
        UserDefaults.standard.set(previous, forKey: "updateChannel")
      } else {
        UserDefaults.standard.removeObject(forKey: "updateChannel")
      }
      UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
    }
    UserDefaults.standard.setVolatileDomain(
      arguments.merging(["updateChannel": "stable", "automaticUpdateChecks": true]) { _, new in new
      }, forName: UserDefaults.argumentDomain)
    let suite = "Neylu-update-cache-channel-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("0.2.0-beta.1", forKey: BackgroundUpdateChecker.availableKey)
    let settings = MonitorSettings()
    var pending: CheckedContinuation<AvailableUpdate?, Error>?
    var requested: UpdateChannel?
    let checker = BackgroundUpdateChecker(
      settings: settings, defaults: defaults, version: "0.1.0-rc.1",
      check: { _, channel in
        requested = channel
        return try await withCheckedThrowingContinuation { pending = $0 }
      })
    defer {
      checker.stop()
      pending?.resume(throwing: CancellationError())
    }
    #expect(settings.availableUpdateVersion == nil)
    #expect(defaults.object(forKey: BackgroundUpdateChecker.availableKey) == nil)
    settings.onUpdateChannelChange = { checker.channelChanged() }
    let owner = SettingsMenuButton.Coordinator(settings: settings)
    let menu = owner.makeMenu(pullsDown: false)
    let channels = try #require(owner.item(21, in: menu)?.submenu)
    #expect(channels.items.count == 2)
    #expect(channels.items[0].state == .on && channels.items[1].state == .off)
    channels.performActionForItem(at: 1)
    #expect(settings.updateChannel == .development)
    owner.menuNeedsUpdate(menu)
    #expect(channels.items[0].state == .off && channels.items[1].state == .on)
    checker.checkIfDue()
    for _ in 0..<100 where pending == nil { try await Task.sleep(nanoseconds: 10_000_000) }
    try #require(pending != nil)
    #expect(requested == .development)
    let candidate = try #require(
      AvailableUpdate.newest(
        in: [channelRelease("0.2.0-beta.1")], current: ReleaseVersion("0.1.0-rc.1")!,
        architecture: "arm64", channel: .development))
    checker.accept(candidate)
    #expect(settings.availableUpdateVersion == "0.2.0-beta.1")
    channels.performActionForItem(at: 0)
    #expect(settings.updateChannel == .stable)
    #expect(settings.availableUpdateVersion == nil)
    #expect(defaults.object(forKey: BackgroundUpdateChecker.availableKey) == nil)
    let old = pending
    pending = nil
    old?.resume(returning: candidate)
    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(settings.availableUpdateVersion == nil)
    requested = nil
    checker.checkIfDue()
    for _ in 0..<100 where pending == nil { try await Task.sleep(nanoseconds: 10_000_000) }
    try #require(pending != nil)
    #expect(requested == .stable)
    let fresh = pending
    pending = nil
    fresh?.resume(returning: nil)
  }

  @Test @MainActor func switchingBetaUpdatesInvalidatesManualCheck() async throws {
    try TestSupport.prepareNativeTests()
    var channel = UpdateChannel.development
    var requests: [(UpdateChannel, CheckedContinuation<AvailableUpdate?, Error>)] = []
    let owner = UpdateController(
      current: "0.1.0-rc.1", channel: { channel },
      lookup: { _, _, selected in
        try await withCheckedThrowingContinuation { requests.append((selected, $0)) }
      })
    var discoveries: [String?] = []
    owner.onDiscovery = { discoveries.append($0?.version.text) }
    owner.present()
    let window = try #require(NSApp.windows.first { $0.isVisible && $0.title == L("update.title") })
    defer {
      window.close()
      for (_, request) in requests { request.resume(throwing: CancellationError()) }
    }
    for _ in 0..<100 where requests.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
    try #require(requests.count == 1)
    channel = .stable
    owner.channelChanged()
    for _ in 0..<100 where requests.count < 2 { try await Task.sleep(nanoseconds: 10_000_000) }
    try #require(requests.count == 2)
    #expect(requests.map(\.0) == [.development, .stable])
    let old = requests.removeFirst().1
    let fresh = requests.removeFirst().1
    let candidate = try #require(
      AvailableUpdate.newest(
        in: [channelRelease("0.2.0-beta.1")], current: ReleaseVersion("0.1.0-rc.1")!,
        architecture: "arm64", channel: .development))
    old.resume(returning: candidate)
    fresh.resume(returning: nil)
    for _ in 0..<100 where discoveries.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
    #expect(discoveries.count == 1 && discoveries[0] == nil)
  }
}
