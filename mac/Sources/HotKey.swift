// The global shortcuts (they work while another app, e.g. the game, is in front). Uses Apple's hot-key API:
// it needs no special permission and only reports the exact combinations registered - it cannot see any other key.
// It also tells us when a shortcut is let go, which is what "peek (hold)" needs.
import Cocoa
import Carbon.HIToolbox

final class HotKeyCenter {
    static let shared = HotKeyCenter()
    static let emergencyID: UInt32 = 99
    var onEvent: ((UInt32, Bool) -> Void)?     // shortcut id, true = pressed / false = released
    var onEmergency: (() -> Void)?
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlerInstalled = false

    private init() {}

    private func ensureHandler() -> Bool {
        if handlerInstalled { return true }
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let status = InstallEventHandler(GetApplicationEventTarget(), { (_, event, _) -> OSStatus in
            var hkID = EventHotKeyID()
            let err = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                        nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            if err != noErr { return err }
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            if hkID.id == HotKeyCenter.emergencyID {
                // emergency quit: act right here, do not wait for anything else in the app
                if pressed { HotKeyCenter.shared.onEmergency?() }
                return noErr
            }
            let id = hkID.id
            DispatchQueue.main.async {
                HotKeyCenter.shared.onEvent?(id, pressed)
            }
            return noErr
        }, 2, &specs, nil, nil)
        if status != noErr {
            Log.write("hotkey: could not install the handler (\(status))")
            return false
        }
        handlerInstalled = true
        return true
    }

    @discardableResult
    func register(id: UInt32, code: Int, modifiers: Int) -> Bool {
        unregister(id: id)
        if !ensureHandler() { return false }
        let hotKeyID = EventHotKeyID(signature: OSType(0x54414B4F), id: id)
        var ref: EventHotKeyRef?
        let result = RegisterEventHotKey(UInt32(code), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if result == noErr, let r = ref {
            refs[id] = r
            return true
        }
        Log.write("hotkey \(id): could not register \(HotKeyText.describe(code: code, mods: modifiers)) (\(result)) - another app may already use it")
        return false
    }

    // Control + Option + Shift + Q: closes the app instantly, whatever state it is in.
    @discardableResult
    func registerEmergency() -> Bool {
        let mods = controlKey | optionKey | shiftKey
        let ok = register(id: HotKeyCenter.emergencyID, code: 12, modifiers: mods)
        Log.write(ok ? "emergency quit shortcut registered" : "emergency shortcut: could not register")
        return ok
    }

    func unregister(id: UInt32) {
        if let r = refs[id] {
            UnregisterEventHotKey(r)
            refs[id] = nil
        }
    }

    func unregisterAll() {
        for (_, r) in refs { UnregisterEventHotKey(r) }
        refs.removeAll()
    }

    var registeredCount: Int { return refs.count }
}

enum HotKeyText {
    static func carbon(from flags: NSEvent.ModifierFlags) -> Int {
        var m = 0
        if flags.contains(.control) { m |= controlKey }
        if flags.contains(.option) { m |= optionKey }
        if flags.contains(.shift) { m |= shiftKey }
        if flags.contains(.command) { m |= cmdKey }
        return m
    }

    static let names: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W",
        14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
        48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Esc",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11", 109: "F10", 111: "F12",
        118: "F4", 120: "F2", 122: "F1", 123: "Left", 124: "Right", 125: "Down", 126: "Up"
    ]

    static func describe(code: Int, mods: Int) -> String {
        var s = ""
        if mods & controlKey != 0 { s += "\u{2303}" }   // control
        if mods & optionKey != 0 { s += "\u{2325}" }    // option
        if mods & shiftKey != 0 { s += "\u{21E7}" }     // shift
        if mods & cmdKey != 0 { s += "\u{2318}" }       // command
        s += names[code] ?? "Key \(code)"
        return s
    }

    static func describe(_ spec: HotSpec?) -> String {
        guard let s = spec else { return "(off)" }
        return describe(code: s.code, mods: s.mods)
    }
}
