import Foundation
import DiskArbitration

struct ExternalDiskReading: Identifiable {
    let id: String
    let name: String
    let total: UInt64
    let free: UInt64
    var volumeURL: URL? = nil
    var read: Double = 0
    var write: Double = 0
    var activityReady = false
    var activitySupported = false
}

struct MountedExternalDisk {
    let url: URL
    let reading: ExternalDiskReading
}

// Do not mistake mounted installers, internal APFS helper volumes or network
// shares for newly connected hardware. Locked/unmounted volumes appear once mounted.
func isExternalHardware(internalDevice: Bool?, network: Bool, protocolName: String?) -> Bool {
    internalDevice == false && !network && protocolName?.lowercased() != "disk image"
}

final class ExternalDiskMonitor {
    private var volumes: [MountedExternalDisk] = []
    private var volumeOrder: [String] = []
    private var readers: [String: DiskActivityReader] = [:]
    private var nextDiscovery: TimeInterval = 0
    private let discoverVolumes: () -> [MountedExternalDisk]
    init(discover: @escaping () -> [MountedExternalDisk] = ExternalDiskMonitor.discover) { discoverVolumes = discover }

    static func stableOrder(previous: [String], current: [String]) -> [String] {
        let present = Set(current)
        let kept = previous.filter { present.contains($0) }
        let known = Set(kept)
        return kept + current.filter { !known.contains($0) }
    }
    func invalidate() {
        nextDiscovery = 0
        volumes.removeAll()
        readers.removeAll() // A reattached device must start a new counter baseline.
    }

    func sample(now: TimeInterval) -> [ExternalDiskReading] {
        if now >= nextDiscovery {
            nextDiscovery = now + 10
            volumes = discoverVolumes()
            let ids = Set(volumes.map { $0.reading.id })
            volumeOrder = Self.stableOrder(previous: volumeOrder, current: volumes.map { $0.reading.id })
            let positions = Dictionary(uniqueKeysWithValues: volumeOrder.enumerated().map { ($0.element, $0.offset) })
            volumes.sort { positions[$0.reading.id, default: 0] < positions[$1.reading.id, default: 0] }
            readers = readers.filter { ids.contains($0.key) }
        }
        return volumes.map { volume in
            var reading = volume.reading
            let reader = readers[reading.id] ?? DiskActivityReader(volumeURL: volume.url)
            readers[reading.id] = reader
            if let rates = reader.sample(now: now) {
                reading.read = rates.read
                reading.write = rates.write
                reading.activityReady = true
            }
            reading.activitySupported = reader.sourceAvailable
            return reading
        }
    }

    static func discover() -> [MountedExternalDisk] {
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return [] }
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeUUIDStringKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: .skipHiddenVolumes) ?? []
        return urls.compactMap { url -> MountedExternalDisk? in
            guard let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL),
                  let description = DADiskCopyDescription(disk) as? [String: Any],
                  isExternalHardware(internalDevice: description[kDADiskDescriptionDeviceInternalKey as String] as? Bool,
                    network: description[kDADiskDescriptionVolumeNetworkKey as String] as? Bool ?? false,
                    protocolName: description[kDADiskDescriptionDeviceProtocolKey as String] as? String),
                  let bsd = DADiskGetBSDName(disk),
                  let values = try? url.resourceValues(forKeys: keys),
                  let total = values.volumeTotalCapacity, total > 0,
                  let free = values.volumeAvailableCapacity else { return nil }
            return MountedExternalDisk(url: url, reading: ExternalDiskReading(
                id: (values.volumeUUIDString ?? "unknown") + ":" + String(cString: bsd) + ":" + url.path,
                name: values.volumeName ?? url.lastPathComponent,
                total: UInt64(total), free: min(UInt64(total), UInt64(max(0, free))), volumeURL: url))
        }.sorted {
            if $0.reading.name != $1.reading.name { return $0.reading.name.localizedStandardCompare($1.reading.name) == .orderedAscending }
            return $0.reading.id < $1.reading.id
        }
    }
}
