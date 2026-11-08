import Foundation

// App clients only read static feeds. GitHub REST is used by release automation,
// whose scoped Actions token generates feeds after verifying published installers.
enum UpdateDiscovery {
    private static let stores: [String: AppcastStore] = Dictionary(uniqueKeysWithValues: ["arm64", "x86_64"].map { architecture in
        (architecture, AppcastStore { try await download(architecture: architecture) })
    })
    static func find(current: ReleaseVersion, architecture: String, forceRefresh: Bool = false) async throws -> AvailableUpdate? {
        guard let store = stores[architecture] else { throw UpdateFailure.metadata }
        let releases = try await store.load(forceRefresh: forceRefresh)
        try Task.checkCancellation()
        return try AvailableUpdate.check(in: releases, current: current, architecture: architecture)
    }
    private static func download(architecture: String) async throws -> [GitHubRelease] {
        guard let url = Appcast.downloadURL(for: architecture) else { throw UpdateFailure.metadata }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Neylu-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("appcast.xml")
        try await UpdateDownload(destination: file, limit: Int64(Appcast.limit), progress: { _ in }).fetch(url)
        try Task.checkCancellation()
        return try Appcast.releases(from: Data(contentsOf: file), architecture: architecture)
    }
}
