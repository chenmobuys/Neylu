import AppKit
import Combine

struct DiskEjectFailure: Identifiable {
    let id = UUID()
    let name: String
    let message: String
}

final class DiskActions: ObservableObject {
    @Published private(set) var ejectingID: String?
    @Published var failure: DiskEjectFailure?
    var onFinish: (() -> Void)?
    private let operation: (ExternalDiskReading) throws -> Void

    init(operation: @escaping (ExternalDiskReading) throws -> Void = DiskActions.ejectExternalVolume) {
        self.operation = operation
    }

    func eject(_ volume: ExternalDiskReading) {
        precondition(Thread.isMainThread)
        guard ejectingID == nil, volume.volumeURL != nil else { return }
        ejectingID = volume.id
        failure = nil
        // Apple documents this NSWorkspace operation as safe from any thread.
        // Keep OS unmount/flush work off the sampling and UI run loop.
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let result = Result { try operation(volume) }
            DispatchQueue.main.async { [self] in
                ejectingID = nil
                if case .failure(let error) = result {
                    failure = DiskEjectFailure(name: volume.name, message: error.localizedDescription)
                }
                onFinish?()
            }
        }
    }

    private static func ejectExternalVolume(_ volume: ExternalDiskReading) throws {
        // Revalidate the current mount, including its volume UUID when available. Do not act on
        // a stale row whose path has since been reused by another device.
        guard let url = volume.volumeURL,
              ExternalDiskMonitor.discover().contains(where: { $0.reading.id == volume.id && $0.url == url }) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError,
                          userInfo: [NSLocalizedDescriptionKey: L("disk.changed")])
        }
        try unmountAndEject(at: url)
    }

    static func unmountAndEject(at url: URL) throws {
        try NSWorkspace.shared.unmountAndEjectDevice(at: url)
    }
}
