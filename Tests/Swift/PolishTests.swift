import AppKit
import Testing

@testable import NeyluCore

extension NeyluTests {
  @Test @MainActor func menuSpacingPersistenceAndFixedWidths() throws {
    try TestSupport.prepareNativeTests()
    let suite = "Neylu-spacing-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var configuration = MenuBarConfiguration.defaults
    let compact = MenuBarLayout(basis: .decimal, configuration: configuration)
    configuration.density = .standard
    configuration.save(to: defaults)
    #expect(MenuBarConfiguration.load(from: defaults) == configuration)
    #expect(MetricCapabilities.basic.configuration(configuration).density == .standard)
    let standard = MenuBarLayout(basis: .decimal, configuration: configuration)
    #expect(standard.width == compact.width + CGFloat(3 * (compact.slots.count - 1)))
    defaults.set("invalid", forKey: "menuBarDensity")
    #expect(MenuBarConfiguration.load(from: defaults).density == .compact)
    let meter = MeterView(frame: .zero)
    for density in MenuBarDensity.allCases {
      configuration.density = density
      meter.configuration = configuration
      for basis in [UnitBasis.decimal, .binary] {
        meter.basis = basis
        let width = meter.makeStatusImage().size.width
        for rate in [0.0, 999, 1_000, 1_023, 1_024, 999_999, 1_000_000, 1_073_741_824] {
          meter.reading = Reading(download: rate, upload: rate / 2, networkReady: true)
          let image = meter.makeStatusImage()
          #expect(image.size.width == width)
          #expect(image.representations.count == 2)
        }
      }
    }
  }

  @Test func adaptiveNetworkRangePreservesOriginalRates() throws {
    L10n.useResources(at: TestSupport.root.appendingPathComponent("Resources"))
    let date = Date(timeIntervalSince1970: 10_000)
    var points = (0..<100).map {
      NetworkPoint(timestamp: date.addingTimeInterval(Double($0)), download: 1_024, upload: 512)
    }
    points[40] = NetworkPoint(
      timestamp: points[40].timestamp, download: 100_000_000, upload: 5_000_000)
    let range = NetworkChartScale(points: points)
    #expect(range.hasClippedPeaks)
    #expect(range.maximum < 100_000_000 && range.maximum > 1_024)
    #expect(range.fraction(1_024) > 0.2)
    #expect(range.fraction(100_000_000) == 1)
    let readout = try #require(
      ChartReadout.network(points, at: points[40].timestamp, basis: .decimal, language: .english))
    #expect(readout.value.contains("Download") && readout.value.contains("100 MB/s"))
    #expect(readout.secondaryValue?.contains("Upload") == true)
    #expect(points[40].download == 100_000_000)
    let sustained = points.map {
      NetworkPoint(timestamp: $0.timestamp, download: 100_000_000, upload: 0)
    }
    #expect(!NetworkChartScale(points: sustained).hasClippedPeaks)
    #expect(!NetworkChartScale(points: [points[40]]).hasClippedPeaks)
    #expect(NetworkChartScale(points: []).maximum.isFinite)
    #expect(range.fraction(.nan) == 0 && range.fraction(-1) == 0)
  }

  @Test @MainActor func pinnedNetworkReadoutRetainsOriginalSamples() throws {
    try TestSupport.prepareNativeTests()
    let model = MonitorModel(persistHistory: false)
    model.layout.isVisible = true
    let date = Date()
    let point = NetworkPoint(timestamp: date, download: 9_876_543, upload: 123)
    model.networkHistory = [point]
    model.updateChartWindow(at: date)
    model.toggleInspectionPin()
    model.networkHistory = []
    model.updateChartWindow(at: date.addingTimeInterval(500))
    #expect(model.chartNetworkSamples == [point])
    #expect(
      ChartReadout.network(
        model.chartNetworkSamples, at: date, basis: .decimal, window: model.chartWindow) != nil)
  }

  @Test func updateImageDetachRetriesOnlyBusyVolumes() throws {
    var calls = 0
    var pauses: [Double] = []
    try UpdateMount.detach(
      at: URL(fileURLWithPath: "/private/tmp/fixture"),
      execute: { _ in
        calls += 1
        return calls < 3 ? 16 : 0
      }, pause: { pauses.append($0) })
    #expect(calls == 3 && pauses == [0.2, 0.4])
    calls = 0
    #expect(throws: UpdateFailure.self) {
      try UpdateMount.detach(
        at: URL(fileURLWithPath: "/private/tmp/fixture"),
        execute: { _ in
          calls += 1
          return 1
        }, pause: { _ in Issue.record("Non-busy errors must not retry") })
    }
    #expect(calls == 1)
  }

  @Test func stableDiskOrderAndActionableEjectErrors() {
    #expect(
      ExternalDiskMonitor.stableOrder(previous: ["a", "b", "c"], current: ["c", "b", "d"]) == [
        "b", "c", "d",
      ])
    #expect(
      ExternalDiskMonitor.stableOrder(previous: ["b", "c", "d"], current: ["d", "a", "c"]) == [
        "c", "d", "a",
      ])
    let error = NSError(domain: NSPOSIXErrorDomain, code: Int(EBUSY))
    #expect(DiskActions.failureMessage(error).contains(L("disk.eject_busy_hint")))
    let native = NSError(
      domain: NSCocoaErrorDomain, code: 1,
      userInfo: [NSLocalizedRecoverySuggestionErrorKey: "Native recovery"])
    #expect(DiskActions.failureMessage(native).hasSuffix("Native recovery"))
  }

  @Test @MainActor func cancelledUpdateCheckCannotOverwriteReopenedWindow() async throws {
    try TestSupport.prepareNativeTests()
    var requests: [CheckedContinuation<AvailableUpdate?, Error>] = []
    let controller = UpdateController(
      current: "0.1.0-alpha.9",
      lookup: { _, _ in
        try await withCheckedThrowingContinuation { requests.append($0) }
      })
    var discoveries = 0
    controller.onDiscovery = { _ in discoveries += 1 }
    controller.present()
    let window = try #require(NSApp.windows.first { $0.isVisible && $0.title == L("update.title") })
    defer {
      for request in requests { request.resume(throwing: CancellationError()) }
      window.close()
    }
    func waitFor(_ condition: () -> Bool) async throws {
      let deadline = Date().addingTimeInterval(3)
      while !condition() && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
      try #require(condition())
    }
    try await waitFor { requests.count == 1 }
    window.close()
    controller.present()
    try await waitFor { requests.count == 2 }
    let stale = requests.removeFirst()
    let fresh = requests.removeFirst()
    fresh.resume(returning: nil)
    try await waitFor { discoveries == 1 }
    stale.resume(returning: nil)
    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(discoveries == 1)
    #expect(window.isVisible)
  }

  @Test func updateRetryClassificationAndWorkspaceOwnership() throws {
    L10n.useResources(at: TestSupport.root.appendingPathComponent("Resources"))
    for action in [UpdateRecovery.check, .download, .install] {
      for language in [AppLanguage.english, .simplifiedChinese] {
        #expect(L10n.text(action.titleKey, language: language) != action.titleKey)
        #expect(L10n.text(action.hintKey, language: language) != action.hintKey)
      }
    }
    #expect(
      UpdateRecovery.action(for: URLError(.networkConnectionLost), hasUpdate: true) == .download)
    #expect(UpdateRecovery.action(for: UpdateFailure.checksum, hasUpdate: true) == .download)
    #expect(UpdateRecovery.action(for: UpdateFailure.bundle, hasUpdate: true) == .download)
    #expect(UpdateRecovery.action(for: UpdateFailure.metadata, hasUpdate: true) == .check)
    #expect(UpdateRecovery.action(for: UpdateFailure.launch, hasUpdate: true) == .install)
    #expect(UpdateRecovery.action(for: UpdateFailure.download, hasUpdate: false) == .check)
    var gate = UpdateAttemptGate()
    let old = gate.begin()
    gate.cancel()
    let current = gate.begin()
    #expect(!gate.accepts(old) && gate.accepts(current))
    let fixture = try ToolFixture()
    var first: UpdateWorkspace? = try UpdateWorkspace(root: fixture.root)
    let firstURL = try #require(first?.directory)
    let second = try UpdateWorkspace(root: fixture.root)
    let external = try fixture.write("keep.txt", "keep")
    try FileManager.default.createSymbolicLink(
      at: firstURL.appendingPathComponent("outside"), withDestinationURL: external)
    let mode =
      try FileManager.default.attributesOfItem(atPath: firstURL.path)[.posixPermissions]
      as? NSNumber
    #expect(mode?.intValue == 0o700)
    first = nil
    #expect(!FileManager.default.fileExists(atPath: firstURL.path))
    #expect(FileManager.default.fileExists(atPath: second.directory.path))
    #expect(try String(contentsOf: external, encoding: .utf8) == "keep")
    var transferred: UpdateWorkspace? = try UpdateWorkspace(root: fixture.root)
    let transferredURL = try #require(transferred?.directory)
    transferred?.transferOwnership()
    transferred = nil
    #expect(FileManager.default.fileExists(atPath: transferredURL.path))
  }
}
