// Settings stored in the Mac's own preferences (UserDefaults), the tablet colour themes, and the list of shortcuts.
import Cocoa
import Carbon.HIToolbox

struct Theme {
    let name: String
    let top: NSColor
    let bottom: NSColor
    let camo: [NSColor]      // empty = plain colour fade, otherwise blotches of these colours on top
}

enum Themes {
    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        return NSColor(srgbRed: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: 1.0)
    }

    static let all: [Theme] = [
        Theme(name: "Coyote Tan", top: Themes.rgb(178, 152, 112), bottom: Themes.rgb(126, 102, 70), camo: []),
        Theme(name: "Black", top: Themes.rgb(80, 82, 80), bottom: Themes.rgb(40, 42, 40), camo: []),
        Theme(name: "Ranger Green", top: Themes.rgb(104, 118, 78), bottom: Themes.rgb(62, 74, 44), camo: []),
        Theme(name: "Arid", top: Themes.rgb(222, 204, 166), bottom: Themes.rgb(178, 158, 120), camo: []),
        Theme(name: "JG Camo", top: Themes.rgb(96, 104, 70), bottom: Themes.rgb(58, 66, 44),
              camo: [Themes.rgb(122, 110, 76), Themes.rgb(40, 48, 34), Themes.rgb(150, 138, 98)]),
        Theme(name: "MultiCam", top: Themes.rgb(150, 138, 104), bottom: Themes.rgb(104, 96, 70),
              camo: [Themes.rgb(176, 158, 120), Themes.rgb(98, 110, 78), Themes.rgb(120, 92, 64), Themes.rgb(82, 78, 62)]),
        Theme(name: "Navy", top: Themes.rgb(70, 86, 112), bottom: Themes.rgb(36, 46, 66), camo: [])
    ]

    static func named(_ name: String) -> Theme {
        for t in all where t.name == name { return t }
        return all[0]
    }

    // dark themes get light text on the frame
    static func isDark(_ t: Theme) -> Bool {
        return ["Black", "Ranger Green", "JG Camo", "Navy"].contains(t.name)
    }
}

// A keyboard shortcut: macOS key code + Carbon modifier bits (controlKey, optionKey, shiftKey, cmdKey).
struct HotSpec: Equatable {
    var code: Int
    var mods: Int
}

enum HotAction: String, CaseIterable {
    case toggle, size, opacity, peek, notes, live, drag, timer1, timer2, stopwatch

    var title: String {
        switch self {
        case .toggle: return "Open / minimize the tablet"
        case .size: return "Cycle the tablet size"
        case .opacity: return "Cycle the transparency"
        case .peek: return "Peek (open only while held)"
        case .notes: return "Notes pad"
        case .live: return "Live corner view on / off"
        case .drag: return "Move the live view"
        case .timer1: return "Timer 1 start / cancel"
        case .timer2: return "Timer 2 start / cancel"
        case .stopwatch: return "Stopwatch start / stop / reset"
        }
    }

    // all default shortcuts are Control + Option + a letter or number
    var defaultSpec: HotSpec {
        let m = controlKey | optionKey
        switch self {
        case .toggle: return HotSpec(code: 17, mods: m)      // T
        case .size: return HotSpec(code: 11, mods: m)        // B (bigger)
        case .opacity: return HotSpec(code: 31, mods: m)     // O
        case .peek: return HotSpec(code: 35, mods: m)        // P
        case .notes: return HotSpec(code: 45, mods: m)       // N
        case .live: return HotSpec(code: 37, mods: m)        // L
        case .drag: return HotSpec(code: 46, mods: m)        // M
        case .timer1: return HotSpec(code: 18, mods: m)      // 1
        case .timer2: return HotSpec(code: 19, mods: m)      // 2
        case .stopwatch: return HotSpec(code: 1, mods: m)    // S
        }
    }

    var id: UInt32 { return UInt32(10 + (HotAction.allCases.firstIndex(of: self) ?? 0)) }
}

enum PilotActions {
    static let defaultPages: [[String]] = [
        "MAP,WEB,NOTE,TIME,LIVE,PAGE,TM1,TM2,TM3,TM4,STW,CLR,BACK,FWD,RFSH,ADS,XPAR,LOCK,MSN,MRST,UTC,CPY,SHOT,ZRST".components(separatedBy: ","),
        "MAP,LOG,CALC,N9L,CHK,PAGE,BM1,BM2,BM3,BM4,BM5,BM6,ZM+,ZM-,ZRST,SZ+,SZ-,DRAG,LOGV,PR1,PR2,PR3,SHOT,CPY".components(separatedBy: ","),
        "MAP,WEB,NOTE,TIME,LIVE,PAGE,SET,UPD,CLRD,NONE,NONE,NONE,BACK,FWD,RFSH,ADS,LOCK,XPAR,PR1,PR2,PR3,UTC,SHOT,CPY".components(separatedBy: ",")
    ]

    static let slotNames: [String] = ["T1", "T2", "T3", "T4", "T5", "T6", "L1", "L2", "L3", "L4", "L5", "L6",
                                      "R1", "R2", "R3", "R4", "R5", "R6", "B1", "B2", "B3", "B4", "B5", "B6"]

    // everything a pilot-display button can be set to (id, name shown in the list); the first one is NONE
    static let list: [(String, String)] = [
        ("NONE", "(nothing)"),
        ("MAP", "Map / home page"), ("WEB", "Address bar"), ("NOTE", "Notes pad"),
        ("TIME", "Clock and timer panel"), ("LIVE", "Live corner view on / off"), ("DRAG", "Move the live view"),
        ("PAGE", "Next button page"), ("PG1", "Go to page 1"), ("PG2", "Go to page 2"), ("PG3", "Go to page 3"),
        ("TM1", "Timer 1"), ("TM2", "Timer 2"), ("TM3", "Timer 3"), ("TM4", "Timer 4"),
        ("STW", "Stopwatch"), ("CLR", "Clear timers"), ("MSN", "Mission clock start / pause"), ("MRST", "Mission clock reset"),
        ("UTC", "Local / Zulu clock"),
        ("BACK", "Back"), ("FWD", "Forward"), ("RFSH", "Refresh the page"),
        ("ADS", "Ad blocker on / off"), ("XPAR", "Transparency"), ("LOCK", "Mouse lock on / off"),
        ("CPY", "Copy the page address"), ("SHOT", "Screenshot to clipboard"),
        ("ZRST", "Zoom reset"), ("ZM+", "Zoom in"), ("ZM-", "Zoom out"), ("SZ+", "Tablet bigger"), ("SZ-", "Tablet smaller"),
        ("BM1", "Bookmark 1"), ("BM2", "Bookmark 2"), ("BM3", "Bookmark 3"), ("BM4", "Bookmark 4"), ("BM5", "Bookmark 5"), ("BM6", "Bookmark 6"),
        ("LOG", "Add a time-stamped log line"), ("LOGV", "Copy the mission log"),
        ("CALC", "Bearing / distance tool"), ("N9L", "9-line template"), ("CHK", "Checklist"),
        ("PR1", "Layout preset 1"), ("PR2", "Layout preset 2"), ("PR3", "Layout preset 3"),
        ("SET", "Settings"), ("UPD", "Check for updates"), ("CLRD", "Clear browsing data")
    ]
}

final class Settings {
    static let shared = Settings()
    static let defaultHome = "https://jsoc-tacmap.onrender.com/"
    static let oldHome = "https://jsoctacmap-544084018891.us-east1.run.app"
    private let d = UserDefaults.standard
    private init() {}

    private func str(_ k: String, _ f: String) -> String { return d.string(forKey: k) ?? f }
    private func int(_ k: String, _ f: Int) -> Int { return d.object(forKey: k) == nil ? f : d.integer(forKey: k) }
    private func bool(_ k: String, _ f: Bool) -> Bool { return d.object(forKey: k) == nil ? f : d.bool(forKey: k) }
    private func dbl(_ k: String, _ f: Double) -> Double { return d.object(forKey: k) == nil ? f : d.double(forKey: k) }

    // ---- page / browser
    var homeURL: String {
        get {
            let v = str("homeURL", Settings.defaultHome)
            // the tac map moved: anyone still on the old default address is taken to the new one
            if v.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).lowercased() == Settings.oldHome { return Settings.defaultHome }
            return v
        }
        set { d.set(newValue, forKey: "homeURL") }
    }
    var searchURL: String {
        get { return str("searchURL", "https://duckduckgo.com/?q=") }
        set { d.set(newValue, forKey: "searchURL") }
    }
    var adBlock: Bool { get { return bool("adBlock", true) } set { d.set(newValue, forKey: "adBlock") } }
    var httpsOnly: Bool { get { return bool("httpsOnly", true) } set { d.set(newValue, forKey: "httpsOnly") } }
    var pageWidth: Int { get { return int("pageWidth", 1050) } set { d.set(max(500, min(2400, newValue)), forKey: "pageWidth") } }
    var mapPixelRatio: Double { get { return dbl("mapPixelRatio", 0) } set { d.set(max(0, min(3, newValue)), forKey: "mapPixelRatio") } }

    // ---- look and size
    var layout: String { get { return str("layout", "atak") } set { d.set(newValue == "pilot" ? "pilot" : "atak", forKey: "layout") } }
    var theme: String { get { return str("theme", "Coyote Tan") } set { d.set(newValue, forKey: "theme") } }
    var pilotTheme: String { get { return str("pilotTheme", "Black") } set { d.set(newValue, forKey: "pilotTheme") } }
    var openSize: Int { get { return int("sizePct", 78) } set { d.set(max(25, min(90, newValue)), forKey: "sizePct") } }
    var opacity: Int { get { return int("opacity", 100) } set { d.set(max(25, min(100, newValue)), forKey: "opacity") } }
    var dockOpacity: Int { get { return int("dockOpacity", 100) } set { d.set(max(25, min(100, newValue)), forKey: "dockOpacity") } }
    // where the little minimized tablet was left: offset from the screen's left / top (nil = the bottom-right corner)
    var dockX: Double? {
        get { return d.object(forKey: "dockX") == nil ? nil : d.double(forKey: "dockX") }
        set { if let v = newValue { d.set(v, forKey: "dockX") } else { d.removeObject(forKey: "dockX") } }
    }
    var dockY: Double? {
        get { return d.object(forKey: "dockY") == nil ? nil : d.double(forKey: "dockY") }
        set { if let v = newValue { d.set(v, forKey: "dockY") } else { d.removeObject(forKey: "dockY") } }
    }
    var dockWidth: Int { get { return int("dockWidth", 340) } set { d.set(max(200, min(700, newValue)), forKey: "dockWidth") } }
    var animate: Bool { get { return bool("animate", true) } set { d.set(newValue, forKey: "animate") } }
    var showOnStart: Bool { get { return bool("showOnStart", false) } set { d.set(newValue, forKey: "showOnStart") } }
    var lockMouse: Bool { get { return bool("lockMouse", true) } set { d.set(newValue, forKey: "lockMouse") } }
    var firstRunDone: Bool { get { return bool("firstRunDone", false) } set { d.set(newValue, forKey: "firstRunDone") } }

    // where the open tablet sits: "center", "bottomright" or "custom" (custom = where it was left, the window origin)
    var anchor: String { get { return str("anchor", "center") } set { d.set(newValue, forKey: "anchor") } }

    func skinPath(for layout: String) -> String? { return d.string(forKey: "skin." + layout) }
    func setSkinPath(_ p: String?, for layout: String) {
        if let v = p { d.set(v, forKey: "skin." + layout) } else { d.removeObject(forKey: "skin." + layout) }
    }

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

    // ---- live corner view
    var liveMini: Bool { get { return bool("liveMini", false) } set { d.set(newValue, forKey: "liveMini") } }
    var livePct: Int { get { return int("livePct", 30) } set { d.set(max(15, min(60, newValue)), forKey: "livePct") } }
    // left / top edge as an offset from the screen's left / top (nil = the bottom-right corner)
    var liveX: Double? {
        get { return d.object(forKey: "liveX") == nil ? nil : d.double(forKey: "liveX") }
        set { if let v = newValue { d.set(v, forKey: "liveX") } else { d.removeObject(forKey: "liveX") } }
    }
    var liveY: Double? {
        get { return d.object(forKey: "liveY") == nil ? nil : d.double(forKey: "liveY") }
        set { if let v = newValue { d.set(v, forKey: "liveY") } else { d.removeObject(forKey: "liveY") } }
    }

    // ---- panels, clock, timers
    var showLabels: Bool { get { return bool("showLabels", true) } set { d.set(newValue, forKey: "showLabels") } }
    var showPanel: Bool { get { return bool("showPanel", true) } set { d.set(newValue, forKey: "showPanel") } }
    var labelInset: Bool { get { return bool("labelInset", false) } set { d.set(newValue, forKey: "labelInset") } }
    var alertBeep: Bool { get { return bool("alertBeep", true) } set { d.set(newValue, forKey: "alertBeep") } }
    var zulu: Bool { get { return bool("zulu", false) } set { d.set(newValue, forKey: "zulu") } }
    var timerSecs: [Int] {
        get {
            let parts = str("timers", "60,300,600,900").components(separatedBy: ",")
            var out: [Int] = []
            for i in 0..<4 { out.append(i < parts.count ? max(1, min(86399, Int(parts[i]) ?? 60)) : 60) }
            return out
        }
        set { d.set(newValue.map { String($0) }.joined(separator: ","), forKey: "timers") }
    }

    // ---- game-aware
    var gameOnly: Bool { get { return bool("gameOnly", false) } set { d.set(newValue, forKey: "gameOnly") } }
    var gameProcess: String { get { return str("gameProcess", "Roblox") } set { d.set(newValue, forKey: "gameProcess") } }

    // ---- pilot-display buttons (3 pages x 24), bookmarks (6), layout presets (3)
    func page(_ i: Int) -> [String] {
        let fallback = PilotActions.defaultPages[max(0, min(2, i))]
        let s = d.string(forKey: "page\(i + 1)") ?? ""
        let ids = s.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
        return ids.count == 24 ? ids : fallback
    }
    func setPage(_ i: Int, _ ids: [String]) { d.set(ids.joined(separator: ","), forKey: "page\(i + 1)") }
    func resetPages() { for i in 1...3 { d.removeObject(forKey: "page\(i)") } }

    func bookmark(_ i: Int) -> String { return str("bookmark\(i + 1)", "") }
    func setBookmark(_ i: Int, _ v: String) { d.set(v, forKey: "bookmark\(i + 1)") }
    func preset(_ i: Int) -> String { return str("preset\(i + 1)", "") }
    func setPreset(_ i: Int, _ v: String) { d.set(v, forKey: "preset\(i + 1)") }

    // ---- shortcuts
    func hotkey(_ a: HotAction) -> HotSpec? {
        let key = "hk." + a.rawValue
        if let s = d.string(forKey: key) {
            if s == "off" { return nil }
            let p = s.components(separatedBy: ",")
            if p.count == 2, let c = Int(p[0]), let m = Int(p[1]) { return HotSpec(code: c, mods: m) }
        }
        // 0.1.x stored just the toggle shortcut under other names
        if a == .toggle, d.object(forKey: "hotKeyCode") != nil, d.object(forKey: "hotKeyMods") != nil {
            return HotSpec(code: d.integer(forKey: "hotKeyCode"), mods: d.integer(forKey: "hotKeyMods"))
        }
        return a.defaultSpec
    }
    func setHotkey(_ a: HotAction, _ h: HotSpec?) {
        let key = "hk." + a.rawValue
        if let h = h { d.set("\(h.code),\(h.mods)", forKey: key) } else { d.set("off", forKey: key) }
    }
    func resetHotkeys() {
        for a in HotAction.allCases { d.removeObject(forKey: "hk." + a.rawValue) }
        d.removeObject(forKey: "hotKeyCode")
        d.removeObject(forKey: "hotKeyMods")
    }

    func resetAll() {
        if let id = Bundle.main.bundleIdentifier { d.removePersistentDomain(forName: id) }
        d.synchronize()
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
