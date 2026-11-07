import AppKit
import SwiftUI

/// AppKit tracking works on macOS 12 and in a nonactivating menu bar panel.
struct ChartHoverArea: NSViewRepresentable {
    let onMove: (CGPoint?) -> Void
    func makeNSView(context: Context) -> ChartTrackingView { ChartTrackingView(onMove: onMove) }
    func updateNSView(_ view: ChartTrackingView, context: Context) { view.onMove = onMove }
    static func dismantleNSView(_ view: ChartTrackingView, coordinator: ()) { view.onMove = { _ in } }
}

final class ChartTrackingView: NSView {
    var onMove: (CGPoint?) -> Void
    private var tracking: NSTrackingArea?
    init(onMove: @escaping (CGPoint?) -> Void) { self.onMove = onMove; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        updateTrackingAreas()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        tracking = area
        addTrackingArea(area)
    }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onMove(bounds.contains(point) ? point : nil)
    }
    override func mouseExited(with event: NSEvent) { onMove(nil) }
}
