import AppKit
import Foundation

// A separate, signed executable survives the normal app shutdown. It only
// operates on a same-user application and a private staging folder beside it.
let args = CommandLine.arguments
guard args.count == 7, let pid = Int32(args[2]), pid > 1,
      let version = ReleaseVersion(args[3]), ["arm64", "x86_64"].contains(args[4]) else { exit(1) }
let target = URL(fileURLWithPath: args[1]).standardizedFileURL
let stage = URL(fileURLWithPath: args[0]).deletingLastPathComponent().standardizedFileURL
let downloads = URL(fileURLWithPath: args[5]).standardizedFileURL
L10n.useResources(at: stage.appendingPathComponent("Resources", isDirectory: true))
let language = AppLanguage(rawValue: args[6]) ?? .automatic
let candidate = stage.appendingPathComponent("Neylu.app")
let backup = stage.appendingPathComponent("Previous.app")
let fm = FileManager.default

func launch(_ app: URL) throws {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Error?
    var launched: NSRunningApplication?
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    configuration.activates = false
    NSWorkspace.shared.openApplication(at: app, configuration: configuration) { application, error in
        result = error
        launched = application
        semaphore.signal()
    }
    guard semaphore.wait(timeout: .now() + 30) == .success, result == nil else { throw UpdateFailure.operation }
    guard let launched, launched.bundleURL?.standardizedFileURL == app.standardizedFileURL else { throw UpdateFailure.launch }
    try UpdateFiles.confirmLaunch(isRunning: { kill(launched.processIdentifier, 0) == 0 },
                                  pause: { Thread.sleep(forTimeInterval: 3) })
}

do {
    let attrs = try fm.attributesOfItem(atPath: stage.path)
    guard target.deletingLastPathComponent() == stage.deletingLastPathComponent(),
          stage.lastPathComponent.hasPrefix(".Neylu-update-"), UpdateFiles.regularDirectory(stage),
          (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
          (attrs[.posixPermissions] as? NSNumber)?.intValue == 0o700,
          let parent = NSRunningApplication(processIdentifier: pid),
          parent.bundleURL?.standardizedFileURL == target,
          UpdateFiles.canReplace(target), try UpdateFiles.isUpgrade(version, from: target) else { throw UpdateFailure.destination }
    let team = try UpdateFiles.signingTeam(target)
    try UpdateFiles.validate(candidate, version: version, architecture: args[4], requiredTeam: team)
    try Data().write(to: stage.appendingPathComponent("ready"), options: .atomic)
    let deadline = Date().addingTimeInterval(120)
    while kill(pid, 0) == 0 && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
    guard kill(pid, 0) != 0 && errno == ESRCH else { throw UpdateFailure.timeout }
    // Validate again immediately before committing the replacement.
    guard try UpdateFiles.isUpgrade(version, from: target) else { throw UpdateFailure.bundle }
    try UpdateFiles.validate(candidate, version: version, architecture: args[4], requiredTeam: team)
    try UpdateFiles.install(candidate: candidate, target: target, backup: backup, launch: launch)
    try? fm.removeItem(at: stage)
    // Only remove our own private temporary download folder.
    if downloads.deletingLastPathComponent().resolvingSymlinksInPath() == fm.temporaryDirectory.resolvingSymlinksInPath(),
       downloads.lastPathComponent.hasPrefix("Neylu-update-") { try? fm.removeItem(at: downloads) }
} catch {
    // Never delete a backup if restoration failed; it remains recoverable.
    if !fm.fileExists(atPath: backup.path) { try? fm.removeItem(at: stage) }
    if kill(pid, 0) != 0 && errno == ESRCH { try? launch(target) }
    DispatchQueue.main.async {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L10n.text("update.error.title", language: language)
        let reason = UpdateFailure.describe(error, language: language)
        alert.informativeText = reason
        if fm.fileExists(atPath: backup.path) {
            alert.informativeText += "\n\n" + String(format: L10n.text("update.error.backup_location", language: language), backup.path)
        }
        alert.addButton(withTitle: L10n.text("action.ok", language: language))
        alert.runModal()
        NSApp.terminate(nil)
    }
    NSApplication.shared.run()
    exit(1)
}
