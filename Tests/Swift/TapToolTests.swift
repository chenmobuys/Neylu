import Foundation
import Testing

extension NeyluTests {
  @Test func homebrewPublishedMetadata() throws {
    let f = try ToolFixture()
    let metadata = try f.metadata()
    let meta = try f.json("metadata.json", metadata)
    let tap = f.root.appendingPathComponent("tap")
    let arguments = [
      "--tag", "v0.1.0-alpha.4", "--assets", f.root.appendingPathComponent("assets").path,
      "--metadata", meta.path, "--tap", tap.path,
    ]
    try ToolRunner.requireSuccess(ToolRunner.python("scripts/update-tap.py", arguments))
    let cask = tap.appendingPathComponent("Casks/neylu.rb")
    let original = try String(contentsOf: cask, encoding: .utf8)
    #expect(original.contains("version \"0.1.0-alpha.4\""))
    try ToolRunner.requireSuccess(ToolRunner.python("scripts/update-tap.py", arguments))
    #expect(try String(contentsOf: cask, encoding: .utf8) == original)
    for (key, value) in [
      ("draft", true as Any), ("published_at", NSNull()), ("tag_name", "v0.1.0-alpha.3"),
    ] {
      var invalid = metadata
      invalid[key] = value
      try f.json("metadata.json", invalid)
      let result = try ToolRunner.python("scripts/update-tap.py", arguments)
      #expect(result.status != 0 && result.error.contains("ValueError:"))
      #expect(try String(contentsOf: cask, encoding: .utf8) == original)
    }
    for (key, value) in [
      ("digest", "sha256:" + String(repeating: "c", count: 64) as Any), ("size", 0 as Any),
      ("state", "new" as Any), ("browser_download_url", "https://example.com/installer.dmg" as Any),
    ] {
      var invalid = metadata
      var rows = invalid["assets"] as! [[String: Any]]
      rows[0][key] = value
      invalid["assets"] = rows
      try f.json("metadata.json", invalid)
      ToolRunner.requireRejected(try ToolRunner.python("scripts/update-tap.py", arguments))
      #expect(try String(contentsOf: cask, encoding: .utf8) == original)
    }
  }
  @Test func badInstallerNeverUpdatesHomebrew() throws {
    let f = try ToolFixture()
    let metadata = try f.metadata()
    let meta = try f.json("metadata.json", metadata)
    let args = [
      "--tag", "v0.1.0-alpha.4", "--assets", f.root.appendingPathComponent("assets").path,
      "--metadata", meta.path, "--tap", f.root.appendingPathComponent("tap").path,
    ]
    let image = try f.write("assets/Neylu-0.1.0-alpha.4-arm64.dmg", "tampered")
    ToolRunner.requireRejected(try ToolRunner.python("scripts/update-tap.py", args))
    try FileManager.default.removeItem(at: image)
    ToolRunner.requireRejected(
      try ToolRunner.python("scripts/update-tap.py", args), type: "FileNotFoundError")
    #expect(
      !FileManager.default.fileExists(
        atPath: f.root.appendingPathComponent("tap/Casks/neylu.rb").path))
  }
  @Test func homebrewCannotDowngradeOrReplaceChecksums() throws {
    let f = try ToolFixture()
    let cask = f.root.appendingPathComponent("Casks/neylu.rb")
    let sums = [
      "arm64": String(repeating: "a", count: 64), "x86_64": String(repeating: "b", count: 64),
    ]
    let data = String(data: try JSONSerialization.data(withJSONObject: sums), encoding: .utf8)!
    func content(_ version: String, _ checksums: String = data) throws -> String {
      try ToolRunner.value(
        "release.cask_text('chenmobuys/Neylu', args[0], json.loads(args[1]), allow_prerelease=True)",
        [version, checksums])
    }
    func apply(_ source: String) throws -> Bool {
      try ToolRunner.value("tap.apply(Path(args[0]), args[1])", [cask.path, source])
    }
    for (version, expected) in [
      ("0.1.0-alpha.10", true), ("0.1.0-alpha.9", false), ("0.1.0-beta.1", true),
      ("0.1.0-alpha.11", false), ("0.1.0-rc.1", true), ("0.1.0", true), ("0.1.0-rc.2", false),
    ] {
      #expect(try apply(content(version)) == expected)
    }
    let original = try String(contentsOf: cask, encoding: .utf8)
    let changed = data.replacingOccurrences(
      of: String(repeating: "a", count: 64), with: String(repeating: "c", count: 64))
    ToolRunner.requireRejected(
      try ToolRunner.call(
        "tap.apply(Path(args[0]), args[1])", [cask.path, content("0.1.0", changed)]))
    #expect(try String(contentsOf: cask, encoding: .utf8) == original)
    #expect(try apply(content("0.1.1-alpha.1")))
    #expect(try !apply(content("0.1.0")))
    try "invalid cask".write(to: cask, atomically: true, encoding: .utf8)
    ToolRunner.requireRejected(
      try ToolRunner.call("tap.apply(Path(args[0]), args[1])", [cask.path, content("0.1.1")]))
    try FileManager.default.removeItem(at: cask)
    let outside = try f.write("outside.rb", "preserve")
    try FileManager.default.createSymbolicLink(at: cask, withDestinationURL: outside)
    ToolRunner.requireRejected(
      try ToolRunner.call("tap.apply(Path(args[0]), args[1])", [cask.path, content("0.1.1")]))
    #expect(try String(contentsOf: outside, encoding: .utf8) == "preserve")
  }
  @Test func strictToolSemanticVersions() throws {
    for value in ["1.2.3-alpha.0", "01.2.3", "1.2.3-alpha.01", "v1.2.3", "1.2.3;echo bad"] {
      ToolRunner.requireRejected(try ToolRunner.call("tap.version_key(args[0])", [value]))
    }
  }
}
