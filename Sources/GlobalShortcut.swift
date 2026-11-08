import AppKit
import Carbon.HIToolbox

struct ShortcutChord: Codable, Equatable {
    let key: UInt32
    let modifiers: UInt32
    let label: String
    var isValid: Bool {
        key < 128 && ![48, 36, 51, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 117].contains(key) && (modifiers & UInt32(controlKey | optionKey) != 0 || modifiers & UInt32(cmdKey | shiftKey) == UInt32(cmdKey | shiftKey)) &&
        modifiers & ~UInt32(controlKey | optionKey | cmdKey | shiftKey) == 0 && !label.isEmpty && label.count <= 32
    }
    static func load(from defaults: UserDefaults = .standard) -> Self? {
        guard let data = defaults.data(forKey: "globalShortcut"), let chord = try? JSONDecoder().decode(Self.self, from: data), chord.isValid else { return nil }
        return chord
    }
}

// A single registered system hotkey; no global keyboard event monitor.
final class GlobalShortcut {
    typealias Register = (UInt32, UInt32, EventHotKeyID, inout EventHotKeyRef?) -> OSStatus
    private let register: Register
    private let unregister: (EventHotKeyRef) -> Void
    private var registration: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var held = false
    private var generation: UInt32 = 0
    var action: (() -> Void)?
    private(set) var chord: ShortcutChord?
    init(register: Register? = nil, unregister: ((EventHotKeyRef) -> Void)? = nil) {
        self.register = register ?? { key, modifiers, id, result in
            RegisterEventHotKey(key, modifiers, id, GetApplicationEventTarget(), 0, &result)
        }
        self.unregister = unregister ?? { UnregisterEventHotKey($0) }
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                    MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                  id.signature == 0x4E594C55, id.id == owner.generation else { return OSStatus(eventNotHandledErr) }
            if GetEventKind(event) == UInt32(kEventHotKeyReleased) { owner.held = false }
            else if !owner.held { owner.held = true; owner.action?() }
            return noErr
        }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    @discardableResult func set(_ next: ShortcutChord?) -> Bool {
        guard next != chord else { return true }
        if let next {
            guard next.isValid else { return false }
            if next.key == chord?.key && next.modifiers == chord?.modifiers { chord = next; return true }
        }
        var newRegistration: EventHotKeyRef?
        let nextID = generation &+ 1
        if let next {
            guard handler != nil,
                  register(next.key, next.modifiers, EventHotKeyID(signature: 0x4E594C55, id: nextID), &newRegistration) == noErr else { return false }
        }
        if let registration { unregister(registration) }
        registration = newRegistration; generation = nextID; held = false; chord = next
        return true
    }
    deinit {
        if let registration { unregister(registration) }
        if let handler { RemoveEventHandler(handler) }
    }
}

final class ShortcutRecorder: NSTextField {
    var recorded: ShortcutChord?
    var onRecord: (() -> Void)?
    var onBeginRecording: (() -> Void)?
    var isRecording = false
    func beginRecording() {
        recorded = nil
        isRecording = true
        onBeginRecording?()
        stringValue = L("shortcut.press_keys")
        window?.makeFirstResponder(self)
    }
    override var acceptsFirstResponder: Bool { true }
    override func accessibilityPerformPress() -> Bool { beginRecording(); return true }
    override func becomeFirstResponder() -> Bool { true }
    override func mouseDown(with event: NSEvent) { beginRecording() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, window?.firstResponder === self, (event.modifierFlags.contains(.control) || event.modifierFlags.contains(.option) || event.modifierFlags.contains([.command, .shift])) else { return false }
        keyDown(with: event); return true
    }
    override func keyDown(with event: NSEvent) {
        if !isRecording && event.keyCode == 49 { beginRecording(); return }
        if event.keyCode == 48 { window?.selectNextKeyView(nil); return }
        if event.keyCode == 36 { window?.defaultButtonCell?.performClick(nil); return }
        if event.keyCode == 53 { NSApp.abortModal(); return }
        guard isRecording else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.control) || flags.contains(.option) || flags.contains([.command, .shift]), !event.isARepeat,
              let text = event.charactersIgnoringModifiers?.uppercased(), !text.isEmpty,
              ![48, 36, 51, 117, 53].contains(Int(event.keyCode)) else { NSSound.beep(); return }
        var modifiers: UInt32 = 0
        var label = ""
        for (flag, mask, glyph) in [(NSEvent.ModifierFlags.control, controlKey, "⌃"), (.option, optionKey, "⌥"), (.shift, shiftKey, "⇧"), (.command, cmdKey, "⌘")] {
            if flags.contains(flag) { modifiers |= UInt32(mask); label += glyph }
        }
        let specialKeys: [UInt16: String] = [49: "␣", 123: "←", 124: "→", 125: "↓", 126: "↑"]
        let scalar = text.unicodeScalars.first!.value
        let keyLabel = specialKeys[event.keyCode] ?? ((0xF704...0xF71B).contains(scalar) ? "F" + String(scalar - 0xF704 + 1) : text)
        let next = ShortcutChord(key: UInt32(event.keyCode), modifiers: modifiers, label: label + keyLabel)
        guard next.isValid else { return }
        recorded = next; stringValue = next.label; isRecording = false; onRecord?()
    }
}

extension GlobalShortcut {
    func makeConfigurationAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = L("shortcut.title")
        alert.informativeText = L("shortcut.hint")
        alert.addButton(withTitle: L("action.save"))
        alert.addButton(withTitle: L("action.cancel"))
        alert.addButton(withTitle: L("shortcut.remove"))
        let recorder = ShortcutRecorder(labelWithString: chord?.label ?? L("shortcut.record"))
        recorder.setAccessibilityRole(.button)
        recorder.setAccessibilityLabel(L("shortcut.title"))
        recorder.setAccessibilityHelp(L("shortcut.hint"))
        recorder.isBordered = true; recorder.isBezeled = true
        recorder.bezelStyle = .roundedBezel
        recorder.drawsBackground = true
        recorder.backgroundColor = .textBackgroundColor
        recorder.focusRingType = .exterior
        recorder.alignment = .center; recorder.font = .systemFont(ofSize: 17)
        recorder.frame = NSRect(x: 0, y: 0, width: 300, height: 32)
        alert.accessoryView = recorder
        alert.buttons[0].isEnabled = false
        alert.buttons[2].isEnabled = chord != nil
        recorder.onBeginRecording = { [weak alert] in alert?.buttons.first?.isEnabled = false }
        recorder.onRecord = { [weak alert] in alert?.buttons.first?.isEnabled = true }
        alert.window.initialFirstResponder = alert.buttons[1]
        return alert
    }
    func configure() {
        let alert = makeConfigurationAlert()
        guard let recorder = alert.accessoryView as? ShortcutRecorder else { return }
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn || response == .alertThirdButtonReturn else { return }
        let next = response == .alertThirdButtonReturn ? nil : recorder.recorded ?? chord
        guard set(next) else {
            let error = NSAlert(); error.messageText = L("shortcut.unavailable"); error.runModal(); return
        }
        if let next, let data = try? JSONEncoder().encode(next) { UserDefaults.standard.set(data, forKey: "globalShortcut") }
        else { UserDefaults.standard.removeObject(forKey: "globalShortcut") }
    }
}
