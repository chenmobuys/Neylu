import Foundation
import Testing

struct AppcastFixture {
  let files: ToolFixture
  let metadata: [String: Any]
  let metadataURL: URL
  let items: [String: String]
  init(minimum: String = "12.0.0") throws {
    files = try ToolFixture()
    metadata = try files.metadata()
    metadataURL = try files.json("metadata.json", metadata)
    items = try ToolRunner.value(
      "{arch: ET.tostring(item, encoding='unicode') for arch, item in appcast.candidate(json.loads(Path(args[0]).read_text()), Path(args[1]), '4', minimum_system=args[2]).items()}",
      [metadataURL.path, files.root.appendingPathComponent("assets").path, minimum])
  }
  func merge(_ item: String, arch: String = "arm64", old: String? = nil) throws -> String {
    try ToolRunner.value(
      "appcast.merge(args[0].encode() if args[0] else None, ET.fromstring(args[1]), args[2]).decode()",
      [old ?? "", item, arch])
  }
  func rejectMerge(_ item: String, arch: String = "arm64", old: String) throws {
    ToolRunner.requireRejected(
      try ToolRunner.call(
        "appcast.merge(args[0].encode(), ET.fromstring(args[1]), args[2])", [old, item, arch]))
  }
  func versions(_ feed: String, arch: String = "arm64") throws -> [String] {
    try ToolRunner.value("list(appcast.read_items(args[0].encode(), args[1]))", [feed, arch])
  }
  func candidate(_ metadata: [String: Any], build: String = "4") throws -> ToolResult {
    let path = try files.json("candidate.json", metadata)
    return try ToolRunner.call(
      "appcast.candidate(json.loads(Path(args[0]).read_text()), Path(args[1]), args[2]) and None",
      [path.path, files.root.appendingPathComponent("assets").path, build])
  }
}

extension NeyluTests {
  @Test func appcastRoundTrip() throws {
    let f = try AppcastFixture()
    for arch in ["arm64", "x86_64"] {
      let item = f.items[arch]!
      let feed = try f.merge(item, arch: arch)
      #expect(try f.versions(feed, arch: arch) == ["0.1.0-alpha.4"])
      let body: String = try ToolRunner.value(
        "appcast.field(appcast.read_items(args[0].encode(), args[1])['0.1.0-alpha.4'], 'description')",
        [feed, arch])
      #expect(body == f.metadata["body"] as? String && feed.contains("&amp;"))
      #expect(try f.merge(item, arch: arch, old: feed) == feed)
      let invalid = try ToolRunner.call(
        "appcast.read_items(args[0].encode(), args[1])",
        [feed, arch == "arm64" ? "x86_64" : "arm64"])
      ToolRunner.requireRejected(invalid)
    }
  }
  @Test func appcastMetadataVerification() throws {
    let f = try AppcastFixture()
    for (field, value) in [
      ("digest", "sha256:" + String(repeating: "0", count: 64) as Any), ("size", 999 as Any),
      ("browser_download_url", "https://evil.example/file.dmg" as Any),
    ] {
      var broken = f.metadata
      var assets = broken["assets"] as! [[String: Any]]
      assets[0][field] = value
      broken["assets"] = assets
      ToolRunner.requireRejected(try f.candidate(broken))
    }
    for (field, value) in [
      ("draft", true as Any), ("prerelease", false as Any),
      ("html_url", "https://evil.example/release" as Any),
    ] {
      var broken = f.metadata
      broken[field] = value
      ToolRunner.requireRejected(try f.candidate(broken))
    }
    for build in ["0", "01", "-1", "1;echo bad", "18446744073709551616"] {
      ToolRunner.requireRejected(try f.candidate(f.metadata, build: build))
    }
  }
  @Test func immutableAppcastHistory() throws {
    let f = try AppcastFixture()
    let item = f.items["arm64"]!
    let old = try f.merge(item)
    let sum = (f.metadata["assets"] as! [[String: Any]])[0]["digest"] as! String
    try f.rejectMerge(
      item.replacingOccurrences(
        of: String(sum.dropFirst(7)), with: String(repeating: "0", count: 64)), old: old)
    let newer = item.replacingOccurrences(of: "0.1.0-alpha.4", with: "0.1.0-alpha.5")
      .replacingOccurrences(of: "<sparkle:version>4<", with: "<sparkle:version>5<")
    let updated = try f.merge(newer, old: old)
    #expect(try f.versions(f.merge(item, old: updated)) == ["0.1.0-alpha.5", "0.1.0-alpha.4"])
  }
  @Test func appcastXMLSecurity() throws {
    let f = try AppcastFixture()
    let feed = try f.merge(f.items["arm64"]!)
    let badFeeds = [
      "", feed.replacingOccurrences(of: "<rss ", with: "<!DOCTYPE rss [<!ENTITY x \"bad\">]><rss "),
      feed.replacingOccurrences(of: "<rss ", with: "<!ENTITY x \"bad\"><rss "),
      String(repeating: "x", count: 2 * 1024 * 1024 + 1),
      feed.replacingOccurrences(
        of: "xmlns:neylu=\"https://github.com/chenmobuys/Neylu/appcast\"",
        with: "xmlns:neylu=\"https://evil.example\""),
      feed.replacingOccurrences(of: "<sparkle:channel>alpha", with: "<sparkle:channel>stable"),
    ]
    for value in badFeeds {
      let input = try f.files.write("bad.xml", value)
      let result = try ToolRunner.call(
        "appcast.read_items(Path(args[0]).read_bytes(), 'arm64')", [input.path])
      #expect(
        result.status != 0
          && (result.error.contains("ValueError:") || result.error.contains("ParseError:")),
        Comment(rawValue: result.error))
    }
  }
  @Test func appcastRetentionPreservesStable() throws {
    let f = try AppcastFixture()
    let original = f.items["arm64"]!
    var feed: String?
    let versions = (0..<12).map { "0.1.\($0)" } + (1...21).map { "0.2.0-alpha.\($0)" }
    for (index, version) in versions.enumerated() {
      var item = original.replacingOccurrences(of: "0.1.0-alpha.4", with: version)
        .replacingOccurrences(of: "<sparkle:version>4<", with: "<sparkle:version>\(index + 1)<")
      if !version.contains("-") {
        item = item.replacingOccurrences(of: "<sparkle:channel>alpha</sparkle:channel>", with: "")
      }
      feed = try f.merge(item, old: feed)
    }
    let retained = try f.versions(feed!)
    #expect(
      retained.count == 20 && retained.contains("0.1.11") && retained.contains("0.2.0-alpha.21")
        && !retained.contains("0.1.0"))
  }
  @Test func historicalMinimumSystem() throws {
    let historical = try AppcastFixture(minimum: "13.0.0")
    let current = try AppcastFixture()
    let old = try historical.merge(historical.items["arm64"]!)
    #expect(old.contains("<sparkle:minimumSystemVersion>13.0.0</sparkle:minimumSystemVersion>"))
    try historical.rejectMerge(current.items["arm64"]!, old: old)
    for (file, count) in [("appcast.yml", 1), ("homebrew.yml", 2)] {
      let workflow = try String(
        contentsOf: TestSupport.root.appendingPathComponent(".github/workflows/" + file),
        encoding: .utf8)
      #expect(
        workflow.components(separatedBy: "--build-script .build/release-build.sh").count - 1
          == count)
    }
  }
  @Test func releaseAutomationConnections() throws {
    let text = try String(
      contentsOf: TestSupport.root.appendingPathComponent(".github/workflows/release.yml"),
      encoding: .utf8)
    #expect(
      text.contains("uses: ./.github/workflows/homebrew.yml")
        && text.contains("uses: ./.github/workflows/appcast.yml"))
    #expect(
      text.components(separatedBy: "needs: [prepare, publish]").count == 3
        && !text.contains("appcast.xml dist/"))
    let client = try String(
      contentsOf: TestSupport.root.appendingPathComponent("Sources/UpdateDiscovery.swift"),
      encoding: .utf8)
    let build = try String(
      contentsOf: TestSupport.root.appendingPathComponent("build.sh"), encoding: .utf8)
    #expect(!client.contains("api.github.com") && !build.contains("Sparkle.framework"))
  }
}
