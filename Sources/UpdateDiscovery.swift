import Foundation

// All release discovery goes through the same bounded, validated download path.
enum UpdateDiscovery {
    static func find(current: ReleaseVersion, architecture: String) async throws -> AvailableUpdate? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Neylu-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("releases.json")
        try await UpdateDownload(destination: file, limit: 2 * 1024 * 1024, progress: { _ in }).fetch(
            URL(string: "https://api.github.com/repos/chenmobuys/Neylu/releases?per_page=100")!)
        try Task.checkCancellation()
        let releases = try JSONDecoder().decode([GitHubRelease].self, from: Data(contentsOf: file))
        return try AvailableUpdate.check(in: releases, current: current, architecture: architecture)
    }
}

