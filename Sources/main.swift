import AppKit
import SwiftUI

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
    override func layout() {
        super.layout()
        window?.invalidateShadow()
    }
}

final class DetailPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

func detailFrame(button: NSRect, visible: NSRect, content: NSSize) -> NSRect {
    let width = min(content.width, visible.width - 16)
    let height = min(content.height, visible.height - 16)
    let x = min(max(button.midX - width / 2, visible.minX + 8), visible.maxX - width - 8)
    let top = visible.maxY - 8
    return NSRect(x: x, y: max(visible.minY + 8, top - height), width: width, height: height)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private var meter: MeterView!
    private let sampler = Sampler()
    private let model = MonitorModel()
    private var panel: DetailPanel!
    private var hosting: NSHostingController<DetailView>!
    private var outsideMonitor: Any?
    private var keyMonitor: Any?
    private var timer: Timer?
    private var terminationSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Avoid duplicate readouts if the app is opened twice.
        if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.QuietBar").count > 1 {
            NSApp.terminate(nil)
            return
        }
        signal(SIGTERM, SIG_IGN)
        terminationSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        terminationSource?.setEventHandler { NSApp.terminate(nil) }
        terminationSource?.resume()
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
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.contentTintColor = nil
        button.target = self
        button.action = #selector(toggleDetails)
        button.toolTip = "Neylu · 网速 / 内存 / CPU"
        button.setAccessibilityRole(.button)
        hosting = NSHostingController(rootView: DetailView(model: model))
        panel = DetailPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
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
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = 18
            // Leave tint and appearance unset: macOS owns material, contrast,
            // accent and accessibility adaptations. Do not stack custom blur.
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
        model.onSettingsChange = { [weak self] in self?.applySettings() }
        applySettings()
        timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.update(recordHistory: true) }
        timer?.tolerance = 0.25
        RunLoop.main.add(timer!, forMode: .common)
        if CommandLine.arguments.contains("--show-details") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.toggleDetails() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(saveHistory), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wake), name: NSWorkspace.didWakeNotification, object: nil)
    }
    private func applySettings() {
        sampler.selectedInterface = nil
        meter.basis = model.basis
        item.length = MeterView.meterWidth(for: model.basis)
        update()
    }
    private func update(recordHistory: Bool = false) {
        model.reading = sampler.sample()
        if recordHistory { model.recordCPU(model.reading) }
        meter.reading = model.reading
        item.button?.image = meter.makeStatusImage()
        item.button?.setAccessibilityLabel(meter.accessibilitySummary)
    }
    func applicationWillTerminate(_ notification: Notification) { model.saveHistoryNow() }
    @objc private func saveHistory() { model.saveHistoryNow() }
    @objc private func wake() { update() }
    @objc func showAbout(_ sender: Any?) {
        panel.orderOut(nil)
        let text = "简洁的 macOS 菜单栏监控工具"
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let credits = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ])
        NSApp.activate(ignoringOtherApps: true)
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "Neylu", .credits: credits
        ]
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            options[.applicationIcon] = icon
        }
        NSApp.orderFrontStandardAboutPanel(options: options)
    }
    @objc private func hideDetails() { panel.orderOut(nil) }
    @objc private func toggleDetails() {
        guard let button = item.button, let statusWindow = button.window else { return }
        if panel.isVisible { panel.orderOut(nil); return }
        let loginEnabled = ServiceManagement.SMAppService.mainApp.status == .enabled
        if model.loginEnabled != loginEnabled { model.loginEnabled = loginEnabled }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? statusWindow.screen ?? NSScreen.main!
        let rawAnchor = statusWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let isOnscreen = rawAnchor.midX >= screen.frame.minX && rawAnchor.midX <= screen.frame.maxX && abs(rawAnchor.maxY - screen.frame.maxY) < 100
        let anchorX = isOnscreen ? rawAnchor.midX : mouse.x
        let anchor = NSRect(x: anchorX, y: screen.visibleFrame.maxY, width: 0, height: 0)
        let frame = detailFrame(button: anchor, visible: screen.visibleFrame, content: hosting.view.fittingSize)
        panel.setFrame(frame, display: true)
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        panel.makeFirstResponder(nil)
        if let index = CommandLine.arguments.firstIndex(of: "--panel-report"), CommandLine.arguments.count > index + 1 {
            let report: [String: Any] = ["panelTop": panel.frame.maxY, "menuBottom": anchor.minY, "visibleTop": screen.visibleFrame.maxY, "gap": anchor.minY - panel.frame.maxY, "width": panel.frame.width, "height": panel.frame.height, "surface": String(describing: type(of: panel.contentView!.subviews.first!)), "appearance": panel.effectiveAppearance.name.rawValue, "appearanceFollowsSystem": NSApp.appearance == nil, "reduceTransparency": NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            }
        }
    }
}

import ServiceManagement

if CommandLine.arguments.contains("--self-test") {
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
    precondition(r.download >= 0 && r.upload >= 0)
    precondition(sampler.interfaces.contains { $0.name == r.interface } || !r.networkReady)
    sampler.selectedInterface = "neylu-nonexistent-test-interface"
    let offline = sampler.sample()
    precondition(!offline.networkReady && offline.download == 0 && offline.upload == 0)
    sampler.selectedInterface = nil
    precondition(!sampler.sample().networkReady)
    if r.networkReady {
        sampler.selectedInterface = r.interface
        precondition(!sampler.sample().networkReady)
        Thread.sleep(forTimeInterval: 0.2)
        precondition(sampler.sample().networkReady)
    }
    print("PASS: decimal/binary boundaries, manual/automatic/offline interfaces, unit boundaries, missing samples, CPU and memory kernel sampling. Network interface: \(r.interface); ready: \(r.networkReady).")
    exit(0)
}

if CommandLine.arguments.contains("--diagnose") {
    let sampler = Sampler()
    _ = sampler.sample()
    Thread.sleep(forTimeInterval: 1)
    let reading = sampler.sample()
    let output: [String: Any] = ["elapsedSinceBootSeconds": elapsedSinceBoot().map { $0 as Any } ?? NSNull(), "cpuPercent": reading.cpu, "cpuTemperatureCelsius": reading.cpuTemperature.map { $0 as Any } ?? NSNull(), "memoryPercent": reading.memory,
        "usedMemoryBytes": reading.usedMemory, "totalMemoryBytes": reading.totalMemory,
        "downloadBytesPerSecond": reading.download, "uploadBytesPerSecond": reading.upload,
        "interface": reading.interface, "gpuPercent": reading.gpu, "gpuReady": reading.gpuReady, "gpuCores": reading.gpuCores ?? 0, "diskTotalBytes": reading.diskTotal, "diskFreeBytes": reading.diskFree, "diskReady": reading.diskReady, "diskReadBytesPerSecond": reading.diskRead, "diskWriteBytesPerSecond": reading.diskWrite, "diskActivityReady": reading.diskActivityReady, "cpuReady": reading.cpuReady,
        "networkReady": reading.networkReady, "memoryReady": reading.memoryReady]
    let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    exit(reading.cpuReady && reading.memoryReady ? 0 : 1)
}

if let index = CommandLine.arguments.firstIndex(of: "--preview"), CommandLine.arguments.count > index + 1 {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 184, height: 176))
    root.wantsLayer = true
    root.layer?.backgroundColor = NSColor(calibratedWhite: 0.5, alpha: 1).cgColor
    let native = CommandLine.arguments.contains("--preview-native")
    for (offset, appearance, basis) in [(CGFloat(0), NSAppearance.Name.aqua, UnitBasis.decimal), (CGFloat(44), NSAppearance.Name.darkAqua, UnitBasis.decimal), (CGFloat(88), NSAppearance.Name.aqua, UnitBasis.binary), (CGFloat(132), NSAppearance.Name.darkAqua, UnitBasis.binary)] {
        let bar = NSView(frame: NSRect(x: 0, y: offset, width: 184, height: 44))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = (appearance == .aqua ? (native ? NSColor(calibratedRed: 0.02, green: 0.45, blue: 0.75, alpha: 1) : NSColor(calibratedWhite: 0.94, alpha: 1)) : NSColor(calibratedWhite: 0.12, alpha: 1)).cgColor
        bar.appearance = NSAppearance(named: appearance)
        let meter = MeterView(frame: NSRect(x: 16, y: 10, width: MeterView.meterWidth(for: basis), height: 24))
        meter.basis = native ? .decimal : basis
        if native { meter.frame.size.width = MeterView.meterWidth(for: meter.basis) }
        let maximum = CommandLine.arguments.contains("--preview-maximum")
        let maximumRate = basis == .binary ? 1_023.0 * 1_024 : 999_000
        meter.reading = Reading(cpu: maximum ? 100 : 14, memory: maximum ? 100 : 82, download: maximum ? maximumRate : 529_000, upload: maximum ? maximumRate : 13_000, cpuReady: true, networkReady: true, memoryReady: true)
        if native {
            let button = NSStatusBarButton(frame: meter.frame)
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.contentTintColor = nil
            button.image = meter.makeStatusImage()
            button.appearsDisabled = offset >= 88
            bar.addSubview(button)
        } else { bar.addSubview(meter) }
        root.addSubview(bar)
    }
    let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds)!
    root.cacheDisplay(in: root.bounds, to: bitmap)
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
