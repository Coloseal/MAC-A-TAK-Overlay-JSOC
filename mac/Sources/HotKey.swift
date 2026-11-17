// The global shortcut (works while another app, e.g. the game, is in front). Uses Apple's hot-key API:
// it needs no special permission and only reports the one combination you chose - it cannot see any other key.
import Cocoa
import Carbon.HIToolbox

final class HotKeyCenter {
    static let shared = HotKeyCenter()
    var onPress: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerInstalled = false

    private init() {}

    @discardableResult
    func register(keyCode: Int, modifiers: Int) -> Bool {
        unregister()
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { (_, _, _) -> OSStatus in
                DispatchQueue.main.async {
                    HotKeyCenter.shared.onPress?()
                }
                return noErr
            }, 1, &spec, nil, nil)
            if status != noErr {
                Log.write("hotkey: could not install the handler (\(status))")
                return false
            }
            handlerInstalled = true
        }
        let hotKeyID = EventHotKeyID(signature: OSType(0x54414B4F), id: 1)
        var ref: EventHotKeyRef?
        let result = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if result == noErr {
            hotKeyRef = ref
            Log.write("hotkey registered: \(HotKeyText.describe(code: keyCode, mods: modifiers))")
            return true
        }
        Log.write("hotkey: could not register (\(result)) - another app may already use it")
        return false
    }

    func unregister() {
        if let r = hotKeyRef {
            UnregisterEventHotKey(r)
            hotKeyRef = nil
        }
    }
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
}
