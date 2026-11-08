import Foundation

enum EnergyMode: String, CaseIterable {
    case off, automatic, on
    var localizationKey: String {
        switch self { case .off: return "energy.off"; case .automatic: return "energy.automatic"; case .on: return "energy.on" }
    }
    var title: String { L(localizationKey) }
    static func load(from defaults: UserDefaults = .standard) -> Self {
        Self(rawValue: defaults.string(forKey: "energyMode") ?? "") ?? .off
    }
    func save(to defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: "energyMode") }
    func interval(requested: TimeInterval, detailsVisible: Bool, lowPower: Bool) -> TimeInterval {
        guard !detailsVisible, self == .on || (self == .automatic && lowPower) else { return requested }
        return max(5, requested)
    }
}

struct SamplingDemand: Equatable {
    var details = true
    var systemDisk = true
    var temperature = false
    var needsTemperature: Bool { details || temperature }
    static let full = SamplingDemand()
}

/// Cache display-only addresses, never the counters used to calculate rates.
struct NetworkAddressCache {
    private var cached: (name: String, value: String, expires: TimeInterval)?
    mutating func invalidate() { cached = nil }
    mutating func address(for name: String, now: TimeInterval, read: () -> String) -> String {
        if let cached, cached.name == name, now < cached.expires { return cached.value }
        let value = read()
        cached = (name, value, now + 10)
        return value
    }
}
