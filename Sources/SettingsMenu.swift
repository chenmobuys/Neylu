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
    let settings: MonitorSettings
    func makeCoordinator() -> Coordinator { Coordinator(settings: settings) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.isBordered = true
        button.bezelStyle = .accessoryBarAction
        button.preferredEdge = .maxY
        (button.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        button.menu = context.coordinator.makeMenu()
        button.imagePosition = .imageOnly
        button.menu?.items.first?.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "更多")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        button.selectItem(at: 0)
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = "单位、开机启动与更多设置"
        button.setAccessibilityLabel("更多设置")
        return button
    }
    func updateNSView(_ view: NSPopUpButton, context: Context) {
        // Keep the button, coordinator and any open NSMenu intact.
        context.coordinator.settings = settings
    }
    final class Coordinator: NSObject, NSMenuDelegate {
        var settings: MonitorSettings
        init(settings: MonitorSettings) { self.settings = settings }
        func makeMenu() -> NSMenu {
            let menu = NSMenu(title: "更多")
            menu.autoenablesItems = false
            menu.delegate = self
            // Pull-down buttons display and hide this first item automatically.
            menu.addItem(NSMenuItem(title: "", action: nil, keyEquivalent: ""))
            let units = NSMenu(title: "单位进位")
            units.autoenablesItems = false
            for basis in UnitBasis.allCases {
                let title = basis == .decimal ? "十进制（1000）" : "二进制（1024）"
                let item = NSMenuItem(title: title, action: #selector(selectBasis(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = basis.rawValue
                item.state = settings.basis == basis ? .on : .off
                units.addItem(item)
            }
            let unitItem = NSMenuItem(title: "单位进位", action: nil, keyEquivalent: "")
            unitItem.submenu = units
            menu.addItem(unitItem)
            let login = NSMenuItem(title: "开机启动", action: #selector(toggleLogin), keyEquivalent: "")
            login.tag = 1
            login.target = self
            login.state = SMAppService.mainApp.status == .enabled ? .on : .off
            menu.addItem(login)
            menu.addItem(.separator())
            let activity = NSMenuItem(title: "打开活动监视器", action: #selector(openActivity), keyEquivalent: "")
            activity.target = self
            menu.addItem(activity)
            let about = NSMenuItem(title: "关于 Neylu…", action: #selector(showAbout), keyEquivalent: "")
            about.target = self
            menu.addItem(about)
            menu.addItem(.separator())
            let quit = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "")
            quit.target = self
            menu.addItem(quit)
            return menu
        }
        func menuNeedsUpdate(_ menu: NSMenu) {
            for item in menu.items.first(where: { $0.submenu != nil })?.submenu?.items ?? [] {
                item.state = (item.representedObject as? String) == settings.basis.rawValue ? .on : .off
            }
            menu.item(withTag: 1)?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
        @objc private func selectBasis(_ sender: NSMenuItem) {
            guard let raw = sender.representedObject as? String, let basis = UnitBasis(rawValue: raw) else { return }
            settings.basis = basis
        }
        @objc private func toggleLogin() { settings.setLogin(SMAppService.mainApp.status != .enabled) }
        @objc private func openActivity() {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
        }
        @objc private func showAbout() {
            NSApp.sendAction(#selector(AppDelegate.showAbout(_:)), to: NSApp.delegate, from: self)
        }
        @objc private func quitApp() { NSApp.terminate(nil) }
    }
}

struct MonitorFooter: View {
    var body: some View {
        HStack {
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                Text(uptime).font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            Spacer()
            Text("每 2 秒更新").font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
    }
    private var uptime: String {
        guard let elapsed = elapsedSinceBoot() else { return "开机时间：—" }
        let minutes = Int(elapsed) / 60
        let days = minutes / 1440
        let hours = minutes % 1440 / 60
        return "开机时间：\(days > 0 ? "\(days) 天 " : "")\(hours) 小时 \(minutes % 60) 分钟"
    }
}

struct MonitorAlertView: View {
    @ObservedObject var alerts: MonitorAlerts
    var body: some View {
        if let message = alerts.message {
            Text(message).font(.system(size: 10.5)).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}
