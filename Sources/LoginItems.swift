import AppKit
import ServiceManagement

enum LoginItemState { case disabled, enabled, requiresApproval }
protocol LoginItemService {
    var state: LoginItemState { get }
    func setEnabled(_ enabled: Bool) throws
}

/// Native ServiceManagement on both paths; no LaunchAgent files or shell commands.
struct SystemLoginItems: LoginItemService {
    static let helperIdentifier = "io.github.chenmobuys.Neylu.LoginHelper"
    var state: LoginItemState {
        if #available(macOS 13.0, *) {
            let main = SMAppService.mainApp.status
            let helper = SMAppService.loginItem(identifier: Self.helperIdentifier).status
            if main == .enabled || helper == .enabled { return .enabled }
            if main == .requiresApproval || helper == .requiresApproval { return .requiresApproval }
            return .disabled
        }
        return LegacyLoginItems.enabled ? .enabled : .disabled
    }
    func setEnabled(_ enabled: Bool) throws {
        if #available(macOS 13.0, *) {
            let main = SMAppService.mainApp
            let helper = SMAppService.loginItem(identifier: Self.helperIdentifier)
            if enabled {
                if main.status != .enabled && main.status != .requiresApproval { try main.register() }
                if main.status == .enabled && helper.status == .enabled { try helper.unregister() }
                if main.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            } else {
                if main.status == .enabled || main.status == .requiresApproval { try main.unregister() }
                if helper.status == .enabled || helper.status == .requiresApproval { try helper.unregister() }
            }
        } else if !LegacyLoginItems.setEnabled(enabled) {
            throw NSError(domain: "io.github.chenmobuys.Neylu.LoginItems", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: L("login.change_failed")])
        }
    }
}

@available(macOS, introduced: 12.0, deprecated: 13.0)
private enum LegacyLoginItems {
    static var enabled: Bool {
        guard let job = SMJobCopyDictionary(kSMDomainUserLaunchd, SystemLoginItems.helperIdentifier as CFString)?.takeRetainedValue() as? [String: Any] else { return false }
        return job["OnDemand"] as? Bool ?? false
    }
    static func setEnabled(_ enabled: Bool) -> Bool {
        SMLoginItemSetEnabled(SystemLoginItems.helperIdentifier as CFString, enabled)
    }
}
