import AppKit
import Darwin
import Foundation
import Testing
@testable import NeyluCore

extension NeyluTests {
  @Test @MainActor func manualUpdateResultSupersedesPendingBackgroundCheck() async throws {
    let suite = "Neylu-manual-update-race-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
    defer { UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain) }
    UserDefaults.standard.setVolatileDomain(arguments.merging(["automaticUpdateChecks": true]) { _, new in new }, forName: UserDefaults.argumentDomain)
    let settings = MonitorSettings()
    var pending: CheckedContinuation<AvailableUpdate?, Error>?
    let checker = BackgroundUpdateChecker(settings: settings, defaults: defaults, version: "0.1.0-alpha.9", check: { _, _ in
      try await withCheckedThrowingContinuation { pending = $0 }
    })
    defer { checker.stop(); pending?.resume(throwing: CancellationError()) }
    checker.checkIfDue()
    for _ in 0..<100 where pending == nil { try await Task.sleep(nanoseconds: 10_000_000) }
    try #require(pending != nil)
    let update = AvailableUpdate(version: ReleaseVersion("0.1.0")!, notes: "", page: URL(string: AvailableUpdate.repository)!, package: URL(string: AvailableUpdate.repository)!, digest: "", size: 1, filename: "")
    checker.accept(update)
    let old = pending
    pending = nil
    old?.resume(returning: nil)
    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(settings.availableUpdateVersion == update.version.text)
    #expect(defaults.string(forKey: BackgroundUpdateChecker.availableKey) == update.version.text)
  }

  @Test func updaterCommandsBoundRuntimeAndOutput() async throws {
    let f = try ToolFixture()
    let source = try f.write("fixture.swift", """
      import Foundation
      import Darwin
      let mode = CommandLine.arguments[1]
      if mode == "output" { FileHandle.standardOutput.write(Data(repeating: 65, count: 2 * 1024 * 1024)); exit(0) }
      if mode == "exit" { print("diagnostic"); exit(7) }
      signal(SIGTERM, SIG_IGN)
      try String(getpid()).write(toFile: CommandLine.arguments[2], atomically: true, encoding: .utf8)
      while true { usleep(10000) }
      """)
    let binary = f.root.appendingPathComponent("command")
    try ToolRunner.requireSuccess(ToolRunner.run("/usr/bin/xcrun", ["swiftc", source.path, "-o", binary.path]))
    let result = try UpdateFiles.execute(binary.path, ["exit"])
    #expect(result.status == 7 && String(data: result.output, encoding: .utf8) == "diagnostic\n")
    #expect(throws: UpdateFailure.operation) { try UpdateFiles.run(binary.path, ["exit"]) }
    #expect(throws: UpdateFailure.operation) { try UpdateFiles.run(binary.path, ["output"], outputLimit: 1024) }
    let timeoutPID = f.root.appendingPathComponent("timeout.pid")
    let start = ProcessInfo.processInfo.systemUptime
    #expect(throws: UpdateFailure.preparationTimeout) { try UpdateFiles.run(binary.path, ["hang", timeoutPID.path], timeout: 2) }
    #expect(ProcessInfo.processInfo.systemUptime - start < 6)
    if let pid = try? String(contentsOf: timeoutPID, encoding: .utf8), let number = pid_t(pid) {
      #expect(kill(number, 0) != 0 && errno == ESRCH)
    } else { Issue.record("Command did not start before the timeout") }
    let cancelPID = f.root.appendingPathComponent("cancel.pid")
    let task = Task.detached { try UpdateFiles.run(binary.path, ["hang", cancelPID.path], timeout: 20) }
    for _ in 0..<200 where !FileManager.default.fileExists(atPath: cancelPID.path) { try await Task.sleep(nanoseconds: 10_000_000) }
    let started = FileManager.default.fileExists(atPath: cancelPID.path)
    task.cancel()
    do { _ = try await task.value; Issue.record("Cancelled command returned success") }
    catch { #expect(error is CancellationError) }
    try #require(started)
    let pid = try #require(pid_t(String(contentsOf: cancelPID, encoding: .utf8)))
    #expect(kill(pid, 0) != 0 && errno == ESRCH)
    // Detaching during cleanup must remain available in an already-cancelled task.
    let detached = Task.detached { () throws -> Int32 in
      withUnsafeCurrentTask { $0?.cancel() }
      return try UpdateFiles.execute(binary.path, ["exit"], cancellable: false).status
    }
    #expect(try await detached.value == 7)
  }
}
