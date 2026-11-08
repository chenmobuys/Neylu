// A repeatable local microbenchmark, not an estimate of whole-app Energy Impact.
// No monitoring history or readings are written to disk; output contains timings only.
import AppKit
import SwiftUI
import Darwin

L10n.useResources(at: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources"))
NSApplication.shared.setActivationPolicy(.accessory)
func cpuSeconds() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
}
func argument(_ name: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: name), index + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[index + 1]
}
func usageInfo() -> rusage_info_v4? {
    var info = rusage_info_v4()
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0) }
    }
    return result == 0 ? info : nil
}
if CommandLine.arguments.contains("--idle-process") {
    let duration = Double(argument("--duration") ?? "15") ?? 15
    let warmup = Double(argument("--warmup") ?? "1") ?? 1
    let interval = Int(argument("--interval") ?? "2") ?? 2
    let mode = EnergyMode(rawValue: argument("--energy-mode") ?? "off") ?? .off
    precondition((1...600).contains(duration) && (0.1...60).contains(warmup) && RefreshInterval(rawValue: interval) != nil)
    UserDefaults.standard.setVolatileDomain(["refreshInterval": interval, "energyMode": mode.rawValue,
        "historyRange": 120, "automaticUpdateChecks": false], forName: UserDefaults.argumentDomain)
    let persistent = CommandLine.arguments.contains("--history")
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Neylu-energy-" + UUID().uuidString)
    let model = MonitorModel(persistHistory: persistent, historyURL: folder.appendingPathComponent("history.sqlite"))
    precondition(!persistent || model.historyStorageAvailable, "Temporary history store failed to open")
    let delegate = AppDelegate(model: model)
    NSApp.delegate = delegate
    if CommandLine.arguments.contains("--show-details") {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { delegate.toggleDetails() }
    }
    var startCPU = 0.0, startWall = 0.0
    var initialUsage: rusage_info_v4?
    Timer.scheduledTimer(withTimeInterval: warmup, repeats: false) { _ in
        startCPU = cpuSeconds(); startWall = ProcessInfo.processInfo.systemUptime; initialUsage = usageInfo()
    }
    Timer.scheduledTimer(withTimeInterval: warmup + duration, repeats: false) { _ in
        let elapsed = ProcessInfo.processInfo.systemUptime - startWall
        let consumed = cpuSeconds() - startCPU
        let finalUsage = usageInfo()
        var report: [String: Any] = ["elapsed_seconds": elapsed, "warmup_seconds": warmup,
            "cpu_percent_of_one_core": consumed / elapsed * 100, "history_persistence": persistent,
            "requested_interval_seconds": interval, "energy_mode": mode.rawValue,
            "effective_interval_seconds": mode.interval(requested: TimeInterval(interval), detailsVisible: CommandLine.arguments.contains("--show-details"), lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled),
            "details_visible": CommandLine.arguments.contains("--show-details"),
            "scope": "isolated actual app delegate and normal sampling; optional temporary SQLite; not Energy Impact or power in watts"]
        if persistent {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            report["history_file_bytes"] = files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        }
        if let finalUsage {
            report["resident_memory_bytes"] = finalUsage.ri_resident_size
            report["physical_footprint_bytes"] = finalUsage.ri_phys_footprint
            if let initialUsage {
                report["interrupt_wakeups"] = finalUsage.ri_interrupt_wkups - initialUsage.ri_interrupt_wkups
                report["package_idle_wakeups"] = finalUsage.ri_pkg_idle_wkups - initialUsage.ri_pkg_idle_wkups
                report["disk_bytes_read"] = finalUsage.ri_diskio_bytesread - initialUsage.ri_diskio_bytesread
                report["disk_bytes_written"] = finalUsage.ri_diskio_byteswritten - initialUsage.ri_diskio_byteswritten
            }
        }
        print(String(data: try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        try? FileManager.default.removeItem(at: folder)
        exit(0)
    }
    NSApp.run()
    exit(0)
}
let sampler = Sampler()
_ = sampler.sample()
let sampleCPU = cpuSeconds()
let sampleWall = ProcessInfo.processInfo.systemUptime
for _ in 0..<20 { _ = sampler.sample() }
let sampleSeconds = ProcessInfo.processInfo.systemUptime - sampleWall
let sampleCPUSeconds = cpuSeconds() - sampleCPU
let reading = sampler.sample()
func measure(visible: Bool) -> [String: Double] {
    let model = MonitorModel(persistHistory: false)
    model.layout.isVisible = visible
    let host = NSHostingController(rootView: DetailView(model: model))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 720), styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host.view
    host.view.layoutSubtreeIfNeeded()
    let bitmap = host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds)!
    let start = Date()
    for i in 0..<60 { model.recordCPU(reading, at: start.addingTimeInterval(Double(i) * 2)) }
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    let wall = ProcessInfo.processInfo.systemUptime
    let cpu = cpuSeconds()
    for i in 0..<60 {
        model.reading = reading
        model.recordCPU(reading, at: start.addingTimeInterval(120 + Double(i) * 2))
        RunLoop.current.run(until: Date().addingTimeInterval(0.003))
        host.view.layoutSubtreeIfNeeded()
        host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
    }
    let cpuElapsed = cpuSeconds() - cpu
    let elapsed = ProcessInfo.processInfo.systemUptime - wall
    window.close()
    return ["cpu_ms_per_update": cpuElapsed * 1000 / 60, "wall_ms_per_update": elapsed * 1000 / 60]
}
let hidden = measure(visible: false)
let visible = measure(visible: true)
var usage = rusage()
getrusage(RUSAGE_SELF, &usage)
let report: [String: Any] = ["sampler_cpu_ms_per_sample": sampleCPUSeconds * 1000 / 20,
    "sampler_wall_ms_per_sample": sampleSeconds * 1000 / 20,
    "hidden_detail": hidden, "visible_detail": visible, "harness_peak_rss_bytes": usage.ru_maxrss,
    "scope": "20 live samples, 60 forced offscreen UI updates per state; not whole-app CPU or Energy Impact"]
print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
