import AppKit
import SwiftUI

final class MonitorSettings: ObservableObject {
    private let loginService: LoginItemService
    @Published private(set) var loginState: LoginItemState = .disabled
    var loginEnabled: Bool { loginState == .enabled }
    init(loginService: LoginItemService = SystemLoginItems()) {
        self.loginService = loginService
        refreshLoginStatus()
    }
    func refreshLoginStatus() {
        let value = loginService.state
        if value != loginState { loginState = value }
    }
    @Published var basis = UnitBasis(rawValue: UserDefaults.standard.string(forKey: "unitBasis") ?? "") ?? .decimal {
        didSet {
            guard basis != oldValue else { return }
            UserDefaults.standard.set(basis.rawValue, forKey: "unitBasis")
            onChange?()
        }
    }
    @Published var appearanceMode = AppearanceMode.load() {
        didSet {
            guard appearanceMode != oldValue else { return }
            appearanceMode.save()
            onAppearanceChange?()
        }
    }
    @Published var refreshInterval = RefreshInterval.load() {
        didSet {
            guard refreshInterval != oldValue else { return }
            refreshInterval.save()
            onRefreshIntervalChange?()
        }
    }
    @Published var energyMode = EnergyMode.load() {
        didSet { guard energyMode != oldValue else { return }; energyMode.save(); onRefreshIntervalChange?() }
    }
    @Published var historyRange = HistoryRange.load() {
        didSet { guard historyRange != oldValue else { return }; historyRange.save(); onHistoryRangeChange?() }
    }
    var onHistoryRangeChange: (() -> Void)?
    @Published var language = AppLanguage.load() {
        didSet {
            guard language != oldValue else { return }
            language.save()
            onLanguageChange?()
        }
    }
    @Published var menuBarConfiguration = MenuBarConfiguration.load() {
        didSet {
            guard menuBarConfiguration != oldValue else { return }
            menuBarConfiguration.save()
            onMenuBarChange?()
        }
    }
    @Published var hideNetworkAddress = UserDefaults.standard.bool(forKey: "hideNetworkAddress") {
        didSet { UserDefaults.standard.set(hideNetworkAddress, forKey: "hideNetworkAddress") }
    }
    func restoreMenuBarLayout() { menuBarConfiguration = .defaults }
    @Published var availableUpdateVersion: String?
    @Published var automaticUpdateChecks = UserDefaults.standard.object(forKey: "automaticUpdateChecks") as? Bool ?? true {
        didSet {
            guard automaticUpdateChecks != oldValue else { return }
            UserDefaults.standard.set(automaticUpdateChecks, forKey: "automaticUpdateChecks")
            onAutomaticUpdateChange?()
        }
    }
    var diagnosticsProvider: (() -> String)?
    @discardableResult func copyDiagnostics(to pasteboard: NSPasteboard = .general) -> Bool {
        guard let report = diagnosticsProvider?() else { return false }
        return Diagnostics.copy(report, to: pasteboard)
    }
    var onAutomaticUpdateChange: (() -> Void)?
    var onConfigureShortcut: (() -> Void)?
    var onMenuBarChange: (() -> Void)?
    var onLanguageChange: (() -> Void)?
    var onRefreshIntervalChange: (() -> Void)?
    var onAppearanceChange: (() -> Void)?
    var onChange: (() -> Void)?
    var onError: ((String) -> Void)?
    func setLogin(_ enabled: Bool) {
        do { try loginService.setEnabled(enabled) }
        catch { onError?(error.localizedDescription) }
        refreshLoginStatus()
    }
}

final class MonitorAlerts: ObservableObject {
    @Published var message: String?
}

// AppKit owns press feedback, menu placement and tracking. Live samples never
// replace the control or its menu; checkmarks update only before opening.
struct SettingsMenuButton: NSViewRepresentable {
    @ObservedObject var settings: MonitorSettings
    func makeCoordinator() -> Coordinator { Coordinator(settings: settings) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.isBordered = true
        button.bezelStyle = .accessoryBarAction
        button.preferredEdge = .maxY
        (button.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        button.menu = context.coordinator.makeMenu()
        button.imagePosition = .imageOnly
        button.menu?.items.first?.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: L("menu.more"))?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        button.selectItem(at: 0)
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = L("menu.settings_hint")
        button.setAccessibilityLabel(L("menu.more_settings"))
        return button
    }
    func updateNSView(_ view: NSPopUpButton, context: Context) {
        // Keep the button, coordinator and any open NSMenu intact.
        context.coordinator.settings = settings
        context.coordinator.updateTitles(view.menu)
        view.toolTip = L("menu.settings_hint")
        view.setAccessibilityLabel(L("menu.more_settings"))
        view.setAccessibilityValue(settings.availableUpdateVersion.map { String(format: L("menu.update_available_format"), $0) })
    }
    final class Coordinator: NSObject, NSMenuDelegate {
        var settings: MonitorSettings
        init(settings: MonitorSettings) { self.settings = settings }
        func makeMenu(pullsDown: Bool = true) -> NSMenu {
            let menu = NSMenu(title: L("menu.more"))
            menu.autoenablesItems = false
            menu.delegate = self
            let preferences = NSMenu(title: L("menu.preferences"))
            // Pull-down buttons display and hide this first item automatically.
            if pullsDown { menu.addItem(NSMenuItem(title: "", action: nil, keyEquivalent: "")) }
            let menuBar = NSMenuItem(title: L("menu.menu_bar_items"), action: #selector(showMenuBarSettings), keyEquivalent: "")
            menuBar.tag = 6
            menuBar.target = self
            menu.addItem(menuBar)
            let appearance = NSMenu(title: L("menu.appearance"))
            appearance.autoenablesItems = false
            for mode in AppearanceMode.allCases {
                let item = NSMenuItem(title: mode.title, action: #selector(selectAppearance(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = mode.rawValue
                item.state = settings.appearanceMode == mode ? .on : .off
                appearance.addItem(item)
            }
            let appearanceItem = NSMenuItem(title: L("menu.appearance"), action: nil, keyEquivalent: "")
            appearanceItem.tag = 3
            appearanceItem.submenu = appearance
            menu.addItem(appearanceItem)
            let preferencesItem = NSMenuItem(title: L("menu.preferences"), action: nil, keyEquivalent: "")
            preferencesItem.tag = 16
            preferencesItem.submenu = preferences
            menu.addItem(preferencesItem)
            let refresh = NSMenu(title: L("menu.refresh_interval"))
            refresh.autoenablesItems = false
            for interval in RefreshInterval.allCases {
                let item = NSMenuItem(title: interval.title, action: #selector(selectRefreshInterval(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = interval.rawValue
                item.state = settings.refreshInterval == interval ? .on : .off
                refresh.addItem(item)
            }
            let refreshItem = NSMenuItem(title: L("menu.refresh_interval"), action: nil, keyEquivalent: "")
            refreshItem.tag = 4
            refreshItem.submenu = refresh
            preferences.addItem(refreshItem)
            let range = NSMenu(title: L("history.range"))
            for choice in HistoryRange.allCases {
                let option = NSMenuItem(title: choice.title, action: #selector(selectHistoryRange(_:)), keyEquivalent: "")
                option.target = self; option.representedObject = choice.rawValue
                option.state = settings.historyRange == choice ? .on : .off
                range.addItem(option)
            }
            let rangeItem = NSMenuItem(title: L("history.range"), action: nil, keyEquivalent: "")
            rangeItem.tag = 20; rangeItem.submenu = range
            rangeItem.toolTip = L("history.range_hint")
            preferences.addItem(rangeItem)
            let energy = NSMenu(title: L("menu.energy_mode"))
            for mode in EnergyMode.allCases {
                let option = NSMenuItem(title: mode.title, action: #selector(selectEnergyMode(_:)), keyEquivalent: "")
                option.target = self; option.representedObject = mode.rawValue
                energy.addItem(option)
            }
            let energyItem = NSMenuItem(title: L("menu.energy_mode"), action: nil, keyEquivalent: "")
            energyItem.tag = 17; energyItem.submenu = energy
            energyItem.toolTip = L("energy.hint")
            preferences.addItem(energyItem)
            let units = NSMenu(title: L("menu.units"))
            for basis in UnitBasis.allCases {
                let option = NSMenuItem(title: L(basis == .decimal ? "units.decimal" : "units.binary"), action: #selector(selectBasis(_:)), keyEquivalent: "")
                option.target = self; option.representedObject = basis.rawValue
                units.addItem(option)
            }
            let unitsItem = NSMenuItem(title: L("menu.units"), action: nil, keyEquivalent: "")
            unitsItem.tag = 2; unitsItem.submenu = units
            preferences.addItem(unitsItem)
            let shortcut = NSMenuItem(title: L("shortcut.configure"), action: #selector(configureShortcut), keyEquivalent: "")
            shortcut.tag = 19; shortcut.target = self; preferences.addItem(shortcut)
            let language = NSMenu(title: L("menu.language"))
            language.autoenablesItems = false
            for choice in AppLanguage.allCases {
                let item = NSMenuItem(title: choice.title, action: #selector(selectLanguage(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = choice.rawValue
                item.state = settings.language == choice ? .on : .off
                language.addItem(item)
            }
            let languageItem = NSMenuItem(title: L("menu.language"), action: nil, keyEquivalent: "")
            languageItem.tag = 5
            languageItem.submenu = language
            preferences.addItem(languageItem)
            preferences.addItem(.separator())
            let login = NSMenuItem(title: L("menu.open_at_login"), action: #selector(toggleLogin), keyEquivalent: "")
            login.tag = 1
            login.target = self
            login.state = settings.loginEnabled ? .on : .off
            preferences.addItem(login)
            menu.addItem(.separator())
            let activity = NSMenuItem(title: L("menu.activity_monitor"), action: #selector(openActivity), keyEquivalent: "")
            activity.tag = 10
            activity.target = self
            menu.addItem(activity)
            menu.addItem(.separator())
            let update = NSMenuItem(title: L("menu.check_for_updates"), action: #selector(checkForUpdates), keyEquivalent: "")
            update.tag = 13
            update.target = self
            menu.addItem(update)
            let automatic = NSMenuItem(title: L("menu.automatic_updates"), action: #selector(toggleAutomaticUpdates), keyEquivalent: "")
            automatic.tag = 15
            automatic.target = self
            preferences.addItem(automatic)
            let notes = NSMenuItem(title: L("menu.release_notes"), action: #selector(showReleaseNotes), keyEquivalent: "")
            notes.tag = 14
            notes.target = self
            menu.addItem(notes)
            let diagnostics = NSMenuItem(title: L("menu.copy_diagnostics"), action: #selector(copyDiagnostics), keyEquivalent: "")
            diagnostics.tag = 18; diagnostics.target = self
            menu.addItem(diagnostics)
            let about = NSMenuItem(title: L("menu.about"), action: #selector(showAbout), keyEquivalent: "")
            about.tag = 11
            about.target = self
            menu.addItem(about)
            menu.addItem(.separator())
            let quit = NSMenuItem(title: L("menu.quit"), action: #selector(quitApp), keyEquivalent: "")
            quit.tag = 12
            quit.target = self
            menu.addItem(quit)
            configureDelegates(menu)
            menuNeedsUpdate(menu)
            return menu
        }
        func item(_ tag: Int, in menu: NSMenu?) -> NSMenuItem? {
            for candidate in menu?.items ?? [] {
                if candidate.tag == tag { return candidate }
                if let found = item(tag, in: candidate.submenu) { return found }
            }
            return nil
        }
        private func configureDelegates(_ menu: NSMenu) {
            menu.delegate = self
            menu.autoenablesItems = false
            for item in menu.items { if let child = item.submenu { configureDelegates(child) } }
        }
        // Mutate existing items on language changes; never replace a tracking menu.
        func updateTitles(_ menu: NSMenu?) {
            guard let menu else { return }
            menu.title = L("menu.more")
            for (tag, key) in [(1, "menu.open_at_login"), (3, "menu.appearance"), (4, "menu.refresh_interval"), (5, "menu.language"), (6, "menu.menu_bar_items"),
                               (10, "menu.activity_monitor"), (11, "menu.about"), (12, "menu.quit"), (13, "menu.check_for_updates"), (14, "menu.release_notes"), (15, "menu.automatic_updates"), (16, "menu.preferences"), (17, "menu.energy_mode"), (18, "menu.copy_diagnostics"), (19, "shortcut.configure"), (20, "history.range"), (2, "menu.units")] {
                item(tag, in: menu)?.title = L(key)
                item(tag, in: menu)?.submenu?.title = L(key)
            }
            if let version = settings.availableUpdateVersion {
                item(13, in: menu)?.title = String(format: L("menu.update_available_format"), version)
            }
            item(17, in: menu)?.toolTip = L("energy.hint")
            item(20, in: menu)?.toolTip = L("history.range_hint")
            for option in item(2, in: menu)?.submenu?.items ?? [] {
                if let basis = (option.representedObject as? String).flatMap(UnitBasis.init(rawValue:)) {
                    option.title = L(basis == .decimal ? "units.decimal" : "units.binary")
                    option.toolTip = L(basis == .decimal ? "units.decimal_hint" : "units.binary_hint")
                    option.state = settings.basis == basis ? .on : .off
                }
            }
            for option in item(20, in: menu)?.submenu?.items ?? [] {
                if let choice = (option.representedObject as? Int).flatMap(HistoryRange.init(rawValue:)) {
                    option.title = choice.title
                    option.state = settings.historyRange == choice ? .on : .off
                }
            }
            item(15, in: menu)?.state = settings.automaticUpdateChecks ? .on : .off
            for item in item(3, in: menu)?.submenu?.items ?? [] {
                if let raw = item.representedObject as? String, let choice = AppearanceMode(rawValue: raw) { item.title = choice.title }
            }
            for item in item(4, in: menu)?.submenu?.items ?? [] {
                if let raw = item.representedObject as? Int, let choice = RefreshInterval(rawValue: raw) { item.title = choice.title }
            }
            for option in item(17, in: menu)?.submenu?.items ?? [] {
                if let mode = (option.representedObject as? String).flatMap(EnergyMode.init) {
                    option.title = mode.title; option.state = settings.energyMode == mode ? .on : .off
                }
            }
            for item in item(5, in: menu)?.submenu?.items ?? [] {
                if let raw = item.representedObject as? String, let choice = AppLanguage(rawValue: raw) { item.title = choice.title }
            }
        }
        func menuNeedsUpdate(_ trackingMenu: NSMenu) {
            var menu = trackingMenu
            while let parent = menu.supermenu { menu = parent }
            settings.refreshLoginStatus()
            updateTitles(menu)
            for item in item(5, in: menu)?.submenu?.items ?? [] {
                item.state = (item.representedObject as? String) == settings.language.rawValue ? .on : .off
            }
            for item in item(3, in: menu)?.submenu?.items ?? [] {
                item.state = (item.representedObject as? String) == settings.appearanceMode.rawValue ? .on : .off
            }
            for item in item(4, in: menu)?.submenu?.items ?? [] {
                item.state = (item.representedObject as? Int) == settings.refreshInterval.rawValue ? .on : .off
            }
            item(1, in: menu)?.state = settings.loginState == .requiresApproval ? .mixed : (settings.loginEnabled ? .on : .off)
            item(1, in: menu)?.toolTip = settings.loginState == .requiresApproval ? L("login.approval_hint") : nil
        }
        @objc private func copyDiagnostics() { settings.copyDiagnostics() }
        @objc private func selectLanguage(_ sender: NSMenuItem) {
            guard let raw = sender.representedObject as? String, let choice = AppLanguage(rawValue: raw) else { return }
            settings.language = choice
        }
        @objc private func selectAppearance(_ sender: NSMenuItem) {
            guard let raw = sender.representedObject as? String, let mode = AppearanceMode(rawValue: raw) else { return }
            settings.appearanceMode = mode
        }
        @objc private func configureShortcut() { settings.onConfigureShortcut?() }
        @objc private func selectEnergyMode(_ sender: NSMenuItem) {
            guard let raw = sender.representedObject as? String, let mode = EnergyMode(rawValue: raw) else { return }
            settings.energyMode = mode
        }
        @objc private func selectBasis(_ sender: NSMenuItem) {
            guard let raw = sender.representedObject as? String, let basis = UnitBasis(rawValue: raw) else { return }
            settings.basis = basis
        }
        @objc private func selectHistoryRange(_ sender: NSMenuItem) {
            guard let raw = sender.representedObject as? Int, let choice = HistoryRange(rawValue: raw) else { return }
            settings.historyRange = choice
        }
        @objc private func selectRefreshInterval(_ sender: NSMenuItem) {
            guard let raw = sender.representedObject as? Int, let interval = RefreshInterval(rawValue: raw) else { return }
            settings.refreshInterval = interval
        }

        @objc private func toggleLogin() { settings.setLogin(!settings.loginEnabled) }
        @objc private func openActivity() {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
        }
        @objc private func showMenuBarSettings() {
            NSApp.sendAction(#selector(AppDelegate.showMenuBarSettings(_:)), to: NSApp.delegate, from: self)
        }
        @objc private func toggleAutomaticUpdates() { settings.automaticUpdateChecks.toggle() }
        @objc private func checkForUpdates() {
            NSApp.sendAction(#selector(AppDelegate.checkForUpdates(_:)), to: NSApp.delegate, from: self)
        }
        @objc private func showReleaseNotes() {
            NSApp.sendAction(#selector(AppDelegate.showReleaseNotes(_:)), to: NSApp.delegate, from: self)
        }
        @objc private func showAbout() {
            NSApp.sendAction(#selector(AppDelegate.showAbout(_:)), to: NSApp.delegate, from: self)
        }
        @objc private func quitApp() { NSApp.terminate(nil) }
    }
}

struct MonitorFooter: View {
    @ObservedObject var settings: MonitorSettings
    var body: some View {
        HStack {
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                Text(uptime).font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            Spacer()
            SettingsMenuButton(settings: settings).frame(width: 26, height: 24)
                .overlay(alignment: .topTrailing) {
                    if settings.availableUpdateVersion != nil {
                        Circle().fill(.tint).frame(width: 5, height: 5).allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .accessibilityHint(settings.availableUpdateVersion.map { String(format: L("menu.update_available_format"), $0) } ?? L("menu.settings_hint"))
        }
    }
    private var uptime: String {
        #if NEYLU_PREVIEW
        return L10n.uptime(minutes: 2 * 1440 + 6 * 60 + 18)
        #else
        return L10n.uptime(minutes: elapsedSinceBoot().map { Int($0) / 60 })
        #endif
    }
}

struct MonitorAlertView: View {
    @ObservedObject var alerts: MonitorAlerts
    var onSizeChange: (() -> Void)?
    var body: some View {
        Group {
            if let message = alerts.message {
                Text(message).font(.system(size: 10.5)).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .onReceive(alerts.$message.dropFirst()) { _ in DispatchQueue.main.async { onSizeChange?() } }
    }
}
