import AppKit
import Combine

// Native controls with app-owned text: the standard About panel takes some
// labels from the OS language and caches them independently of our preference.
final class AboutController: NSWindowController {
    private let version = NSTextField(labelWithString: "")
    private let summary = NSTextField(wrappingLabelWithString: "")
    private let license = NSButton()
    private let appBundle: Bundle
    private var subscriptions = Set<AnyCancellable>()

    init(settings: MonitorSettings, bundle: Bundle = .main) {
        appBundle = bundle
        let window = UtilityWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 250),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        let icon = NSImageView()
        icon.image = appBundle.url(forResource: "AppIcon", withExtension: "icns").flatMap(NSImage.init(contentsOf:))
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityLabel("Neylu")
        let name = NSTextField(labelWithString: "Neylu")
        name.font = .systemFont(ofSize: 19, weight: .semibold)
        version.font = .systemFont(ofSize: 11)
        version.textColor = .secondaryLabelColor
        summary.font = .systemFont(ofSize: 12)
        summary.alignment = .center
        let github = NSButton(title: "GitHub", target: self, action: #selector(openGitHub))
        license.target = self
        license.action = #selector(openLicense)
        for button in [github, license] {
            button.isBordered = false
            button.font = .systemFont(ofSize: 11)
            button.contentTintColor = .linkColor
        }
        let links = NSStackView(views: [github, license])
        links.orientation = .horizontal
        links.spacing = 18
        let stack = NSStackView(views: [icon, name, version, summary, links])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.setCustomSpacing(14, after: icon)
        stack.setCustomSpacing(14, after: version)
        stack.setCustomSpacing(16, after: summary)
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20),
            summary.widthAnchor.constraint(equalTo: stack.widthAnchor),
            icon.widthAnchor.constraint(equalToConstant: 64),
            icon.heightAnchor.constraint(equalToConstant: 64)
        ])
        refreshText()
        window.contentView!.layoutSubtreeIfNeeded()
        window.setContentSize(NSSize(width: 360, height: stack.fittingSize.height + 44))
        window.center()
        settings.$language.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshText() }
        }.store(in: &subscriptions)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        refreshText()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func refreshText() {
        window?.title = L("about.title")
        let release = appBundle.object(forInfoDictionaryKey: "NeyluReleaseVersion") as? String ?? "—"
        let build = appBundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        version.stringValue = String(format: L("about.version_format"), release, build)
        summary.stringValue = L("app.description")
        license.title = L("about.license")
        window?.contentView?.needsLayout = true
        window?.contentView?.layoutSubtreeIfNeeded()
    }
    @objc private func openGitHub() {
        NSWorkspace.shared.open(URL(string: "https://github.com/chenmobuys/Neylu")!)
    }
    @objc private func openLicense() {
        if let url = appBundle.url(forResource: "LICENSE", withExtension: nil) { NSWorkspace.shared.open(url) }
    }
}
