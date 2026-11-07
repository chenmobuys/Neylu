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
if CommandLine.arguments.contains("--idle-process") {
    // Run the actual delegate and normal two-second sampling timer in isolation.
    // The injected model never opens the user's history database.
    let delegate = AppDelegate(model: MonitorModel(persistHistory: false))
    NSApp.delegate = delegate
    var startCPU = 0.0
    var startWall = 0.0
    Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { _ in
        startCPU = cpuSeconds()
        startWall = ProcessInfo.processInfo.systemUptime
    }
    Timer.scheduledTimer(withTimeInterval: 16, repeats: false) { _ in
        let elapsed = ProcessInfo.processInfo.systemUptime - startWall
        let consumed = cpuSeconds() - startCPU
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-o", "rss=", "-p", String(getpid())]
        let pipe = Pipe()
        ps.standardOutput = pipe
        try! ps.run()
        let residentKB = Int(String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))!
        ps.waitUntilExit()
        let report: [String: Any] = ["elapsed_seconds": elapsed, "cpu_percent_of_one_core": consumed / elapsed * 100,
            "resident_memory_bytes": residentKB * 1024, "history_persistence": false,
            "scope": "actual app delegate, menu bar rendering and default sampling timer; 15-second idle sample, not Energy Impact or power in watts"]
        print(String(data: try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
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
