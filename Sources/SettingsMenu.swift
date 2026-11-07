import AppKit
import SwiftUI
import ServiceManagement

final class MonitorSettings: ObservableObject {
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
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
    var onMenuBarChange: (() -> Void)?
    var onLanguageChange: (() -> Void)?
    var onRefreshIntervalChange: (() -> Void)?
    var onAppearanceChange: (() -> Void)?
    var onChange: (() -> Void)?
    var onError: ((String) -> Void)?
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { onError?(error.localizedDescription) }
        loginEnabled = SMAppService.mainApp.status == .enabled
        if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
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
    }
    final class Coordinator: NSObject, NSMenuDelegate {
        var settings: MonitorSettings
        init(settings: MonitorSettings) { self.settings = settings }
        func makeMenu(pullsDown: Bool = true) -> NSMenu {
            let menu = NSMenu(title: L("menu.more"))
            menu.autoenablesItems = false
            menu.delegate = self
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
            menu.addItem(refreshItem)
            let units = NSMenu(title: L("menu.units"))
            units.autoenablesItems = false
            for basis in UnitBasis.allCases {
                let title = basis == .decimal ? L("units.decimal") : L("units.binary")
                let item = NSMenuItem(title: title, action: #selector(selectBasis(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = basis.rawValue
                item.toolTip = basis == .decimal ? L("units.decimal_hint") : L("units.binary_hint")
                item.state = settings.basis == basis ? .on : .off
                units.addItem(item)
            }
            let unitItem = NSMenuItem(title: L("menu.units"), action: nil, keyEquivalent: "")
            unitItem.tag = 2
            unitItem.submenu = units
            menu.addItem(unitItem)
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
            menu.addItem(languageItem)
            let login = NSMenuItem(title: L("menu.open_at_login"), action: #selector(toggleLogin), keyEquivalent: "")
            login.tag = 1
            login.target = self
            login.state = SMAppService.mainApp.status == .enabled ? .on : .off
            menu.addItem(login)
            menu.addItem(.separator())
            let activity = NSMenuItem(title: L("menu.activity_monitor"), action: #selector(openActivity), keyEquivalent: "")
            activity.tag = 10
            activity.target = self
            menu.addItem(activity)
            let update = NSMenuItem(title: L("menu.check_for_updates"), action: #selector(checkForUpdates), keyEquivalent: "")
            update.tag = 13
            update.target = self
            menu.addItem(update)
            let notes = NSMenuItem(title: L("menu.release_notes"), action: #selector(showReleaseNotes), keyEquivalent: "")
            notes.tag = 14
            notes.target = self
            menu.addItem(notes)
            let about = NSMenuItem(title: L("menu.about"), action: #selector(showAbout), keyEquivalent: "")
            about.tag = 11
            about.target = self
            menu.addItem(about)
            menu.addItem(.separator())
            let quit = NSMenuItem(title: L("menu.quit"), action: #selector(quitApp), keyEquivalent: "")
            quit.tag = 12
            quit.target = self
            menu.addItem(quit)
            return menu
        }
        // Mutate existing items on language changes; never replace a tracking menu.
        func updateTitles(_ menu: NSMenu?) {
            guard let menu else { return }
            menu.title = L("menu.more")
            for (tag, key) in [(1, "menu.open_at_login"), (2, "menu.units"), (3, "menu.appearance"), (4, "menu.refresh_interval"), (5, "menu.language"), (6, "menu.menu_bar_items"),
                               (10, "menu.activity_monitor"), (11, "menu.about"), (12, "menu.quit"), (13, "menu.check_for_updates"), (14, "menu.release_notes")] {
                menu.item(withTag: tag)?.title = L(key)
                menu.item(withTag: tag)?.submenu?.title = L(key)
            }
            for item in menu.item(withTag: 3)?.submenu?.items ?? [] {
                if let raw = item.representedObject as? String, let choice = AppearanceMode(rawValue: raw) { item.title = choice.title }
            }
            for item in menu.item(withTag: 4)?.submenu?.items ?? [] {
                if let raw = item.representedObject as? Int, let choice = RefreshInterval(rawValue: raw) { item.title = choice.title }
            }
            for item in menu.item(withTag: 2)?.submenu?.items ?? [] {
                if let raw = item.representedObject as? String, let choice = UnitBasis(rawValue: raw) {
                    item.title = choice == .decimal ? L("units.decimal") : L("units.binary")
                    item.toolTip = choice == .decimal ? L("units.decimal_hint") : L("units.binary_hint")
                }
            }
            for item in menu.item(withTag: 5)?.submenu?.items ?? [] {
                if let raw = item.representedObject as? String, let choice = AppLanguage(rawValue: raw) { item.title = choice.title }
            }
        }
        func menuNeedsUpdate(_ menu: NSMenu) {
            updateTitles(menu)
            for item in menu.item(withTag: 5)?.submenu?.items ?? [] {
                item.state = (item.representedObject as? String) == settings.language.rawValue ? .on : .off
            }
            for item in menu.item(withTag: 3)?.submenu?.items ?? [] {
                item.state = (item.representedObject as? String) == settings.appearanceMode.rawValue ? .on : .off
            }
            for item in menu.item(withTag: 2)?.submenu?.items ?? [] {
                item.state = (item.representedObject as? String) == settings.basis.rawValue ? .on : .off
            }
            for item in menu.item(withTag: 4)?.submenu?.items ?? [] {
                item.state = (item.representedObject as? Int) == settings.refreshInterval.rawValue ? .on : .off
            }
            menu.item(withTag: 1)?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
        @objc private func selectLanguage(_ sender: NSMenuItem) {
            guard let raw = sender.representedObject as? String, let choice = AppLanguage(rawValue: raw) else { return }
            settings.language = choice
        }
        @objc private func selectAppearance(_ sender: NSMenuItem) {
            guard let raw = sender.representedObject as? String, let mode = AppearanceMode(rawValue: raw) else { return }
            settings.appearanceMode = mode
        }
        @objc private func selectRefreshInterval(_ sender: NSMenuItem) {
            guard let raw = sender.representedObject as? Int, let interval = RefreshInterval(rawValue: raw) else { return }
            settings.refreshInterval = interval
        }
        @objc private func selectBasis(_ sender: NSMenuItem) {
            guard let raw = sender.representedObject as? String, let basis = UnitBasis(rawValue: raw) else { return }
            settings.basis = basis
        }
        @objc private func toggleLogin() { settings.setLogin(SMAppService.mainApp.status != .enabled) }
        @objc private func openActivity() {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
        }
        @objc private func showMenuBarSettings() {
            NSApp.sendAction(#selector(AppDelegate.showMenuBarSettings(_:)), to: NSApp.delegate, from: self)
        }
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
        }
    }
    private var uptime: String {
        if CommandLine.arguments.contains("--screenshot-mode") { return L10n.uptime(minutes: 2 * 1440 + 6 * 60 + 18) }
        return L10n.uptime(minutes: elapsedSinceBoot().map { Int($0) / 60 })
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
