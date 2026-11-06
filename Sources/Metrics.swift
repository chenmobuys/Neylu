import Foundation
import Darwin
import SystemConfiguration
import IOKit

struct Reading {
    var cpuTemperature: Double?
    var cpu: Double = 0
    var cpuUser: Double = 0
    var cpuSystem: Double = 0
    var cpuIdle: Double = 100
    var gpu: Double = 0
    var gpuRenderer: Double = 0
    var gpuTiler: Double = 0
    var gpuName = "GPU"
    var gpuCores: Int?
    var gpuReady = false
    var diskName = "Macintosh HD"
    var diskTotal: UInt64 = 0
    var diskFree: UInt64 = 0
    var diskReady = false
    var diskRead: Double = 0
    var diskWrite: Double = 0
    var diskActivityReady = false
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
    var label: String { self == .decimal ? "1000 · KB" : "1024 · KiB" }
}

struct NetworkInterface: Identifiable, Equatable {
    let name: String
    let title: String
    let active: Bool
    var id: String { name }
}

// Sampling uses cumulative kernel counters and monotonic elapsed time.
final class Sampler {
    var selectedInterface: String? {
        didSet { if selectedInterface != oldValue { previousNetwork = nil } }
    }
    private(set) var interfaces: [NetworkInterface] = []
    private let diskActivityReader = DiskActivityReader()
    private let temperatureReader = CPUTemperatureReader()
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
            result.address = interfaceAddress(net.name)
            if let old = previousNetwork, old.name == net.name, now > old.time,
               net.input >= old.input, net.output >= old.output {
                result.download = Double(net.input - old.input) / (now - old.time)
                result.upload = Double(net.output - old.output) / (now - old.time)
                result.networkReady = true
            }
            previousNetwork = (net.name, net.input, net.output, now)
        } else {
            previousNetwork = nil
        }
        result.cpuTemperature = temperatureReader.read(now: now)
        readGPU(into: &result)
        readDisk(into: &result, now: now)
        if let activity = diskActivityReader.sample(now: now) {
            result.diskRead = activity.read
            result.diskWrite = activity.write
            result.diskActivityReady = true
        }
        return result
    }

    private func readGPU(into reading: inout Reading) {
        guard accelerator != 0 else { return }
        if let name = IORegistryEntryCreateCFProperty(accelerator, "model" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String { reading.gpuName = name }
        reading.gpuCores = (IORegistryEntryCreateCFProperty(accelerator, "gpu-core-count" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.intValue
        guard let stats = IORegistryEntryCreateCFProperty(accelerator, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
              let utilization = stats["Device Utilization %"] as? NSNumber else { return }
        reading.gpu = min(100, max(0, utilization.doubleValue))
        reading.gpuRenderer = min(100, max(0, (stats["Renderer Utilization %"] as? NSNumber)?.doubleValue ?? 0))
        reading.gpuTiler = min(100, max(0, (stats["Tiler Utilization %"] as? NSNumber)?.doubleValue ?? 0))
        reading.gpuReady = true
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
        while let ptr = current {
            let entry = ptr.pointee
            defer { current = entry.ifa_next }
            guard String(cString: entry.ifa_name) == name, let address = entry.ifa_addr,
                  Int32(address.pointee.sa_family) == AF_INET else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: host)
            }
        }
        return "—"
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
        var labels: [String: String] = [:]
        if let known = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] {
            for interface in known {
                if let name = SCNetworkInterfaceGetBSDName(interface) as String?,
                   let label = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? {
                    labels[name] = label
                }
            }
        }
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let start = list else { interfaces = []; return nil }
        defer { freeifaddrs(list) }
        var current: UnsafeMutablePointer<ifaddrs>? = start
        var choices: [NetworkInterface] = []
        var counters: [String: (input: UInt64, output: UInt64)] = [:]
        while let ptr = current {
            let entry = ptr.pointee
            defer { current = entry.ifa_next }
            guard let address = entry.ifa_addr, Int32(address.pointee.sa_family) == AF_LINK else { continue }
            let name = String(cString: entry.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("utun") || name.hasPrefix("bridge") || name.hasPrefix("ppp") || name == primary || name == selectedInterface else { continue }
            let active = entry.ifa_flags & UInt32(IFF_UP) != 0 && entry.ifa_flags & UInt32(IFF_RUNNING) != 0
            let label = labels[name].map { "\($0) (\(name))" } ?? name
            choices.append(NetworkInterface(name: name, title: label, active: active))
            if active, let wide = wideCounters(index: Int32(if_nametoindex(entry.ifa_name))) {
                counters[name] = (wide.0, wide.1)
            }
        }
        interfaces = choices.sorted {
            if $0.active != $1.active { return $0.active }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        // Automatic follows the OS primary route. Sample only one interface, including VPNs.
        // If there is no route, fall back to an active physical adapter, keeping the last
        // one while it remains available so cumulative historical totals cannot cause jitter.
        let target: String?
        if let selectedInterface { target = selectedInterface }
        else if let primary, counters[primary] != nil { target = primary }
        else if let old = previousNetwork?.name, old.hasPrefix("en"), counters[old] != nil { target = old }
        else { target = interfaces.first { $0.active && $0.name.hasPrefix("en") && counters[$0.name] != nil }?.name }
        guard let target, let value = counters[target] else { return nil }
        return (target, value.input, value.output)
    }
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
