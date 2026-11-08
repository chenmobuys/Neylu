import AppKit
import SwiftUI
import ServiceManagement
import Carbon.HIToolbox

L10n.useResources(at: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources"))

if CommandLine.arguments.contains("--self-test") {
    let runtimeStarted = ProcessInfo.processInfo.systemUptime
    func report(_ message: String) {
        print(String(format: "[runtime +%.2fs] %@", ProcessInfo.processInfo.systemUptime - runtimeStarted, message))
        fflush(stdout)
    }
    report("START: native runtime regression tests")
    _ = NSApplication.shared
    // A standalone test executable has no app-bundle icon. On Intel CI,
    // NSAlert's nib otherwise asks IconServices synchronously for its default
    // image and can stall for minutes. Use the same bundled icon as the app.
    let runtimeIconURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("build/Neylu.app/Contents/Resources/AppIcon.icns")
    let runtimeIcon = NSImage(contentsOf: runtimeIconURL)!
    runtimeIcon.setName(NSImage.applicationIconName)
    NSApp.applicationIconImage = runtimeIcon
    precondition(NSImage(named: NSImage.applicationIconName) === runtimeIcon)
    report("PASS: test process uses the built app icon without default IconServices lookup")
    precondition(!MenuBarConfiguration.defaults.visibleMetrics.contains(.temperature))
    precondition(!SamplingDemand(details: false, systemDisk: false).needsTemperature)
    precondition(SamplingDemand(details: false, systemDisk: false, temperature: true).needsTemperature)
    let percentMeter = MeterView(frame: .zero)
    percentMeter.configuration = MenuBarConfiguration(items: [MenuBarItem(metric: .memory, enabled: true)])
    let percentWidth = percentMeter.makeStatusImage().size.width
    for value in [0.0, 9, 50, 99, 100] {
        percentMeter.reading = Reading(memory: value, usedMemory: 41_600_000_000, memoryReady: true)
        precondition(percentMeter.makeStatusImage().size.width == percentWidth)
        precondition(percentMeter.accessibilitySummary.contains(String(Int(value)) + "%"))
        precondition(!percentMeter.accessibilitySummary.contains("GB"))
    }
    let temperatureMeter = MeterView(frame: .zero)
    temperatureMeter.configuration = MenuBarConfiguration(items: [MenuBarItem(metric: .temperature, enabled: true)])
    let temperatureWidth = temperatureMeter.makeStatusImage().size.width
    for value in [Double(45), 99.9, 100, 129.9, .nan, .infinity, -1, 130] {
        temperatureMeter.reading.cpuTemperature = value
        precondition(temperatureMeter.makeStatusImage().size.width == temperatureWidth)
        if value.isFinite && value > 0 && value < 130 { precondition(temperatureMeter.accessibilitySummary.contains("°C")) }
        else { precondition(temperatureMeter.accessibilitySummary.contains("—")) }
    }
    temperatureMeter.reading.cpuTemperature = nil
    precondition(temperatureMeter.accessibilitySummary.contains("—"))
    for container in [CGFloat(0), 20, 161, 320] {
        let readout = ChartReadout(timestamp: Date(), value: "CPU 100% · User 50% · System 50%")
        let width = ChartTooltipLayout.width(for: readout, container: container)
        for position in [CGFloat(-100), 0, container / 2, container, container + 100] {
            let x = ChartTooltipLayout.originX(selection: position, width: width, container: container)
            precondition(x >= 0 && x + width <= container)
        }
    }
    precondition(ShortcutChord(key: 45, modifiers: UInt32(cmdKey | shiftKey), label: "⌘⇧N").isValid)
    report("PASS: memory percentages retain stable widths; temperature and tooltip edges stay within stable allocations")
    let supportedModel = MonitorModel(persistHistory: false)
    let savedForCapabilities = supportedModel.settings.menuBarConfiguration
    var requested = MenuBarConfiguration.defaults
    requested.setEnabled(true, for: .temperature)
    supportedModel.settings.menuBarConfiguration = requested
    var capacityChanges = 0
    supportedModel.onCapabilitiesChange = { capacityChanges += 1 }
    supportedModel.reading = Reading(capabilities: .basic)
    precondition(!supportedModel.availableMenuBarItems.contains { $0.metric == .gpu || $0.metric == .temperature })
    precondition(!supportedModel.effectiveMenuBarConfiguration.visibleMetrics.contains(.gpu))
    precondition(!supportedModel.effectiveMenuBarConfiguration.visibleMetrics.contains(.temperature))
    precondition(supportedModel.settings.menuBarConfiguration == requested)
    let filteredController = MenuBarSettingsController(model: supportedModel)
    func settingsViews(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(settingsViews) }
    let settingsRoot = filteredController.window!.contentView!
    settingsRoot.layoutSubtreeIfNeeded()
    let settingControls = settingsViews(settingsRoot)
    precondition(!settingControls.contains { $0 is NSPopUpButton })
    let resetControl = settingControls.compactMap { $0 as? NSButton }.first { $0.title == L("menu_bar.restore_layout") }!
    precondition(!resetControl.isBordered)
    precondition(!settingControls.compactMap { $0 as? NSButton }.contains { $0.title.contains("IP") })
    let metricsTable = NSTableView()
    precondition(filteredController.numberOfRows(in: metricsTable) == 4)
    var writable: [String] = []
    for row in 0..<filteredController.numberOfRows(in: metricsTable) {
        let item = filteredController.tableView(metricsTable, pasteboardWriterForRow: row) as! NSPasteboardItem
        writable.append(item.string(forType: NSPasteboard.PasteboardType("io.github.chenmobuys.Neylu.menuBarMetric"))!)
    }
    precondition(!writable.contains("gpu") && !writable.contains("temperature"))
    precondition(filteredController.tableView(metricsTable, pasteboardWriterForRow: 99) == nil)
    let movedWithoutGPU = MetricCapabilities.basic.moving(.cpu, to: 0, in: requested)
    precondition(MetricCapabilities.basic.items(movedWithoutGPU).first?.metric == .cpu)
    precondition(movedWithoutGPU.items.first(where: { $0.metric == .temperature })?.enabled == true)
    precondition(MetricCapabilities.basic.moving(.temperature, to: 0, in: requested) == requested)
    supportedModel.reading = Reading(capabilities: MetricCapabilities(), cpuTemperature: 42, gpu: 10, gpuReady: true)
    precondition(supportedModel.effectiveMenuBarConfiguration.visibleMetrics.contains(.temperature))
    precondition(supportedModel.effectiveMenuBarConfiguration.visibleMetrics.contains(.gpu))
    let changesAfterDiscovery = capacityChanges
    supportedModel.reading = Reading() // No new support probe; this tick has no values.
    precondition(supportedModel.capabilities == MetricCapabilities() && capacityChanges == changesAfterDiscovery)
    precondition(supportedModel.effectiveMenuBarConfiguration.visibleMetrics.contains(.temperature))
    let gpuOnly = ChartReadout.gpu([GPUPoint(timestamp: Date(), total: 30, renderer: nil, tiler: nil)], at: Date(), language: .english,
                                  rendererAvailable: false, tilerAvailable: false)!
    precondition(gpuOnly.value == "30%")
    supportedModel.settings.menuBarConfiguration = savedForCapabilities
    report("PASS: unsupported metrics are absent from status configuration and table/drag rows; preferences survive, hidden-row reordering is safe and missing ticks preserve support")
    let polishSuite = "Neylu-polish-" + UUID().uuidString
    let polishDefaults = UserDefaults(suiteName: polishSuite)!
    let testChord = ShortcutChord(key: 0, modifiers: UInt32(controlKey | optionKey), label: "⌃⌥A")
    precondition(testChord.isValid && ShortcutChord.load(from: polishDefaults) == nil)
    polishDefaults.set(try! JSONEncoder().encode(testChord), forKey: "globalShortcut")
    precondition(ShortcutChord.load(from: polishDefaults) == testChord)
    polishDefaults.set(Data("invalid".utf8), forKey: "globalShortcut")
    precondition(ShortcutChord.load(from: polishDefaults) == nil)
    precondition(!ShortcutChord(key: 0, modifiers: UInt32(cmdKey), label: "⌘A").isValid)
    precondition(!ShortcutChord(key: 56, modifiers: UInt32(optionKey), label: "⌥⇧").isValid)
    var registrationFails = false
    var registeredKeys: [UInt32] = []
    var unregisteredKeys = 0
    let shortcut = GlobalShortcut(register: { key, _, _, result in
        registeredKeys.append(key)
        if registrationFails { return OSStatus(eventHotKeyExistsErr) }
        result = OpaquePointer(bitPattern: Int(key) + 1)
        return noErr
    }, unregister: { _ in unregisteredKeys += 1 })
    precondition(shortcut.set(testChord))
    let relabeled = ShortcutChord(key: testChord.key, modifiers: testChord.modifiers, label: "⌃⌥Q")
    precondition(shortcut.set(relabeled) && registeredKeys == [0])
    registrationFails = true
    let conflicting = ShortcutChord(key: 1, modifiers: UInt32(optionKey), label: "⌥S")
    precondition(!shortcut.set(conflicting) && shortcut.chord == relabeled && unregisteredKeys == 0)
    precondition(shortcut.set(nil) && shortcut.chord == nil && unregisteredKeys == 1)
    precondition(registeredKeys == [0, 1])
    polishDefaults.removePersistentDomain(forName: polishSuite)
    let pinModel = MonitorModel(persistHistory: false)
    let pinNow = Date()
    let pinReading = Reading(cpuUser: 20, cpuSystem: 5, gpu: 30, gpuReady: true, usedMemory: 1024, totalMemory: 2048,
                             download: 20, upload: 10, cpuReady: true, networkReady: true, memoryReady: true)
    pinModel.recordCPU(pinReading, at: pinNow.addingTimeInterval(-86_400))
    pinModel.toggleInspectionPin()
    let pinnedWindow = pinModel.chartWindow
    let pinnedCPU = pinModel.chartCPU
    let pinnedGPU = pinModel.chartGPU
    let pinnedMemory = pinModel.chartMemory
    let pinnedNetwork = pinModel.chartNetwork
    // Twenty-four hours of simulated two-second samples; no wall-clock claims.
    report("START: 24-hour simulated recording (43,200 samples)")
    for index in 1...43_200 {
        pinModel.recordCPU(pinReading, at: pinNow.addingTimeInterval(-86_400 + Double(index) * 2))
    }
    precondition(pinModel.isInspectionPinned && pinModel.chartWindow.end == pinnedWindow.end)
    precondition(pinModel.chartCPU == pinnedCPU && pinModel.chartGPU == pinnedGPU)
    precondition(pinModel.chartMemory == pinnedMemory && pinModel.chartNetwork == pinnedNetwork)
    precondition(pinModel.history.last?.timestamp == pinNow && pinModel.history.count <= 1801)
    pinModel.resumeInspection()
    precondition(!pinModel.isInspectionPinned && pinModel.chartWindow.end > pinnedWindow.end)
    precondition(pinModel.chartCPU.last?.timestamp == pinNow && pinModel.chartCPU.count <= 240)
    precondition(pinModel.chartGPU.last?.timestamp == pinNow && pinModel.chartMemory.last?.timestamp == pinNow && pinModel.chartNetwork.last?.timestamp == pinNow)
    pinModel.toggleInspectionPin(); pinModel.reloadHistory()
    precondition(!pinModel.isInspectionPinned)
    let oldConfiguration = pinModel.settings.menuBarConfiguration
    let savedPrivacy = pinModel.settings.hideNetworkAddress
    pinModel.settings.hideNetworkAddress = true
    pinModel.settings.menuBarConfiguration.setEnabled(false, for: .cpu)
    pinModel.settings.restoreMenuBarLayout()
    precondition(pinModel.settings.menuBarConfiguration == .defaults && pinModel.history.last?.timestamp == pinNow)
    precondition(pinModel.settings.hideNetworkAddress)
    pinModel.settings.menuBarConfiguration = oldConfiguration
    pinModel.settings.hideNetworkAddress = savedPrivacy
    report("PASS: memory display boundaries, isolated shortcut registration/conflict rollback, layout-only reset and 24-hour simulated recording with frozen charts")
    let energySuite = "Neylu-efficiency-" + UUID().uuidString
    let energyDefaults = UserDefaults(suiteName: energySuite)!
    precondition(EnergyMode.load(from: energyDefaults) == .off)
    energyDefaults.set("invalid", forKey: "energyMode")
    precondition(EnergyMode.load(from: energyDefaults) == .off)
    EnergyMode.automatic.save(to: energyDefaults)
    precondition(EnergyMode.load(from: energyDefaults) == .automatic)
    energyDefaults.removePersistentDomain(forName: energySuite)
    for interval in RefreshInterval.allCases {
        for mode in EnergyMode.allCases {
            precondition(mode.interval(requested: interval.seconds, detailsVisible: true, lowPower: true) == interval.seconds)
            precondition(mode.interval(requested: interval.seconds, detailsVisible: false, lowPower: false) == (mode == .on ? max(5, interval.seconds) : interval.seconds))
            precondition(mode.interval(requested: interval.seconds, detailsVisible: false, lowPower: true) == (mode == .off ? interval.seconds : max(5, interval.seconds)))
        }
    }
    var addressCache = NetworkAddressCache()
    var addressReads = 0
    func readAddress() -> String { addressReads += 1; return "address-" + String(addressReads) }
    precondition(addressCache.address(for: "en0", now: 0, read: readAddress) == "address-1")
    precondition(addressCache.address(for: "en0", now: 9, read: readAddress) == "address-1")
    precondition(addressCache.address(for: "en0", now: 10, read: readAddress) == "address-2")
    precondition(addressCache.address(for: "en1", now: 11, read: readAddress) == "address-3")
    addressCache.invalidate()
    precondition(addressCache.address(for: "en1", now: 12, read: readAddress) == "address-4")
    let cachedMeter = MeterView(frame: .zero)
    cachedMeter.configuration = MenuBarConfiguration(items: [MenuBarItem(metric: .cpu, enabled: true)])
    cachedMeter.reading = Reading(cpu: 20.01, cpuReady: true)
    let oldKey = cachedMeter.displayKey
    cachedMeter.reading = Reading(cpu: 20.02, memory: 99, cpuReady: true)
    precondition(cachedMeter.displayKey == oldKey)
    cachedMeter.reading = Reading(cpu: 21, cpuReady: true)
    precondition(cachedMeter.displayKey != oldKey)
    report("PASS: all energy policies preserve foreground refresh, address cache expires/invalidates and unchanged displayed values have stable render keys")
    do {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Neylu-range-runtime-" + UUID().uuidString)
        let url = folder.appendingPathComponent("history.sqlite")
        let defaults = UserDefaults.standard
        let oldRange = defaults.object(forKey: "historyRange")
        defer {
            if let oldRange { defaults.set(oldRange, forKey: "historyRange") } else { defaults.removeObject(forKey: "historyRange") }
            try? FileManager.default.removeItem(at: folder)
        }
        HistoryRange.twoMinutes.save()
        let now = Date()
        do {
            let store = try HistoryStore(url: url)
            for index in 0..<60 {
                let date = now.addingTimeInterval(Double(index - 59) * 60)
                store.append(HistorySample(timestamp: date, cpu: CPUPoint(timestamp: date, user: 20, system: 5), gpu: nil))
            }
            try store.flush()
        }
        let model = MonitorModel(historyURL: url)
        precondition(model.history.count <= 3)
        model.settings.historyRange = .oneHour
        let live = Reading(cpu: 30, cpuUser: 25, cpuSystem: 5, cpuReady: true)
        model.recordCPU(live, at: Date())
        let deadline = Date().addingTimeInterval(3)
        while model.isHistoryLoading && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        precondition(!model.isHistoryLoading && model.history.count >= 59)
        precondition(model.history.last!.user == 25 && model.chartCPU.count <= 240)
        model.settings.historyRange = .fifteenMinutes
        model.settings.historyRange = .twoMinutes
        let shortDeadline = Date().addingTimeInterval(3)
        while model.isHistoryLoading && Date() < shortDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        precondition(model.chartWindow.maximumDuration == 120 && model.history.allSatisfy { $0.timestamp >= Date().addingTimeInterval(-121) })
        let before = model.chartCPU
        model.layout.isVisible = false
        model.recordCPU(live, at: Date().addingTimeInterval(1))
        precondition(model.chartCPU == before)
        model.layout.isVisible = true
        model.updateChartWindow(at: Date().addingTimeInterval(1))
        precondition(model.chartCPU.last!.user == 25)
        report("PASS: asynchronous range loading merges live samples, stale requests cannot overwrite a newer range and hidden plots skip preparation")
    } catch { fatalError("History range integration failed: \(error)") }
    let backgroundSampler = Sampler()
    backgroundSampler.setDemand(SamplingDemand(details: false, systemDisk: false))
    let backgroundReading = backgroundSampler.sample()
    precondition(backgroundReading.memoryReady && backgroundReading.cpuTemperature == nil && !backgroundReading.diskReady && !backgroundReading.diskActivityReady && backgroundReading.externalDisks.isEmpty)
    backgroundSampler.setDemand(.full)
    let firstForeground = backgroundSampler.sample()
    precondition(!firstForeground.diskActivityReady)
    report("PASS: background demand omits detail-only hardware while foreground disk rates establish a fresh baseline")
    let inspectStart = Date(timeIntervalSince1970: 1000)
    let inspectPoints = [CPUPoint(timestamp: inspectStart, user: 8, system: 5), CPUPoint(timestamp: inspectStart.addingTimeInterval(2), user: 20, system: 10)]
    precondition(ChartReadout.nearest(inspectPoints, at: inspectStart.addingTimeInterval(1.8), timestamp: \.timestamp) == inspectPoints[1])
    precondition(ChartReadout.nearest(inspectPoints, at: nil, timestamp: \.timestamp) == nil)
    let inspectWindow = HistoryWindow(earliest: inspectStart.addingTimeInterval(-1), now: inspectStart)
    precondition(ChartReadout.nearest(inspectPoints, at: inspectStart.addingTimeInterval(1.8), timestamp: \.timestamp, window: inspectWindow) == inspectPoints[0])
    precondition(ChartReadout.cpu([], at: inspectStart, language: .english) == nil)
    precondition(ChartReadout.cpu(inspectPoints, at: inspectStart, language: .english)!.value.contains("13%"))
    let absentGPU = ChartReadout.gpu([GPUPoint(timestamp: inspectStart, total: 0, renderer: nil, tiler: 0)], at: inspectStart, language: .english)!
    precondition(absentGPU.value.contains("—") && absentGPU.value.contains("0%"))
    precondition(ChartReadout.memory([MemoryPoint(timestamp: inspectStart, used: 1024, total: 2048)], at: inspectStart, basis: .binary)!.value.contains("KiB"))
    precondition(UpdateCheckSchedule.remaining(lastAttempt: nil, now: inspectStart) == 0)
    precondition(UpdateCheckSchedule.remaining(lastAttempt: inspectStart.addingTimeInterval(1), now: inspectStart) == 0)
    precondition(UpdateCheckSchedule.remaining(lastAttempt: inspectStart, now: inspectStart.addingTimeInterval(100)) == 86300)
    precondition(UpdateCheckSchedule.remaining(lastAttempt: inspectStart, now: inspectStart.addingTimeInterval(86400)) == 0)
    report("PASS: inspection uses actual nearest samples, missing GPU counters stay unavailable, units and daily scheduling handle boundary cases")
    MainActor.assumeIsolated {
        let suite = "Neylu-background-updates-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = MonitorSettings()
        settings.automaticUpdateChecks = true
        var checks = 0
        let candidate = AvailableUpdate(version: ReleaseVersion("0.1.0-alpha.10")!, notes: "", page: URL(string: AvailableUpdate.repository)!, package: URL(string: AvailableUpdate.repository)!, digest: "", size: 0, filename: "")
        let checker = BackgroundUpdateChecker(settings: settings, defaults: defaults, version: "0.1.0-alpha.3", check: { _ in checks += 1; return candidate })
        checker.checkIfDue(now: inspectStart)
        let deadline = Date().addingTimeInterval(2)
        while settings.availableUpdateVersion == nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        precondition(settings.availableUpdateVersion == candidate.version.text && checks == 1)
        checker.checkIfDue(now: inspectStart.addingTimeInterval(100))
        precondition(checks == 1)
        checker.stop()
        let freshSettings = MonitorSettings()
        freshSettings.automaticUpdateChecks = true
        let restored = BackgroundUpdateChecker(settings: freshSettings, defaults: defaults, version: "0.1.0-alpha.3", check: { _ in checks += 1; return nil })
        precondition(freshSettings.availableUpdateVersion == candidate.version.text)
        restored.checkIfDue(now: inspectStart.addingTimeInterval(86400))
        let clearDeadline = Date().addingTimeInterval(2)
        while freshSettings.availableUpdateVersion != nil && Date() < clearDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        precondition(freshSettings.availableUpdateVersion == nil && checks == 2)
        restored.stop()
        freshSettings.automaticUpdateChecks = false
        restored.checkIfDue(now: inspectStart.addingTimeInterval(172800))
        precondition(checks == 2)
        var completeCancelled: CheckedContinuation<AvailableUpdate?, Error>?
        let cancelled = BackgroundUpdateChecker(settings: settings, defaults: defaults, version: "0.1.0-alpha.3", check: { _ in
            try await withCheckedThrowingContinuation { completeCancelled = $0 }
        })
        settings.availableUpdateVersion = nil
        cancelled.checkIfDue(now: inspectStart.addingTimeInterval(172800))
        let cancellationDeadline = Date().addingTimeInterval(2)
        while completeCancelled == nil && Date() < cancellationDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        precondition(completeCancelled != nil)
        cancelled.stop()
        completeCancelled?.resume(returning: candidate)
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        precondition(settings.availableUpdateVersion == nil) // A cancelled result must not restore a stale badge.
        defaults.removeObject(forKey: BackgroundUpdateChecker.attemptKey)
        let failed = BackgroundUpdateChecker(settings: settings, defaults: defaults, version: "0.1.0-alpha.3", check: { _ in checks += 1; throw URLError(.notConnectedToInternet) })
        failed.checkIfDue(now: inspectStart.addingTimeInterval(172800))
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        failed.checkIfDue(now: inspectStart.addingTimeInterval(172801))
        precondition(checks == 3)
        failed.stop()
        report("PASS: background updates cache valid versions, coalesce daily checks, clear stale badges, respect opt-out and back off offline failures")
    }
    let recoveryModel = MonitorModel(persistHistory: false)
    recoveryModel.historySaveFailed("disk full")
    precondition(recoveryModel.error != nil)
    recoveryModel.historySaveRecovered()
    precondition(recoveryModel.error == nil)
    recoveryModel.historySaveFailed("disk full")
    recoveryModel.error = "unrelated settings error"
    recoveryModel.historySaveRecovered()
    precondition(recoveryModel.error == "unrelated settings error")
    report("PASS: history recovery clears only its own stale error without hiding unrelated failures")
    let timelineModel = MonitorModel(persistHistory: false)
    let timelineStart = Date()
    let sample = Reading(gpuReady: true, usedMemory: 20, totalMemory: 48,
                         cpuReady: true, networkReady: true, memoryReady: true)
    timelineModel.recordCPU(sample, at: timelineStart)
    precondition(timelineModel.chartWindow.fraction(timelineStart) == 1)
    timelineModel.recordCPU(sample, at: timelineStart.addingTimeInterval(2))
    precondition(timelineModel.chartWindow.fraction(timelineStart) == 0)
    precondition(timelineModel.chartWindow.fraction(timelineStart.addingTimeInterval(2)) == 1)
    timelineModel.recordCPU(sample, at: timelineStart.addingTimeInterval(122))
    precondition(timelineModel.chartWindow.end.timeIntervalSince(timelineModel.chartWindow.start) == 120)
    timelineModel.recordCPU(sample, at: timelineStart.addingTimeInterval(124))
    precondition(timelineModel.chartWindow.end.timeIntervalSince(timelineModel.chartWindow.start) == 120)
    timelineModel.recordCPU(sample, at: timelineStart.addingTimeInterval(300))
    precondition(timelineModel.history.count == 1 && timelineModel.gpuHistory.count == 1 && timelineModel.memoryHistory.count == 1 && timelineModel.networkHistory.count == 1)
    precondition(timelineModel.chartWindow.end.timeIntervalSince(timelineModel.chartWindow.start) == 1)
    timelineModel.recordCPU(sample, at: timelineStart.addingTimeInterval(302))
    precondition(timelineModel.chartWindow.fraction(timelineStart.addingTimeInterval(300)) == 0)
    report("PASS: all four charts share startup, fixed-window and post-pause ranges without adding samples")
    let resizeGate = StatusItemResizeGate(interval: 0.005)
    var resizeRequests = 0, staleReveal = 0, latestReveal = 0, geometryReads = 0
    var displayedImage = "old"
    resizeGate.begin(resize: { resizeRequests += 1 },
                     geometry: { [] }, reveal: { staleReveal += 1 })
    resizeGate.begin(resize: { resizeRequests += 1 }, geometry: {
        precondition(displayedImage == "old")
        precondition(resizeGate.isActive)
        geometryReads += 1
        // Two quiet frames followed by another system move must not reveal early.
        return [NSRect(x: geometryReads <= 3 ? 10 : 20, y: 0, width: 100, height: 22)]
    }, reveal: {
        precondition(!resizeGate.isActive && geometryReads >= 7)
        displayedImage = "new"
        latestReveal += 1
    })
    let resizeDeadline = Date().addingTimeInterval(3)
    while latestReveal == 0 && Date() < resizeDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    precondition(displayedImage == "new" && resizeRequests == 2 && staleReveal == 0 && latestReveal == 1)
    resizeGate.begin(resize: { resizeRequests += 1 }, geometry: { [] }, reveal: { staleReveal += 1 })
    resizeGate.cancel()
    RunLoop.current.run(until: Date().addingTimeInterval(0.03))
    precondition(!resizeGate.isActive && resizeRequests == 3 && staleReveal == 0)
    report("PASS: menu bar expansion retains its old image through renewed movement, cancels stale transitions and switches only after geometry settles")
    var allocationPolls = 0
    var allocationRevealed = false
    resizeGate.begin(resize: {}, geometry: { [] }, refresh: { allocationPolls += 1 },
                     ready: { allocationPolls >= 7 }, reveal: {
        precondition(allocationPolls >= 7)
        allocationRevealed = true
    })
    let allocationDeadline = Date().addingTimeInterval(3)
    while !allocationRevealed && Date() < allocationDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    precondition(allocationRevealed)
    report("PASS: quiet geometry cannot reveal the pending layout until its target allocation is ready")
    final class SlowTestSampler: MetricSampling {
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        var blockNext = true
        var calls = 0
        var resets = 0
        var diskRefreshes = 0
        func sample() -> Reading {
            precondition(!Thread.isMainThread)
            calls += 1
            if blockNext {
                blockNext = false
                entered.signal()
                precondition(release.wait(timeout: .now() + 5) == .success)
            }
            return Reading(cpu: Double(calls), cpuReady: true)
        }
        func resetAfterWake() { precondition(!Thread.isMainThread); resets += 1 }
        func refreshDisks(into reading: inout Reading) {
            precondition(!Thread.isMainThread)
            diskRefreshes += 1
            reading.diskName = "Fresh disk"
        }
    }
    func pumpMain(until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        precondition(condition())
    }
    let slowSampler = SlowTestSampler()
    let service = SamplingService(makeSampler: { precondition(!Thread.isMainThread); return slowSampler })
    var deliveries: [(Reading, Bool)] = []
    var diskDeliveries = 0
    service.onSample = { reading, _, record in precondition(Thread.isMainThread); deliveries.append((reading, record)) }
    service.onDisks = { _ in precondition(Thread.isMainThread); diskDeliveries += 1 }
    service.sample()
    precondition(slowSampler.entered.wait(timeout: .now() + 3) == .success)
    var mainResponded = false
    DispatchQueue.main.async { mainResponded = true }
    pumpMain { mainResponded } // The worker remains blocked while main handles input/work.
    for _ in 0..<20 { service.sample(recordHistory: true) }
    slowSampler.release.signal()
    pumpMain { deliveries.count == 2 }
    precondition(slowSampler.calls == 2 && deliveries[1].1)
    slowSampler.blockNext = true
    service.sample(recordHistory: true)
    precondition(slowSampler.entered.wait(timeout: .now() + 3) == .success)
    for _ in 0..<20 { service.refreshDisks() }
    service.suspend()
    service.resumeAfterWake()
    slowSampler.release.signal()
    pumpMain { deliveries.count == 3 }
    precondition(slowSampler.calls == 4 && slowSampler.resets == 1)
    precondition(deliveries.last!.0.cpu == 4 && !deliveries.last!.1)
    precondition(deliveries.last!.0.diskName == "Fresh disk" && slowSampler.diskRefreshes == 1)
    service.refreshDisks()
    pumpMain { diskDeliveries == 1 }
    precondition(slowSampler.diskRefreshes == 2)
    service.suspend()
    report("PASS: blocked sampling leaves main responsive, requests coalesce, callbacks use main, stale sleep results are discarded and disk events survive wake")
    for generation in 1...5 {
        let profile = CPUTemperatureProfile.forModel("Apple M\(generation) Max")!
        precondition(!profile.keys.isEmpty && profile.averagesSensors)
    }
    precondition(CPUTemperatureProfile.forModel("Apple M10") == nil)
    precondition(CPUTemperatureProfile.forModel("Unknown") == nil)
    precondition(CPUTemperatureProfile.forModel("Intel(R) Core(TM) i7")?.keys.contains("Tp0P") == false)
    precondition(CPUTemperatureProfile.forModel("Apple M1")?.keys.contains("Tp0P") == true)
    precondition(CPUTemperatureReader.decode([0x32, 0x80], type: 0x73703738) == 50.5)
    precondition(CPUTemperatureReader.decode([0, 0, 0x48, 0x42], type: 0x666c7420) == 50)
    precondition(CPUTemperatureReader.decode([0, 0, 0xc0, 0x7f], type: 0x666c7420) == nil)
    precondition(CPUTemperatureReader.decode([0xff, 0], type: 0x73703738) == nil)
    precondition(CPUTemperatureReader.decode([0], type: 0x73703738) == nil)
    precondition(CPUTemperatureReader(model: "Unknown").read(now: 0) == nil)
    report("PASS: generation-specific Intel/M1–M5 temperature mappings, unsupported models and invalid sensor payloads")
    var partialGPUReading = Reading()
    applyGPUStatistics(["Device Utilization %": 45, "Tiler Utilization %": 0], to: &partialGPUReading)
    precondition(partialGPUReading.gpuReady && partialGPUReading.gpuRenderer == nil && partialGPUReading.gpuTiler == 0)
    applyGPUStatistics(["Device Utilization %": Double.nan, "Renderer Utilization %": true], to: &partialGPUReading)
    precondition(!partialGPUReading.gpuReady && partialGPUReading.gpuRenderer == nil && partialGPUReading.gpuTiler == nil)
    report("PASS: missing/invalid GPU counters are distinct from actual zero utilization")
    precondition(preferredNetworkAddress([]) == "—")
    precondition(preferredNetworkAddress([""]) == "—")
    precondition(preferredNetworkAddress(["2001:db8::12", "192.0.2.1"]) == "192.0.2.1")
    precondition(preferredNetworkAddress(["fe80::1%en0", "2001:db8::12"]) == "2001:db8::12")
    precondition(preferredNetworkAddress(["fe80::1%en0", "febf::1", "invalid"]) == "—")
    precondition(preferredNetworkAddress(["fd12:3456::1"]) == "fd12:3456::1")
    report("PASS: IPv4 preference, IPv6 fallback and link-local address filtering")
    let appearanceSuite = "NeyluAppearanceTest-" + UUID().uuidString
    let appearanceDefaults = UserDefaults(suiteName: appearanceSuite)!
    precondition(AppearanceMode.load(from: appearanceDefaults) == .automatic)
    precondition(AppearanceMode.allCases == [.automatic, .light, .dark])
    for mode in AppearanceMode.allCases {
        mode.save(to: appearanceDefaults)
        precondition(AppearanceMode.load(from: UserDefaults(suiteName: appearanceSuite)!) == mode)
    }
    appearanceDefaults.set("unknown-future-mode", forKey: "appearanceMode")
    precondition(AppearanceMode.load(from: appearanceDefaults) == .automatic)
    precondition(AppearanceMode.automatic.appKitAppearance == nil)
    precondition(AppearanceMode.light.appKitAppearance?.name == .aqua)
    precondition(AppearanceMode.dark.appKitAppearance?.name == .darkAqua)
    precondition(AppLanguage.load(from: appearanceDefaults) == .automatic)
    precondition(AppLanguage.allCases == [.automatic, .simplifiedChinese, .english])
    precondition(AppLanguage.automatic.resolved(preferredLanguages: ["zh-Hans-CN", "en"]) == .simplifiedChinese)
    precondition(AppLanguage.automatic.resolved(preferredLanguages: ["en-US", "zh-Hans"]) == .english)
    precondition(AppLanguage.automatic.resolved(preferredLanguages: ["fr-FR"]) == .english)
    precondition(AppLanguage.automatic.resolved(preferredLanguages: []) == .english)
    precondition(AppLanguage.english.resolved(preferredLanguages: ["zh-Hans"]) == .english)
    for language in AppLanguage.allCases {
        language.save(to: appearanceDefaults)
        precondition(AppLanguage.load(from: UserDefaults(suiteName: appearanceSuite)!) == language)
    }
    appearanceDefaults.set("unsupported", forKey: "appLanguage")
    precondition(AppLanguage.load(from: appearanceDefaults) == .automatic)
    precondition(L10n.text("overview.title", language: .english) == "System Overview")
    precondition(L10n.text("overview.title", language: .simplifiedChinese) == "系统概览")
    precondition(L10n.uptime(minutes: 1501, language: .english) == "Uptime: 1d 1h 1m")
    precondition(L10n.uptime(minutes: 61, language: .simplifiedChinese) == "开机时间：1 小时 1 分钟")
    precondition(L10n.uptime(minutes: nil, language: .english) == "Uptime: —")
    report("PASS: language defaults/order, system resolution, preference persistence, translations and uptime formatting")
    precondition(MenuBarConfiguration.load(from: appearanceDefaults) == .defaults)
    precondition(MenuBarConfiguration.defaults.visibleMetrics == [.network, .memory, .gpu, .cpu])
    var menuLayout = MenuBarConfiguration.defaults
    menuLayout.setEnabled(true, for: .gpu)
    menuLayout.setEnabled(false, for: .memory)
    menuLayout.move(.gpu, to: 0)
    menuLayout.save(to: appearanceDefaults)
    precondition(MenuBarConfiguration.load(from: UserDefaults(suiteName: appearanceSuite)!) == menuLayout)
    precondition(menuLayout.visibleMetrics == [.gpu, .network, .cpu])
    menuLayout.move(.gpu, to: 5)
    precondition(menuLayout.visibleMetrics == [.network, .cpu, .gpu])
    let normalized = MenuBarConfiguration(items: [MenuBarItem(metric: .cpu, enabled: true), MenuBarItem(metric: .cpu, enabled: false)])
    precondition(normalized.items.count == MenuBarMetric.allCases.count && normalized.visibleMetrics == [.cpu])
    appearanceDefaults.set([["metric": "unknown", "enabled": true], ["metric": "gpu", "enabled": true]], forKey: "menuBarItems")
    precondition(MenuBarConfiguration.load(from: appearanceDefaults).visibleMetrics == [.gpu])
    var withTemperature = MenuBarConfiguration.load(from: appearanceDefaults)
    precondition(!withTemperature.visibleMetrics.contains(.temperature))
    withTemperature.setEnabled(true, for: .temperature)
    withTemperature.move(.temperature, to: 0)
    withTemperature.save(to: appearanceDefaults)
    precondition(MenuBarConfiguration.load(from: appearanceDefaults).visibleMetrics == [.temperature, .gpu])
    appearanceDefaults.set("invalid", forKey: "menuBarItems")
    precondition(MenuBarConfiguration.load(from: appearanceDefaults) == .defaults)
    var hiddenLayout = MenuBarConfiguration.defaults
    for metric in MenuBarMetric.allCases { hiddenLayout.setEnabled(false, for: metric) }
    hiddenLayout.save(to: appearanceDefaults)
    precondition(MenuBarConfiguration.load(from: appearanceDefaults).visibleMetrics.isEmpty)
    precondition(MeterView.meterWidth(for: .decimal, configuration: hiddenLayout) == 20)
    let testMeter = MeterView(frame: .zero)
    testMeter.reading = Reading(cpu: 100, gpu: 100, gpuReady: true, diskTotal: 1000, diskFree: 0, diskReady: true,
                                memory: 100, download: 999_000_000_000, upload: 999_000_000_000, cpuReady: true, networkReady: true, memoryReady: true)
    func permutations(_ items: [MenuBarMetric]) -> [[MenuBarMetric]] {
        guard !items.isEmpty else { return [[]] }
        return items.flatMap { first in permutations(items.filter { $0 != first }).map { [first] + $0 } }
    }
    let rateAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular)]
    for basis in UnitBasis.allCases {
        for exponent in 1...4 {
            for mantissa in [0.0, 9.95, 9.999, 999.0] {
                let rate = formattedRate(mantissa * pow(basis.radix, Double(exponent)), basis: basis)
                precondition(ceil((rate as NSString).size(withAttributes: rateAttributes).width) <= MeterView.rateWidth(for: basis))
            }
        }
    }
    report("START: exhaustive metric permutation rendering")
    for order in permutations(MenuBarMetric.allCases) {
        testMeter.configuration = MenuBarConfiguration(items: order.map { MenuBarItem(metric: $0, enabled: true) })
        for basis in UnitBasis.allCases {
            testMeter.basis = basis
            let image = testMeter.makeStatusImage()
            precondition(image.size.width == MeterView.meterWidth(for: basis, configuration: testMeter.configuration))
            precondition(image.representations.count == 2)
            precondition(image.isTemplate)
        }
    }
    report("PASS: exhaustive metric permutation rendering")
    testMeter.reading = Reading(cpu: 73, memory: 61, cpuReady: true, memoryReady: true)
    testMeter.configuration = MenuBarConfiguration(items: [.memory, .cpu].map { MenuBarItem(metric: $0, enabled: true) })
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    let originalArgumentDomain = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
    let appBundle = Bundle(url: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/Neylu.app"))!
    let visibilityModel = MonitorModel(persistHistory: false)
    visibilityModel.layout.isVisible = false
    let hiddenHost = NSHostingController(rootView: DetailView(model: visibilityModel))
    hiddenHost.view.frame = NSRect(x: 0, y: 0, width: 380, height: 600)
    hiddenHost.view.layoutSubtreeIfNeeded()
    precondition(hiddenHost.view.fittingSize.width == 380)
    visibilityModel.layout.isVisible = true
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    hiddenHost.view.layoutSubtreeIfNeeded()
    precondition(hiddenHost.view.fittingSize.width == 380)
    let recorderWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
    recorderWindow.isReleasedWhenClosed = false
    let recorder = ShortcutRecorder(labelWithString: "")
    recorder.frame = NSRect(x: 10, y: 10, width: 200, height: 30)
    recorderWindow.contentView!.addSubview(recorder)
    let recordEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.control, .option], timestamp: 0,
        windowNumber: recorderWindow.windowNumber, context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)!
    precondition(!recorder.performKeyEquivalent(with: recordEvent) && recorder.recorded == nil)
    precondition(recorderWindow.makeFirstResponder(recorder))
    precondition(!recorder.performKeyEquivalent(with: recordEvent))
    recorder.beginRecording()
    precondition(recorderWindow.firstResponder === recorder)
    precondition(recorder.performKeyEquivalent(with: recordEvent) && recorder.recorded == testChord && !recorder.isRecording)
    recorderWindow.makeFirstResponder(nil)
    precondition(!recorder.performKeyEquivalent(with: recordEvent))
    recorderWindow.close()
    report("PASS: native shortcut recorder captures local keys only while it is the focused responder")
    report("START: construct native shortcut alert")
    let shortcutAlert = shortcut.makeConfigurationAlert()
    report("PASS: native shortcut alert constructed")
    report("START: lay out native shortcut alert")
    shortcutAlert.layout()
    report("PASS: native shortcut alert laid out")
    let alertRecorder = shortcutAlert.accessoryView as! ShortcutRecorder
    precondition(!shortcutAlert.buttons[0].isEnabled && !shortcutAlert.buttons[2].isEnabled)
    precondition(alertRecorder.isBezeled && !alertRecorder.isRecording)
    report("START: activate shortcut recorder through accessibility")
    precondition(alertRecorder.accessibilityPerformPress())
    report("PASS: shortcut recorder accessibility activation")
    precondition(alertRecorder.isRecording)
    let alertEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0,
        windowNumber: shortcutAlert.window.windowNumber, context: nil, characters: "N", charactersIgnoringModifiers: "N", isARepeat: false, keyCode: 45)!
    report("START: deliver shortcut key equivalent")
    precondition(alertRecorder.performKeyEquivalent(with: alertEvent))
    report("PASS: shortcut key equivalent delivered")
    precondition(shortcutAlert.buttons[0].isEnabled && !alertRecorder.isRecording)
    precondition(alertRecorder.recorded?.label == "⇧⌘N")
    alertRecorder.beginRecording()
    precondition(!shortcutAlert.buttons[0].isEnabled && alertRecorder.recorded == nil)
    precondition(alertRecorder.performKeyEquivalent(with: alertEvent) && shortcutAlert.buttons[0].isEnabled)
    report("PASS: native shortcut dialog requires explicit recording, enables Save after capture and supports accessibility activation")
    let escapeWindow = UtilityWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
    escapeWindow.isReleasedWhenClosed = false
    escapeWindow.orderFront(nil)
    precondition(escapeWindow.isVisible)
    escapeWindow.cancelOperation(nil)
    precondition(!escapeWindow.isVisible)
    final class FocusablePreviewControl: NSView {
        override var acceptsFirstResponder: Bool { true }
    }
    let focusWindow = UtilityWindow(contentRect: NSRect(x: 0, y: 0, width: 120, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
    focusWindow.isReleasedWhenClosed = false
    let focusControl = FocusablePreviewControl(frame: NSRect(x: 8,y: 8,width: 50,height: 20))
    focusWindow.contentView!.addSubview(focusControl)
    focusWindow.initialFirstResponder = focusControl
    focusWindow.makeKeyAndOrderFront(nil)
    precondition(focusWindow.firstResponder !== focusControl)
    focusWindow.selectNextKeyView(nil)
    precondition(focusWindow.firstResponder === focusControl)
    focusWindow.makeKeyAndOrderFront(nil)
    precondition(focusWindow.firstResponder === focusControl)
    focusWindow.close()
    report("PASS: utility windows avoid automatic link/control focus on opening, preserve Tab navigation and retain focus when brought forward")
    let privateReading = Reading(cpuTemperature: 52, gpuRenderer: nil, gpuTiler: 0, gpuReady: true,
        diskName: "PRIVATE-VOLUME", interface: "PRIVATE-INTERFACE", address: "198.51.100.42", cpuReady: true)
    let englishDomain = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
    UserDefaults.standard.setVolatileDomain(["appLanguage": "en"], forName: UserDefaults.argumentDomain)
    let diagnostics = Diagnostics.report(reading: privateReading, settings: MonitorSettings(), historyAvailable: true,
        bundle: appBundle, hardware: "Apple Test CPU", system: OperatingSystemVersion(majorVersion: 12, minorVersion: 7, patchVersion: 0))
    precondition(diagnostics.contains("Apple Test CPU") && diagnostics.contains("macOS 12.7.0"))
    precondition(!diagnostics.contains("PRIVATE-VOLUME") && !diagnostics.contains("PRIVATE-INTERFACE") && !diagnostics.contains("198.51.100.42"))
    precondition(!diagnostics.contains("/Users/") && !diagnostics.contains("52"))
    let clipboard = NSPasteboard.withUniqueName()
    precondition(Diagnostics.copy(diagnostics, to: clipboard))
    precondition(clipboard.string(forType: .string) == diagnostics)
    clipboard.releaseGlobally()
    UserDefaults.standard.setVolatileDomain(englishDomain, forName: UserDefaults.argumentDomain)
    report("PASS: diagnostics allowlist excludes addresses, names, paths and monitoring values and copies to an isolated pasteboard")
    let settingsCoordinator = SettingsMenuButton.Coordinator(settings: visibilityModel.settings)
    visibilityModel.settings.availableUpdateVersion = "0.1.0-alpha.10"
    let badgeMenu = settingsCoordinator.makeMenu(pullsDown: false)
    settingsCoordinator.updateTitles(badgeMenu)
    precondition(badgeMenu.item(withTag: 13)!.title.contains("0.1.0-alpha.10"))
    precondition(settingsCoordinator.item(15, in: badgeMenu)!.state == (visibilityModel.settings.automaticUpdateChecks ? .on : .off))
    precondition(badgeMenu.items.filter { !$0.isSeparatorItem }.map(\.tag) == [6,3,16,10,13,14,18,11,12])
    precondition(settingsCoordinator.item(16, in: badgeMenu)!.submenu!.items.filter { !$0.isSeparatorItem }.map(\.tag) == [4,20,17,2,19,5,1,15])
    precondition(settingsCoordinator.item(21, in: badgeMenu) == nil)
    let unitsMenu = settingsCoordinator.item(2, in: badgeMenu)!.submenu!
    precondition(unitsMenu.items.count == 2)
    let savedBasis = visibilityModel.settings.basis
    let chooseBinary = unitsMenu.items.first { ($0.representedObject as? String) == UnitBasis.binary.rawValue }!
    _ = (chooseBinary.target as! NSObject).perform(chooseBinary.action!, with: chooseBinary)
    settingsCoordinator.menuNeedsUpdate(unitsMenu)
    precondition(visibilityModel.settings.basis == .binary && chooseBinary.state == .on)
    precondition(unitsMenu.items.filter { $0.state == .on }.count == 1)
    visibilityModel.settings.basis = savedBasis
    let rangeMenu = settingsCoordinator.item(20, in: badgeMenu)!.submenu!
    let rangeOptions = rangeMenu.items
    precondition(rangeOptions.compactMap { $0.representedObject as? Int } == [120, 900, 3600])
    let oldRange = visibilityModel.settings.historyRange
    let chosenRange = rangeOptions.first { ($0.representedObject as? Int) == 900 }!
    _ = (chosenRange.target as! NSObject).perform(chosenRange.action!, with: chosenRange)
    precondition(visibilityModel.settings.historyRange == .fifteenMinutes)
    settingsCoordinator.menuNeedsUpdate(rangeMenu)
    precondition(rangeMenu.items[1] === chosenRange && chosenRange.state == .on)
    precondition(rangeMenu.items.filter { $0.state == .on }.count == 1)
    visibilityModel.settings.historyRange = oldRange
    settingsCoordinator.menuNeedsUpdate(rangeMenu)
    let nestedPreferences = settingsCoordinator.item(16, in: badgeMenu)!.submenu!
    let nestedRefresh = settingsCoordinator.item(4, in: badgeMenu)!
    settingsCoordinator.menuNeedsUpdate(nestedPreferences)
    precondition(settingsCoordinator.item(4, in: badgeMenu) === nestedRefresh)
    final class FakeLoginService: LoginItemService {
        var state: LoginItemState = .requiresApproval
        var changes: [Bool] = []
        var fail = false
        func setEnabled(_ value: Bool) throws {
            changes.append(value)
            if fail { throw NSError(domain: "test", code: 1) }
            state = value ? .enabled : .disabled
        }
    }
    let fakeLogin = FakeLoginService()
    let loginSettings = MonitorSettings(loginService: fakeLogin)
    let loginCoordinator = SettingsMenuButton.Coordinator(settings: loginSettings)
    let loginMenu = loginCoordinator.makeMenu(pullsDown: false)
    precondition(loginCoordinator.item(1, in: loginMenu)!.state == .mixed)
    loginSettings.setLogin(true)
    loginCoordinator.menuNeedsUpdate(loginMenu)
    precondition(loginCoordinator.item(1, in: loginMenu)!.state == .on && fakeLogin.changes == [true])
    fakeLogin.fail = true
    var loginFailed = false
    loginSettings.onError = { _ in loginFailed = true }
    loginSettings.setLogin(false)
    precondition(loginFailed && loginSettings.loginEnabled)
    let hover = ChartTrackingView(onMove: { _ in })
    let hoverWindow = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 200,height: 100), styleMask: .borderless, backing: .buffered, defer: false)
    hoverWindow.isReleasedWhenClosed = false
    hoverWindow.contentView!.addSubview(hover)
    hover.frame = NSRect(x: 20,y: 20,width: 100,height: 50)
    var tracked: CGPoint?
    hover.onMove = { tracked = $0 }
    hover.updateTrackingAreas()
    let move = NSEvent.mouseEvent(with: .mouseMoved, location: NSPoint(x: 70,y: 45), modifierFlags: [], timestamp: 0, windowNumber: hoverWindow.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
    hover.mouseMoved(with: move)
    precondition(tracked != nil && abs(tracked!.x - 50) < 0.01)
    precondition(hover.hitTest(.zero) == nil && hover.trackingAreas.count == 1)
    hover.mouseExited(with: move)
    precondition(tracked == nil)
    hoverWindow.close()
    report("PASS: grouped native menus retain identity, pending login approval/failures reflect actual service state and macOS 12 AppKit chart tracking works")
    report("PASS: details unmount/reopen at fixed width, utility windows dismiss on Escape and native update menus expose badge/version and opt-out state")
    let aboutController = AboutController(settings: MonitorSettings(), bundle: appBundle)
    func allViews(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(allViews) }
    for language in [AppLanguage.english, .simplifiedChinese] {
        UserDefaults.standard.setVolatileDomain(originalArgumentDomain.merging(["appLanguage": language.rawValue]) { _, new in new }, forName: UserDefaults.argumentDomain)
        aboutController.refreshText()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        aboutController.window!.contentView!.layoutSubtreeIfNeeded()
        let views = allViews(aboutController.window!.contentView!)
        let text = views.compactMap { ($0 as? NSTextField)?.stringValue }
        let buttons = views.compactMap { ($0 as? NSButton)?.title }
        precondition(aboutController.window!.title == L10n.text("about.title", language: language))
        precondition(text.contains(L10n.text("app.description", language: language)))
        precondition(buttons.contains(L10n.text("about.license", language: language)))
        if language == .english {
            precondition(text.allSatisfy { $0.range(of: #"[\u4e00-\u9fff]"#, options: .regularExpression) == nil })
            precondition(text.contains { $0.hasPrefix("Version 0.1.0-alpha.") && $0.contains("Build ") })
        }
    }
    let notesController = ReleaseNotesController(settings: MonitorSettings(), bundle: appBundle)
    let notesWindow = notesController.window!
    let bundledNotes = try! String(contentsOf: appBundle.url(forResource: "ReleaseNotes", withExtension: "md")!, encoding: .utf8)
    for language in [AppLanguage.english, .simplifiedChinese] {
        UserDefaults.standard.setVolatileDomain(originalArgumentDomain.merging(["appLanguage": language.rawValue]) { _, new in new }, forName: UserDefaults.argumentDomain)
        notesController.refreshText()
        notesWindow.contentView!.layoutSubtreeIfNeeded()
        precondition(notesController.window === notesWindow)
        let views = allViews(notesWindow.contentView!)
        let textView = views.compactMap { $0 as? NSTextView }.first!
        let expected = ReleaseNotesRenderer.render(ReleaseNotesText.localized(bundledNotes, language: language))
        precondition(textView.string == expected.string && !textView.string.isEmpty)
        precondition(!textView.isEditable && textView.isSelectable)
        precondition(notesWindow.title == L10n.text("menu.release_notes", language: language))
        precondition(views.compactMap { ($0 as? NSButton)?.title }.contains(L10n.text("whats_new.continue", language: language)))
        precondition(views.compactMap { $0 as? NSScrollView }.first!.hasVerticalScroller)
        if language == .english {
            precondition(textView.string.range(of: #"[\u4e00-\u9fff]"#, options: .regularExpression) == nil)
        }
        for theme in [NSAppearance.Name.aqua, .darkAqua] {
            notesWindow.appearance = NSAppearance(named: theme)
            textView.layoutManager!.ensureLayout(for: textView.textContainer!)
            precondition(textView.layoutManager!.usedRect(for: textView.textContainer!).height > 0)
        }
    }
    report("PASS: installed-version release notes load offline, render localized Markdown and retain native scrolling and window identity across appearance/language changes")
    UserDefaults.standard.setVolatileDomain(originalArgumentDomain, forName: UserDefaults.argumentDomain)
    report("PASS: the same native About window switches all owned labels between English and Simplified Chinese")

    for basis in UnitBasis.allCases {
        testMeter.basis = basis
        let source = testMeter.makeStatusImage()
        let mask = StatusImageMask(image: source, contentWidth: source.size.width)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let nativeButton = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: source.size.width, height: source.size.height))
        nativeButton.imagePosition = .imageOnly
        nativeButton.imageScaling = .scaleNone
        nativeButton.clipsToBounds = true
        // Exercise contraction as well as expansion with the actual native cell.
        for extra: CGFloat in [68, 34, 0, 34, 68, 0] {
            nativeButton.frame.size.width = source.size.width + extra
            let result = mask.imageForStatusButton(in: nativeButton.bounds.size)
            nativeButton.image = result
            let actualRect = nativeButton.cell!.imageRect(forBounds: nativeButton.bounds)
            precondition(abs(actualRect.minX - nativeButton.bounds.minX) < 0.5)
            precondition(actualRect.width == nativeButton.bounds.width)
            precondition(result.size == nativeButton.bounds.size && result.isTemplate == source.isTemplate)
            for (before, after) in zip(source.representations, result.representations) {
                let original = before as! NSBitmapImageRep, masked = after as! NSBitmapImageRep
                var ink = 0
                for x in 0..<masked.pixelsWide {
                    for y in 0..<masked.pixelsHigh {
                        let expected = x < original.pixelsWide ? original.colorAt(x: x, y: y)!.alphaComponent : 0
                        let actual = masked.colorAt(x: x, y: y)!.alphaComponent
                        precondition(actual == expected)
                        if actual > 0 { ink += 1 }
                    }
                }
                precondition(ink > 0)
            }
        }
    }
    report("PASS: actual native status cell stays at x=0 through expansion/contraction; 1x/2x content pixels remain fixed at the left with a transparent tail")
    let alignmentSource = NSImage(size: NSSize(width: 64, height: 22), flipped: false) { rect in
        NSColor.blue.setFill(); rect.fill(); return true
    }
    let alignmentButton = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 180, height: 24))
    alignmentButton.title = ""
    alignmentButton.isBordered = false
    alignmentButton.imagePosition = .imageOnly
    alignmentButton.imageScaling = .scaleNone
    alignmentButton.contentTintColor = nil
    alignmentButton.image = alignmentSource
    precondition(alignmentButton.cell!.imageRect(forBounds: alignmentButton.bounds).minX == 58)
    let alignmentMask = StatusImageMask(image: alignmentSource, contentWidth: 64)
    alignmentButton.image = alignmentMask.imageForStatusButton(in: alignmentButton.bounds.size)
    alignmentButton.postsFrameChangedNotifications = true
    let alignmentObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: alignmentButton, queue: nil) { _ in
        alignmentButton.image = alignmentMask.imageForStatusButton(in: alignmentButton.bounds.size)
    }
    for width: CGFloat in [180, 140, 100, 64, 48, 100, 180] {
        alignmentButton.frame.size.width = width
        precondition(alignmentButton.image!.size.width == alignmentButton.bounds.width)
        precondition(abs(alignmentButton.cell!.imageRect(forBounds: alignmentButton.bounds).midY - alignmentButton.bounds.midY) < 0.5)
        let bitmap = alignmentButton.bitmapImageRepForCachingDisplay(in: alignmentButton.bounds)!
        alignmentButton.cacheDisplay(in: alignmentButton.bounds, to: bitmap)
        var left = bitmap.pixelsWide, right = -1
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                if color.blueComponent > 0.8 && color.redComponent < 0.2 && color.alphaComponent > 0.5 {
                    left = min(left, x); right = max(right, x)
                }
            }
        }
        let scale = CGFloat(bitmap.pixelsWide) / width
        precondition(left == 0 && right == Int(min(width, 64) * scale) - 1)
    }
    NotificationCenter.default.removeObserver(alignmentObserver)
    report("PASS: real NSStatusBarButton output pixels remain at the left after automatic frame-change updates for both growth and shrinkage")
    testMeter.configuration = normalized
    precondition(!testMeter.accessibilitySummary.contains("GPU") && testMeter.accessibilitySummary.contains("CPU"))
    let beforeReadingChange = testMeter.makeStatusImage().size.width
    testMeter.reading = Reading()
    precondition(testMeter.makeStatusImage().size.width == beforeReadingChange)
    testMeter.configuration = hiddenLayout
    precondition(testMeter.makeStatusImage().size.width == 16 && testMeter.accessibilitySummary == "Neylu")
    report("PASS: menu bar visibility/order persistence, corrupt preferences, all-hidden entry, all metric permutations and stable image widths")
    precondition(RefreshInterval.load(from: appearanceDefaults) == .twoSeconds)
    precondition(RefreshInterval.allCases.map(\.rawValue) == [1, 2, 5, 10])
    for interval in RefreshInterval.allCases {
        interval.save(to: appearanceDefaults)
        precondition(RefreshInterval.load(from: UserDefaults(suiteName: appearanceSuite)!) == interval)
    }
    appearanceDefaults.set(3, forKey: "refreshInterval")
    precondition(RefreshInterval.load(from: appearanceDefaults) == .twoSeconds)
    appearanceDefaults.removePersistentDomain(forName: appearanceSuite)
    report("PASS: refresh interval defaults/order, preference round trip and invalid interval fallback")
    report("PASS: appearance defaults/order, preference round trip, invalid preference fallback and system appearance mapping")
    let cases: [(Double, UnitBasis, String)] = [
        (0, .decimal, "0 KB/s"), (529_000, .decimal, "529 KB/s"),
        (999_500, .decimal, "1.0 MB/s"), (1_200_000, .decimal, "1.2 MB/s"),
        (1_048_576, .binary, "1.0 MiB/s"), (1_073_741_824, .binary, "1.0 GiB/s"),
        (1_023 * 1_024, .binary, "1023 KiB/s"), (1_023.5 * 1_024, .binary, "1.0 MiB/s"),
        (-1, .binary, "0 KiB/s")]
    for (input, basis, expected) in cases {
        let actual = formattedRate(input, basis: basis)
        precondition(actual == expected, "Rate \(input): \(actual) != \(expected)")
    }
    precondition(formattedRate(0, basis: .binary, ready: false) == "—")
    precondition(formattedMemory(48 * 1_024 * 1_024 * 1_024, basis: .binary) == "48 GiB")
    precondition(formattedMemory(48_000_000_000, basis: .decimal) == "48 GB")
    precondition(percent(99.8, ready: true) == "100%")
    precondition(percent(-2, ready: true) == "0%")
    precondition(percent(50, ready: false) == "—")
    precondition(isExternalHardware(internalDevice: false, network: false, protocolName: "USB"))
    precondition(isExternalHardware(internalDevice: false, network: false, protocolName: "PCI-Express"))
    precondition(!isExternalHardware(internalDevice: true, network: false, protocolName: "PCI-Express"))
    precondition(!isExternalHardware(internalDevice: false, network: false, protocolName: "Disk Image"))
    precondition(!isExternalHardware(internalDevice: false, network: true, protocolName: "SMB"))
    precondition(!isExternalHardware(internalDevice: nil, network: false, protocolName: nil))
    var diskCounters = DiskIOCounters()
    precondition(diskCounters.sample(read: 1000, written: 2000, now: 10) == nil)
    let diskRates = diskCounters.sample(read: 1400, written: 2600, now: 12)!
    precondition(diskRates.read == 200 && diskRates.write == 300)
    precondition(diskCounters.sample(read: 0, written: 0, now: 14) == nil)
    precondition(diskCounters.sample(read: 50, written: 100, now: 14) == nil)
    let afterReset = diskCounters.sample(read: 150, written: 300, now: 16)!
    precondition(afterReset.read == 50 && afterReset.write == 100)
    var mountedFixtures = [MountedExternalDisk(url: URL(fileURLWithPath: "/"), reading: ExternalDiskReading(id: "external-a", name: "Demo SSD", total: 1000, free: 400))]
    var diskDiscoveries = 0
    let testDisks = ExternalDiskMonitor(discover: { diskDiscoveries += 1; return mountedFixtures })
    precondition(testDisks.sample(now: 10).map(\.id) == ["external-a"])
    mountedFixtures.append(MountedExternalDisk(url: URL(fileURLWithPath: "/"), reading: ExternalDiskReading(id: "external-b", name: "USB", total: 500, free: 100)))
    precondition(testDisks.sample(now: 11).count == 1 && diskDiscoveries == 1)
    testDisks.invalidate()
    let connected = testDisks.sample(now: 12)
    precondition(connected.count == 2 && connected.allSatisfy { !$0.activityReady })
    mountedFixtures.removeFirst()
    testDisks.invalidate()
    precondition(testDisks.sample(now: 13).map(\.id) == ["external-b"])
    mountedFixtures.removeAll()
    testDisks.invalidate()
    precondition(testDisks.sample(now: 14).isEmpty)
    report("PASS: disk discovery cache, connection/removal invalidation and fresh reconnect baselines")
    let ejectFixture = ExternalDiskReading(id: "test-eject", name: "Test Volume", total: 100, free: 50, volumeURL: URL(fileURLWithPath: "/Volumes/Neylu-Test-Only"))
    func waitForEjection(_ actions: DiskActions) {
        let deadline = Date().addingTimeInterval(5)
        while actions.ejectingID != nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        precondition(actions.ejectingID == nil)
    }
    var ejectCalls = 0
    var ejectCompletions = 0
    let successfulEject = DiskActions(operation: { _ in ejectCalls += 1 })
    successfulEject.onFinish = { precondition(Thread.isMainThread); ejectCompletions += 1 }
    successfulEject.eject(ejectFixture)
    successfulEject.eject(ejectFixture)
    waitForEjection(successfulEject)
    precondition(ejectCalls == 1 && ejectCompletions == 1 && successfulEject.failure == nil)
    let busyEject = DiskActions(operation: { _ in throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError, userInfo: [NSLocalizedDescriptionKey: "Test volume is busy"]) })
    busyEject.eject(ejectFixture)
    waitForEjection(busyEject)
    precondition(busyEject.failure?.message == "Test volume is busy")
    precondition(busyEject.failure?.name == "Test Volume")
    successfulEject.eject(ExternalDiskReading(id: "demo", name: "Demo", total: 100, free: 50))
    precondition(successfulEject.ejectingID == nil && ejectCalls == 1)
    report("PASS: ejection duplicate-click guard, main-thread completion, OS error presentation data and inert demo volumes")
    report("PASS: external hardware filtering and disk I/O counter baselines, resets and zero-time intervals")
    let sampler = Sampler()
    _ = sampler.sample()
    Thread.sleep(forTimeInterval: 1)
    let r = sampler.sample()
    precondition(r.cpuReady && (0...100).contains(r.cpu))
    precondition(abs(r.cpuUser + r.cpuSystem + r.cpuIdle - 100) < 0.001)
    precondition(abs(r.cpuUser + r.cpuSystem - r.cpu) < 0.001)
    precondition(r.memoryReady && (0...100).contains(r.memory))
    precondition(r.usedMemory <= r.totalMemory && r.totalMemory > 0)
    precondition(r.diskReady && r.diskTotal > 0 && r.diskFree <= r.diskTotal)
    if r.gpuReady { precondition((0...100).contains(r.gpu)) }
    let position = detailFrame(button: NSRect(x: 900, y: 1000, width: 140, height: 24), visible: NSRect(x: 0, y: 0, width: 1200, height: 1000), content: NSSize(width: 380, height: 480))
    precondition(position.maxY == 992 && position.maxX <= 1192)
    var mountEventReading = Reading(cpu: 42, memory: 63, download: 123, upload: 456, cpuReady: true, networkReady: true, memoryReady: true)
    sampler.refreshDisks(into: &mountEventReading)
    precondition(mountEventReading.cpu == 42 && mountEventReading.memory == 63)
    precondition(mountEventReading.download == 123 && mountEventReading.upload == 456)
    precondition(mountEventReading.cpuReady && mountEventReading.networkReady && mountEventReading.memoryReady)
    report("PASS: mount/eject refresh preserves CPU, memory and network readings")
    sampler.resetAfterWake()
    let wakeReading = sampler.sample()
    precondition(!wakeReading.cpuReady && !wakeReading.networkReady && !wakeReading.diskActivityReady)
    precondition(wakeReading.externalDisks.allSatisfy { !$0.activityReady })
    precondition(wakeReading.memoryReady)
    report("PASS: wake starts fresh CPU/network/disk baselines without stale rate spikes")
    precondition(r.download >= 0 && r.upload >= 0)
    precondition(automaticNetworkInterface(primary: "utun2", previous: "en0", available: ["en0", "utun2"]) == "utun2")
    precondition(automaticNetworkInterface(primary: "en4", previous: "en0", available: ["en0", "en4"]) == "en4")
    precondition(automaticNetworkInterface(primary: nil, previous: "en4", available: ["en0", "en4"]) == "en4")
    precondition(automaticNetworkInterface(primary: nil, previous: "utun2", available: ["utun2", "en10", "en2"]) == "en2")
    precondition(automaticNetworkInterface(primary: "en0", previous: "en0", available: []) == nil)
    report("PASS: decimal/binary formatting, automatic primary/VPN routing, stable physical fallback, offline routes and live kernel sampling")
    exit(0)
}
