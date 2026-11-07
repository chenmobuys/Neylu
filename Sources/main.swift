import AppKit
import Foundation

if CommandLine.arguments.contains("--diagnose") {
    let sampler = Sampler()
    _ = sampler.sample()
    Thread.sleep(forTimeInterval: 1)
    let reading = sampler.sample()
    let output: [String: Any] = ["elapsedSinceBootSeconds": elapsedSinceBoot().map { $0 as Any } ?? NSNull(), "cpuPercent": reading.cpu, "cpuTemperatureCelsius": reading.cpuTemperature.map { $0 as Any } ?? NSNull(), "memoryPercent": reading.memory,
        "usedMemoryBytes": reading.usedMemory, "totalMemoryBytes": reading.totalMemory,
        "downloadBytesPerSecond": reading.download, "uploadBytesPerSecond": reading.upload,
        "interface": reading.interface, "gpuPercent": reading.gpu, "gpuReady": reading.gpuReady, "gpuCores": reading.gpuCores ?? 0, "diskTotalBytes": reading.diskTotal, "diskFreeBytes": reading.diskFree, "diskReady": reading.diskReady, "diskReadBytesPerSecond": reading.diskRead, "diskWriteBytesPerSecond": reading.diskWrite, "diskActivityReady": reading.diskActivityReady, "cpuReady": reading.cpuReady,
        "networkReady": reading.networkReady, "memoryReady": reading.memoryReady,
        "externalDisks": reading.externalDisks.map { ["id": $0.id, "name": $0.name, "totalBytes": $0.total, "freeBytes": $0.free, "readBytesPerSecond": $0.read, "writeBytesPerSecond": $0.write, "activityReady": $0.activityReady] as [String: Any] }]
    let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    exit(reading.cpuReady && reading.memoryReady ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
