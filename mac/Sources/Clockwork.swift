// Clock, four countdown timers, stopwatch and mission clock (the numbers and the rules; the drawing is elsewhere).
import Cocoa

struct PanelLine {
    let text: String
    let state: Int       // 0 normal, 1 on (green), 2 off / unavailable (dim), 3 alarm (flashes)
}

final class TimerSlot {
    var preset: Int
    var running = false
    var done = false
    var endMs: Int64 = 0
    var doneMs: Int64 = 0
    init(_ p: Int) { preset = p }
}

final class Clockwork {
    var timers: [TimerSlot]
    var stwRunning = false
    var stwUsed = false
    var stwStartMs: Int64 = 0
    var stwBaseMs: Int64 = 0
    var msnRunning = false
    var msnUsed = false
    var msnStartMs: Int64 = 0
    var msnBaseMs: Int64 = 0
    var onAlert: ((Int) -> Void)?
    private let settings = Settings.shared
    private let localFormat = DateFormatter()
    private let zuluFormat = DateFormatter()

    init() {
        timers = Settings.shared.timerSecs.map { TimerSlot($0) }
        localFormat.dateFormat = "HH:mm:ss"
        zuluFormat.dateFormat = "HH:mm:ss"
        zuluFormat.timeZone = TimeZone(identifier: "UTC")
    }

    // a clock that only counts up (not affected by the user changing the Mac's time)
    var nowMs: Int64 { return Int64(ProcessInfo.processInfo.systemUptime * 1000.0) }

    var flashOn: Bool { return (nowMs / 500) % 2 == 0 }
    var anyAlert: Bool { return timers.contains { $0.done } }
    var anyRunning: Bool { return timers.contains { $0.running } || stwRunning || msnRunning }

    // ---- actions
    func pressTimer(_ i: Int) {
        guard i >= 0 && i < timers.count else { return }
        let t = timers[i]
        if t.done { t.done = false }                      // acknowledge the alarm
        else if t.running { t.running = false }           // cancel
        else { t.running = true; t.endMs = nowMs + Int64(t.preset) * 1000 }
    }

    func setPreset(_ i: Int, _ secs: Int) {
        guard i >= 0 && i < timers.count && secs >= 1 else { return }
        timers[i].preset = min(86399, secs)
        var all = settings.timerSecs
        all[i] = timers[i].preset
        settings.timerSecs = all
    }

    var stwMs: Int64 { return stwBaseMs + (stwRunning ? nowMs - stwStartMs : 0) }

    func pressStopwatch() {
        if stwRunning { stwRunning = false; stwBaseMs += nowMs - stwStartMs }
        else if stwUsed { stwUsed = false; stwBaseMs = 0 }
        else { stwUsed = true; stwRunning = true; stwStartMs = nowMs }
    }

    var msnMs: Int64 { return msnBaseMs + (msnRunning ? nowMs - msnStartMs : 0) }

    func pressMission() {
        if msnRunning { msnRunning = false; msnBaseMs += nowMs - msnStartMs }
        else { msnUsed = true; msnRunning = true; msnStartMs = nowMs }
    }

    func resetMission() { msnRunning = false; msnUsed = false; msnBaseMs = 0 }

    func clearTimers() {
        for t in timers { t.running = false; t.done = false }
        stwRunning = false; stwUsed = false; stwBaseMs = 0
    }

    // called a few times a second
    func tick() {
        let now = nowMs
        for i in 0..<timers.count {
            let t = timers[i]
            if t.running && now >= t.endMs {
                t.running = false
                t.done = true
                t.doneMs = now
                onAlert?(i)
            } else if t.done && now - t.doneMs > 300000 {
                t.done = false                             // stops flashing after 5 minutes
            }
        }
    }

    // ---- text
    static func fmt(_ ms: Int64) -> String {
        let s = Int(max(0, ms) / 1000)
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60) }
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    static func fmtPreset(_ secs: Int) -> String {
        if secs >= 3600 { return String(format: "%d:%02d:%02d", secs / 3600, (secs / 60) % 60, secs % 60) }
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }

    // "5" (minutes), "5:30" or "1:05:00"  ->  seconds (0 = not understood)
    static func parseDuration(_ s: String) -> Int {
        let p = s.trimmingCharacters(in: .whitespaces).components(separatedBy: ":")
        let n = p.map { Int($0) }
        if n.contains(where: { $0 == nil }) { return 0 }
        let v = n.map { $0 ?? 0 }
        if v.count == 1 { return max(0, min(86399, v[0] * 60)) }
        if v.count == 2 { return max(0, min(86399, v[0] * 60 + v[1])) }
        if v.count == 3 { return max(0, min(86399, v[0] * 3600 + v[1] * 60 + v[2])) }
        return 0
    }

    func clockText(seconds: Bool) -> String {
        let z = settings.zulu
        let full = (z ? zuluFormat : localFormat).string(from: Date())
        let t = seconds ? full : String(full.prefix(5))
        return (z ? "ZULU " : "LCL ") + t
    }

    // the line shown on the little minimized tablet (nil = nothing to show)
    func dockInfo() -> String? {
        for (i, t) in timers.enumerated() where t.done { return flashOn ? "TMR \(i + 1) DONE" : "" }
        var best = Int64.max
        var bi = -1
        for i in 0..<timers.count where timers[i].running {
            let left = timers[i].endMs - nowMs
            if left < best { best = left; bi = i }
        }
        if bi >= 0 { return "TMR \(bi + 1) " + Clockwork.fmt(best + 999) }
        if msnRunning { return "MSN " + Clockwork.fmt(msnMs) }
        return nil
    }

    func panelLines() -> [PanelLine] {
        var l: [PanelLine] = [PanelLine(text: clockText(seconds: true), state: 0)]
        if msnUsed { l.append(PanelLine(text: "MSN " + Clockwork.fmt(msnMs), state: msnRunning ? 1 : 2)) }
        for (i, t) in timers.enumerated() {
            if t.done { l.append(PanelLine(text: "TMR\(i + 1) DONE", state: 3)) }
            else if t.running { l.append(PanelLine(text: "TMR\(i + 1) " + Clockwork.fmt(t.endMs - nowMs + 999), state: 1)) }
        }
        if stwUsed { l.append(PanelLine(text: "STW " + Clockwork.fmt(stwMs), state: stwRunning ? 1 : 2)) }
        return l
    }

    func stateColor(_ st: Int) -> NSColor {
        switch st {
        case 1: return NSColor(srgbRed: 125 / 255.0, green: 235 / 255.0, blue: 95 / 255.0, alpha: 1)
        case 2: return NSColor(srgbRed: 135 / 255.0, green: 140 / 255.0, blue: 125 / 255.0, alpha: 1)
        case 3: return flashOn ? NSColor(srgbRed: 1.0, green: 175 / 255.0, blue: 35 / 255.0, alpha: 1)
                               : NSColor(srgbRed: 1.0, green: 70 / 255.0, blue: 50 / 255.0, alpha: 1)
        default: return NSColor(srgbRed: 232 / 255.0, green: 236 / 255.0, blue: 224 / 255.0, alpha: 1)
        }
    }
}
