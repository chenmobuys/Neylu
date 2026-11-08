// Compiled by render-docs.sh against the real App views. No system history is read.
import AppKit
import SwiftUI

L10n.useResources(at: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources"))

if let index = CommandLine.arguments.firstIndex(of: "--language"), index + 1 < CommandLine.arguments.count,
   let language = AppLanguage(rawValue: CommandLine.arguments[index + 1]), language != .automatic {
    // In-memory only; do not change the running app's saved language.
    UserDefaults.standard.setVolatileDomain(["appLanguage": language.rawValue], forName: UserDefaults.argumentDomain)
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for (name, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
    let appearance = NSAppearance(named: appearanceName)!
    application.appearance = appearance
    let model = MonitorModel(persistHistory: false)
    model.applyScreenshotFixture()
    let root = DetailView(model: model)
        .environment(\.colorScheme, name == "dark" ? .dark : .light)
        .environment(\.displayScale, 2)
        .environment(\.controlActiveState, .key)
    let hosting = NSHostingController(rootView: root)
    var size = NSSize(width: 380, height: hosting.view.fittingSize.height)
    hosting.view.frame = NSRect(origin: .zero, size: size)
    hosting.view.appearance = appearance
    hosting.view.wantsLayer = true
    hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless,
                          backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.contentView = hosting.view
    // Scroll content reports its intrinsic height after the first layout pass.
    for _ in 0..<3 {
        hosting.view.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        size = NSSize(width: 380, height: hosting.view.fittingSize.height)
        window.setContentSize(size)
        hosting.view.frame = NSRect(origin: .zero, size: size)
    }
    hosting.view.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    // Render shared native controls with a stable system background for docs.
    // WindowServer glass cannot be represented faithfully in a transparent PNG.
    let content = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2),
        pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    content.size = size
    hosting.view.cacheDisplay(in: hosting.view.bounds, to: content)
    let output = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2),
        pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    output.size = size
    let context = NSGraphicsContext(bitmapImageRep: output)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.clear(CGRect(x: 0, y: 0, width: size.width, height: size.height))
    NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 18, yRadius: 18).addClip()
    appearance.performAsCurrentDrawingAppearance {
        NSColor.windowBackgroundColor.setFill()
        NSRect(origin: .zero, size: size).fill()
        let foreground = NSImage(size: size)
        foreground.addRepresentation(content)
        foreground.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)
    }
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    try output.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent("overview-\(name)@2x.png"))

    let meter = MeterView(frame: NSRect(x: 0, y: 0, width: MeterView.meterWidth(for: .decimal), height: 22))
    meter.appearance = appearance
    meter.reading = model.reading
    let barSize = NSSize(width: meter.frame.width + 16, height: 30)
    let bar = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(barSize.width * 4),
        pixelsHigh: Int(barSize.height * 4), bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bar.size = barSize
    let barContext = NSGraphicsContext(bitmapImageRep: bar)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = barContext
    barContext.cgContext.clear(CGRect(origin: .zero, size: barSize))
    barContext.cgContext.translateBy(x: 8, y: barSize.height - 4)
    barContext.cgContext.scaleBy(x: 1, y: -1)
    appearance.performAsCurrentDrawingAppearance { meter.draw(meter.bounds) }
    barContext.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    try bar.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent("menu-\(name)@4x.png"))
}

if CommandLine.arguments.contains("--settings") {
    let model = MonitorModel(persistHistory: false)
    model.applyScreenshotFixture()
    let controller = MenuBarSettingsController(model: model)
    let view = controller.window!.contentView!
    view.layoutSubtreeIfNeeded()
    let image = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: image)
    try image.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent("menu-bar-settings.png"))
}
