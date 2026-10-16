import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A keyboard shortcut: a key plus Carbon modifier flags. Saved as "keyCode:modifiers".
struct HotKeySpec: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let control = UInt32(controlKey)
    static let option = UInt32(optionKey)
    static let shift = UInt32(shiftKey)
    static let command = UInt32(cmdKey)

    static let defaultCopy = HotKeySpec(keyCode: UInt32(kVK_ANSI_C), modifiers: control | option | command)

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Reads a saved value. Also understands the preset names version 1.0 used.
    init?(string: String) {
        let ctrlOptCmd = HotKeySpec.control | HotKeySpec.option | HotKeySpec.command
        switch string {
        case "", "none":
            return nil
        case "ctrlOptCmdC":
            self.init(keyCode: UInt32(kVK_ANSI_C), modifiers: ctrlOptCmd)
        case "ctrlOptCmdI":
            self.init(keyCode: UInt32(kVK_ANSI_I), modifiers: ctrlOptCmd)
        case "ctrlOptCmdN":
            self.init(keyCode: UInt32(kVK_ANSI_N), modifiers: ctrlOptCmd)
        case "ctrlOptCmdP":
            self.init(keyCode: UInt32(kVK_ANSI_P), modifiers: ctrlOptCmd)
        case "shiftOptCmdI":
            self.init(keyCode: UInt32(kVK_ANSI_I), modifiers: HotKeySpec.shift | HotKeySpec.option | HotKeySpec.command)
        default:
            let parts = string.split(separator: ":")
            guard parts.count == 2, let code = UInt32(parts[0]), let mods = UInt32(parts[1]) else { return nil }
            self.init(keyCode: code, modifiers: mods)
        }
    }

    /// From a key press while recording. Needs Command, Control or Option, except for F-keys.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= HotKeySpec.control }
        if flags.contains(.option) { mods |= HotKeySpec.option }
        if flags.contains(.shift) { mods |= HotKeySpec.shift }
        if flags.contains(.command) { mods |= HotKeySpec.command }
        let code = UInt32(event.keyCode)
        let hasMainModifier = mods & (HotKeySpec.control | HotKeySpec.option | HotKeySpec.command) != 0
        guard hasMainModifier || KeyNames.isFunctionKey(Int(code)) else { return nil }
        self.init(keyCode: code, modifiers: mods)
    }

    var stringValue: String { "\(keyCode):\(modifiers)" }

    var display: String {
        var text = ""
        if modifiers & HotKeySpec.control != 0 { text += "⌃" }
        if modifiers & HotKeySpec.option != 0 { text += "⌥" }
        if modifiers & HotKeySpec.shift != 0 { text += "⇧" }
        if modifiers & HotKeySpec.command != 0 { text += "⌘" }
        return text + KeyNames.name(for: Int(keyCode))
    }
}

enum KeyNames {
    static let functionKeys: [Int] = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    static func isFunctionKey(_ code: Int) -> Bool { functionKeys.contains(code) }

    static let names: [Int: String] = {
        var table: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
            kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
            kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
            kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
            kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
            kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
            kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".",
            kVK_ANSI_Slash: "/", kVK_ANSI_Backslash: "\\", kVK_ANSI_Grave: "`",
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        ]
        for (index, code) in functionKeys.enumerated() {
            table[code] = "F\(index + 1)"
        }
        return table
    }()

    static func name(for code: Int) -> String {
        names[code] ?? "Key \(code)"
    }
}

/// Global keyboard shortcuts. Uses the Carbon hot key API, which needs no
/// Accessibility or Input Monitoring permission.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var specs: [UInt32: HotKeySpec] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: @MainActor () -> Void] = [:]
    private var handlerInstalled = false
    private(set) var isSuspended = false

    func set(id: UInt32, to spec: HotKeySpec?, action: @escaping @MainActor () -> Void) {
        actions[id] = action
        let unchanged = specs[id] == spec && (spec == nil || isSuspended || refs[id] != nil)
        if unchanged { return }
        unregister(id)
        specs[id] = spec
        if !isSuspended { register(id) }
    }

    /// Lets the shortcut recorder see key combos that are already in use.
    func suspend() {
        isSuspended = true
        for id in Array(refs.keys) { unregister(id) }
    }

    func resume() {
        isSuspended = false
        for id in Array(specs.keys) { register(id) }
    }

    func fire(_ id: UInt32) {
        actions[id]?()
    }

    private func register(_ id: UInt32) {
        guard let spec = specs[id], refs[id] == nil else { return }
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4E4D_504C), id: id) // 'NMPL'
        let status = RegisterEventHotKey(spec.keyCode, spec.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs[id] = ref
        } else {
            NSLog("Nameplate: couldn't register \(spec.display) (status \(status)); another app may be using it.")
        }
    }

    private func unregister(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyPressed, 1, &eventType, nil, nil)
        handlerInstalled = true
    }
}

/// Carbon calls this on the main thread when a registered shortcut is pressed.
private func hotKeyPressed(_ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                   nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr else { return status }
    let id = hotKeyID.id
    Task { @MainActor in
        HotKeyCenter.shared.fire(id)
    }
    return noErr
}

/// Click, then press the keys you want. Escape cancels; Delete clears.
@MainActor
struct ShortcutRecorder: View {
    @Binding var value: String
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                if recording { stop() } else { start() }
            } label: {
                Text(recording ? "Press keys…" : (HotKeySpec(string: value)?.display ?? "Record Shortcut"))
                    .frame(minWidth: 110)
            }
            if !recording, HotKeySpec(string: value) != nil {
                Button {
                    value = "none"
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove this shortcut")
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        HotKeyCenter.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
            } else if event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete),
                      event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                value = "none"
                stop()
            } else if let spec = HotKeySpec(event: event) {
                value = spec.stringValue
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording {
            recording = false
            HotKeyCenter.shared.resume()
        }
    }
}
