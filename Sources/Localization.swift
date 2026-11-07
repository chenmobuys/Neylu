import Foundation

// Explicit app preference; automatic resolves only among the languages we ship.
enum AppLanguage: String, CaseIterable {
    case automatic, simplifiedChinese = "zh-Hans", english = "en"

    var title: String {
        switch self {
        case .automatic: return L("language.system_default")
        case .simplifiedChinese: return L("language.simplified_chinese")
        case .english: return L("language.english")
        }
    }
    func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard self == .automatic else { return self }
        for identifier in preferredLanguages {
            let base = identifier.lowercased().replacingOccurrences(of: "_", with: "-")
            if base == "zh" || base.hasPrefix("zh-") { return .simplifiedChinese }
            if base == "en" || base.hasPrefix("en-") { return .english }
        }
        return .english
    }
    static func load(from defaults: UserDefaults = .standard) -> AppLanguage {
        AppLanguage(rawValue: defaults.string(forKey: "appLanguage") ?? "") ?? .automatic
    }
    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: "appLanguage")
    }
}

enum L10n {
    private static let lock = NSLock()
    private static var root = Bundle.main.resourceURL ?? Bundle.main.bundleURL
    private static var bundles: [String: Bundle] = [:]

    // Standalone tests and the staged updater use the same .lproj resources.
    // The app itself uses Bundle.main's standard Resources directory.
    static func useResources(at directory: URL) {
        lock.lock(); defer { lock.unlock() }
        root = directory
        bundles.removeAll()
    }
    private static func bundle(for language: AppLanguage) -> Bundle? {
        lock.lock(); defer { lock.unlock() }
        if let cached = bundles[language.rawValue] { return cached }
        let bundle = Bundle(url: root.appendingPathComponent(language.rawValue + ".lproj"))
        bundles[language.rawValue] = bundle
        return bundle
    }
    static func text(_ key: String, language: AppLanguage = AppLanguage.load(), preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        let selected = language.resolved(preferredLanguages: preferredLanguages)
        let value = bundle(for: selected)?.localizedString(forKey: key, value: nil, table: "Localizable")
        if let value, value != key { return value }
        return bundle(for: .english)?.localizedString(forKey: key, value: key, table: "Localizable") ?? key
    }
    static func cores(_ count: Int, language: AppLanguage = AppLanguage.load()) -> String {
        count == 1 ? text("metrics.one_core", language: language) : String(format: text("metrics.cores_format", language: language), String(count))
    }
    static func uptime(minutes: Int?, language: AppLanguage = AppLanguage.load()) -> String {
        guard let minutes else { return text("uptime.unavailable", language: language) }
        let days = minutes / 1440
        let hours = minutes % 1440 / 60
        let dayText = days > 0 ? String(format: text("uptime.days_format", language: language), String(days)) : ""
        let time = dayText + String(format: text("uptime.hours_minutes_format", language: language), String(hours), String(minutes % 60))
        return String(format: text("uptime.format", language: language), time)
    }
}

func L(_ key: String) -> String { L10n.text(key) }
