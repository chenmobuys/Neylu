import AppKit
import Combine

/// Read the exact notices shipped with this installation, without launching
/// another application or requiring a network connection.
final class LicenseController: NSWindowController {
    private let heading = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(wrappingLabelWithString: "")
    private let sections = NSSegmentedControl()
    private let text = NSTextView()
    private let copy = NSButton()
    private let done = NSButton()
    private let appBundle: Bundle
    private var subscriptions = Set<AnyCancellable>()
    private var documentText: String?

    init(settings: MonitorSettings, bundle: Bundle = .main) {
        appBundle = bundle
        let window = UtilityWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 540),
                                   styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 460, height: 400)
        let icon = NSImageView()
        icon.image = bundle.url(forResource: "AppIcon", withExtension: "icns").flatMap(NSImage.init(contentsOf:))
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityLabel("Neylu")
        heading.font = .systemFont(ofSize: 17, weight: .semibold)
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        let titles = NSStackView(views: [heading, subtitle])
        titles.orientation = .vertical; titles.alignment = .leading; titles.spacing = 4
        let header = NSStackView(views: [icon, titles])
        header.orientation = .horizontal; header.alignment = .centerY; header.spacing = 12
        sections.segmentCount = 2
        sections.trackingMode = .selectOne
        sections.segmentStyle = .rounded
        sections.selectedSegment = 0
        sections.target = self; sections.action = #selector(changeSection)
        sections.setContentHuggingPriority(.required, for: .vertical)
        text.frame = NSRect(x: 0, y: 0, width: 492, height: 340)
        text.minSize = .zero
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.lineFragmentPadding = 0
        text.textContainerInset = NSSize(width: 0, height: 8)
        text.isEditable = false; text.isSelectable = true; text.drawsBackground = false
        text.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
        let scroll = NSScrollView()
        scroll.documentView = text; scroll.hasVerticalScroller = true
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        copy.bezelStyle = .rounded; copy.target = self; copy.action = #selector(copyDocument)
        done.bezelStyle = .rounded; done.target = self; done.action = #selector(dismiss)
        done.keyEquivalent = "\r"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [copy, spacer, done])
        footer.orientation = .horizontal; footer.spacing = 8
        let separator = NSBox(); separator.boxType = .separator
        let stack = NSStackView(views: [header, sections, scroll, separator, footer])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -20),
            icon.widthAnchor.constraint(equalToConstant: 36), icon.heightAnchor.constraint(equalToConstant: 36),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        refreshText()
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
        window?.title = L("about.license")
        heading.stringValue = L("licenses.title")
        subtitle.stringValue = L("licenses.subtitle")
        sections.setLabel(L("licenses.mit"), forSegment: 0)
        sections.setLabel(L("licenses.third_party"), forSegment: 1)
        sections.setAccessibilityLabel(L("licenses.sections"))
        copy.title = L("licenses.copy")
        done.title = L("action.close")
        refreshDocument(resetScroll: false)
    }
    @objc private func changeSection() { refreshDocument(resetScroll: true) }
    private func refreshDocument(resetScroll: Bool) {
        let thirdParty = sections.selectedSegment == 1
        let url = appBundle.url(forResource: thirdParty ? "THIRD_PARTY_NOTICES" : "LICENSE", withExtension: thirdParty ? "md" : nil)
        documentText = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        copy.isEnabled = documentText != nil
        text.setAccessibilityLabel(L(thirdParty ? "licenses.third_party" : "licenses.mit"))
        let content = documentText ?? L("licenses.unavailable")
        if thirdParty, documentText != nil {
            text.textStorage?.setAttributedString(ReleaseNotesRenderer.render(content))
        } else {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4
            // Unwrap the source file's fixed-width lines for readable resizing;
            // copying still returns the exact bundled original.
            let display = content.components(separatedBy: "\n\n").map {
                $0.split(separator: "\n").joined(separator: " ")
            }.joined(separator: "\n\n")
            let attributed = NSMutableAttributedString(string: display, attributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph
            ])
            if documentText != nil {
                let titleRange = (display as NSString).lineRange(for: NSRange(location: 0, length: 0))
                attributed.addAttribute(.font, value: NSFont.systemFont(ofSize: 14, weight: .semibold), range: titleRange)
            }
            text.textStorage?.setAttributedString(attributed)
        }
        if resetScroll { text.scrollRangeToVisible(NSRange(location: 0, length: 0)) }
    }
    @objc private func copyDocument() {
        guard let documentText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(documentText, forType: .string)
    }
    @objc private func dismiss() { close() }
}
