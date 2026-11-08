import Foundation
import Testing

extension NeyluTests {
  @Test func ciPhasesAreSeparateAndPreserveFailureStatus() throws {
    let fixture = try ToolFixture()
    let log = fixture.root.appendingPathComponent("commands")
    let summary = fixture.root.appendingPathComponent("summary")
    let executable = try fixture.write(
      "bin/swift",
      """
      #!/bin/bash
      printf '%s\\n' "$*" >> "$NEYLU_CI_COMMANDS"
      if [ "$1" = build ]; then exit 0; fi
      if [ "$1" = test ]; then exit 7; fi
      exit 9
      """)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let environment = [
      "PATH": executable.deletingLastPathComponent().path + ":/usr/bin:/bin:/usr/sbin:/sbin",
      "NEYLU_CI_COMMANDS": log.path,
      "GITHUB_STEP_SUMMARY": summary.path,
    ]
    let script = TestSupport.root.appendingPathComponent("scripts/test-ci.sh").path
    let compile = try ToolRunner.run(
      "/bin/bash", [script, "--compile-only"], environment: environment)
    try ToolRunner.requireSuccess(compile)
    let compilation = try String(contentsOf: log, encoding: .utf8)
    #expect(compilation.hasPrefix("build ") && !compilation.contains("test --skip-build"))
    try "".write(to: log, atomically: true, encoding: .utf8)
    let execute = try ToolRunner.run("/bin/bash", [script, "--run-only"], environment: environment)
    #expect(execute.status == 7)
    let execution = try String(contentsOf: log, encoding: .utf8)
    #expect(execution.hasPrefix("test --skip-build ") && !execution.contains("build --build-tests"))
    #expect(execution.contains("--disable-xctest"))
    let report = try String(contentsOf: summary, encoding: .utf8)
    #expect(report.contains("compilation") && report.contains("execution"))
    #expect(report.contains("exit status **7**"))
  }
}
