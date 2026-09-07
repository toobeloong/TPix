import AppKit
import Carbon.HIToolbox

struct HotkeyCombo: Codable, Equatable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32

    var isEmpty: Bool {
        keyCode == 0 && modifiers == 0
    }

    static let none = HotkeyCombo(keyCode: 0, modifiers: 0)

    var displayString: String {
        if isEmpty { return "未设置" }
        var parts: [String] = []
        let mods = modifiers
        if mods & UInt32(cmdKey) != 0 { parts.append("⌘") }
        if mods & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if mods & UInt32(controlKey) != 0 { parts.append("⌃") }
        if mods & UInt32(optionKey) != 0 { parts.append("⌥") }
        parts.append(KeyFormatter.string(for: keyCode))
        return parts.joined()
    }

    static let areaCapture = HotkeyCombo(keyCode: UInt32(kVK_ANSI_1), modifiers: UInt32(cmdKey | shiftKey))
    static let fullScreen = HotkeyCombo(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey | shiftKey))
    static let delay = HotkeyCombo(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(cmdKey | shiftKey))
    static let scroll = HotkeyCombo(keyCode: UInt32(kVK_ANSI_5), modifiers: UInt32(cmdKey | shiftKey))
    static let record = HotkeyCombo(keyCode: UInt32(kVK_ANSI_6), modifiers: UInt32(cmdKey | shiftKey))
    static let pin = HotkeyCombo(keyCode: UInt32(kVK_ANSI_7), modifiers: UInt32(cmdKey | shiftKey))
    static let colorPicker = HotkeyCombo(keyCode: UInt32(kVK_ANSI_8), modifiers: UInt32(cmdKey | shiftKey))
    static let ocr = HotkeyCombo(keyCode: UInt32(kVK_ANSI_9), modifiers: UInt32(cmdKey | shiftKey))
}

enum KeyFormatter {
    static func string(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Escape: return "⎋"
        default: return "Key\(keyCode)"
        }
    }
}

enum HotkeyID: Int {
    case areaCapture = 1, fullScreenCapture, delayCapture, scrollCapture, recordScreen, pinImage, colorPicker, ocr, windowUnderCursor, repeatLastCapture
}

final class HotkeyManager {
    private var registered: [HotkeyID: EventHotKeyRef] = [:]
    private var handlers: [HotkeyID: () -> Void] = [:]
    private var eventHandler: EventHandlerRef?

    init() {
        installEventHandler()
    }

    func registerAll() {
        let s = SettingsStore.shared
        register(.areaCapture, combo: s.settings.areaCaptureHotkey) { CaptureCoordinator.shared.startAreaCapture() }
        register(.fullScreenCapture, combo: s.settings.fullScreenHotkey) { CaptureCoordinator.shared.startFullScreenCapture() }
        register(.delayCapture, combo: s.settings.delayCaptureHotkey) { CaptureCoordinator.shared.startDelayCapture() }
        register(.scrollCapture, combo: s.settings.scrollCaptureHotkey) { CaptureCoordinator.shared.startScrollCapture() }
        register(.recordScreen, combo: s.settings.recordHotkey) { CaptureCoordinator.shared.toggleRecording() }
        register(.pinImage, combo: s.settings.pinHotkey) { CaptureCoordinator.shared.startPinFromClipboard() }
        register(.colorPicker, combo: s.settings.colorPickerHotkey) { CaptureCoordinator.shared.startColorPicker() }
        register(.ocr, combo: s.settings.ocrHotkey) { CaptureCoordinator.shared.startOCR() }
        register(.windowUnderCursor, combo: s.settings.windowUnderCursorHotkey) { CaptureCoordinator.shared.captureWindowUnderCursor() }
        register(.repeatLastCapture, combo: s.settings.repeatLastCaptureHotkey) { CaptureCoordinator.shared.repeatLastCapture() }
    }

    func register(_ id: HotkeyID, combo: HotkeyCombo, handler: @escaping () -> Void) {
        unregister(id)
        if combo.isEmpty { return }
        let hotkeyId = EventHotKeyID(signature: OSType(0x50415841), id: UInt32(id.rawValue))
        var ref: EventHotKeyRef?
        let result = RegisterEventHotKey(combo.keyCode, combo.modifiers, hotkeyId, GetApplicationEventTarget(), 0, &ref)
        if result == noErr, let ref = ref {
            registered[id] = ref
            handlers[id] = handler
        }
    }

    func unregister(_ id: HotkeyID) {
        if let ref = registered[id] {
            UnregisterEventHotKey(ref)
            registered.removeValue(forKey: id)
        }
        handlers.removeValue(forKey: id)
    }

    func unregisterAll() {
        for (_, ref) in registered { UnregisterEventHotKey(ref) }
        registered.removeAll()
        handlers.removeAll()
    }

    private func installEventHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: @convention(c) (EventHandlerCallRef?, EventRef?, UnsafeMutableRawPointer?) -> OSStatus = { _, eventRef, _ in
            guard let eventRef = eventRef else { return noErr }
            var hotkeyId = EventHotKeyID()
            let status = GetEventParameter(eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkeyId)
            if status == noErr {
                let mgr = HotkeyManager.self
                if let id = HotkeyID(rawValue: Int(hotkeyId.id)) {
                    DispatchQueue.main.async {
                        mgr.shared.handlers[id]?()
                    }
                }
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, nil, &eventHandler)
    }

    static var shared: HotkeyManager {
        struct S { static let i = HotkeyManager() }
        return S.i
    }
}
