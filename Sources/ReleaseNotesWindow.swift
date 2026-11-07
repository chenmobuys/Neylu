import AppKit
import Combine

/// Installed-version notes stay local and independent of an in-progress update.
final class ReleaseNotesController: NSWindowController {
    private let heading = NSTextField(wrappingLabelWithString: "")
    private let notes = NSTextView()
    private let website = NSButton()
    private let done = NSButton()
    private let appBundle: Bundle
    private var afterUpdate = false
    private var subscriptions = Set<AnyCancellable>()

    init(settings: MonitorSettings, bundle: Bundle = .main) {
        appBundle = bundle
        let window = UtilityWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 334),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.isReleasedWhenClosed = false
        let icon = NSImageView()
        icon.image = bundle.url(forResource: "AppIcon", withExtension: "icns").flatMap(NSImage.init(contentsOf:))
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityLabel("Neylu")
        heading.font = .systemFont(ofSize: 14, weight: .semibold)
        let header = NSStackView(views: [icon, heading])
        header.orientation = .horizontal
        header.spacing = 14
        header.alignment = .centerY
        notes.frame = NSRect(x: 0, y: 0, width: 372, height: 180)
        notes.minSize = .zero
        notes.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        notes.isVerticallyResizable = true
        notes.isHorizontallyResizable = false
        notes.autoresizingMask = [.width]
        notes.textContainer?.widthTracksTextView = true
        notes.textContainerInset = NSSize(width: 0, height: 4)
        notes.textContainer?.lineFragmentPadding = 0
        notes.isEditable = false
        notes.isSelectable = true
        notes.drawsBackground = false
        notes.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
        let scroll = NSScrollView()
        scroll.documentView = notes
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        website.target = self
        website.action = #selector(openChangelog)
        website.isBordered = false
        website.font = .systemFont(ofSize: 11)
        website.contentTintColor = .linkColor
        done.target = self
        done.action = #selector(dismiss)
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [website, spacer, done])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let stack = NSStackView(views: [header, scroll, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -24),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            icon.widthAnchor.constraint(equalToConstant: 40),
            icon.heightAnchor.constraint(equalToConstant: 40),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 180),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        refreshText()
        window.contentView!.layoutSubtreeIfNeeded()
        window.setContentSize(NSSize(width: 420, height: stack.fittingSize.height + 48))
        window.center()
        settings.$language.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshText() }
        }.store(in: &subscriptions)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present(afterUpdate: Bool = false) {
        self.afterUpdate = afterUpdate
        refreshText()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func refreshText() {
        window?.title = L(afterUpdate ? "whats_new.title" : "menu.release_notes")
        let version = appBundle.object(forInfoDictionaryKey: "NeyluReleaseVersion") as? String ?? "—"
        heading.stringValue = String(format: L(afterUpdate ? "whats_new.updated_format" : "whats_new.version_format"), version)
        website.title = L("whats_new.full_changelog")
        done.title = L("whats_new.continue")
        let markdown = appBundle.url(forResource: "ReleaseNotes", withExtension: "md").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        notes.textStorage?.setAttributedString(ReleaseNotesRenderer.render(markdown.map { ReleaseNotesText.localized($0, language: AppLanguage.load()) } ?? L("whats_new.unavailable")))
    }
    @objc private func dismiss() { close() }
    @objc private func openChangelog() {
        NSWorkspace.shared.open(URL(string: "https://github.com/chenmobuys/Neylu/blob/main/CHANGELOG.md")!)
    }
}
