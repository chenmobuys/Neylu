import Darwin
import Foundation
import Testing

extension NeyluTests {
  @Test(.enabled(if: ProcessInfo.processInfo.environment["NEYLU_HELPER_INTEGRATION"] == "1"))
  func nativeUpdaterReplacementAndRollback() throws {
    let fixture = try ToolFixture()
    let fm = FileManager.default
    var workers: [Process] = []
    var pids: [pid_t] = []
    defer {
      for worker in workers where worker.isRunning {
        worker.terminate()
        worker.waitUntilExit()
      }
      for pid in pids { kill(pid, SIGTERM) }
    }
    let source = try fixture.write(
      "fixture.swift",
      """
      import AppKit
      let app = NSApplication.shared
      app.setActivationPolicy(.accessory)
      let folder = Bundle.main.bundleURL.deletingLastPathComponent()
      let phase = try String(contentsOf: Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/phase"), encoding: .utf8)
      try String(ProcessInfo.processInfo.processIdentifier).write(to: folder.appendingPathComponent(phase + ".pid"), atomically: true, encoding: .utf8)
      if phase == "crash" { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exit(0) } }
      app.run()
      """)
    let binary = fixture.root.appendingPathComponent("Fixture")
    try ToolRunner.requireSuccess(
      ToolRunner.run(
        "/usr/bin/xcrun", ["swiftc", source.path, "-framework", "AppKit", "-o", binary.path]))
    func makeApp(_ path: URL, phase: String, version: String) throws {
      let contents = path.appendingPathComponent("Contents")
      let resources = contents.appendingPathComponent("Resources")
      try fm.createDirectory(
        at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
      try fm.createDirectory(at: resources, withIntermediateDirectories: true)
      try fm.copyItem(at: binary, to: contents.appendingPathComponent("MacOS/Neylu"))
      try phase.write(
        to: resources.appendingPathComponent("phase"), atomically: true, encoding: .utf8)
      let plist: [String: Any] = [
        "CFBundleExecutable": "Neylu", "CFBundleIdentifier": "io.github.chenmobuys.Neylu",
        "CFBundleName": "Neylu Test Fixture", "CFBundlePackageType": "APPL", "CFBundleVersion": "1",
        "CFBundleShortVersionString": "0.1.0", "NeyluReleaseVersion": version,
        "LSMinimumSystemVersion": "12.0", "LSUIElement": true,
      ]
      try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(
        to: contents.appendingPathComponent("Info.plist"))
      try ToolRunner.requireSuccess(
        ToolRunner.run("/usr/bin/codesign", ["--force", "--sign", "-", path.path]))
    }
    func waitFor(_ path: URL, worker: Process? = nil) throws {
      let deadline = ProcessInfo.processInfo.systemUptime + 25
      while ProcessInfo.processInfo.systemUptime < deadline {
        if fm.fileExists(atPath: path.path) { return }
        if let worker, !worker.isRunning {
          throw TestSupport.Failure(message: "Updater exited before readiness")
        }
        Thread.sleep(forTimeInterval: 0.1)
      }
      throw TestSupport.Failure(message: "Timed out waiting for " + path.lastPathComponent)
    }
    let target = fixture.root.appendingPathComponent("Neylu.app")
    let stage = fixture.root.appendingPathComponent(".Neylu-update-fixture")
    #if arch(arm64)
      let architecture = "arm64"
    #else
      let architecture = "x86_64"
    #endif
    func start(_ parent: pid_t, phase: String, version: String) throws -> Process {
      try fm.createDirectory(
        at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
      try makeApp(stage.appendingPathComponent("Neylu.app"), phase: phase, version: version)
      let helper = stage.appendingPathComponent("NeyluUpdater")
      try fm.copyItem(
        at: TestSupport.app.appendingPathComponent("Contents/Helpers/NeyluUpdater"), to: helper)
      try fm.createDirectory(
        at: stage.appendingPathComponent("Resources"), withIntermediateDirectories: false)
      for language in ["en", "zh-Hans"] {
        try fm.copyItem(
          at: TestSupport.app.appendingPathComponent("Contents/Resources/\(language).lproj"),
          to: stage.appendingPathComponent("Resources/\(language).lproj"))
      }
      let worker = Process()
      worker.executableURL = helper
      worker.arguments = [
        target.path, String(parent), version, architecture,
        fixture.root.appendingPathComponent("download").path, "en",
      ]
      try worker.run()
      workers.append(worker)
      try waitFor(stage.appendingPathComponent("ready"), worker: worker)
      return worker
    }
    try makeApp(target, phase: "old", version: "0.1.0-alpha.2")
    try ToolRunner.requireSuccess(ToolRunner.run("/usr/bin/open", ["-n", target.path]))
    let oldFile = fixture.root.appendingPathComponent("old.pid")
    let newFile = fixture.root.appendingPathComponent("new.pid")
    try waitFor(oldFile)
    let old = try #require(pid_t(String(contentsOf: oldFile, encoding: .utf8)))
    pids.append(old)
    let first = try start(old, phase: "new", version: "0.1.0-alpha.3")
    kill(old, SIGTERM)
    try waitFor(newFile)
    let installed = try #require(pid_t(String(contentsOf: newFile, encoding: .utf8)))
    pids.append(installed)
    let deadline = ProcessInfo.processInfo.systemUptime + 35
    while first.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
      Thread.sleep(forTimeInterval: 0.1)
    }
    try #require(!first.isRunning)
    #expect(first.terminationStatus == 0)
    #expect(
      try String(
        contentsOf: target.appendingPathComponent("Contents/Resources/phase"), encoding: .utf8)
        == "new")
    #expect(!fm.fileExists(atPath: stage.path))
    let second = try start(installed, phase: "crash", version: "0.1.0-alpha.4")
    try fm.removeItem(at: newFile)
    kill(installed, SIGTERM)
    try waitFor(newFile)
    let restored = try #require(pid_t(String(contentsOf: newFile, encoding: .utf8)))
    pids.append(restored)
    #expect(restored != installed)
    let plist =
      try PropertyListSerialization.propertyList(
        from: Data(contentsOf: target.appendingPathComponent("Contents/Info.plist")), format: nil)
      as! [String: Any]
    #expect(plist["NeyluReleaseVersion"] as? String == "0.1.0-alpha.3")
    second.terminate()
    second.waitUntilExit()
    #expect(!fm.fileExists(atPath: stage.path))
  }
}
