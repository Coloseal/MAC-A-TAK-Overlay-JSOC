// What every button, soft key and shortcut does, plus layouts, presets, bookmarks, export / import and updates.
import Cocoa
import WebKit
import ServiceManagement

// "start the app when I log in" (macOS 13 and newer)
enum LoginItem {
    static var isOn: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }

    static func set(_ on: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                Log.write("login item: \(error)")
            }
        }
    }
}

// a menu item that runs a closure
final class ActionItem: NSMenuItem {
    var handler: (() -> Void)?

    convenience init(_ title: String, _ h: @escaping () -> Void) {
        self.init(title: title, action: #selector(ActionItem.fire), keyEquivalent: "")
        handler = h
        target = self
    }

    @objc func fire() { handler?() }
}

extension AppController {
    // ---------------------------------------------------------------- every button
    func press(_ rawId: String) {
        var id = rawId
        if id.hasPrefix("SK:") { id = actionAt(slot: String(id.dropFirst(3))) }   // a pilot-display button: what it does on this page
        switch id {
        case "NONE": return
        case "PAGE": softPage = (softPage + 1) % 3
        case "PG1": softPage = 0
        case "PG2": softPage = 1
        case "PG3": softPage = 2
        case "BM1", "BM2", "BM3", "BM4", "BM5", "BM6": openBookmark((Int(String(id.suffix(1))) ?? 1) - 1)
        case "ZM+": setPageWidth(settings.pageWidth - 100)
        case "ZM-": setPageWidth(settings.pageWidth + 100)
        case "SZ+": setOpenSize(settings.openSize + 5)
        case "SZ-": setOpenSize(settings.openSize - 5)
        case "DRAG": toggleLiveDrag()
        case "LOG": addLogLine()
        case "LOGV": copyLog()
        case "CALC": showTools(tab: 0)
        case "N9L": showTools(tab: 1)
        case "CHK": showTools(tab: 2)
        case "PR1": applyPreset(0)
        case "PR2": applyPreset(1)
        case "PR3": applyPreset(2)
        case "SET", "GEAR", "MENU": DispatchQueue.main.async { [weak self] in self?.openSettings() }
        case "UPD": DispatchQueue.main.async { [weak self] in self?.checkUpdates(manual: true) }
        case "CLRD": DispatchQueue.main.async { [weak self] in self?.confirmClearData() }
        case "MAP": loadHome(); focusPage()
        case "WEB": toggleBar()
        case "NOTE", "NOTES": setNotes(!notesVisible)
        case "TIME", "TMR": settings.showPanel = !settings.showPanel
        case "LIVE": setLiveMini(!settings.liveMini)
        case "TM1": clock.pressTimer(0)
        case "TM2": clock.pressTimer(1)
        case "TM3": clock.pressTimer(2)
        case "TM4": clock.pressTimer(3)
        case "STW": clock.pressStopwatch()
        case "CLR": clock.clearTimers()
        case "BACK": if web.canGoBack { web.goBack() }; focusPage()
        case "FWD": if web.canGoForward { web.goForward() }; focusPage()
        case "RFSH": web.reload(); focusPage()
        case "ADS": setAdBlock(!settings.adBlock)
        case "XPAR": cycleOpacity()
        case "LOCK": setLockMouse(!settings.lockMouse)
        case "MSN": clock.pressMission()
        case "MRST": clock.resetMission()
        case "UTC": settings.zulu = !settings.zulu
        case "CPY": copyAddress()
        case "SHOT": takeScreenshot()
        case "ZRST": setPageWidth(1050)
        case "VB_UP": setOpacity(settings.opacity + 10)
        case "VB_DN": setOpacity(settings.opacity - 10)
        case "BK_UP": setOpenSize(settings.openSize + 5)
        case "BK_DN": setOpenSize(settings.openSize - 5)
        case "VC_UP": setPageWidth(settings.pageWidth - 100)       // zoom in = a narrower page
        case "VC_DN": setPageWidth(settings.pageWidth + 100)
        case "OFF": minimize()
        case "TIMERMENU": showTimerMenu()
        default: break
        }
        lastSig = ""
        refreshUI()
    }

    // ---------------------------------------------------------------- page / look
    func toggleBar() {
        tablet.barVisible = !tablet.barVisible
        if tablet.barVisible { window.makeFirstResponder(tablet.bar.field) } else { focusPage() }
    }

    func setPageWidth(_ w: Int) {
        settings.pageWidth = w
        tablet.pageWidthCSS = settings.pageWidth
        tablet.needsLayout = true
        notifyPage()
        registerScripts()
    }

    func setOpenSize(_ n: Int) {
        let c = NSPoint(x: window.frame.midX, y: window.frame.midY)
        settings.openSize = n
        if state == .open && settings.anchor == "custom" {
            let sz = openFrame(on: window.screen ?? currentScreen()).size
            settings.openOrigin = NSPoint(x: c.x - sz.width / 2, y: c.y - sz.height / 2)
        }
        applyGeometry()
    }

    func cycleSize() {
        let presets = [40, 55, 65, 78, 90]
        var next = presets[0]
        for p in presets where p > settings.openSize + 2 { next = p; break }
        setOpenSize(next)
    }

    func setOpacity(_ n: Int) {
        settings.opacity = n
        applyWindowAlpha()
    }

    func cycleOpacity() {
        let steps = [100, 85, 70, 55, 40]
        var next = 100
        for s in steps where s < settings.opacity - 2 { next = s; break }
        setOpacity(next)
        showToast("Transparency \(next)%")
    }

    func setLockMouse(_ on: Bool) { settings.lockMouse = on }

    func setAdBlock(_ on: Bool) {
        settings.adBlock = on
        lastAdBlock = on
        applyAdBlock(then: nil)
        registerScripts()
    }

    func setLayout(_ id: String) {
        settings.layout = id
        applyGeometry()
        softPage = min(softPage, 2)
    }

    // re-place and redraw everything after a size / layout / look change
    func applyGeometry() {
        syncLayout()
        tablet.pageWidthCSS = settings.pageWidth
        let screen = window.screen ?? currentScreen()
        if !animating {
            switch state {
            case .open: window.setFrame(openFrame(on: screen), display: true)
            case .docked: window.setFrame(dockFrame(on: screen), display: true)
            case .live: window.setFrame(liveFrame(on: screen), display: true)
            }
        }
        applyWindowAlpha()
        tablet.needsLayout = true
        tablet.needsDisplay = true
        notifyPage()
        lastSig = ""
        refreshUI()
    }

    // the Settings window changed something
    func applyAll() {
        if settings.homeURL != lastHome {
            lastHome = settings.homeURL
            loadHome()
        }
        if settings.adBlock != lastAdBlock {
            lastAdBlock = settings.adBlock
            applyAdBlock(then: nil)
        }
        for i in 0..<4 { clock.timers[i].preset = settings.timerSecs[i] }
        applyGeometry()
        rebuildMenu()
    }

    // ---------------------------------------------------------------- notes and tools
    func setNotes(_ show: Bool) {
        if show && toolsVisible {
            toolsVisible = false
            toolsPanel.saveAll()
        }
        notesVisible = show
        if !show { notesPanel.save() }
        applySidePanel()
        if show && state != .open && !animating {
            focusNotesOnOpen = true
            expand()
            return
        }
        if show { notesPanel.focusBox() } else { focusPage() }
        rebuildMenu()
        refreshUI()
    }

    func showTools(tab: Int) {
        if toolsVisible && toolsTab == tab {
            showTools(false)
            return
        }
        toolsTab = tab
        toolsPanel.selectTab(tab)
        showTools(true)
    }

    func showTools(_ show: Bool) {
        if show && notesVisible {
            notesVisible = false
            notesPanel.save()
        }
        toolsVisible = show
        if !show { toolsPanel.saveAll() }
        applySidePanel()
        if show && state != .open && !animating {
            expand()
            return
        }
        if show { toolsPanel.selectTab(toolsTab) } else { focusPage() }
        rebuildMenu()
        refreshUI()
    }

    func applySidePanel() {
        let p: NSView? = notesVisible ? notesPanel : (toolsVisible ? toolsPanel : nil)
        if tablet.sidePanel !== p { tablet.sidePanel = p }
        tablet.needsLayout = true
    }

    // ---------------------------------------------------------------- mission log, bookmarks, copy / screenshot
    func addLogLine() {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        if settings.zulu { f.timeZone = TimeZone(identifier: "UTC") }
        notesPanel.appendLog("[" + f.string(from: Date()) + (settings.zulu ? "Z" : "") + "] ")
        if toolsVisible {
            toolsVisible = false
            toolsPanel.saveAll()
        }
        notesVisible = true
        focusNotesOnOpen = true
        notesPanel.gotoPage(3)
        applySidePanel()
        if state != .open && !animating { expand() } else { notesPanel.focusBox() }
    }

    func copyLog() {
        if notesPanel.logText.isEmpty {
            showToast("The mission log is empty")
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(notesPanel.logText, forType: .string)
            showToast("Mission log copied")
        }
    }

    func openBookmark(_ i: Int) {
        let b = settings.bookmark(i)
        var url = ""
        if let bar = b.firstIndex(of: "|") { url = String(b[b.index(after: bar)...]).trimmingCharacters(in: .whitespaces) }
        if url.isEmpty {
            showToast("Bookmark \(i + 1) is empty - set it in Settings")
            return
        }
        if let u = WebSupport.resolveInput(url, search: settings.searchURL) {
            web.load(URLRequest(url: u))
            focusPage()
        }
    }

    func copyAddress() {
        if let u = web.url?.absoluteString, u.hasPrefix("http") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(u, forType: .string)
            showToast("Address copied")
        }
    }

    func takeScreenshot() {
        web.takeSnapshot(with: nil) { [weak self] image, _ in
            guard let img = image else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([img])
            self?.showToast("Screenshot copied - paste it anywhere")
        }
    }

    // ---------------------------------------------------------------- the timer button's menu (ATAK)
    func showTimerMenu() {
        let menu = NSMenu()
        for i in 0..<4 {
            let t = clock.timers[i]
            let label: String
            if t.done { label = "Timer \(i + 1) is up - dismiss" }
            else if t.running { label = "Timer \(i + 1)  " + Clockwork.fmt(t.endMs - clock.nowMs + 999) + "  -  cancel" }
            else { label = "Start timer \(i + 1)  (" + Clockwork.fmtPreset(t.preset) + ")" }
            menu.addItem(ActionItem(label) { [weak self] in self?.clock.pressTimer(i); self?.refreshUI() })
        }
        menu.addItem(NSMenuItem.separator())
        let stw: String
        if clock.stwUsed { stw = clock.stwRunning ? "Stopwatch  " + Clockwork.fmt(clock.stwMs) + "  -  stop" : "Stopwatch  " + Clockwork.fmt(clock.stwMs) + "  -  reset" }
        else { stw = "Start stopwatch" }
        menu.addItem(ActionItem(stw) { [weak self] in self?.clock.pressStopwatch(); self?.refreshUI() })
        let msn: String
        if clock.msnRunning { msn = "Mission clock  " + Clockwork.fmt(clock.msnMs) + "  -  pause" }
        else { msn = clock.msnUsed ? "Mission clock  " + Clockwork.fmt(clock.msnMs) + "  -  resume" : "Start mission clock" }
        menu.addItem(ActionItem(msn) { [weak self] in self?.clock.pressMission(); self?.refreshUI() })
        if clock.msnUsed { menu.addItem(ActionItem("Reset mission clock") { [weak self] in self?.clock.resetMission(); self?.refreshUI() }) }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(ActionItem("Clear all timers") { [weak self] in self?.clock.clearTimers(); self?.refreshUI() })
        menu.addItem(ActionItem(settings.showPanel ? "Hide the clock panel" : "Show the clock panel") { [weak self] in
            guard let self = self else { return }
            self.settings.showPanel = !self.settings.showPanel
            self.refreshUI()
        })
        menu.addItem(ActionItem(settings.zulu ? "Show local time" : "Show Zulu (UTC) time") { [weak self] in
            guard let self = self else { return }
            self.settings.zulu = !self.settings.zulu
            self.refreshUI()
        })
        busy += 1
        busySince = Date()
        let loc = tablet.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        menu.popUp(positioning: nil, at: loc, in: tablet)
        busy -= 1
    }

    // ---------------------------------------------------------------- layout presets
    func savePreset(_ i: Int) {
        let f = window.frame
        let parts: [String] = [
            String(settings.openSize), settings.anchor,
            settings.anchor == "custom" ? String(Int(f.midX)) : "", settings.anchor == "custom" ? String(Int(f.midY)) : "",
            String(settings.opacity), String(settings.pageWidth),
            settings.showPanel ? "1" : "0", settings.showLabels ? "1" : "0", settings.labelInset ? "1" : "0"
        ]
        settings.setPreset(i, parts.joined(separator: "|"))
        showToast("Layout saved as preset \(i + 1)")
    }

    func applyPreset(_ i: Int) {
        let s = settings.preset(i)
        if s.isEmpty {
            showToast("Preset \(i + 1) is empty - save one in Settings")
            return
        }
        let p = s.components(separatedBy: "|")
        if p.count < 9 { return }
        if let n = Int(p[0]) { settings.openSize = n }
        if p[1] == "center" || p[1] == "bottomright" || p[1] == "custom" { settings.anchor = p[1] }
        if settings.anchor == "custom", let cx = Double(p[2]), let cy = Double(p[3]) {
            let sz = openFrame(on: window.screen ?? currentScreen()).size
            settings.openOrigin = NSPoint(x: CGFloat(cx) - sz.width / 2, y: CGFloat(cy) - sz.height / 2)
        } else if settings.anchor == "custom" {
            settings.anchor = "center"
        }
        if let n = Int(p[4]) { settings.opacity = n }
        if let n = Int(p[5]) { settings.pageWidth = n }
        settings.showPanel = p[6] == "1"
        settings.showLabels = p[7] == "1"
        settings.labelInset = p[8] == "1"
        applyGeometry()
        showToast("Preset \(i + 1) applied")
    }

    // ---------------------------------------------------------------- settings window and dialogs
    func openSettings() {
        if settingsController == nil { settingsController = SettingsWindowController(app: self) }
        settingsOpen = true
        settingsController?.show()
    }

    func confirmClearData() {
        let a = NSAlert()
        a.messageText = "Clear browsing data?"
        a.informativeText = "This removes history, cookies, cache and saved site logins for the tablet's browser."
        a.addButton(withTitle: "Clear")
        a.addButton(withTitle: "Cancel")
        if present(a) == .alertFirstButtonReturn { clearBrowsingData() }
    }

    func clearBrowsingData() {
        let store = WKWebsiteDataStore.default()
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: Date(timeIntervalSince1970: 0)) { [weak self] in
            DispatchQueue.main.async { self?.showToast("Browsing data cleared") }
        }
    }

    // The file chooser is attached to the Settings window as a sheet. (macOS shows the chooser from a separate system
    // process, so it can not be forced above the tablet the way our own windows are - a sheet always shows on top of its window.)
    func chooseSkin(for layout: String) {
        guard let sw = settingsController?.window else { return }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.message = "Choose a PNG picture of the device (transparent background, same shape)"
        panel.allowedFileTypes = ["png"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: sw) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async { self?.useSkin(path: url.path, layout: layout) }
        }
    }

    func useSkin(path: String, layout: String) {
        if AppController.readSkin(path) != nil {
            settings.setSkinPath(path, for: layout)
            loadSkin()
            tablet.needsDisplay = true
        } else {
            let a = NSAlert()
            a.alertStyle = .warning
            a.messageText = "That picture can't be used"
            a.informativeText = "Please choose a normal PNG picture (under 12 MB) of the device with a transparent background."
            a.addButton(withTitle: "OK")
            present(a)
        }
    }

    func resetSkin(for layout: String) {
        settings.setSkinPath(nil, for: layout)
        loadSkin()
        tablet.needsDisplay = true
    }

    // ---------------------------------------------------------------- export / import / restart
    func exportSettings() {
        guard let sw = settingsController?.window, let id = Bundle.main.bundleIdentifier else { return }
        let panel = NSSavePanel()
        panel.message = "Export your Tac Map Overlay settings"
        panel.nameFieldStringValue = "TacMapOverlay-settings.plist"
        panel.beginSheetModal(for: sw) { [weak self] r in
            guard r == .OK, let url = panel.url else { return }
            let dict = UserDefaults.standard.persistentDomain(forName: id) ?? [:]
            if let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0) {
                try? data.write(to: url)
                self?.showToast("Settings exported")
            }
        }
    }

    func importSettings() {
        guard let sw = settingsController?.window else { return }
        let panel = NSOpenPanel()
        panel.message = "Import Tac Map Overlay settings"
        panel.allowedFileTypes = ["plist"]
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: sw) { [weak self] r in
            guard r == .OK, let url = panel.url, let self = self else { return }
            guard let data = try? Data(contentsOf: url),
                  let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                  let dict = obj as? [String: Any],
                  dict["layout"] != nil || dict["homeURL"] != nil || dict["sizePct"] != nil || dict["firstRunDone"] != nil else {
                let a = NSAlert()
                a.messageText = "That doesn't look like a Tac Map Overlay settings file."
                a.addButton(withTitle: "OK")
                self.present(a)
                return
            }
            let a = NSAlert()
            a.messageText = "Replace your current settings with this file and restart the app?"
            a.addButton(withTitle: "Replace and restart")
            a.addButton(withTitle: "Cancel")
            if self.present(a) == .alertFirstButtonReturn, let id = Bundle.main.bundleIdentifier {
                UserDefaults.standard.setPersistentDomain(dict, forName: id)
                self.relaunch()
            }
        }
    }

    func restartInSafeMode() {
        let a = NSAlert()
        a.messageText = "Restart the app with DEFAULT settings?"
        a.informativeText = "Your current settings are saved first in ~/Library/Application Support/TacMapOverlay/settings-backup.plist"
        a.addButton(withTitle: "Restart")
        a.addButton(withTitle: "Cancel")
        if present(a) != .alertFirstButtonReturn { return }
        if let id = Bundle.main.bundleIdentifier, let dict = UserDefaults.standard.persistentDomain(forName: id),
           let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0) {
            try? FileManager.default.createDirectory(atPath: CrashGuard.folder, withIntermediateDirectories: true)
            try? data.write(to: URL(fileURLWithPath: CrashGuard.folder + "/settings-backup.plist"))
        }
        settings.resetAll()
        relaunch()
    }

    // starts a fresh copy a moment after this one has closed
    func relaunch() {
        let path = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open -n \"$0\"", path]
        try? p.run()
        notesPanel.save()
        toolsPanel.saveAll()
        HotKeyCenter.shared.unregisterAll()
        CrashGuard.cleanExit()
        exit(0)
    }

    func openLogFolder() {
        let logs = NSHomeDirectory() + "/Library/Logs/TacMapOverlay.log"
        if FileManager.default.fileExists(atPath: logs) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: logs)])
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs"))
        }
    }

    // ---------------------------------------------------------------- updates
    func checkUpdates(manual: Bool) {
        Updater.check { [weak self] info in
            guard let self = self else { return }
            if let info = info {
                self.pendingUpdate = info
                self.rebuildMenu()
                if manual {
                    let a = NSAlert()
                    a.messageText = "Update available: v\(info.latest)"
                    a.informativeText = (info.notes.isEmpty ? "" : info.notes + "\n\n") + "You have v\(Updater.current)."
                    a.addButton(withTitle: Updater.canInstall(info) ? "Update now" : "Open download page")
                    a.addButton(withTitle: "Later")
                    if self.present(a) == .alertFirstButtonReturn { self.runUpdate() }
                } else {
                    self.showToast("Update available: v\(info.latest) - open the menu bar icon to install")
                }
            } else if manual {
                let a = NSAlert()
                a.messageText = "You are up to date"
                a.informativeText = "Version \(Updater.current) is the newest Mac version."
                a.addButton(withTitle: "OK")
                self.present(a)
            }
        }
    }

    func runUpdate() {
        guard let info = pendingUpdate else { return }
        if !Updater.canInstall(info) {
            if let u = URL(string: info.url) { NSWorkspace.shared.open(u) }
            return
        }
        showToast("Downloading the update...")
        Updater.install(info) { [weak self] ok, message in
            guard let self = self else { return }
            if ok {
                self.forceQuit()      // the helper script swaps the app and starts the new one
            } else {
                let a = NSAlert()
                a.alertStyle = .warning
                a.messageText = "The update could not be installed"
                a.informativeText = message + "\n\nYou can download it from the releases page instead."
                a.addButton(withTitle: "Open download page")
                a.addButton(withTitle: "Cancel")
                if self.present(a) == .alertFirstButtonReturn, let u = URL(string: info.url) { NSWorkspace.shared.open(u) }
            }
        }
    }
}
