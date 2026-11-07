import AppKit

/// Foundation parses Markdown; AppKit supplies native typography without web content.
enum ReleaseNotesRenderer {
    static func render(_ markdown: String) -> NSAttributedString {
        let base: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor]
        guard let parsed = try? AttributedString(markdown: markdown, options: .init(allowsExtendedAttributes: false, interpretedSyntax: .full)) else {
            return NSAttributedString(string: markdown, attributes: base)
        }
        let result = NSMutableAttributedString()
        var previousBlock: Int?
        var previousItem: Int?
        for run in parsed.runs {
            let components = run.presentationIntent?.components ?? []
            let block = components.first?.identity
            var attributes = base
            var font = NSFont.systemFont(ofSize: 12)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 3
            paragraph.paragraphSpacing = 8
            var prefix = ""
            var listDepth = 0
            var item: Int?
            for component in components {
                switch component.kind {
                case .header(let level):
                    font = .systemFont(ofSize: level <= 2 ? 15 : 13, weight: .semibold)
                    paragraph.paragraphSpacing = 10
                case .orderedList, .unorderedList:
                    listDepth += 1
                case .listItem(let ordinal) where item == nil:
                    item = component.identity
                    let list = components.first {
                        switch $0.kind { case .orderedList, .unorderedList: return true; default: return false }
                    }
                    let ordered: Bool
                    if case .orderedList = list?.kind { ordered = true } else { ordered = false }
                    prefix = ordered ? "\(ordinal).\t" : "•\t"
                case .codeBlock:
                    font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
                    attributes[.backgroundColor] = NSColor.quaternaryLabelColor
                case .blockQuote:
                    paragraph.headIndent += 12
                    paragraph.firstLineHeadIndent += 12
                    attributes[.foregroundColor] = NSColor.secondaryLabelColor
                default: break
                }
            }
            if listDepth > 0 {
                paragraph.firstLineHeadIndent += CGFloat(listDepth - 1) * 14
                paragraph.headIndent += CGFloat(listDepth) * 14
                paragraph.tabStops = [NSTextTab(textAlignment: .left, location: paragraph.headIndent)]
                paragraph.paragraphSpacing = 6
            }
            let inline = run.inlinePresentationIntent ?? []
            if inline.contains(.code) { font = .monospacedSystemFont(ofSize: 11.5, weight: .regular) }
            var traits: NSFontTraitMask = []
            if inline.contains(.stronglyEmphasized) { traits.insert(.boldFontMask) }
            if inline.contains(.emphasized) { traits.insert(.italicFontMask) }
            if !traits.isEmpty { font = NSFontManager.shared.convert(font, toHaveTrait: traits) }
            if inline.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.link, ["https", "http"].contains(link.scheme?.lowercased() ?? ""), link.host != nil {
                attributes[.link] = link
            }
            attributes[.font] = font
            attributes[.paragraphStyle] = paragraph
            if block != previousBlock {
                if result.length > 0 { result.append(NSAttributedString(string: "\n", attributes: base)) }
                if item != previousItem { result.append(NSAttributedString(string: prefix, attributes: attributes)) }
                previousBlock = block
                previousItem = item
            }
            result.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        return result
    }
}

/// A monotonic version watermark avoids duplicate prompts after restarts or downgrades.
enum ReleaseNotesHistory {
    static let preferenceKey = "latestLaunchedReleaseVersion"

    static func shouldPresent(current: String, defaults: UserDefaults = .standard) -> Bool {
        guard let version = ReleaseVersion(current) else { return false }
        let previous = defaults.string(forKey: preferenceKey).flatMap(ReleaseVersion.init)
        guard let previous else {
            defaults.set(current, forKey: preferenceKey)
            return false // First install (or first launch with this feature): establish a baseline.
        }
        guard version > previous else { return false }
        defaults.set(current, forKey: preferenceKey)
        return true
    }
}

final class UtilityWindow: NSWindow {
    override func makeKeyAndOrderFront(_ sender: Any?) {
        let opening = !isVisible
        let event = NSApp.currentEvent
        let keyboardInitiated = event?.type == .keyDown || event?.type == .keyUp
        super.makeKeyAndOrderFront(sender)
        // Pointer/programmatic openings should not preselect the first link or
        // control. Tab still enters the native key-view loop; existing windows
        // retain the user's focus, and keyboard-initiated openings stay native.
        if opening && !keyboardInitiated { makeFirstResponder(nil) }
    }
    override func cancelOperation(_ sender: Any?) { close() }
}
