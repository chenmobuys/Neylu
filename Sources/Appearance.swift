import AppKit

// The order is also the order presented in the native settings submenu.
enum AppearanceMode: String, CaseIterable {
    case automatic, light, dark

    var title: String {
        switch self {
        case .automatic: return L("appearance.automatic")
        case .light: return L("appearance.light")
        case .dark: return L("appearance.dark")
        }
    }
    var appKitAppearance: NSAppearance? {
        switch self {
        case .automatic: return nil // nil lets AppKit track system changes.
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
    static func load(from defaults: UserDefaults = .standard) -> AppearanceMode {
        AppearanceMode(rawValue: defaults.string(forKey: "appearanceMode") ?? "") ?? .automatic
    }
    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: "appearanceMode")
    }
}
