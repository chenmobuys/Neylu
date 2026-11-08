import Foundation
import Testing

extension NeyluTests {
  @Test func legacyLoginQueryAvailability() throws {
    let fixture = try ToolFixture()
    let source = try fixture.write(
      "compatibility.swift",
      """
      import NeyluLegacyServiceManagement
      import CoreFoundation
      func readLoginItem(_ identifier: CFString) {
        _ = NeyluCopyLegacyLoginJob(identifier)
      }
      """)
    let module = TestSupport.root.appendingPathComponent("Sources/LegacyServiceManagement")
    for arch in ["arm64", "x86_64"] {
      let arguments = [
        "swiftc", "-typecheck", "-warnings-as-errors", "-I", module.path,
        "-module-cache-path", fixture.root.appendingPathComponent("ModuleCache").path,
        source.path, "-target",
      ]
      try ToolRunner.requireSuccess(
        ToolRunner.run("/usr/bin/xcrun", arguments + [arch + "-apple-macosx12.0"]))
      let modern = try ToolRunner.run(
        "/usr/bin/xcrun", arguments + [arch + "-apple-macosx13.0"])
      #expect(modern.status != 0)
      #expect(modern.error.contains("NeyluCopyLegacyLoginJob"))
      #expect(modern.error.contains("obsoleted in macOS 13.0"))
    }
  }
}
