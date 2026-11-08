import Darwin
import Foundation
import Testing

struct PublisherCall {
  let method: String
  let path: String
  let payload: [String: Any]?
}

extension ToolRunner {
  // Synchronous JSON RPC is only a language boundary: the mock GitHub API,
  // state, failure injection and every assertion live in Swift.
  static func publish(_ fixture: AppcastFixture, api: (PublisherCall) throws -> Any?) throws
    -> ToolResult
  {
    let script = """
      import sys, json, importlib.util
      from pathlib import Path
      sys.path.insert(0, sys.argv[1] + '/scripts')
      import appcast
      spec = importlib.util.spec_from_file_location('publisher', sys.argv[1] + '/scripts/publish-appcast.py')
      publisher = importlib.util.module_from_spec(spec)
      spec.loader.exec_module(publisher)
      def api(method, path, payload=None):
          print(json.dumps({'request': {'method': method, 'path': path, 'payload': payload}}), flush=True)
          reply = json.loads(sys.stdin.readline())
          if 'error' in reply: raise RuntimeError(reply['error'])
          return reply['value']
      items = appcast.candidate(json.loads(Path(sys.argv[2]).read_text()), Path(sys.argv[3]), '4')
      print(json.dumps({'result': publisher.publish(api, items)}), flush=True)
      """
    let task = Process()
    let input = Pipe()
    let output = Pipe()
    let errors = Pipe()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    task.arguments = [
      "python3", "-u", "-c", script, TestSupport.root.path, fixture.metadataURL.path,
      fixture.files.root.appendingPathComponent("assets").path,
    ]
    task.standardInput = input
    task.standardOutput = output
    task.standardError = errors
    try task.run()
    let timeout = DispatchWorkItem { if task.isRunning { task.terminate() } }
    DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeout)
    defer { timeout.cancel() }
    let stream = fdopen(dup(output.fileHandleForReading.fileDescriptor), "r")!
    defer { fclose(stream) }
    var buffer: UnsafeMutablePointer<CChar>?
    var capacity = 0
    var text = ""
    defer { free(buffer) }
    while getline(&buffer, &capacity, stream) >= 0 {
      let line = String(cString: buffer!)
      guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
        let request = object["request"] as? [String: Any]
      else {
        text += line
        continue
      }
      let call = PublisherCall(
        method: request["method"] as! String, path: request["path"] as! String,
        payload: request["payload"] as? [String: Any])
      let reply: [String: Any]
      do { reply = ["value": try api(call) ?? NSNull()] } catch {
        reply = ["error": String(describing: error)]
      }
      try input.fileHandleForWriting.write(
        contentsOf: JSONSerialization.data(withJSONObject: reply) + Data([10]))
    }
    task.waitUntilExit()
    return ToolResult(
      status: task.terminationStatus, output: text,
      error: String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
  }
}

final class PublisherAPI {
  var calls: [PublisherCall] = []
  var parent: String?
  var files: [String: Data] = [:]
  var missingFeed = false
  var conflictingRef = false
  func reply(_ call: PublisherCall) throws -> Any? {
    calls.append(call)
    if call.path == "git/ref/heads/updates" { return parent.map { ["object": ["sha": $0]] } }
    if call.path.hasPrefix("git/commits/") { return ["tree": ["sha": "tree"]] }
    if call.path.hasPrefix("contents/") {
      guard !missingFeed else { return nil }
      let name = String(call.path.split(separator: "/")[1].split(separator: "?")[0])
      guard let bytes = files[name] else { return nil }
      return ["type": "file", "size": bytes.count, "content": bytes.base64EncodedString()]
    }
    if call.path == "git/trees" {
      for row in call.payload!["tree"] as! [[String: Any]] {
        files[row["path"] as! String] = Data((row["content"] as! String).utf8)
      }
      return ["sha": "new-tree"]
    }
    if call.path == "git/commits" { return ["sha": "new-commit"] }
    if call.path == "git/refs/heads/updates" {
      #expect(call.payload?["force"] as? Bool == false)
      if conflictingRef { throw TestSupport.Failure(message: "conflicting ref") }
      parent = call.payload?["sha"] as? String
      return [:] as [String: String]
    }
    if call.path == "git/refs" {
      #expect(call.payload?["ref"] as? String == "refs/heads/updates")
      parent = call.payload?["sha"] as? String
      return [:] as [String: String]
    }
    Issue.record(Comment(rawValue: "Unexpected API call " + call.path))
    throw TestSupport.Failure(message: "Unexpected API route")
  }
}

extension NeyluTests {
  @Test func downloadIndexUsesSemanticVersionsAndCompleteArchitecturePairs() throws {
    let fixture = try AppcastFixture()
    var feeds: [String: String] = [:]
    var olderIntel = ""
    for arch in ["arm64", "x86_64"] {
      let item = try #require(fixture.items[arch])
      let old = try fixture.merge(
        item.replacingOccurrences(of: "0.1.0-alpha.4", with: "0.1.0-alpha.9"), arch: arch)
      if arch == "x86_64" { olderIntel = old }
      var next = item.replacingOccurrences(of: "0.1.0-alpha.4", with: "0.1.0-alpha.10")
      if arch == "x86_64" { next = next.replacingOccurrences(of: ">12.0.0<", with: ">13.0.0<") }
      feeds[arch] = try fixture.merge(next, arch: arch, old: old)
    }
    func render(_ feeds: [String: String]) throws -> String {
      let file = try fixture.files.json("feeds.json", feeds)
      return try ToolRunner.value(
        "publisher.download_index({'appcast-' + a + '.xml': v.encode() for a, v in json.loads(Path(args[0]).read_text()).items()}).decode()",
        [file.path])
    }
    let index = try render(feeds)
    #expect(index.contains("v0.1.0-alpha.10/Neylu-0.1.0-alpha.10-arm64.dmg"))
    #expect(index.contains("v0.1.0-alpha.10/Neylu-0.1.0-alpha.10-x86_64.dmg"))
    #expect(!index.contains("alpha.9"))
    #expect(index.contains("macOS 13+") && index.contains("macOS 12+"))
    feeds["x86_64"] = olderIntel
    let incomplete = try render(feeds)
    #expect(incomplete.contains("alpha.9") && !incomplete.contains("alpha.10"))
  }
  @Test func staticPublisherIdempotenceAndBranchIsolation() throws {
    let fixture = try AppcastFixture()
    let api = PublisherAPI()
    try ToolRunner.requireSuccess(ToolRunner.publish(fixture, api: api.reply))
    #expect(Set(api.files.keys) == ["appcast-arm64.xml", "appcast-x86_64.xml", "downloads.md"])
    #expect(api.parent == "new-commit")
    api.calls.removeAll()
    try ToolRunner.requireSuccess(ToolRunner.publish(fixture, api: api.reply))
    #expect(api.calls.allSatisfy { $0.method == "GET" })
    api.files.removeValue(forKey: "downloads.md")
    api.calls.removeAll()
    try ToolRunner.requireSuccess(ToolRunner.publish(fixture, api: api.reply))
    #expect(api.files["downloads.md"] != nil)
    #expect(api.calls.contains { $0.method == "POST" && $0.path == "git/trees" })
    api.calls.removeAll()
    var changed = fixture.metadata
    changed["body"] = (changed["body"] as! String) + "\nClarified notes"
    try fixture.files.json("metadata.json", changed)
    try ToolRunner.requireSuccess(ToolRunner.publish(fixture, api: api.reply))
    let patches = api.calls.filter { $0.method == "PATCH" }
    #expect(patches.count == 1 && patches[0].payload?["force"] as? Bool == false)
    #expect(patches[0].path == "git/refs/heads/updates")
    let commit = try #require(api.calls.first { $0.method == "POST" && $0.path == "git/commits" })
    #expect(commit.payload?["parents"] as? [String] == ["new-commit"])
  }
  @Test func staticPublisherMissingFeedAndConflictingRef() throws {
    let fixture = try AppcastFixture()
    let missing = PublisherAPI()
    missing.parent = "old"
    missing.missingFeed = true
    let missingResult = try ToolRunner.publish(fixture, api: missing.reply)
    #expect(missingResult.status != 0 && missingResult.error.contains("missing an architecture"))
    let conflict = PublisherAPI()
    try ToolRunner.requireSuccess(ToolRunner.publish(fixture, api: conflict.reply))
    var changed = fixture.metadata
    changed["body"] = "Clarified release notes"
    try fixture.files.json("metadata.json", changed)
    conflict.calls.removeAll()
    conflict.conflictingRef = true
    let result = try ToolRunner.publish(fixture, api: conflict.reply)
    #expect(result.status != 0 && result.error.contains("conflicting ref"))
    #expect(conflict.calls.filter { $0.method == "PATCH" }.count == 1)
  }
}
