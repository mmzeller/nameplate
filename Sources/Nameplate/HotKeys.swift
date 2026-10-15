import AppKit
import Carbon.HIToolbox

/// Global keyboard shortcuts. Uses the Carbon hot key API, which needs no
/// Accessibility or Input Monitoring permission.
enum HotKeyChoice: String, CaseIterable {
    case off = "none"
    case ctrlOptCmdC, ctrlOptCmdI, ctrlOptCmdN, ctrlOptCmdP, shiftOptCmdI

    var title: String {
        switch self {
        case .off: return "None"
        case .ctrlOptCmdC: return "⌃⌥⌘C"
        case .ctrlOptCmdI: return "⌃⌥⌘I"
        case .ctrlOptCmdN: return "⌃⌥⌘N"
        case .ctrlOptCmdP: return "⌃⌥⌘P"
        case .shiftOptCmdI: return "⇧⌥⌘I"
        }
    }

    var keyCode: UInt32 {
        switch self {
        case .off: return 0
        case .ctrlOptCmdC: return UInt32(kVK_ANSI_C)
        case .ctrlOptCmdI, .shiftOptCmdI: return UInt32(kVK_ANSI_I)
        case .ctrlOptCmdN: return UInt32(kVK_ANSI_N)
        case .ctrlOptCmdP: return UInt32(kVK_ANSI_P)
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .off: return 0
        case .shiftOptCmdI: return UInt32(shiftKey | optionKey | cmdKey)
        default: return UInt32(controlKey | optionKey | cmdKey)
        }
    }
}

@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var registered: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: @MainActor () -> Void] = [:]
    private var handlerInstalled = false

    func set(id: UInt32, to choice: HotKeyChoice, action: @escaping @MainActor () -> Void) {
        if let existing = registered.removeValue(forKey: id) {
            UnregisterEventHotKey(existing)
        }
        actions[id] = nil
        guard choice != .off else { return }

        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4E4D_504C), id: id) // 'NMPL'
        let status = RegisterEventHotKey(choice.keyCode, choice.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            registered[id] = ref
            actions[id] = action
        } else {
            NSLog("Nameplate: could not register hot key \(choice.title) (status \(status)); another app may be using it.")
        }
    }

    func fire(_ id: UInt32) {
        actions[id]?()
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
