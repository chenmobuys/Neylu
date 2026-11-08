import CryptoKit
import Foundation
import Testing

struct ToolResult {
  let status: Int32
  let output: String
  let error: String
}

enum ToolRunner {
  static func run(
    _ command: String, _ arguments: [String], at directory: URL = TestSupport.root,
    environment: [String: String] = [:]
  ) throws -> ToolResult {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: command)
    task.arguments = arguments
    task.currentDirectoryURL = directory
    task.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
    // Files avoid pipe backpressure when an expected tool failure produces a traceback.
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
      "Neylu-process-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let out = folder.appendingPathComponent("stdout")
    let err = folder.appendingPathComponent("stderr")
    FileManager.default.createFile(atPath: out.path, contents: nil)
    FileManager.default.createFile(atPath: err.path, contents: nil)
    let output = try FileHandle(forWritingTo: out)
    let error = try FileHandle(forWritingTo: err)
    defer {
      try? output.close()
      try? error.close()
    }
    task.standardOutput = output
    task.standardError = error
    TestSupport.progress("[tool] Starting " + command)
    try task.run()
    task.waitUntilExit()
    TestSupport.progress("[tool] Finished " + command + " (\(task.terminationStatus))")
    return ToolResult(
      status: task.terminationStatus, output: try String(contentsOf: out, encoding: .utf8),
      error: try String(contentsOf: err, encoding: .utf8))
  }
  static func python(
    _ script: String, _ arguments: [String] = [], environment: [String: String] = [:]
  ) throws -> ToolResult {
    try run("/usr/bin/env", ["python3", script] + arguments, environment: environment)
  }
  // Python remains the implementation language of the release tools. This
  // adapter only invokes their functions; all fixtures and assertions are Swift.
  static func call(
    _ expression: String, _ arguments: [String] = [], environment: [String: String] = [:]
  ) throws -> ToolResult {
    let adapter = """
      import sys, json, importlib.util, xml.etree.ElementTree as ET
      from pathlib import Path
      root = Path(sys.argv[1])
      sys.path.insert(0, str(root / 'scripts'))
      import release, appcast
      def module(name, path):
          spec = importlib.util.spec_from_file_location(name, root / path)
          value = importlib.util.module_from_spec(spec)
          spec.loader.exec_module(value)
          return value
      tap = module('update_tap', 'scripts/update-tap.py')
      icon = module('optimize_icon', 'Assets/optimize-icon.py')
      publisher = module('publisher', 'scripts/publish-appcast.py')
      args = sys.argv[2:]
      result = \(expression)
      if result is not None: print(json.dumps(result))
      """
    return try python("-c", [adapter, TestSupport.root.path] + arguments, environment: environment)
  }
  static func requireSuccess(
    _ result: ToolResult, sourceLocation: SourceLocation = #_sourceLocation
  ) throws {
    try #require(
      result.status == 0, Comment(rawValue: result.error + result.output),
      sourceLocation: sourceLocation)
  }
  static func requireRejected(
    _ result: ToolResult, type: String = "ValueError",
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    #expect(
      result.status != 0 && result.error.contains(type + ":"), Comment(rawValue: result.error),
      sourceLocation: sourceLocation)
  }
}

final class ToolFixture {
  let root: URL
  init() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "Neylu-tool-tests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }
  deinit { try? FileManager.default.removeItem(at: root) }
  @discardableResult func write(_ path: String, _ data: Data) throws -> URL {
    let url = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
    return url
  }
  @discardableResult func write(_ path: String, _ text: String) throws -> URL {
    try write(path, Data(text.utf8))
  }
  @discardableResult func json(_ path: String, _ value: Any) throws -> URL {
    try write(path, JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
  }
  func metadata(
    _ version: String = "0.1.0-alpha.4", build: String = "4",
    body: String = "### English\n\n- **Fix** & <data>\n<!-- neylu:zh-Hans -->\n中文"
  ) throws -> [String: Any] {
    var assets: [[String: Any]] = []
    for arch in ["arm64", "x86_64"] {
      let name = "Neylu-\(version)-\(arch).dmg"
      let data = Data(arch.utf8)
      try write("assets/" + name, data)
      let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
      assets.append([
        "name": name, "size": data.count, "state": "uploaded", "digest": "sha256:" + sha,
        "browser_download_url":
          "https://github.com/chenmobuys/Neylu/releases/download/v\(version)/\(name)",
      ])
    }
    return [
      "tag_name": "v" + version,
      "html_url": "https://github.com/chenmobuys/Neylu/releases/tag/v" + version,
      "draft": false, "prerelease": version.contains("-"), "body": body,
      "published_at": "2026-11-07T14:00:00Z", "assets": assets,
    ]
  }
}

enum ToolFixtures {
  static func appcasts() throws -> URL {
    let destination = FileManager.default.temporaryDirectory.appendingPathComponent(
      "Neylu-appcast-fixtures-" + UUID().uuidString)
    do {
      for (index, version) in ["0.1.0", "0.2.0-alpha.2", "0.2.0-alpha.10"].enumerated() {
        let files = try ToolFixture()
        let metadata = try files.metadata(
          version,
          body: "<!-- neylu:en -->\n### English\n\n- **Fix** & <data>\n<!-- neylu:zh-Hans -->\n中文更新"
        )
        let path = try files.json("release.json", metadata)
        try ToolRunner.requireSuccess(
          ToolRunner.python(
            "scripts/appcast.py",
            [
              "--metadata", path.path, "--assets", files.root.appendingPathComponent("assets").path,
              "--build", String(index + 1), "--output", destination.path,
            ]))
      }
      return destination
    } catch {
      try? FileManager.default.removeItem(at: destination)
      throw error
    }
  }
}

extension ToolRunner {
  static func value<T: Decodable>(
    _ expression: String, _ arguments: [String] = [], as type: T.Type = T.self
  ) throws -> T {
    let result = try call(expression, arguments)
    try requireSuccess(result)
    return try JSONDecoder().decode(
      type, from: Data((result.output.split(separator: "\n").last.map(String.init) ?? "").utf8))
  }
}

extension ToolFixture {
  @discardableResult func stub(_ name: String, _ body: String) throws -> URL {
    let url = try write("bin/" + name, "#!/bin/bash\nset -eu\n" + body + "\n")
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    return url
  }
  var stubEnvironment: [String: String] {
    [
      "PATH": root.appendingPathComponent("bin").path + ":"
        + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")
    ]
  }
  func app(version: String = "1.2.3") throws -> URL {
    let path = "Neylu.app/Contents/"
    for name in [
      "MacOS/Neylu", "Helpers/NeyluUpdater", "Resources/AppIcon.icns", "Resources/LICENSE",
      "Resources/THIRD_PARTY_NOTICES.md", "Resources/ReleaseNotes.md",
      "Library/LoginItems/NeyluLoginHelper.app/Contents/MacOS/NeyluLoginHelper",
    ] {
      try write(path + name, "fixture")
    }
    for language in ["en", "zh-Hans"] {
      try write(
        path + "Resources/\(language).lproj/Localizable.strings", "\"fixture.key\" = \"Fixture\";")
    }
    let build = try String(
      contentsOf: TestSupport.root.appendingPathComponent("BUILD_NUMBER"), encoding: .utf8
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    let info: [String: Any] = [
      "CFBundleShortVersionString": version.components(separatedBy: "-")[0],
      "NeyluReleaseVersion": version,
      "LSMinimumSystemVersion": "12.0", "CFBundleVersion": build,
      "CFBundleIdentifier": "io.github.chenmobuys.Neylu",
    ]
    try write(
      path + "Info.plist",
      PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0))
    try write(
      path + "Library/LoginItems/NeyluLoginHelper.app/Contents/Info.plist",
      PropertyListSerialization.data(
        fromPropertyList: [
          "CFBundleIdentifier": "io.github.chenmobuys.Neylu.LoginHelper",
          "LSMinimumSystemVersion": "12.0",
        ], format: .xml, options: 0))
    return root.appendingPathComponent("Neylu.app")
  }
}
