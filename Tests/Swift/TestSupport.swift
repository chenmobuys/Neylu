import AppKit
import Foundation
import Testing

@testable import NeyluCore

@Suite(.serialized)
struct NeyluTests {}

enum TestSupport {
  struct Failure: Error { let message: String }
  static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
  static let app = root.appendingPathComponent("build/Neylu.app")
  static func waitForSignal(_ semaphore: DispatchSemaphore) async -> Bool {
    await withCheckedContinuation { continuation in
      DispatchQueue.global().async {
        continuation.resume(returning: semaphore.wait(timeout: .now() + 3) == .success)
      }
    }
  }
  @MainActor static func prepareNativeTests() throws {
    try #require(FileManager.default.changeCurrentDirectoryPath(root.path))
    L10n.useResources(at: root.appendingPathComponent("Resources"))
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    let image = try #require(
      NSImage(contentsOf: app.appendingPathComponent("Contents/Resources/AppIcon.icns")))
    image.setName(NSImage.applicationIconName)
    NSApp.applicationIconImage = image
  }
}
