import AppKit

/// Explicit allowlist: never serialize Reading, preferences, errors or paths.
/// In particular address, interface, disk/volume names and sample values stay out.
enum Diagnostics {
    static func report(reading: Reading, settings: MonitorSettings, historyAvailable: Bool,
                       bundle: Bundle = .main, hardware: String = cpuModelName(),
                       system: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
                       lowPower: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled,
                       detailsVisible: Bool = false) -> String {
        let language = settings.language
        func text(_ key: String) -> String { L10n.text(key, language: language) }
        func state(_ ready: Bool) -> String { text(ready ? "diagnostics.available" : "diagnostics.not_available") }
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        let interval = settings.energyMode.interval(requested: settings.refreshInterval.seconds, detailsVisible: detailsVisible, lowPower: lowPower)
        let fields: [(String, String)] = [
            ("diagnostics.version", bundle.object(forInfoDictionaryKey: "NeyluReleaseVersion") as? String ?? "—"),
            ("diagnostics.build", bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"),
            ("diagnostics.system", "macOS \(system.majorVersion).\(system.minorVersion).\(system.patchVersion)"),
            ("diagnostics.hardware", hardware), ("diagnostics.architecture", architecture),
            ("diagnostics.requested_interval", String(Int(settings.refreshInterval.seconds)) + " s"),
            ("diagnostics.effective_interval", String(Int(interval)) + " s"),
            ("menu.energy_mode", text(settings.energyMode.localizationKey)), ("diagnostics.low_power", text(lowPower ? "energy.on" : "energy.off")),
            ("history.range", text(settings.historyRange.localizationKey)), ("diagnostics.history", state(historyAvailable)),
            ("diagnostics.cpu", state(reading.cpuReady)), ("diagnostics.gpu", state(reading.gpuReady)),
            ("diagnostics.renderer", state(reading.gpuRenderer != nil)), ("diagnostics.tiler", state(reading.gpuTiler != nil)),
            ("diagnostics.memory", state(reading.memoryReady)), ("diagnostics.network", state(reading.networkReady)),
            ("diagnostics.temperature", state(reading.cpuTemperature != nil)),
            ("diagnostics.disk", state(reading.diskActivityReady))
        ]
        return "Neylu\n" + fields.map { text($0.0) + ": " + $0.1 }.joined(separator: "\n") + "\n\n" + text("diagnostics.privacy")
    }
    @discardableResult
    static func copy(_ report: String, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        return pasteboard.writeObjects([report as NSString])
    }
}
