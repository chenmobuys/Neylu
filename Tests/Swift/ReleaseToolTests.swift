import Foundation
import Testing

extension NeyluTests {
  @Test func releaseTagValidation() throws {
    #expect(
      try ToolRunner.value(
        "release.validate_tag(args[0], args[1])", ["v1.2.3", "1.2.3"], as: Bool.self) == false)
    for stage in ["alpha", "beta", "rc"] {
      let version = "1.2.3-\(stage).1"
      #expect(
        try ToolRunner.value(
          "release.validate_tag(args[0], args[1])", ["v" + version, version], as: Bool.self))
      ToolRunner.requireRejected(
        try ToolRunner.call("release.validate_tag(args[0], args[1])", ["v" + version, "1.2.3"]))
    }
    for version in ["main", "1.2.3-alpha.0", "1.2.3-preview.1", "1.2.3;echo bad", "../1.2.3"] {
      ToolRunner.requireRejected(
        try ToolRunner.call("release.validate_tag(args[0], args[0][1:])", ["v" + version]))
    }
  }
  @Test func exactReleaseNotes() throws {
    let source =
      "# Log\n## [Unreleased]\nfuture\n## [1.2.3-alpha.2]\n- second\n## [1.2.3-alpha.1]\n- first\n## [1.2.3]\n- stable\n"
    let notes: String = try ToolRunner.value(
      "release.release_notes(args[0], args[1])", [source, "1.2.3-alpha.2"])
    #expect(notes.contains("second") && !notes.contains("- first") && !notes.contains("future"))
    #expect(
      try ToolRunner.value(
        "release.release_notes(args[0], args[1])", [source, "1.2.3"], as: String.self)
        .hasSuffix("- stable\n"))
    ToolRunner.requireRejected(
      try ToolRunner.call("release.release_notes(args[0], args[1])", [source, "1.2.30"]))
  }
  @Test func distributionPolicyAndTapCLI() throws {
    let source = "## [1.2.3]\n- shipped\n"
    for mode in ["adhoc", "notarized"] {
      let notes: String = try ToolRunner.value("release.release_notes(args[0], '1.2.3', args[1])", [source, mode])
      #expect(notes.contains("neylu-distribution: " + mode))
      #expect(notes.contains(mode == "adhoc" ? "not notarized by Apple" : "notarized by Apple"))
      let f = try ToolFixture()
      let metadata = try f.metadata("1.2.3")
      let path = try f.json("release.json", metadata)
      let tap = f.root.appendingPathComponent("tap")
      try ToolRunner.requireSuccess(ToolRunner.python(TestSupport.root.appendingPathComponent("scripts/update-tap.py").path, ["--tag", "v1.2.3", "--assets", f.root.appendingPathComponent("assets").path, "--metadata", path.path, "--tap", tap.path, "--distribution", mode]))
      let content = try String(contentsOf: tap.appendingPathComponent("Casks/neylu.rb"), encoding: .utf8)
      #expect(content.contains("# Distribution: " + mode))
      #expect(content.contains("quarantine") == (mode == "adhoc"))
      ToolRunner.requireRejected(try ToolRunner.call("tap.apply(Path(args[0]), Path(args[0]).read_text().replace('# Distribution: ' + args[1], '# Distribution: ' + args[2]))", [tap.appendingPathComponent("Casks/neylu.rb").path, mode, mode == "adhoc" ? "notarized" : "adhoc"]))
    }
  }
  @Test func publishedInstallerDigests() throws {
    let fixture = try ToolFixture()
    let metadata = try fixture.metadata("1.2.3-alpha.2")
    let assets = fixture.root.appendingPathComponent("assets").path
    let meta = try fixture.json("metadata.json", metadata)
    let verify =
      "release.verify_github_assets(Path(args[0]), args[1], release.ARCHITECTURES, json.loads(Path(args[2]).read_text()))"
    try ToolRunner.requireSuccess(ToolRunner.call(verify, [assets, "1.2.3-alpha.2", meta.path]))
    let extra = try fixture.write("assets/release.json", "{}")
    ToolRunner.requireRejected(
      try ToolRunner.call(
        "release.verify_assets(Path(args[0]), args[1], release.ARCHITECTURES)",
        [assets, "1.2.3-alpha.2"]))
    try FileManager.default.removeItem(at: extra)
    try fixture.write("assets/Neylu-1.2.3-alpha.2-arm64.dmg", "tampered")
    ToolRunner.requireRejected(try ToolRunner.call(verify, [assets, "1.2.3-alpha.2", meta.path]))
    try fixture.write("assets/Neylu-1.2.3-alpha.2-arm64.dmg", "arm64")
    var invalid = metadata
    var rows = invalid["assets"] as! [[String: Any]]
    rows[0]["digest"] = NSNull()
    invalid["assets"] = rows
    try fixture.json("metadata.json", invalid)
    ToolRunner.requireRejected(try ToolRunner.call(verify, [assets, "1.2.3-alpha.2", meta.path]))
    ToolRunner.requireRejected(
      try ToolRunner.call("release.asset_name(args[0], args[1])", ["1.2.3", "unknown"]))
  }
  @Test func stableCaskValidation() throws {
    let checksums =
      "{\"arm64\":\"\(String(repeating: "a", count: 64))\",\"x86_64\":\"\(String(repeating: "b", count: 64))\"}"
    let expression = "release.cask_text(args[0], args[1], json.loads(args[2]))"
    let text: String = try ToolRunner.value(expression, ["owner/Neylu", "1.2.3", checksums])
    #expect(
      text.contains("Neylu-#{version}-#{arch}.dmg")
        && text.contains("arch arm: \"arm64\", intel: \"x86_64\""))
    #expect(
      text.contains(String(repeating: "a", count: 64))
        && text.contains(String(repeating: "b", count: 64)))
    #expect(!text.contains("no_check") && text.contains("quarantine"))
    #expect(text.contains("# Distribution: adhoc") && !text.contains("postflight"))
    let notarized: String = try ToolRunner.value(
      "release.cask_text(args[0], args[1], json.loads(args[2]), distribution='notarized')",
      ["owner/Neylu", "1.2.3", checksums])
    #expect(notarized.contains("# Distribution: notarized") && !notarized.contains("quarantine"))
    ToolRunner.requireRejected(try ToolRunner.call("release.distribution_mode(args[0])", ["automatic"]))
    for args in [
      ["bad\"/repo", "1.2.3", checksums], ["owner/repo", "1.2.3-alpha.1", checksums],
      ["owner/repo", "1.2.3", "{\"arm64\":\"fake\"}"],
    ] {
      ToolRunner.requireRejected(try ToolRunner.call(expression, args))
    }
  }
  @Test func previewCaskExplicitOptIn() throws {
    let checksums =
      "{\"arm64\":\"\(String(repeating: "a", count: 64))\",\"x86_64\":\"\(String(repeating: "b", count: 64))\"}"
    let expression =
      "release.cask_text('owner/Neylu', args[0], json.loads(args[1]), allow_prerelease=True)"
    for stage in ["alpha", "beta", "rc"] {
      let version = "0.1.0-\(stage).1"
      let text: String = try ToolRunner.value(expression, [version, checksums])
      #expect(text.contains("version \"\(version)\"") && text.contains("auto_updates true"))
      let parts = text.components(separatedBy: "  caveats <<~EOS")
      try #require(parts.count == 2)
      #expect(!parts[0].contains("xattr") && !parts[0].contains("quarantine"))
      #expect(parts[1].contains("xattr -dr com.apple.quarantine \"#{appdir}/Neylu.app\""))
      #expect(
        !text.contains("no_check") && !text.contains("postflight")
          && !text.contains("system_command"))
    }
    for invalid in ["0.1.0-preview.1", "../0.1.0", "0.1.0-alpha.0"] {
      ToolRunner.requireRejected(try ToolRunner.call(expression, [invalid, checksums]))
    }
  }
  @Test func installerRejectsUnsafeEntries() throws {
    for kind in ["empty", "symlink", "directory"] {
      let f = try ToolFixture()
      let image = try f.write(
        "dist/Neylu-1.2.3-alpha.3-arm64.dmg", kind == "empty" ? "" : "installer")
      if kind == "symlink" {
        let outside = f.root.appendingPathComponent("outside")
        try FileManager.default.moveItem(at: image, to: outside)
        try FileManager.default.createSymbolicLink(at: image, withDestinationURL: outside)
      } else if kind == "directory" {
        try FileManager.default.createDirectory(
          at: f.root.appendingPathComponent("dist/unexpected"), withIntermediateDirectories: true)
      }
      ToolRunner.requireRejected(
        try ToolRunner.call(
          "release.verify_assets(Path(args[0]), '1.2.3-alpha.3', ['arm64'])",
          [f.root.appendingPathComponent("dist").path]))
    }
  }
  @Test func stableSigningPolicy() throws {
    let f = try ToolFixture()
    let app = try f.app()
    try f.stub("lipo", "echo arm64")
    let calls = f.root.appendingPathComponent("codesign-calls")
    try f.stub(
      "codesign",
      "echo \"$*\" >> \"\(calls.path)\"\nif [[ \"${1:-}\" == -d ]]; then echo Signature=adhoc >&2; fi"
    )
    ToolRunner.requireRejected(
      try ToolRunner.call(
        "release.check(Path(args[0]), '1.2.3', 'arm64')", [app.path], environment: f.stubEnvironment
      ))
    let rejected = try String(contentsOf: calls, encoding: .utf8)
    #expect(rejected.contains("-d --verbose=4"))
    try Data().write(to: calls)
    try ToolRunner.requireSuccess(
      ToolRunner.call(
        "release.check(Path(args[0]), '1.2.3', 'arm64', require_notarization=False)", [app.path],
        environment: f.stubEnvironment))
    let verification = try String(contentsOf: calls, encoding: .utf8)
    #expect(
      verification.trimmingCharacters(in: .whitespacesAndNewlines) == "--verify --strict --deep "
        + app.path)
  }
  @Test func busyUnmountRetriesNeverForce() throws {
    for (failures, status, expected) in [(2, 16, 3), (9, 16, 6), (9, 1, 1)] {
      let f = try ToolFixture()
      let count = f.root.appendingPathComponent("count")
      let calls = f.root.appendingPathComponent("calls")
      try f.stub(
        "hdiutil",
        "count=0\n[[ ! -f \"\(count.path)\" ]] || count=$(cat \"\(count.path)\")\ncount=$((count + 1))\necho $count > \"\(count.path)\"\necho \"$*\" >> \"\(calls.path)\"\nif (( count <= \(failures) )); then exit \(status); fi"
      )
      let mount = f.root.appendingPathComponent("mounted")
      let result = try ToolRunner.call(
        "release.detach_image(Path(args[0]))", [mount.path], environment: f.stubEnvironment)
      #expect((result.status == 0) == (failures == 2))
      let lines = try String(contentsOf: calls, encoding: .utf8).split(separator: "\n")
      #expect(lines.count == expected && lines.allSatisfy { $0 == "detach " + mount.path })
    }
  }
  @Test func minimumSystemAndProjectMetadata() throws {
    for minimum in ["12.0", "13.0"] {
      let input = "<key>LSMinimumSystemVersion</key><string>\(minimum)</string>"
      #expect(
        try ToolRunner.value("release.minimum_from_build_script(args[0])", [input], as: String.self)
          == minimum + ".0")
    }
    ToolRunner.requireRejected(
      try ToolRunner.call(
        "release.minimum_from_build_script(args[0])",
        [
          "<key>LSMinimumSystemVersion</key><string>12.0</string><key>LSMinimumSystemVersion</key><string>13.0</string>"
        ]))
    let digests =
      "{\"arm64\":\"" + String(repeating: "a", count: 64) + "\",\"x86_64\":\""
      + String(repeating: "b", count: 64) + "\"}"
    for (minimum, system) in [("12.0.0", "monterey"), ("13.0.0", "ventura")] {
      let cask: String = try ToolRunner.value(
        "release.cask_text('owner/Neylu', '1.2.3', json.loads(args[0]), minimum_system=args[1])",
        [digests, minimum])
      #expect(cask.contains("depends_on macos: :" + system))
    }
  }
  @Test func projectReleaseMetadata() throws {
    let version = try String(
      contentsOf: TestSupport.root.appendingPathComponent("VERSION"), encoding: .utf8
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    _ = try ToolRunner.value(
      "release.validate_tag(args[0], args[1])", ["v" + version, version], as: Bool.self)
    let notes = try String(
      contentsOf: TestSupport.root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
    #expect(
      !(try ToolRunner.value(
        "release.release_notes(args[0], args[1])", [notes, version], as: String.self)).isEmpty)
    let build = try String(
      contentsOf: TestSupport.root.appendingPathComponent("BUILD_NUMBER"), encoding: .utf8)
    #expect(build.trimmingCharacters(in: .whitespacesAndNewlines).allSatisfy { $0.isNumber })
  }
}
