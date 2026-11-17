// Settings stored in the Mac's own preferences (UserDefaults), plus the tablet colour themes.
import Cocoa
import Carbon.HIToolbox

struct Theme {
    let name: String
    let top: NSColor
    let bottom: NSColor
}

enum Themes {
    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        return NSColor(srgbRed: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: 1.0)
    }

    static let all: [Theme] = [
        Theme(name: "Coyote Tan", top: Themes.rgb(178, 152, 112), bottom: Themes.rgb(126, 102, 70)),
        Theme(name: "Black", top: Themes.rgb(80, 82, 80), bottom: Themes.rgb(40, 42, 40)),
        Theme(name: "Ranger Green", top: Themes.rgb(104, 118, 78), bottom: Themes.rgb(62, 74, 44)),
        Theme(name: "Arid", top: Themes.rgb(222, 204, 166), bottom: Themes.rgb(178, 158, 120)),
        Theme(name: "Navy", top: Themes.rgb(70, 86, 112), bottom: Themes.rgb(36, 46, 66))
    ]

    static func named(_ name: String) -> Theme {
        for t in all where t.name == name { return t }
        return all[0]
    }
}

final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard
    private init() {}

    private func boolValue(_ key: String, _ fallback: Bool) -> Bool {
        if d.object(forKey: key) == nil { return fallback }
        return d.bool(forKey: key)
    }

    private func numberValue(_ key: String, _ fallback: Double) -> Double {
        if d.object(forKey: key) == nil { return fallback }
        return d.double(forKey: key)
    }

    var homeURL: String {
        get { return d.string(forKey: "homeURL") ?? "https://jsoctacmap-544084018891.us-east1.run.app/" }
        set { d.set(newValue, forKey: "homeURL") }
    }

    var searchURL: String {
        get { return d.string(forKey: "searchURL") ?? "https://duckduckgo.com/?q=" }
        set { d.set(newValue, forKey: "searchURL") }
    }

    var sizePct: Double {
        get { return numberValue("sizePct", 78) }
        set { d.set(newValue, forKey: "sizePct") }
    }

    var opacity: Double {
        get { return numberValue("opacity", 100) }
        set { d.set(newValue, forKey: "opacity") }
    }

    var dockWidth: Double {
        get { return numberValue("dockWidth", 340) }
        set { d.set(newValue, forKey: "dockWidth") }
    }

    var lockMouse: Bool {
        get { return boolValue("lockMouse", true) }
        set { d.set(newValue, forKey: "lockMouse") }
    }

    var adBlock: Bool {
        get { return boolValue("adBlock", true) }
        set { d.set(newValue, forKey: "adBlock") }
    }

    var httpsOnly: Bool {
        get { return boolValue("httpsOnly", true) }
        set { d.set(newValue, forKey: "httpsOnly") }
    }

    var animate: Bool {
        get { return boolValue("animate", true) }
        set { d.set(newValue, forKey: "animate") }
    }

    var firstRunDone: Bool {
        get { return boolValue("firstRunDone", false) }
        set { d.set(newValue, forKey: "firstRunDone") }
    }

    var theme: String {
        get { return d.string(forKey: "theme") ?? "Coyote Tan" }
        set { d.set(newValue, forKey: "theme") }
    }

    // Default shortcut: Control + Option + T
    var hotKeyCode: Int {
        get { return d.object(forKey: "hotKeyCode") == nil ? 17 : d.integer(forKey: "hotKeyCode") }
        set { d.set(newValue, forKey: "hotKeyCode") }
    }

    var hotKeyMods: Int {
        get { return d.object(forKey: "hotKeyMods") == nil ? (controlKey | optionKey) : d.integer(forKey: "hotKeyMods") }
        set { d.set(newValue, forKey: "hotKeyMods") }
    }

    // Path of a picture chosen by the person to use instead of the drawn tablet (PNG with a transparent background).
    var skinPath: String? {
        get { return d.string(forKey: "skinPath") }
        set {
            if let v = newValue { d.set(v, forKey: "skinPath") } else { d.removeObject(forKey: "skinPath") }
        }
    }

    // Where the person left the open tablet (window origin).
    var openOrigin: NSPoint? {
        get {
            if d.object(forKey: "openX") == nil { return nil }
            return NSPoint(x: d.double(forKey: "openX"), y: d.double(forKey: "openY"))
        }
        set {
            if let p = newValue {
                d.set(Double(p.x), forKey: "openX")
                d.set(Double(p.y), forKey: "openY")
            } else {
                d.removeObject(forKey: "openX")
                d.removeObject(forKey: "openY")
            }
        }
    }
}

// A small log file for diagnosing problems: ~/Library/Logs/TacMapOverlay.log
enum Log {
    private static var lines = 0

    static func write(_ text: String) {
        lines += 1
        if lines > 2000 { return }
        let dir = NSHomeDirectory() + "/Library/Logs"
        let path = dir + "/TacMapOverlay.log"
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = stamp + "  " + text + "\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: path) {
                if let h = FileHandle(forWritingAtPath: path) {
                    h.seekToEndOfFile()
                    h.write(data)
                    h.closeFile()
                }
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }
}
