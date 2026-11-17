// Safety net: if the app crashes it closes itself instead of lingering, if it freezes it is closed automatically,
// and after a bad exit the next start comes up in a safe state.
import Cocoa
import Darwin

private func crashSignalHandler(_ sig: Int32) {
    alarm(2)                       // if writing the log hangs too, the system ends us 2 seconds later
    Log.write("CRASH: signal \(sig) - closing the app")
    _exit(1)
}

enum CrashGuard {
    static let folder = NSHomeDirectory() + "/Library/Application Support/TacMapOverlay"
    static let markerPath = folder + "/running"
    private(set) static var previousRunEndedBadly = false

    private static let lock = NSLock()
    private static var lastBeat = ProcessInfo.processInfo.systemUptime
    private static var watchdogStarted = false

    static func start() {
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        previousRunEndedBadly = FileManager.default.fileExists(atPath: markerPath)
        try? "\(getpid())".write(toFile: markerPath, atomically: true, encoding: .utf8)

        for s in [SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGABRT, SIGTRAP] {
            signal(s, crashSignalHandler)
        }
        NSSetUncaughtExceptionHandler { exception in
            Log.write("CRASH: uncaught exception \(exception.name.rawValue): \(exception.reason ?? "")")
            _exit(1)
        }
    }

    // A normal, clean exit: remove the marker so the next start is normal.
    static func cleanExit() {
        try? FileManager.default.removeItem(atPath: markerPath)
    }

    static func heartbeat() {
        lock.lock()
        lastBeat = ProcessInfo.processInfo.systemUptime
        lock.unlock()
    }

    // A separate thread watches that the app's main thread keeps answering. If it is frozen for 20 s, the app is ended.
    static func startWatchdog() {
        if watchdogStarted { return }
        watchdogStarted = true
        heartbeat()
        let t = Thread {
            var lastLoop = ProcessInfo.processInfo.systemUptime
            while true {
                Thread.sleep(forTimeInterval: 2.0)
                let now = ProcessInfo.processInfo.systemUptime
                lock.lock()
                if now - lastLoop > 6.0 { lastBeat = now }     // the Mac was asleep, not the app
                lastLoop = now
                let silent = now - lastBeat
                lock.unlock()
                if silent > 20.0 {
                    Log.write("HANG: the app did not respond for \(Int(silent)) seconds - closing it")
                    kill(getpid(), SIGKILL)
                }
            }
        }
        t.name = "TacMapOverlay watchdog"
        t.qualityOfService = .utility
        t.start()
    }
}
