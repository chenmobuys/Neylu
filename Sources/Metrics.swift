import Foundation
import Darwin
import SystemConfiguration
import IOKit

struct Reading {
    var cpuTemperature: Double?
    var cpuTemperatureSupported = true
    var cpu: Double = 0
    var cpuUser: Double = 0
    var cpuSystem: Double = 0
    var cpuIdle: Double = 100
    var gpu: Double = 0
    var gpuRenderer: Double?
    var gpuTiler: Double?
    var gpuCores: Int?
    var gpuReady = false
    var diskName = "Macintosh HD"
    var diskTotal: UInt64 = 0
    var diskFree: UInt64 = 0
    var diskReady = false
    var diskRead: Double = 0
    var diskWrite: Double = 0
    var diskActivityReady = false
    var externalDisks: [ExternalDiskReading] = []
    var memory: Double = 0
    var usedMemory: UInt64 = 0
    var totalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
    var download: Double = 0
    var upload: Double = 0
    var interface = "—"
    var address = "—"
    var cpuReady = false
    var networkReady = false
    var memoryReady = false
}

enum UnitBasis: String, CaseIterable, Identifiable {
    case decimal, binary
    var id: String { rawValue }
    var radix: Double { self == .decimal ? 1_000 : 1_024 }
    var units: [String] { self == .decimal ? ["B", "KB", "MB", "GB", "TB"] : ["B", "KiB", "MiB", "GiB", "TiB"] }
}

// Sampling uses cumulative kernel counters and monotonic elapsed time.
final class Sampler {
    private var demand = SamplingDemand.full
    private var addressCache = NetworkAddressCache()
    func setDemand(_ value: SamplingDemand) {
        if !demand.details && value.details {
            addressCache.invalidate()
            diskActivityReader.resetBaseline()
            externalDiskMonitor.invalidate()
            temperatureReader?.invalidateCache()
            nextDiskRead = 0
        }
        demand = value
    }
    func resetAfterWake() {
        addressCache.invalidate()
        previousCPU = nil
        previousNetwork = nil
        nextDiskRead = 0
        diskActivityReader.resetBaseline()
        externalDiskMonitor.invalidate()
        temperatureReader?.invalidateCache()
    }
    private let diskActivityReader = DiskActivityReader()
    private let externalDiskMonitor = ExternalDiskMonitor()
    func refreshDisks(into reading: inout Reading) {
        externalDiskMonitor.invalidate()
        nextDiskRead = 0
        let now = ProcessInfo.processInfo.systemUptime
        if demand.details || demand.systemDisk { readDisk(into: &reading, now: now) }
        if demand.details { reading.externalDisks = externalDiskMonitor.sample(now: now) }
    }
    private var temperatureReader: CPUTemperatureReader?
    private let accelerator = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOAccelerator"))
    private var diskCache: (name: String, total: UInt64, free: UInt64)?
    private var nextDiskRead: TimeInterval = 0
    private let hostPort = mach_host_self()
    deinit {
        mach_port_deallocate(mach_task_self_, hostPort)
        if accelerator != 0 { IOObjectRelease(accelerator) }
    }
    private var previousCPU: [UInt32]?
    private var previousNetwork: (name: String, input: UInt64, output: UInt64, time: TimeInterval)?
    private let store = SCDynamicStoreCreate(nil, "Neylu" as CFString, nil, nil)

    func sample() -> Reading {
        var result = Reading()
        var cpu = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let cpuStatus = withUnsafeMutablePointer(to: &cpu) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(hostPort, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        if cpuStatus == KERN_SUCCESS {
            let ticks = [cpu.cpu_ticks.0, cpu.cpu_ticks.1, cpu.cpu_ticks.2, cpu.cpu_ticks.3]
            if let old = previousCPU {
                let delta = zip(ticks, old).map { UInt64($0 &- $1) }
                let total = delta.reduce(0, +)
                if total > 0 {
                    result.cpu = Double(total - delta[Int(CPU_STATE_IDLE)]) / Double(total) * 100
                    result.cpuUser = Double(delta[Int(CPU_STATE_USER)] + delta[Int(CPU_STATE_NICE)]) / Double(total) * 100
                    result.cpuSystem = Double(delta[Int(CPU_STATE_SYSTEM)]) / Double(total) * 100
                    result.cpuIdle = Double(delta[Int(CPU_STATE_IDLE)]) / Double(total) * 100
                    result.cpuReady = true
                }
            }
            previousCPU = ticks
        }
        var vm = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vmStatus = withUnsafeMutablePointer(to: &vm) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &vmCount)
            }
        }
        if vmStatus == KERN_SUCCESS {
            // App memory (anonymous minus purgeable), wired and compressed pages.
            // File-backed cache remains available for reuse, as in Activity Monitor.
            let appPages = UInt64(vm.internal_page_count) - min(UInt64(vm.internal_page_count), UInt64(vm.purgeable_count))
            let pages = appPages + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)
            result.usedMemory = min(pages * UInt64(vm_kernel_page_size), result.totalMemory)
            result.memory = Double(result.usedMemory) / Double(result.totalMemory) * 100
            result.memoryReady = true
        }
        let now = ProcessInfo.processInfo.systemUptime
        if let net = networkCounters() {
            result.interface = net.name
            if demand.details { result.address = addressCache.address(for: net.name, now: now) { interfaceAddress(net.name) } }
            if let old = previousNetwork, old.name == net.name, now > old.time,
               net.input >= old.input, net.output >= old.output {
                result.download = Double(net.input - old.input) / (now - old.time)
                result.upload = Double(net.output - old.output) / (now - old.time)
                result.networkReady = true
            }
            previousNetwork = (net.name, net.input, net.output, now)
        } else {
            previousNetwork = nil
            addressCache.invalidate()
        }
        readGPU(into: &result)
        if demand.details || demand.systemDisk { readDisk(into: &result, now: now) }
        if demand.details {
            let reader = temperatureReader ?? CPUTemperatureReader()
            temperatureReader = reader
            result.cpuTemperature = reader.read(now: now)
            result.cpuTemperatureSupported = reader.supportsDevice
            result.externalDisks = externalDiskMonitor.sample(now: now)
            if let activity = diskActivityReader.sample(now: now) {
                result.diskRead = activity.read
                result.diskWrite = activity.write
                result.diskActivityReady = true
            }
        }
        return result
    }

    private lazy var gpuCoreCount: Int? = {
        guard accelerator != 0 else { return nil }
        return (IORegistryEntryCreateCFProperty(accelerator, "gpu-core-count" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.intValue
    }()
    private func readGPU(into reading: inout Reading) {
        guard accelerator != 0 else { return }
        reading.gpuCores = gpuCoreCount
        guard let stats = IORegistryEntryCreateCFProperty(accelerator, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] else { return }
        applyGPUStatistics(stats, to: &reading)
    }
    private func readDisk(into reading: inout Reading, now: TimeInterval) {
        if now >= nextDiskRead {
            nextDiskRead = now + 10
            if let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
               let total = values.volumeTotalCapacity, let free = values.volumeAvailableCapacity, total > 0 {
                diskCache = (values.volumeName ?? "Macintosh HD", UInt64(total), min(UInt64(total), UInt64(max(0, free))))
            } else { diskCache = nil }
        }
        if let diskCache {
            reading.diskName = diskCache.name
            reading.diskTotal = diskCache.total
            reading.diskFree = diskCache.free
            reading.diskReady = true
        }
    }

    private func interfaceAddress(_ name: String) -> String {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return "—" }
        defer { freeifaddrs(list) }
        var current = list
        var addresses: [String] = []
        while let ptr = current {
            let entry = ptr.pointee
            defer { current = entry.ifa_next }
            guard String(cString: entry.ifa_name) == name, let address = entry.ifa_addr,
                  [AF_INET, AF_INET6].contains(Int32(address.pointee.sa_family)) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                addresses.append(String(cString: host))
            }
        }
        return preferredNetworkAddress(addresses)
    }

    private func wideCounters(index: Int32) -> (UInt64, UInt64)? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, index]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<if_msghdr2>.alignment)
        defer { buffer.deallocate() }
        guard sysctl(&mib, u_int(mib.count), buffer, &size, nil, 0) == 0 else { return nil }
        var offset = 0
        while offset + MemoryLayout<if_msghdr2>.size <= size {
            let message = buffer.advanced(by: offset).assumingMemoryBound(to: if_msghdr2.self).pointee
            guard message.ifm_msglen > 0 else { break }
            if Int32(message.ifm_index) == index && Int32(message.ifm_type) == RTM_IFINFO2 {
                return (message.ifm_data.ifi_ibytes, message.ifm_data.ifi_obytes)
            }
            offset += Int(message.ifm_msglen)
        }
        return nil
    }

    private func networkCounters() -> (name: String, input: UInt64, output: UInt64)? {
        var primary: String?
        if let store {
            for family in ["IPv4", "IPv6"] {
                if let state = SCDynamicStoreCopyValue(store, "State:/Network/Global/\(family)" as CFString) as? [String: Any],
                   let name = state["PrimaryInterface"] as? String {
                    primary = name
                    break
                }
            }
        }
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let start = list else { return nil }
        defer { freeifaddrs(list) }
        var current: UnsafeMutablePointer<ifaddrs>? = start
        var counters: [String: (input: UInt64, output: UInt64)] = [:]
        while let ptr = current {
            let entry = ptr.pointee
            defer { current = entry.ifa_next }
            guard let address = entry.ifa_addr, Int32(address.pointee.sa_family) == AF_LINK else { continue }
            let name = String(cString: entry.ifa_name)
            guard name.hasPrefix("en") || name == primary else { continue }
            let active = entry.ifa_flags & UInt32(IFF_UP) != 0 && entry.ifa_flags & UInt32(IFF_RUNNING) != 0
            if active, let wide = wideCounters(index: Int32(if_nametoindex(entry.ifa_name))) {
                counters[name] = (wide.0, wide.1)
            }
        }
        let target = automaticNetworkInterface(primary: primary, previous: previousNetwork?.name, available: Array(counters.keys))
        guard let target, let value = counters[target] else { return nil }
        return (target, value.input, value.output)
    }
}

// Follow the OS route (including VPNs). Without one, keep the same active
// physical adapter instead of jumping between cumulative counters.
func automaticNetworkInterface(primary: String?, previous: String?, available: [String]) -> String? {
    if let primary, available.contains(primary) { return primary }
    if let previous, previous.hasPrefix("en"), available.contains(previous) { return previous }
    return available.filter { $0.hasPrefix("en") }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.first
}

func applyGPUStatistics(_ stats: [String: Any], to reading: inout Reading) {
    func percentage(_ key: String) -> Double? {
        guard let number = stats[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
        return min(100, max(0, number.doubleValue))
    }
    let total = percentage("Device Utilization %")
    reading.gpuReady = total != nil
    reading.gpu = total ?? 0
    reading.gpuRenderer = percentage("Renderer Utilization %")
    reading.gpuTiler = percentage("Tiler Utilization %")
}

// Prefer familiar IPv4, otherwise show a usable IPv6 address rather than a dash.
// Link-local addresses identify the local segment, not the Internet connection.
func preferredNetworkAddress(_ addresses: [String]) -> String {
    var fallback: String?
    for address in addresses {
        var ipv4 = in_addr()
        if inet_pton(AF_INET, address, &ipv4) == 1 { return address }
        var ipv6 = in6_addr()
        let unscoped = address.split(separator: "%", maxSplits: 1).first.map(String.init) ?? ""
        if inet_pton(AF_INET6, unscoped, &ipv6) == 1 {
            let linkLocal = withUnsafeBytes(of: ipv6) { $0[0] == 0xfe && $0[1] & 0xc0 == 0x80 }
            if !linkLocal, fallback == nil { fallback = address }
        }
    }
    return fallback ?? "—"
}

func percent(_ value: Double, ready: Bool) -> String {
    ready ? "\(Int(min(100, max(0, value)).rounded()))%" : "—"
}

func formattedRate(_ bytes: Double, basis: UnitBasis, ready: Bool = true) -> String {
    guard ready else { return "—" }
    var value = max(0, bytes) / basis.radix
    var index = 1
    // Advance before rounding would overflow the current unit.
    while value >= basis.radix - 0.5 && index < basis.units.count - 1 {
        value /= basis.radix
        index += 1
    }
    let number = value < 10 && index > 1 ? String(format: "%.1f", value) : String(format: "%.0f", value)
    return "\(number) \(basis.units[index])/s"
}

func formattedMemory(_ bytes: UInt64, basis: UnitBasis) -> String {
    var value = Double(bytes)
    var index = 0
    while value >= basis.radix && index < basis.units.count - 1 { value /= basis.radix; index += 1 }
    let number = value.rounded() == value ? String(format: "%.0f", value) : String(format: "%.1f", value)
    return "\(number) \(basis.units[index])"
}

func cpuModelName() -> String {
    var length = 0
    guard sysctlbyname("machdep.cpu.brand_string", nil, &length, nil, 0) == 0, length > 0 else { return "CPU" }
    var bytes = [CChar](repeating: 0, count: length)
    guard sysctlbyname("machdep.cpu.brand_string", &bytes, &length, nil, 0) == 0 else { return "CPU" }
    return String(cString: bytes)
}

// Wall-clock elapsed time since the kernel's last boot, including sleep.
func elapsedSinceBoot() -> TimeInterval? {
    var boot = timeval()
    var size = MemoryLayout<timeval>.size
    guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0,
          size == MemoryLayout<timeval>.size, boot.tv_sec > 0 else { return nil }
    let timestamp = TimeInterval(boot.tv_sec) + TimeInterval(boot.tv_usec) / 1_000_000
    let elapsed = Date().timeIntervalSince1970 - timestamp
    return elapsed >= 0 ? elapsed : nil
}

func formattedDiskRate(_ bytes: Double, basis: UnitBasis, ready: Bool) -> String {
    guard ready else { return "—" }
    if bytes < basis.radix { return String(format: "%.0f B/s", max(0, bytes)) }
    return formattedRate(bytes, basis: basis)
}
