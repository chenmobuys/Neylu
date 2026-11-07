import AppKit
import SwiftUI
import ServiceManagement

// NSVisualEffectView's backdrop is composited separately from its CALayer.
// Mask the material itself as well as the SwiftUI content, including the window shadow.
final class RoundedMaterialView: NSVisualEffectView {
    private var maskedSize = NSSize.zero
    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0, bounds.size != maskedSize else { return }
        maskedSize = bounds.size
        maskImage = NSImage(size: bounds.size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18).fill()
            return true
        }
    }
}

// The window needs a transparent, rounded root as well as rounded glass.
// Glass cornerRadius shapes its material, not the enclosing window backing.
final class DetailSurfaceContainer: NSView {
    override var isOpaque: Bool { false }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = 18
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func refreshAccessibility() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
                ? NSColor.windowBackgroundColor.cgColor : NSColor.clear.cgColor
        }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshAccessibility() }
    override func layout() {
        super.layout()
        refreshAccessibility()
        window?.invalidateShadow()
    }
}

@available(macOS 26.0, *)
final class AdaptiveGlassView: NSGlassEffectView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        style = .regular
        cornerRadius = 18
        updateMaterialTint()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateMaterialTint()
    }
    func updateMaterialTint() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        // Keep system glass compositing. A semantic dark tint improves contrast
        // over bright windows without introducing a fixed custom background.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            tintColor = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
                ? NSColor.windowBackgroundColor : (dark ? NSColor.windowBackgroundColor.withAlphaComponent(0.6) : nil)
        }
    }
}

final class DetailPanel: NSPanel {
    var onHide: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func orderOut(_ sender: Any?) { super.orderOut(sender); onHide?() }
    override func cancelOperation(_ sender: Any?) { orderOut(sender) }
}


func detailFrame(button: NSRect, visible: NSRect, content: NSSize) -> NSRect {
    let width = min(content.width, visible.width - 16)
    let height = min(content.height, visible.height - 16)
    let x = min(max(button.midX - width / 2, visible.minX + 8), visible.maxX - width - 8)
    let top = visible.maxY - 8
    return NSRect(x: x, y: max(visible.minY + 8, top - height), width: width, height: height)
}

// NSStatusItem exposes target geometry, not the system menu bar's animation
// timing. Keep the old content left-aligned until the actual status window
// stops moving, then commit the pending layout as one image.
final class StatusItemResizeGate {
    private(set) var isActive = false
    private var generation = 0
    private var work: DispatchWorkItem?
    private let interval: TimeInterval
    init(interval: TimeInterval = 0.08) { self.interval = interval }

    func begin(resize: () -> Void, geometry: @escaping () -> [NSRect], refresh: @escaping () -> Void = {}, ready: @escaping () -> Bool = { true }, reveal: @escaping () -> Void) {
        precondition(Thread.isMainThread)
        generation += 1
        work?.cancel()
        isActive = true
        let token = generation
        resize()
        refresh()
        observe(token: token, previous: geometry(), stable: 0, geometry: geometry, refresh: refresh, ready: ready, reveal: reveal)
    }
    func cancel() {
        generation += 1
        work?.cancel()
        work = nil
        isActive = false
    }
    private func observe(token: Int, previous: [NSRect], stable: Int,
                         geometry: @escaping () -> [NSRect], refresh: @escaping () -> Void, ready: @escaping () -> Bool, reveal: @escaping () -> Void) {
        schedule(after: interval, token: token) { [weak self] in
            guard let self else { return }
            refresh()
            let current = geometry()
            let count = current == previous ? stable + 1 : 0
            if count >= 3 && ready() {
                self.work = nil
                self.isActive = false
                reveal()
            } else {
                self.observe(token: token, previous: current, stable: count, geometry: geometry, refresh: refresh, ready: ready, reveal: reveal)
            }
        }
    }
    private func schedule(after delay: TimeInterval, token: Int, action: @escaping () -> Void) {
        let next = DispatchWorkItem { [weak self] in
            guard let self, token == self.generation else { return }
            action()
        }
        work = next
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: next)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private var meter: MeterView!
    private let sampling = SamplingService()
    private let model: MonitorModel
    init(model: MonitorModel = MonitorModel()) {
        self.model = model
        super.init()
    }
    private var panel: DetailPanel!
    private var hosting: NSHostingController<DetailView>!
    private var menuBarSettings: MenuBarSettingsController?
    private lazy var statusMenuCoordinator = SettingsMenuButton.Coordinator(settings: model.settings)
    private lazy var statusMenu = statusMenuCoordinator.makeMenu(pullsDown: false)
    private var outsideMonitor: Any?
    private var keyMonitor: Any?
    private var timer: Timer?
    private var terminationSource: DispatchSourceSignal?
    private let statusResize = StatusItemResizeGate()
    private var statusMask: StatusImageMask?
    private var statusCanvasSize: NSSize?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Avoid duplicate readouts if the app is opened twice.
        if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "io.github.chenmobuys.Neylu").count > 1 {
            NSApp.terminate(nil)
            return
        }
        signal(SIGTERM, SIG_IGN)
        terminationSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        terminationSource?.setEventHandler { NSApp.terminate(nil) }
        terminationSource?.resume()
        if CommandLine.arguments.contains("--screenshot-mode") {
            NSApp.appearance = NSAppearance(named: CommandLine.arguments.contains("--screenshot-dark") ? .darkAqua : .aqua)
        }
        NSApp.setActivationPolicy(.accessory)
        // Read the bundled icon directly instead of Launch Services' older cache.
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
        item = NSStatusBar.system.statusItem(withLength: MeterView.meterWidth(for: model.basis))
        guard let button = item.button else { return }
        meter = MeterView(frame: NSRect(x: 0, y: 0, width: MeterView.meterWidth(for: model.basis), height: 22))
        meter.basis = model.basis
        meter.configuration = model.settings.menuBarConfiguration
        item.length = MeterView.meterWidth(for: model.basis, configuration: meter.configuration)
        button.imagePosition = .imageOnly
        // The status window may finish resizing after a new image is assigned.
        // Keep every intermediate frame inside the space AppKit has allocated.
        button.imageScaling = .scaleNone
        button.clipsToBounds = true
        button.postsFrameChangedNotifications = true
        button.postsBoundsChangedNotifications = true
        for name in [NSView.frameDidChangeNotification, NSView.boundsDidChangeNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(refreshStatusMask), name: name, object: button)
        }
        button.contentTintColor = nil
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = L("app.status_tooltip")
        button.setAccessibilityRole(.button)
        model.layout.isVisible = false
        hosting = NSHostingController(rootView: DetailView(model: model))
        panel = DetailPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.onHide = { [weak self] in self?.model.layout.isVisible = false }
        panel.autorecalculatesKeyViewLoop = true
        panel.title = "Neylu"
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary, .moveToActiveSpace]
        panel.isReleasedWhenClosed = false
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        let surface: NSView
        if #available(macOS 26.0, *), !CommandLine.arguments.contains("--legacy-material") {
            let glass = AdaptiveGlassView()
            // System glass follows the chosen appearance; only the dark tint
            // uses the native window color to keep text legible over bright content.
            glass.contentView = hosting.view
            surface = glass
        } else {
            let material = RoundedMaterialView()
            material.material = .popover
            material.blendingMode = .behindWindow
            material.state = .followsWindowActiveState
            material.wantsLayer = true
            material.layer?.cornerRadius = 18
            material.layer?.masksToBounds = true
            material.addSubview(hosting.view)
            surface = material
        }
        let container = DetailSurfaceContainer()
        container.addSubview(surface)
        surface.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = container
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            surface.topAnchor.constraint(equalTo: container.topAnchor),
            surface.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: surface.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: surface.bottomAnchor)
        ])
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.panel.orderOut(nil) }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, self?.panel.isVisible == true {
                self?.panel.orderOut(nil)
                return nil
            }
            return event
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(hideDetails), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(hideDetails), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        model.onSettingsChange = { [weak self] in self?.applySettings() }
        model.settings.onMenuBarChange = { [weak self] in self?.applyMenuBarConfiguration() }
        model.settings.onAppearanceChange = { [weak self] in self?.applyAppearance() }
        model.settings.onRefreshIntervalChange = { [weak self] in self?.restartSamplingTimer() }
        model.settings.onLanguageChange = { [weak self] in
            guard let self else { return }
            self.item.button?.toolTip = L("app.status_tooltip")
            self.item.button?.setAccessibilityLabel(self.meter.accessibilitySummary)
            DispatchQueue.main.async { self.updates.refreshLanguage() }
        }
        model.settings.onAutomaticUpdateChange = { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.model.settings.automaticUpdateChecks { self.backgroundUpdates.start() }
                else { self.backgroundUpdates.stop() }
            }
        }
        model.diskActions.onFinish = { [weak self] in self?.volumesChanged() }
        model.layout.onSizeChange = { [weak self] in
            DispatchQueue.main.async { self?.resizeVisibleDetails() }
        }
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(volumesChanged), name: name, object: nil)
        }
        applyAppearance()
        applySettings()
        sampling.onSample = { [weak self] reading, timestamp, recordHistory in
            guard let self else { return }
            self.model.reading = reading
            if recordHistory { self.model.recordCPU(reading, at: timestamp) }
            self.updateMeter()
        }
        sampling.onDisks = { [weak self] disks in
            guard let self else { return }
            var reading = self.model.reading
            reading.diskName = disks.diskName
            reading.diskTotal = disks.diskTotal
            reading.diskFree = disks.diskFree
            reading.diskReady = disks.diskReady
            reading.externalDisks = disks.externalDisks
            self.model.reading = reading
            self.updateMeter()
        }
        update()
        restartSamplingTimer()
        if !CommandLine.arguments.contains("--screenshot-mode") {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updates.onDiscovery = { [weak owner = self] update in owner?.backgroundUpdates.accept(update) }
                self.backgroundUpdates.start()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(accessibilityDisplayChanged), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        if !CommandLine.arguments.contains("--screenshot-mode"),
           let version = Bundle.main.object(forInfoDictionaryKey: "NeyluReleaseVersion") as? String,
           ReleaseNotesHistory.shouldPresent(current: version) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.showReleaseNotes(afterUpdate: true)
            }
        }
        if CommandLine.arguments.contains("--show-updates") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.checkForUpdates(nil) }
        }
        if CommandLine.arguments.contains("--show-menu-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.showMenuBarSettings(nil) }
        }
        if CommandLine.arguments.contains("--show-details") {
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.toggleDetails() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(prepareForSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wake), name: NSWorkspace.didWakeNotification, object: nil)
    }
    private func restartSamplingTimer() {
        timer?.invalidate()
        let interval = model.settings.refreshInterval.seconds
        let replacement = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.update(recordHistory: true) }
        replacement.tolerance = min(0.5, interval * 0.1)
        timer = replacement
        RunLoop.main.add(replacement, forMode: .common)
    }
    @objc private func accessibilityDisplayChanged() {
        (panel?.contentView as? DetailSurfaceContainer)?.refreshAccessibility()
        if #available(macOS 26.0, *), let glass = panel?.contentView?.subviews.first as? AdaptiveGlassView { glass.updateMaterialTint() }
    }
    private func applyAppearance() {
        guard !CommandLine.arguments.contains("--screenshot-mode") else { return }
        NSApp.appearance = model.settings.appearanceMode.appKitAppearance
        panel?.invalidateShadow()
        accessibilityDisplayChanged()
    }
    private func applySettings() {
        meter.basis = model.basis
        applyMenuBarConfiguration()
    }
    private func applyMenuBarConfiguration() {
        meter.configuration = model.settings.menuBarConfiguration
        guard let button = item.button else { return }
        let width = MeterView.meterWidth(for: model.basis, configuration: meter.configuration)
        if width < item.length {
            // The shorter bitmap fits both the old and new allocations.
            statusResize.cancel()
            setStatusContent(meter.makeStatusImage(), width: width)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                item.length = width
            }
        } else if width > item.length {
            statusResize.begin(resize: { [weak self] in
                guard let self else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0
                    context.allowsImplicitAnimation = false
                    self.item.length = width
                    button.window?.contentView?.layoutSubtreeIfNeeded()
                }
            }, geometry: { [weak button] in
                guard let button else { return [] }
                return [button.window?.frame ?? .zero, button.frame, button.bounds]
            }, refresh: { [weak self] in self?.refreshStatusMask() }, ready: { [weak button] in
                guard let button else { return false }
                return abs(button.bounds.width - width) < 0.5
            }, reveal: { [weak self] in self?.updateMeter() })
        } else if !statusResize.isActive {
            updateMeter()
        }
        button.setAccessibilityLabel(meter.accessibilitySummary)
    }
    private func setStatusContent(_ image: NSImage, width: CGFloat) {
        statusMask = StatusImageMask(image: image, contentWidth: width)
        statusCanvasSize = nil
        refreshStatusMask()
    }
    @objc private func refreshStatusMask() {
        guard let mask = statusMask, let button = item.button else { return }
        let size = button.bounds.size
        guard size.width > 0, size.height > 0, size != statusCanvasSize else { return }
        statusCanvasSize = size // Set before assigning image, which may trigger layout.
        button.image = mask.render(in: size)
    }
    @objc func showMenuBarSettings(_ sender: Any?) {
        panel.orderOut(nil)
        if menuBarSettings == nil { menuBarSettings = MenuBarSettingsController(model: model) }
        menuBarSettings?.present()
    }
    private func update(recordHistory: Bool = false) {
        if CommandLine.arguments.contains("--screenshot-mode") {
            model.applyScreenshotFixture()
        } else {
            sampling.sample(recordHistory: recordHistory)
            return
        }
        updateMeter()
    }
    private func updateMeter() {
        meter.reading = model.reading
        guard !statusResize.isActive else { return }
        setStatusContent(meter.makeStatusImage(), width: MeterView.meterWidth(for: meter.basis, configuration: meter.configuration))
        item.button?.setAccessibilityLabel(meter.accessibilitySummary)
    }
    func applicationWillTerminate(_ notification: Notification) {
        statusResize.cancel()
        sampling.suspend()
        model.saveHistoryNow()
        MainActor.assumeIsolated { backgroundUpdates.stop() }
    }
    @objc private func prepareForSleep() {
        timer?.invalidate()
        sampling.suspend()
        MainActor.assumeIsolated { backgroundUpdates.stop() }
        hideDetails()
        model.saveHistoryNow()
    }
    @objc private func wake() {
        if !CommandLine.arguments.contains("--screenshot-mode") { MainActor.assumeIsolated { backgroundUpdates.start() } }
        if CommandLine.arguments.contains("--screenshot-mode") { update() }
        else { sampling.resumeAfterWake() }
        restartSamplingTimer()
    }
    @MainActor private lazy var updates = UpdateController()
    @MainActor private lazy var backgroundUpdates = BackgroundUpdateChecker(settings: model.settings)
    @MainActor @objc func checkForUpdates(_ sender: Any?) {
        hideDetails()
        updates.present()
    }
    private var releaseNotes: ReleaseNotesController?
    @objc func showReleaseNotes(_ sender: Any?) { showReleaseNotes(afterUpdate: false) }
    private func showReleaseNotes(afterUpdate: Bool) {
        hideDetails()
        if releaseNotes == nil { releaseNotes = ReleaseNotesController(settings: model.settings) }
        releaseNotes?.present(afterUpdate: afterUpdate)
    }
    private var about: AboutController?
    @objc func showAbout(_ sender: Any?) {
        hideDetails()
        if about == nil { about = AboutController(settings: model.settings) }
        about?.present()
    }
    @objc private func volumesChanged() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.volumesChanged() }
            return
        }
        guard !CommandLine.arguments.contains("--screenshot-mode") else { return }
        // Mount notifications can arrive back-to-back. Refresh only disk fields,
        // preserving CPU/network baselines and the menu bar's current readings.
        sampling.refreshDisks()
    }
    private func resizeVisibleDetails() {
        guard panel.isVisible, let screen = panel.screen else { return }
        hosting.view.layoutSubtreeIfNeeded()
        let anchor = NSRect(x: panel.frame.midX, y: screen.visibleFrame.maxY, width: 0, height: 0)
        let frame = detailFrame(button: anchor, visible: screen.visibleFrame, content: hosting.view.fittingSize)
        if abs(panel.frame.height - frame.height) > 0.5 { panel.setFrame(frame, display: true) }
    }
    @objc private func hideDetails() { panel.orderOut(nil) }
    @objc private func statusItemClicked() {
        guard let button = item.button else { return }
        if let event = NSApp.currentEvent, event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            hideDetails()
            // Set the menu itself: contextual menus may inherit the status
            // window's dark appearance even if its button is explicitly light.
            statusMenu.appearance = NSApp.effectiveAppearance
            // Keep the normal left-click action; assigning item.menu would take it over.
            NSMenu.popUpContextMenu(statusMenu, with: event, for: button)
        } else {
            toggleDetails()
        }
    }
    @objc private func toggleDetails() {
        guard let button = item.button, let statusWindow = button.window else { return }
        if panel.isVisible { panel.orderOut(nil); return }
        model.layout.isVisible = true
        hosting.view.layoutSubtreeIfNeeded()
        let loginEnabled = ServiceManagement.SMAppService.mainApp.status == .enabled
        if model.loginEnabled != loginEnabled { model.loginEnabled = loginEnabled }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? statusWindow.screen ?? NSScreen.main!
        let rawAnchor = statusWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let isOnscreen = rawAnchor.midX >= screen.frame.minX && rawAnchor.midX <= screen.frame.maxX && abs(rawAnchor.maxY - screen.frame.maxY) < 100
        let anchorX = isOnscreen ? rawAnchor.midX : mouse.x
        let anchor = NSRect(x: anchorX, y: screen.visibleFrame.maxY, width: 0, height: 0)
        model.layout.maximumMetricsHeight = max(120, screen.visibleFrame.height - 160)
        let frame = detailFrame(button: anchor, visible: screen.visibleFrame, content: hosting.view.fittingSize)
        panel.setFrame(frame, display: true)
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        panel.makeFirstResponder(nil)
        if let index = CommandLine.arguments.firstIndex(of: "--panel-report"), CommandLine.arguments.count > index + 1 {
            let report: [String: Any] = ["panelTop": panel.frame.maxY, "menuBottom": anchor.minY, "visibleTop": screen.visibleFrame.maxY, "gap": anchor.minY - panel.frame.maxY, "width": panel.frame.width, "height": panel.frame.height, "surface": String(describing: type(of: panel.contentView!.subviews.first!)), "appearance": panel.effectiveAppearance.name.rawValue, "appearanceFollowsSystem": NSApp.appearance == nil, "refreshInterval": model.settings.refreshInterval.seconds, "timerInterval": timer?.timeInterval ?? 0, "reduceTransparency": NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            }
        }
    }
}
