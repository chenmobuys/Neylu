import Foundation

/// Tokens invalidate late callbacks without deleting a newer attempt's files.
struct UpdateAttemptGate {
    private(set) var generation = 0
    mutating func begin() -> Int { generation += 1; return generation }
    mutating func cancel() { generation += 1 }
    func accepts(_ token: Int) -> Bool { generation == token }
}

/// One attempt owns one private directory. Never sweep directories by prefix.
final class UpdateWorkspace {
    let directory: URL
    private var owned = true
    init(root: URL = FileManager.default.temporaryDirectory) throws {
        directory = root.appendingPathComponent("Neylu-update-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    }
    func transferOwnership() { owned = false }
    deinit {
        guard owned else { return }
        // A failed detach must never turn cleanup into recursive deletion of
        // a mounted image. Leave that private workspace for system cleanup.
        let mount = directory.appendingPathComponent("mount")
        if (try? mount.resourceValues(forKeys: [.isVolumeKey]).isVolume) == true { return }
        try? FileManager.default.removeItem(at: directory)
    }
}

enum UpdateRecovery: Equatable {
    case check, download, install
    static func action(for error: Error, hasUpdate: Bool) -> Self {
        guard hasUpdate else { return .check }
        if let failure = error as? UpdateFailure {
            switch failure {
            case .metadata, .incomplete, .rateLimited: return .check
            case .download, .checksum, .bundle: return .download
            default: return .install
            }
        }
        return (error as NSError).domain == NSURLErrorDomain ? .download : .install
    }
    var titleKey: String {
        switch self {
        case .check: return "update.action.check_again"
        case .download: return "update.action.download_again"
        case .install: return "update.action.install_again"
        }
    }
    var hintKey: String {
        switch self {
        case .check: return "update.recovery.check"
        case .download: return "update.recovery.download"
        case .install: return "update.recovery.install"
        }
    }
}

/// Run on the preparation worker. Retry only a busy image; never force detach.
enum UpdateMount {
    static func detach(at url: URL, execute: ((URL) throws -> Int32)? = nil,
                       pause: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }) throws {
        let operation = execute ?? { mount in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = ["detach", mount.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }
        for attempt in 0..<4 {
            let result = try operation(url)
            if result == 0 { return }
            guard result == 16, attempt < 3 else { throw UpdateFailure.operation }
            pause(0.2 * pow(2, Double(attempt)))
        }
    }
}
