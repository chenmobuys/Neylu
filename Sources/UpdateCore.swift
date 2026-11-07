import Foundation
import CryptoKit
import Security

// Shared by the app, installer helper and tests. No shell interpolation or
// remote executable scripts are used anywhere in the update path.
struct ReleaseVersion: Comparable, Equatable {
    let numbers: [Int]
    let channel: Int // alpha < beta < rc < stable
    let iteration: Int
    let text: String
    init?(_ text: String) {
        let pattern = #"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-(alpha|beta|rc)\.([1-9][0-9]*))?$"#
        guard let match = text.range(of: pattern, options: .regularExpression), match == text.startIndex..<text.endIndex else { return nil }
        let parts = text.split(separator: "-", maxSplits: 1)
        let numbers = parts[0].split(separator: ".").compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }
        self.numbers = numbers
        if parts.count == 2 {
            let suffix = parts[1].split(separator: ".")
            guard let iteration = Int(suffix[1]) else { return nil }
            self.channel = ["alpha": 0, "beta": 1, "rc": 2][String(suffix[0])]!
            self.iteration = iteration
        } else { channel = 3; iteration = 0 }
        self.text = text
    }
    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.numbers != rhs.numbers { return lhs.numbers.lexicographicallyPrecedes(rhs.numbers) }
        if lhs.channel != rhs.channel { return lhs.channel < rhs.channel }
        return lhs.iteration < rhs.iteration
    }
}

enum UpdateFailure: String, Error, LocalizedError, CaseIterable {
    case metadata = "update.error.metadata"
    case download = "update.error.download"
    case checksum = "update.error.integrity_check_failed"
    case bundle = "update.error.bundle_validation"
    case destination = "update.error.destination"
    case operation = "update.error.installation"
    case timeout = "update.error.quit_timeout"
    case incomplete = "update.error.incomplete_release"
    case rateLimited = "update.error.rate_limited"
    case launch = "update.error.startup"
    var errorDescription: String? { L10n.text(rawValue) }
}

struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browser_download_url: String
        let size: Int64
        let state: String
        let digest: String?
    }
    let tag_name: String
    let html_url: String
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
}

struct AvailableUpdate {
    static let repository = "https://github.com/chenmobuys/Neylu"
    let version: ReleaseVersion
    let notes: String
    let page: URL
    let package: URL
    let digest: String
    let size: Int64
    let filename: String

    private static func eligibleVersion(_ release: GitHubRelease, current: ReleaseVersion) -> ReleaseVersion? {
        guard !release.draft, release.tag_name.hasPrefix("v"),
              let version = ReleaseVersion(String(release.tag_name.dropFirst())), version > current,
              release.prerelease == (version.channel < 3), current.channel < 3 || !release.prerelease else { return nil }
        return version
    }

    // A missing installer is not evidence that the installed version is current.
    // Check the newest eligible release first, then validate its installer.
    static func check(in releases: [GitHubRelease], current: ReleaseVersion, architecture: String) throws -> Self? {
        let candidates = releases.compactMap { release -> (GitHubRelease, ReleaseVersion)? in
            eligibleVersion(release, current: current).map { (release, $0) }
        }
        guard let latest = candidates.max(by: { $0.1 < $1.1 }) else { return nil }
        guard let update = newest(in: [latest.0], current: current, architecture: architecture) else { throw UpdateFailure.incomplete }
        return update
    }

    static func newest(in releases: [GitHubRelease], current: ReleaseVersion, architecture: String) -> Self? {
        guard ["arm64", "x86_64"].contains(architecture) else { return nil }
        return releases.compactMap { release -> Self? in
            guard let version = eligibleVersion(release, current: current) else { return nil }
            let page = "\(repository)/releases/tag/\(release.tag_name)"
            guard release.html_url == page else { return nil }
            let filename = "Neylu-\(version.text)-\(architecture).dmg"
            let base = "\(repository)/releases/download/\(release.tag_name)/"
            let packages = release.assets.filter { $0.name == filename }
            guard packages.count == 1, let package = packages.first,
                  package.state == "uploaded", package.size > 0, package.size <= 512 * 1024 * 1024,
                  package.browser_download_url == base + filename,
                  let digest = package.digest, digest.hasPrefix("sha256:"), digest.count == 71,
                  digest.dropFirst(7).allSatisfy({ $0.isHexDigit && $0.isASCII }),
                  let pageURL = URL(string: page), let packageURL = URL(string: package.browser_download_url) else { return nil }
            return Self(version: version, notes: String((release.body ?? "").prefix(12_000)), page: pageURL,
                        package: packageURL, digest: String(digest.dropFirst(7)).lowercased(), size: package.size, filename: filename)
        }.max { $0.version < $1.version }
    }

    func verify(package file: URL) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        var count: Int64 = 0
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            count += Int64(chunk.count)
            guard count <= size else { throw UpdateFailure.checksum }
            hash.update(data: chunk)
        }
        guard count == size, hash.finalize().map({ String(format: "%02x", $0) }).joined() == digest else { throw UpdateFailure.checksum }
    }
}

enum UpdateFiles {
    static let fm = FileManager.default
    static func regularDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true, values.isSymbolicLink != true else { return false }
        return url.standardizedFileURL.path == url.resolvingSymlinksInPath().path
    }
    static func canReplace(_ app: URL) -> Bool {
        let parent = app.deletingLastPathComponent()
        guard app.pathExtension == "app", regularDirectory(app), regularDirectory(parent),
              !app.path.hasPrefix("/Volumes/"), !app.path.contains("/AppTranslocation/"),
              fm.isWritableFile(atPath: app.path), fm.isWritableFile(atPath: parent.path),
              let owner = try? fm.attributesOfItem(atPath: app.path)[.ownerAccountID] as? NSNumber,
              owner.uint32Value == getuid() else { return false }
        return true
    }
    @discardableResult
    static func run(_ path: String, _ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let result = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateFailure.operation }
        return result
    }
    static func signingTeam(_ app: URL) throws -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode), nil) == errSecSuccess else { throw UpdateFailure.bundle }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any] else { throw UpdateFailure.bundle }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }
    static func info(_ app: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { throw UpdateFailure.bundle }
        return info
    }
    static func isUpgrade(_ version: ReleaseVersion, from app: URL) throws -> Bool {
        guard let raw = try info(app)["NeyluReleaseVersion"] as? String, let installed = ReleaseVersion(raw) else { throw UpdateFailure.bundle }
        return version > installed
    }
    static func confirmLaunch(isRunning: () -> Bool, pause: () -> Void) throws {
        guard isRunning() else { throw UpdateFailure.launch }
        pause()
        guard isRunning() else { throw UpdateFailure.launch }
    }
    static func validate(_ app: URL, version: ReleaseVersion, architecture: String, requiredTeam: String?) throws {
        let info = try self.info(app)
        guard regularDirectory(app), info["CFBundleIdentifier"] as? String == "io.github.chenmobuys.Neylu",
              info["NeyluReleaseVersion"] as? String == version.text,
              info["CFBundleExecutable"] as? String == "Neylu",
              let minimum = info["LSMinimumSystemVersion"] as? String else { throw UpdateFailure.bundle }
        let executable = app.appendingPathComponent("Contents/MacOS/Neylu")
        let pieces = minimum.split(separator: ".", omittingEmptySubsequences: false)
        let os = pieces.compactMap { Int($0) }
        guard os.count == pieces.count, os.allSatisfy({ $0 >= 0 }), (1...3).contains(os.count), ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: os[0], minorVersion: os.count > 1 ? os[1] : 0, patchVersion: os.count > 2 ? os[2] : 0)) else { throw UpdateFailure.bundle }
        let team = try signingTeam(app)
        if let requiredTeam {
            guard team == requiredTeam, requiredTeam.count == 10,
                  requiredTeam.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { throw UpdateFailure.bundle }
            var requirement: SecRequirement?
            var code: SecStaticCode?
            let rule = "anchor apple generic and certificate leaf[subject.OU] = \"\(requiredTeam)\""
            guard SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess,
                  SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
                  SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckNestedCode), requirement) == errSecSuccess else { throw UpdateFailure.bundle }
        }
        let architectures = String(data: try run("/usr/bin/lipo", ["-archs", executable.path]), encoding: .utf8)?.split(whereSeparator: \.isWhitespace).map(String.init) ?? []
        guard architectures.contains(architecture) else { throw UpdateFailure.bundle }
    }

    // Stage and backup live beside the destination, so both renames stay on the
    // same volume. Roll back on either replacement or launch failure.
    static func install(candidate: URL, target: URL, backup: URL, launch: (URL) throws -> Void) throws {
        guard canReplace(target), !fm.fileExists(atPath: backup.path),
              candidate.deletingLastPathComponent() == backup.deletingLastPathComponent(),
              candidate.deletingLastPathComponent().deletingLastPathComponent() == target.deletingLastPathComponent() else { throw UpdateFailure.destination }
        try fm.moveItem(at: target, to: backup)
        do {
            try fm.moveItem(at: candidate, to: target)
            try launch(target)
        } catch {
            if fm.fileExists(atPath: target.path) { try? fm.moveItem(at: target, to: candidate) }
            do { try fm.moveItem(at: backup, to: target) }
            catch { throw UpdateFailure.destination } // Preserve backup for recovery.
            throw UpdateFailure.operation
        }
        try? fm.removeItem(at: backup)
    }
}
