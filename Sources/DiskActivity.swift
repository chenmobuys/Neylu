import Foundation
import IOKit
import DiskArbitration

// Resolve the boot volume through its I/O Registry ancestry, rather than summing
// disk images, external devices, partitions and the physical drive together.
final class DiskActivityReader {
    private var driver: io_service_t = 0
    private var previous: (read: UInt64, written: UInt64, time: TimeInterval)?
    private var nextDiscovery: TimeInterval = 0
    deinit { if driver != 0 { IOObjectRelease(driver) } }

    func sample(now: TimeInterval) -> (read: Double, write: Double)? {
        if driver == 0, now >= nextDiscovery {
            nextDiscovery = now + 30
            driver = resolveDriver()
        }
        guard driver != 0,
              let stats = IORegistryEntryCreateCFProperty(driver, "Statistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
              let read = (stats["Bytes (Read)"] as? NSNumber)?.uint64Value,
              let written = (stats["Bytes (Write)"] as? NSNumber)?.uint64Value else {
            previous = nil
            if driver != 0 { IOObjectRelease(driver); driver = 0 }
            return nil
        }
        defer { previous = (read, written, now) }
        guard let previous, now > previous.time, read >= previous.read, written >= previous.written else { return nil }
        return (Double(read - previous.read) / (now - previous.time), Double(written - previous.written) / (now - previous.time))
    }
    private func resolveDriver() -> io_service_t {
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, URL(fileURLWithPath: "/") as CFURL) else { return 0 }
        var entry = DADiskCopyIOMedia(disk)
        for _ in 0..<64 {
            guard entry != 0 else { return 0 }
            if IOObjectConformsTo(entry, "IOBlockStorageDriver") != 0 { return entry }
            var parent: io_registry_entry_t = 0
            let status = IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent)
            IOObjectRelease(entry)
            guard status == KERN_SUCCESS else { return 0 }
            entry = parent
        }
        if entry != 0 { IOObjectRelease(entry) }
        return 0
    }
}
