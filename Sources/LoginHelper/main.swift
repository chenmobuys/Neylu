import AppKit

// ServiceManagement launches this small bundled helper on macOS 12.
// Resolve only its enclosing app; never accept an arbitrary executable path.
let identifier = "io.github.chenmobuys.Neylu"
var mainURL = Bundle.main.bundleURL
for _ in 0..<4 { mainURL.deleteLastPathComponent() }
guard mainURL.pathExtension == "app", Bundle(url: mainURL)?.bundleIdentifier == identifier else { exit(1) }
if NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    NSWorkspace.shared.openApplication(at: mainURL, configuration: configuration) { _, error in exit(error == nil ? 0 : 1) }
    app.run()
}
