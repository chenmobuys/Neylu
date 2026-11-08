import Foundation

enum MenuBarMetric: String, CaseIterable {
    case network, memory, gpu, cpu, disk, temperature
    var title: String {
        switch self {
        case .network: return L("metrics.network_speed")
        case .memory: return L("metrics.memory")
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .disk: return L("menu_bar.startup_disk_usage")
        case .temperature: return L("metrics.cpu_temperature")
        }
    }
    var symbol: String {
        switch self {
        case .network: return "network"
        case .memory: return "memorychip"
        case .cpu: return "cpu"
        case .gpu: return "cpu"
        case .disk: return "internaldrive"
        case .temperature: return "thermometer"
        }
    }
    var shortLabel: String {
        switch self {
        case .network: return "NET"
        case .memory: return "MEM"
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .disk: return "DSK"
        case .temperature: return "TEMP"
        }
    }
}

struct MenuBarItem: Equatable {
    let metric: MenuBarMetric
    var enabled: Bool
}

enum MenuBarDensity: String, CaseIterable {
    case compact, standard
    var title: String {
        switch self {
        case .compact: return L("menu_bar.density.compact")
        case .standard: return L("menu_bar.density.standard")
        }
    }
}

struct MenuBarConfiguration: Equatable {
    var density: MenuBarDensity
    private(set) var items: [MenuBarItem]
    static let defaults = MenuBarConfiguration(items: MenuBarMetric.allCases.map {
        MenuBarItem(metric: $0, enabled: $0 != .disk && $0 != .temperature)
    })
    init(items: [MenuBarItem], density: MenuBarDensity = .compact) {
        self.density = density
        var seen = Set<MenuBarMetric>()
        self.items = items.filter { seen.insert($0.metric).inserted }
        self.items += MenuBarMetric.allCases.filter { !seen.contains($0) }.map { MenuBarItem(metric: $0, enabled: false) }
    }
    var visibleMetrics: [MenuBarMetric] { items.filter(\.enabled).map(\.metric) }
    mutating func setEnabled(_ enabled: Bool, for metric: MenuBarMetric) {
        guard let index = items.firstIndex(where: { $0.metric == metric }) else { return }
        items[index].enabled = enabled
    }
    mutating func move(_ metric: MenuBarMetric, to insertionRow: Int) {
        guard let source = items.firstIndex(where: { $0.metric == metric }), (0...items.count).contains(insertionRow) else { return }
        let item = items.remove(at: source)
        items.insert(item, at: insertionRow > source ? insertionRow - 1 : insertionRow)
    }
    static func load(from defaults: UserDefaults = .standard) -> MenuBarConfiguration {
        guard let stored = defaults.array(forKey: "menuBarItems") as? [[String: Any]] else { return .defaults }
        let items = stored.compactMap { record -> MenuBarItem? in
            guard let raw = record["metric"] as? String, let metric = MenuBarMetric(rawValue: raw), let enabled = record["enabled"] as? Bool else { return nil }
            return MenuBarItem(metric: metric, enabled: enabled)
        }
        if !stored.isEmpty && items.isEmpty { return .defaults }
        return MenuBarConfiguration(items: items, density: MenuBarDensity(rawValue: defaults.string(forKey: "menuBarDensity") ?? "") ?? .compact)
    }
    func save(to defaults: UserDefaults = .standard) {
        defaults.set(density.rawValue, forKey: "menuBarDensity")
        defaults.set(items.map { ["metric": $0.metric.rawValue, "enabled": $0.enabled] as [String: Any] }, forKey: "menuBarItems")
    }
}
