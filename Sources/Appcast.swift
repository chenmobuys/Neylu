import Foundation

/// RSS/appcast fields follow Sparkle's published format. The Neylu extension
/// carries the SHA-256 already verified against the published GitHub installer.
enum Appcast {
    static let sparkle = "http://www.andymatuschak.org/xml-namespaces/sparkle"
    static let neylu = "https://github.com/chenmobuys/Neylu/appcast"
    static let limit = 2 * 1024 * 1024
    static func url(for architecture: String) -> URL? {
        guard ["arm64", "x86_64"].contains(architecture) else { return nil }
        return URL(string: "https://raw.githubusercontent.com/chenmobuys/Neylu/updates/appcast-\(architecture).xml")
    }
    // A fresh query isolates each feed transfer from immutable-URL CDN caches.
    // It does not change the repository, branch, architecture or trust boundary.
    static func downloadURL(for architecture: String, nonce: UUID = UUID()) -> URL? {
        guard let base = url(for: architecture), var parts = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        parts.queryItems = [URLQueryItem(name: "neylu_check", value: nonce.uuidString)]
        return parts.url
    }
    static func acceptsFeedURL(_ candidate: URL) -> Bool {
        guard var parts = URLComponents(url: candidate, resolvingAgainstBaseURL: false), parts.fragment == nil else { return false }
        if let query = parts.queryItems {
            guard query.count == 1, query[0].name == "neylu_check", let value = query[0].value,
                  let nonce = UUID(uuidString: value), nonce.uuidString == value,
                  parts.percentEncodedQuery == "neylu_check=" + value else { return false }
        }
        parts.query = nil
        return ["arm64", "x86_64"].compactMap { url(for: $0) }.contains(parts.url)
    }
    static func releases(from data: Data, architecture: String,
                         system: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) throws -> [GitHubRelease] {
        guard url(for: architecture) != nil, !data.isEmpty, data.count <= limit,
              let xml = String(data: data, encoding: .utf8),
              xml.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil,
              xml.range(of: "<!ENTITY", options: .caseInsensitive) == nil else { throw UpdateFailure.metadata }
        let delegate = Reader(architecture: architecture, system: system)
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), !delegate.failed, delegate.sawChannel, delegate.itemCount > 0 else { throw UpdateFailure.metadata }
        return delegate.releases
    }
    private final class Reader: NSObject, XMLParserDelegate {
        let architecture: String
        let system: OperatingSystemVersion
        var releases: [GitHubRelease] = []
        var failed = false
        var sawChannel = false
        var itemCount = 0
        private var path: [String] = []
        private var fields: [String: String] = [:]
        private var versions = Set<String>()
        init(architecture: String, system: OperatingSystemVersion) { self.architecture = architecture; self.system = system }
        private func key(_ name: String, _ namespace: String?) -> String {
            switch namespace ?? "" {
            case "": return "rss." + name
            case Appcast.sparkle: return "sparkle." + name
            case Appcast.neylu: return "neylu." + name
            default: return "unknown." + name
            }
        }
        private func reject(_ parser: XMLParser) { failed = true; parser.abortParsing() }
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            path.append(key(name, namespaceURI))
            if path.count == 1 {
                if path != ["rss.rss"] || attributes["version"] != "2.0" { reject(parser) }
            } else if path.count == 2 {
                guard path == ["rss.rss", "rss.channel"], !sawChannel else { reject(parser); return }
                sawChannel = true
            } else if path == ["rss.rss", "rss.channel", "rss.item"] {
                fields = [:]; itemCount += 1
                if itemCount > 128 { reject(parser) }
            } else if path.count == 4, path[2] == "rss.item" {
                let field = path[3]
                guard fields[field] == nil else { reject(parser); return }
                fields[field] = ""
                if field == "rss.enclosure" {
                    fields["url"] = attributes["url"]
                    fields["length"] = attributes["length"]
                    fields["type"] = attributes["type"]
                }
            } else if path.count > 4, path[2] == "rss.item" { reject(parser) }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard path.count == 4, path[2] == "rss.item", let field = path.last else { return }
            fields[field, default: ""] += string
            if fields[field]!.utf8.count > 65_536 { reject(parser) }
        }
        func parser(_ parser: XMLParser, foundCDATA data: Data) {
            guard let text = String(data: data, encoding: .utf8) else { reject(parser); return }
            self.parser(parser, foundCharacters: text)
        }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if path == ["rss.rss", "rss.channel", "rss.item"] {
                do { if let release = try item() { releases.append(release) } }
                catch { reject(parser) }
            }
            if !path.isEmpty { path.removeLast() }
        }
        private func item() throws -> GitHubRelease? {
            func text(_ key: String) -> String { fields[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
            let value = text("sparkle.shortVersionString")
            let build = text("sparkle.version")
            guard let version = ReleaseVersion(value), versions.insert(value).inserted,
                  let counter = UInt64(build), counter > 0, String(counter) == build,
                  text("sparkle.channel") == (version.channel < 3 ? ["alpha", "beta", "rc"][version.channel] : "") else { throw UpdateFailure.metadata }
            let parts = text("sparkle.minimumSystemVersion").split(separator: ".", omittingEmptySubsequences: false)
            let minimum = parts.compactMap { Int($0) }
            guard parts.count == 3, minimum.count == 3, minimum.allSatisfy({ $0 >= 0 }),
                  parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { throw UpdateFailure.metadata }
            let tag = "v" + value
            let name = "Neylu-\(value)-\(architecture).dmg"
            let page = AvailableUpdate.repository + "/releases/tag/" + tag
            let url = AvailableUpdate.repository + "/releases/download/" + tag + "/" + name
            let digest = text("neylu.sha256")
            guard text("rss.link") == page, text("url") == url,
                  ["application/octet-stream", "application/x-apple-diskimage"].contains(text("type")),
                  let size = Int64(text("length")), size > 0, size <= 512 * 1024 * 1024,
                  digest.count == 64, digest.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { throw UpdateFailure.incomplete }
            let running = [system.majorVersion, system.minorVersion, system.patchVersion]
            if running.lexicographicallyPrecedes(minimum) { return nil }
            return GitHubRelease(tag_name: tag, html_url: page, body: fields["rss.description"], draft: false,
                                 prerelease: version.channel < 3,
                                 assets: [.init(name: name, browser_download_url: url, size: size, state: "uploaded", digest: "sha256:" + digest)])
        }
    }
}

/// One request serves concurrent manual/background checks. The final departing
/// caller cancels the underlying download; cancelled generations cannot refill cache.
actor AppcastStore {
    private let fetch: () async throws -> [GitHubRelease]
    private let clock: () -> Date
    private var cached: ([GitHubRelease], Date)?
    private var waiters: [UUID: CheckedContinuation<[GitHubRelease], Error>] = [:]
    private var task: Task<Void, Never>?
    private var generation = 0
    init(clock: @escaping () -> Date = Date.init, fetch: @escaping () async throws -> [GitHubRelease]) {
        self.clock = clock; self.fetch = fetch
    }
    func load(forceRefresh: Bool = false) async throws -> [GitHubRelease] {
        try Task.checkCancellation()
        if !forceRefresh, let (value, date) = cached {
            let age = clock().timeIntervalSince(date)
            if age >= 0, age < 60 { return value }
        }
        let id = UUID()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                waiters[id] = continuation
                if task == nil {
                    generation += 1
                    let token = generation
                    task = Task { [fetch] in
                        let result: Result<[GitHubRelease], Error>
                        do { result = .success(try await fetch()) } catch { result = .failure(error) }
                        self.finish(result, generation: token)
                    }
                }
            }
        }, onCancel: { Task { await self.cancel(id) } })
    }
    private func cancel(_ id: UUID) {
        waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
        if waiters.isEmpty { generation += 1; task?.cancel(); task = nil }
    }
    private func finish(_ result: Result<[GitHubRelease], Error>, generation token: Int) {
        guard token == generation else { return }
        task = nil
        if case .success(let value) = result { cached = (value, clock()) }
        let pending = Array(waiters.values)
        waiters.removeAll()
        for waiter in pending { waiter.resume(with: result) }
    }
}
