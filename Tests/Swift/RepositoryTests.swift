import Foundation
import Testing

func matches(_ pattern: String, _ text: String, options: NSRegularExpression.Options = []) throws
  -> [[String]]
{
  let expression = try NSRegularExpression(pattern: pattern, options: options)
  let source = text as NSString
  return expression.matches(in: text, range: NSRange(location: 0, length: source.length)).map {
    result in
    (0..<result.numberOfRanges).map { index in
      let range = result.range(at: index)
      return range.location == NSNotFound ? "" : source.substring(with: range)
    }
  }
}
func readSource(_ path: String) throws -> String {
  try String(contentsOf: TestSupport.root.appendingPathComponent(path), encoding: .utf8)
}
func localTargets(_ source: String) throws -> [String] {
  let links =
    try matches(#"!?\[[^\]]*\]\(([^\s)]+)\)"#, source).map { $0[1] }
    + matches(#"(?:href|src|srcset)="([^"]+)""#, source).map { $0[1] }
  return links.filter {
    !$0.isEmpty && !$0.hasPrefix("#") && URLComponents(string: $0)?.scheme == nil
  }
}
func sourceFiles() throws -> [URL] {
  let iterator = FileManager.default.enumerator(
    at: TestSupport.root.appendingPathComponent("Sources"), includingPropertiesForKeys: nil)!
  return iterator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
}
let catalogLiteral = #""(?:[^"\\]|\\.)*""#
func decodeLiteral(_ source: String) throws -> String {
  try JSONSerialization.jsonObject(with: Data(source.utf8), options: .fragmentsAllowed) as! String
}
func catalog(_ language: String) throws -> [String: String] {
  let source = try readSource("Resources/\(language).lproj/Localizable.strings")
  let rows = try matches(
    "^(" + catalogLiteral + ")\\s*=\\s*(" + catalogLiteral + ");$", source,
    options: .anchorsMatchLines)
  var entries: [String: String] = [:]
  for row in rows {
    let key = try decodeLiteral(row[1])
    let value = try decodeLiteral(row[2])
    try #require(entries[key] == nil, Comment(rawValue: "Duplicate localization key: " + key))
    entries[key] = value
  }
  return entries
}

extension NeyluTests {
  @Test func distributionExcludesDevelopmentModes() throws {
    let forbidden = [
      "--screenshot-mode", "--screenshot-dark", "--show-details", "--show-updates",
      "--show-menu-settings",
      "--legacy-material", "--panel-report", "--diagnose", "applyScreenshotFixture",
    ]
    for file in try sourceFiles()
    where file.deletingLastPathComponent().lastPathComponent == "Sources" {
      let source = try String(contentsOf: file, encoding: .utf8)
      for token in forbidden {
        #expect(!source.contains(token), Comment(rawValue: file.lastPathComponent + ": " + token))
      }
    }
    #expect(
      !FileManager.default.fileExists(
        atPath: TestSupport.root.appendingPathComponent("Sources/ScreenshotFixtures.swift").path))
    #expect(
      FileManager.default.fileExists(
        atPath: TestSupport.root.appendingPathComponent("Tests/Support/ScreenshotFixtures.swift")
          .path))
    let renderer = try readSource("scripts/render-docs.sh")
    #expect(
      renderer.contains("-D NEYLU_PREVIEW")
        && renderer.contains("Tests/Support/ScreenshotFixtures.swift"))
    #expect(!(try readSource("build.sh")).contains("NEYLU_PREVIEW"))
  }
  @Test func documentationLinksAndCase() throws {
    let fm = FileManager.default
    let docs = try [TestSupport.root, TestSupport.root.appendingPathComponent("docs")].flatMap {
      try fm.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil).filter {
        $0.pathExtension == "md"
      }
    }
    for doc in docs {
      for target in try localTargets(String(contentsOf: doc, encoding: .utf8)) {
        let relative = URLComponents(string: target)?.path.removingPercentEncoding ?? target
        let path = doc.deletingLastPathComponent().appendingPathComponent(relative)
        #expect(
          fm.fileExists(atPath: path.path), Comment(rawValue: doc.lastPathComponent + ": " + target)
        )
        var current = doc.deletingLastPathComponent()
        for part in relative.split(separator: "/").map(String.init) {
          if part == ".." {
            current.deleteLastPathComponent()
          } else if part != "." {
            #expect(
              try fm.contentsOfDirectory(atPath: current.path).contains(part),
              Comment(rawValue: "Link casing: " + target))
            current.appendPathComponent(part)
          }
        }
      }
    }
  }
  @Test func readmeParity() throws {
    let chinese = try readSource("README.md")
    let english = try readSource("README.en.md")
    #expect(
      try matches("```sh\\n(.*?)```", chinese, options: .dotMatchesLineSeparators).map { $0[1] }
        == matches("```sh\\n(.*?)```", english, options: .dotMatchesLineSeparators).map { $0[1] })
    func destinations(_ source: String) throws -> Set<String> {
      Set(
        try localTargets(source).filter {
          !$0.hasPrefix("docs/images/")
            && !URL(fileURLWithPath: $0).lastPathComponent.hasPrefix("README.")
        }
        .map { $0.replacingOccurrences(of: "UPDATING.en.md", with: "UPDATING.md") })
    }
    #expect(try destinations(chinese) == destinations(english))
  }
  @Test func documentedRuntimeRequirements() throws {
    let minimums = Set(
      try matches(
        "<key>LSMinimumSystemVersion</key>\\s*<string>([^<]+)</string>", readSource("build.sh")
      ).map { $0[1] })
    try #require(minimums.count == 1)
    var minimum = minimums.first!
    if minimum.hasSuffix(".0") { minimum.removeLast(2) }
    let version = try readSource("VERSION").trimmingCharacters(in: .whitespacesAndNewlines)
    for name in ["README.md", "README.en.md", "CONTRIBUTING.md"] {
      let source = try readSource(name)
      #expect(source.contains("macOS " + minimum))
      for declared in try matches(
        #"(?:当前版本(?:为|是)|Current version:)\s*\*{0,2}([0-9]+\.[0-9]+\.[0-9]+(?:-[a-z]+\.[0-9]+)?)"#,
        source)
      {
        #expect(declared[1] == version)
      }
    }
  }
  @Test func localizationCatalogParity() throws {
    let english = try catalog("en")
    let chinese = try catalog("zh-Hans")
    #expect(english.count > 100 && Set(english.keys) == Set(chinese.keys))
    for (key, value) in english {
      #expect(try !matches(#"^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$"#, key).isEmpty)
      let translated = try #require(chinese[key])
      #expect(
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          && !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      #expect(
        try matches("%(?:@|d|f)", value).map { $0[0] }
          == matches("%(?:@|d|f)", translated).map { $0[0] })
      if key != "language.simplified_chinese" {
        #expect(try matches(#"[\u4e00-\u9fff]"#, value).isEmpty)
      }
    }
  }
  @Test func nativeSourcesUseLocalizationCatalogs() throws {
    let entries = try catalog("en")
    let namespaces = Set(entries.keys.map { $0.components(separatedBy: ".")[0] })
    let keyPattern = #"^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$"#
    for file in try sourceFiles() {
      let source = try String(contentsOf: file, encoding: .utf8)
      for row in try matches(catalogLiteral, source) {
        #expect(
          try matches(#"[\u4e00-\u9fff]"#, row[0]).isEmpty,
          Comment(rawValue: file.lastPathComponent))
        guard let value = try? decodeLiteral(row[0]) else { continue }
        if try !matches(keyPattern, value).isEmpty,
          namespaces.contains(value.components(separatedBy: ".")[0]), value != "history.sqlite"
        {
          #expect(entries[value] != nil, Comment(rawValue: value))
        }
      }
      for row in try matches(#"\b(?:L|L10n\.text)\(("# + catalogLiteral + ")", source) {
        #expect(try entries[decodeLiteral(row[1])] != nil)
      }
    }
  }
}
