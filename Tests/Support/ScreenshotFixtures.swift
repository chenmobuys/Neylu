import AppKit
import Foundation

// Deterministic demo data for documentation screenshots. Never persisted.
extension MonitorModel {
    func applyScreenshotFixture(now: Date = Date()) {
        reading = Reading(cpuTemperature: 48.6, cpu: 18, cpuUser: 12, cpuSystem: 6,
            cpuIdle: 82, gpu: 32, gpuRenderer: 28, gpuTiler: 30, gpuCores: 40,
            gpuReady: true, diskName: "Macintosh HD", diskTotal: 1_000_000_000_000,
            diskFree: 460_000_000_000, diskReady: true, diskRead: 8_600_000,
            diskWrite: 2_400_000, diskActivityReady: true, memory: 43,
            usedMemory: 20_640_000_000, totalMemory: 48_000_000_000,
            download: 1_200_000, upload: 86_000, interface: "en0", address: "192.0.2.1",
            cpuReady: true, networkReady: true, memoryReady: true)
        if CommandLine.arguments.contains("--screenshot-external-disks") {
            reading.externalDisks = (1...(CommandLine.arguments.contains("--screenshot-many-disks") ? 8 : 4)).map { index in
                ExternalDiskReading(id: "demo-external-\(index)", name: "Demo SSD \(index)",
                    total: 2_000_000_000_000, free: UInt64(index) * 200_000_000_000,
                    read: Double(index) * 1_000_000, write: Double(index) * 500_000, activityReady: true)
            }
        }
        history = (0...60).map { i in
            let pulse = pow(max(0, sin(Double(i) * 0.29)), 4)
            return CPUPoint(timestamp: now.addingTimeInterval(Double(i - 60) * 2),
                            user: 12 + 31 * pulse, system: 6 + 5 * pulse)
        }
        gpuHistory = (0...60).map { i in
            let pulse = pow(max(0, sin(Double(i) * 0.22 + 0.8)), 3)
            return GPUPoint(timestamp: now.addingTimeInterval(Double(i - 60) * 2),
                total: 25 + 30 * pulse, renderer: 20 + 28 * pulse, tiler: 23 + 25 * pulse)
        }
        memoryHistory = (0...60).map { i in
            let used = 20_200_000_000.0 + Double(i) * 7_000_000.0 + sin(Double(i) * 0.4) * 60_000_000.0
            return MemoryPoint(timestamp: now.addingTimeInterval(Double(i - 60) * 2),
                               used: UInt64(used), total: reading.totalMemory)
        }
        networkHistory = (0...60).map { i in
            let pulse = pow(max(0, sin(Double(i) * 0.31)), 6)
            let upload = pow(max(0, sin(Double(i) * 0.24 + 1.7)), 8)
            return NetworkPoint(timestamp: now.addingTimeInterval(Double(i - 60) * 2),
                                download: 200_000 + pulse * 1_800_000, upload: 86_000 + upload * 550_000)
        }
        if CommandLine.arguments.contains("--screenshot-unavailable-sensors") {
            reading.cpuTemperature = nil
            reading.cpuTemperatureSupported = false
            reading.gpuRenderer = nil
            reading.gpuTiler = nil
            gpuHistory = gpuHistory.map { GPUPoint(timestamp: $0.timestamp, total: $0.total, renderer: nil, tiler: nil) }
        }
        updateChartWindow(at: now)
    }
}
