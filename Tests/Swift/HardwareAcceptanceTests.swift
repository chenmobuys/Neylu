import AppKit
import Testing
@testable import NeyluCore

extension NeyluTests {
  @Test(.enabled(if: ProcessInfo.processInfo.environment["NEYLU_HARDWARE_ACCEPTANCE"] == "1"))
  @MainActor func physicalDisplayPanelPlacement() async throws {
    try TestSupport.prepareNativeTests()
    let screens = NSScreen.screens
    try #require(!screens.isEmpty, "Requires a real GUI session")
    let panel = DetailPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    defer { panel.close() }
    for screen in screens + screens.prefix(1) {
      let frame = detailFrame(button: NSRect(x: screen.frame.midX, y: screen.frame.maxY, width: 120, height: 24), visible: screen.visibleFrame, content: NSSize(width: 380, height: 580))
      #expect(screen.visibleFrame.contains(frame))
      for name in [NSAppearance.Name.aqua, .darkAqua] {
        panel.appearance = NSAppearance(named: name)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(panel.screen == screen)
        #expect(panel.backingScaleFactor == screen.backingScaleFactor)
      }
    }
    print("PASS panel placement and local light/dark appearance on \(screens.count) physical displays; no system settings changed")
  }
}
