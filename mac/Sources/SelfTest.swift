// Built-in self-test, used by the automatic build on GitHub (TACOVERLAY_SELFTEST=<folder>): it drives the real app through
// every feature, checks the results, and saves screenshots of what it looks like. Normal users never run this.
import Cocoa
import WebKit

@MainActor
final class SelfTest {
    static var current: SelfTest?
    let app: AppController
    let dir: String
    var log = ""
    var passed = 0
    var failed = 0

    init(app: AppController, dir: String) {
        self.app = app
        self.dir = dir
    }

    nonisolated static func begin(app: AppController, dir: String) {
        Task { @MainActor in
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let t = SelfTest(app: app, dir: dir)
            SelfTest.current = t
            await t.run()
        }
    }

    // ---------------------------------------------------------------- helpers
    func note(_ s: String) {
        log += s + "\n"
        try? log.write(toFile: dir + "/selftest.txt", atomically: true, encoding: .utf8)
    }

    func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        if ok { passed += 1 } else { failed += 1 }
        note((ok ? "PASS  " : "FAIL  ") + name + (detail.isEmpty ? "" : "   -- " + detail))
    }

    func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    func eval(_ js: String) async -> String {
        return await withCheckedContinuation { cont in
            app.web.evaluateJavaScript(js) { result, error in
                if let r = result { cont.resume(returning: "\(r)") } else { cont.resume(returning: "nil " + (error?.localizedDescription ?? "")) }
            }
        }
    }

    func webSnapshot() async -> NSImage? {
        return await withCheckedContinuation { cont in
            app.web.takeSnapshot(with: nil) { image, _ in cont.resume(returning: image) }
        }
    }

    func waitLoaded(_ seconds: Double) async {
        var waited = 0.0
        while (app.web.isLoading || waited < 1.0) && waited < seconds {
            await pause(0.25)
            waited += 0.25
        }
        await pause(0.8)
    }

    func savePNG(_ img: NSImage, _ name: String) {
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: dir + "/" + name + ".png"))
    }

    func render(_ view: NSView) -> NSImage? {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        rep.size = view.bounds.size
        let img = NSImage(size: view.bounds.size)
        img.addRepresentation(rep)
        return img
    }

    // a picture of any view (settings tabs): on a plain background so see-through parts are visible
    func shotView(_ view: NSView, _ name: String) {
        guard let base = render(view) else { return }
        let size = view.bounds.size
        let out = NSImage(size: size)
        out.lockFocus()
        NSColor(srgbRed: 0.23, green: 0.37, blue: 0.54, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        base.draw(in: NSRect(origin: .zero, size: size))
        out.unlockFocus()
        savePNG(out, name)
    }

    // a picture of the tablet window, with the live page and the labels on top, on a blue background
    func shot(_ name: String) async {
        guard let cv = app.window.contentView as? TabletView else { return }
        guard let base = render(cv) else { return }
        var webImage: NSImage?
        if !app.web.isHidden { webImage = await webSnapshot() }
        let hudImage = render(cv.hud)
        let size = cv.bounds.size
        let out = NSImage(size: size)
        out.lockFocus()
        NSColor(srgbRed: 0.23, green: 0.37, blue: 0.54, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        base.draw(in: NSRect(origin: .zero, size: size))
        if let wi = webImage {
            let wf = app.web.frame
            wi.draw(in: NSRect(x: wf.minX, y: size.height - wf.maxY, width: wf.width, height: wf.height))
        }
        if let hi = hudImage, !cv.hud.isHidden {
            let hf = cv.hud.frame
            hi.draw(in: NSRect(x: hf.minX, y: size.height - hf.maxY, width: hf.width, height: hf.height))
        }
        out.unlockFocus()
        savePNG(out, name)
    }

    // ---------------------------------------------------------------- the test
    func run() async {
        let s = app.settings
        note("Tac Map Overlay self-test  v\(Updater.current)  macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")

        // ---- pure logic
        check("timer text", Clockwork.fmt(65000) == "01:05" && Clockwork.fmtPreset(330) == "5:30" && Clockwork.fmtPreset(3900) == "1:05:00")
        check("timer parsing", Clockwork.parseDuration("5") == 300 && Clockwork.parseDuration("5:30") == 330 &&
              Clockwork.parseDuration("1:05:00") == 3900 && Clockwork.parseDuration("abc") == 0)
        let b1 = ToolsMath.compute(from: "123456", to: "125456")
        check("bearing / distance 200 m east", b1.contains("DISTANCE  200 m") && b1.contains("BEARING   090"), b1.replacingOccurrences(of: "\n", with: " | "))
        let b2 = ToolsMath.compute(from: "12345678", to: "12345778")
        check("bearing / distance 1000 m north (8 digits)", b2.contains("DISTANCE  1,000 m") && b2.contains("BEARING   000"), b2.replacingOccurrences(of: "\n", with: " | "))
        check("grid parsing", ToolsMath.parseGrid("123 456") != nil && ToolsMath.parseGrid("12345") == nil && ToolsMath.parseGrid("abcd") == nil)
        check("version compare", Updater.isNewer("0.2.0", than: "0.1.9") && !Updater.isNewer("0.1.0", than: "0.1.0") && Updater.isNewer("1.0", than: "0.9.9"))
        let upd = Updater.parse("latest=9.9.9\nurl=https://example.org/x\nnotes=hello\nzip=https://github.com/Coloseal/x.zip\nsha256=" + String(repeating: "a", count: 64))
        check("update file parsing", upd?.latest == "9.9.9" && upd?.zip.hasSuffix("x.zip") == true && upd?.sha256.count == 64)
        check("shortcut ids are different", Set(HotAction.allCases.map { $0.id }).count == HotAction.allCases.count)
        check("shortcuts registered", HotKeyCenter.shared.registeredCount >= 11, "\(HotKeyCenter.shared.registeredCount) registered (10 + emergency)")
        check("every pilot button has a default", PilotActions.defaultPages.allSatisfy { $0.count == 24 } && PilotActions.slotNames.count == 24)

        // ---- the page
        await waitLoaded(30)
        let title = await eval("document.title")
        check("the map page loads", title.contains("TacMap"), title)
        check("ad block rules compiled", app.ruleList != nil)
        check("page flag for the map site", (await eval("typeof window.TAC_OVERLAY")).contains("object"))

        // ---- minimized tablet
        check("starts minimized", app.state == .docked && abs(app.window.frame.width - CGFloat(s.dockWidth)) < 1.5, "state=\(app.state) width=\(app.window.frame.width)")
        await shot("01-docked-atak")

        // ---- open
        app.expand()
        await pause(1.6)
        let want = app.openFrame(on: app.window.screen ?? NSScreen.screens[0])
        check("opens to the set size", app.state == .open && abs(app.window.frame.width - want.width) < 2, "width=\(app.window.frame.width) wanted=\(want.width)")
        await pause(0.6)
        await shot("02-open-atak")

        // ---- colour themes recolour the tablet picture (like on Windows)
        let skinBefore = app.tablet.skin
        let theme0 = s.theme
        s.theme = "JG Camo"
        app.applyAll()
        await pause(1.0)
        await shot("02b-open-atak-camo")
        s.theme = "Black"
        app.applyAll()
        await pause(1.0)
        await shot("02c-open-atak-black")
        if skinBefore != nil {
            check("a theme recolours the tablet picture", app.tablet.skin != nil && app.tablet.skin !== skinBefore)
        } else {
            note("NOTE  no tablet picture in the app, the drawn art is used")
        }
        s.theme = theme0
        app.applyAll()
        await pause(0.6)

        app.press("WEB")
        await pause(0.6)
        check("address bar shows", app.tablet.barVisible)
        await shot("03-address-bar")
        app.press("WEB")

        // ---- notes
        app.press("NOTES")
        await pause(0.6)
        check("notes pad opens", app.notesVisible && app.tablet.sidePanel === app.notesPanel)
        app.notesPanel.appendLog("[12:00:00Z] test line")
        app.notesPanel.gotoPage(3)
        await pause(0.5)
        check("mission log line", app.notesPanel.currentText.contains("test line") && app.notesPanel.currentPage == 3)
        await shot("04-notes-log")
        app.press("NOTES")
        await pause(0.4)

        // ---- tools
        app.press("CALC")
        await pause(0.5)
        check("tools panel opens", app.toolsVisible && app.tablet.sidePanel === app.toolsPanel)
        app.toolsPanel.setGrids(from: "123456", to: "125456")
        await pause(0.3)
        check("calculator in the panel", app.toolsPanel.resultText.contains("DISTANCE  200 m"), app.toolsPanel.resultText)
        await shot("05-tools-bearing")
        app.press("N9L")
        await pause(0.2)
        app.toolsPanel.nt[0].stringValue = "BP MIKE"
        app.toolsPanel.nt[1].stringValue = "270"
        await pause(0.3)
        check("9-line text", app.toolsPanel.nineLineText().contains("LINE 1 IP / BP: BP MIKE"), app.toolsPanel.nineLineText().replacingOccurrences(of: "\n", with: " | "))
        await shot("06-tools-nine-line")
        app.press("CHK")
        await pause(0.4)
        app.toolsPanel.tickFirst()
        check("checklist", app.toolsPanel.checklistCount == 8, "\(app.toolsPanel.checklistCount) items")
        await shot("07-tools-checklist")
        app.showTools(false)
        await pause(0.3)

        // ---- timers
        app.clock.setPreset(0, 2)
        app.press("TM1")
        await pause(0.4)
        check("timer running", app.clock.timers[0].running)
        await pause(2.6)
        check("timer ended with an alarm", app.clock.timers[0].done && app.clock.anyAlert)
        app.lastSig = ""
        app.refreshUI()
        await shot("08-timer-alarm")
        app.press("TM1")
        check("alarm dismissed", !app.clock.timers[0].done)
        app.press("STW")
        await pause(1.2)
        check("stopwatch counts", app.clock.stwRunning && app.clock.stwMs >= 900, "\(app.clock.stwMs) ms")
        app.press("STW")
        app.press("STW")
        check("stopwatch resets", !app.clock.stwUsed && app.clock.stwMs == 0)
        app.press("MSN")
        await pause(0.5)
        check("mission clock", app.clock.msnRunning)
        app.press("MRST")
        check("mission clock reset", !app.clock.msnUsed)
        app.clock.setPreset(0, 60)
        app.handleHotKey(id: HotAction.timer2.id, pressed: true)
        check("timer shortcut", app.clock.timers[1].running)
        app.clock.clearTimers()

        // ---- size, presets, page zoom
        let size0 = s.openSize
        app.savePreset(0)
        app.setOpenSize(55)
        check("size change", s.openSize == 55)
        app.applyPreset(0)
        check("preset restores the size", s.openSize == size0, "\(s.openSize) vs \(size0)")
        app.setPageWidth(950)
        check("page zoom", s.pageWidth == 950)
        app.press("ZRST")
        check("zoom reset", s.pageWidth == 1050)
        app.cycleOpacity()
        check("transparency cycles", s.opacity < 100)
        app.setOpacity(100)

        // ---- settings window
        app.openSettings()
        await pause(0.8)
        check("settings window opens", app.settingsOpen && app.settingsController?.window.isVisible == true)
        if let sc = app.settingsController, let cv = sc.contentView {
            for i in 0..<6 {
                sc.selectTab(i)
                await pause(0.5)
                shotView(cv, "09-settings-tab\(i + 1)")
            }
        }
        app.settingsController?.window.close()
        await pause(0.4)
        check("settings window closes", !app.settingsOpen)

        // ---- pilot display
        app.setLayout("pilot")
        await pause(1.5)
        check("pilot layout open", app.state == .open && app.layoutDef.isPilot && app.hudLabelCount() == 24, "labels=\(app.hudLabelCount())")
        await shot("10-pilot-open")
        app.press("SK:T4")         // page 1, slot T4 = TIME
        await pause(0.4)
        app.press("SK:T6")         // PAGE
        await pause(0.5)
        check("pilot page switch", app.softPage == 1)
        await shot("11-pilot-page2")
        app.press("SK:T6")
        await pause(0.5)
        await shot("12-pilot-page3")
        app.press("PG1")
        app.press("SK:T4")
        let pilotBefore = s.opacity
        app.press("VB_DN")
        check("rocker changes transparency", s.opacity == pilotBefore - 10, "\(s.opacity)")
        app.setOpacity(100)
        app.setLayout("atak")
        await pause(1.0)

        // ---- live corner view
        app.minimize()
        await pause(1.5)
        check("minimized to the little tablet", app.state == .docked)
        await shot("13-docked-again")
        app.setLiveMini(true)
        await pause(1.5)
        let screen = app.window.screen ?? NSScreen.screens[0]
        check("live view on", app.state == .live && app.window.ignoresMouseEvents, "state=\(app.state) clickthrough=\(app.window.ignoresMouseEvents)")
        let pct = app.window.frame.width / screen.frame.width * 100
        check("live view default size about 30%", abs(pct - 30) < 2, "\(pct)%")
        let mode = await eval("JSON.stringify({mode:(window.TAC_OVERLAY||{}).mode,attr:document.documentElement.getAttribute('data-overlay-mode')})")
        check("map page told it is in the live view", mode.contains("mini"), mode)
        await shot("14-live-view")

        // ---- the TOC video wall must keep the page in "full" mode while it is open (so its streams stay connected)
        s.homeURL = "http://localhost:8765/"
        app.lastHome = s.homeURL
        app.loadHome()
        await waitLoaded(10)
        let probe = "JSON.stringify({mode:(window.TAC_OVERLAY||{}).mode,attr:document.documentElement.getAttribute('data-overlay-mode'),ev:(window.__events||[]).join('>')})"
        let t1 = await eval(probe)
        check("test page in the live view = mini", t1.contains("\"mode\":\"mini\""), t1)
        _ = await eval("(function(){var d=document.createElement('div');d.setAttribute('role','dialog');d.setAttribute('aria-label','TOC Video Wall');d.id='fakewall';document.body.appendChild(d);})()")
        await pause(1.2)
        let t2 = await eval(probe)
        check("TOC video wall open while minimized = full", t2.contains("\"mode\":\"full\"") && t2.contains("\"attr\":\"full\""), t2)
        _ = await eval("document.getElementById('fakewall').remove()")
        await pause(1.2)
        let t3 = await eval(probe)
        check("TOC video wall closed = mini again", t3.contains("\"mode\":\"mini\""), t3)

        // ---- peek (hold) and moving the live view
        app.peekPressed()
        await pause(1.6)
        check("peek opens the tablet", app.state == .open)
        _ = await eval("(function(){var d=document.createElement('div');d.setAttribute('role','dialog');d.setAttribute('aria-label','TOC Video Wall');d.id='fakewall';document.body.appendChild(d);})()")
        app.peekReleased()
        await pause(1.6)
        check("letting go minimizes to the live view", app.state == .live)
        await pause(1.0)
        let t4 = await eval(probe)
        check("still full with the wall open after peek", t4.contains("\"mode\":\"full\""), t4)
        _ = await eval("document.getElementById('fakewall').remove()")
        app.toggleLiveDrag()
        await pause(0.5)
        check("move mode on", app.liveDrag && !app.window.ignoresMouseEvents)
        await shot("15-live-move-mode")
        app.setLiveDrag(false)
        check("move mode off", !app.liveDrag && app.window.ignoresMouseEvents)
        s.homeURL = Settings.defaultHome
        app.lastHome = s.homeURL
        app.setLiveMini(false)
        await pause(1.0)
        check("live view off = little tablet", app.state == .docked)

        // ---- the rest
        app.handleHotKey(id: HotAction.notes.id, pressed: true)
        await pause(1.8)
        check("notes shortcut opens the tablet with the notes", app.state == .open && app.notesVisible)
        app.setNotes(false)
        app.minimize()
        await pause(1.2)
        app.showToast("self-test")
        check("toast works", app.toastText == "self-test")

        note("RESULT  passed=\(passed)  failed=\(failed)")
        note("DONE")
        await pause(0.5)
        app.forceQuit()
    }
}
