import Foundation

enum RefreshInterval: Int, CaseIterable {
    case oneSecond = 1, twoSeconds = 2, fiveSeconds = 5, tenSeconds = 10

    var seconds: TimeInterval { TimeInterval(rawValue) }
    var title: String { String(format: L("units.seconds_format"), String(rawValue)) }
    static func load(from defaults: UserDefaults = .standard) -> RefreshInterval {
        RefreshInterval(rawValue: defaults.integer(forKey: "refreshInterval")) ?? .twoSeconds
    }
    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: "refreshInterval")
    }
}
