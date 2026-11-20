// The settings window (opened from the tablet's gear or the menu-bar icon). Six tabs; every change is saved and applied at once.
import Cocoa

// A plain window that also closes when Esc is pressed.
final class SettingsWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        if attachedSheet == nil { close() } else { super.cancelOperation(sender) }
    }
}

final class ClosureTarget: NSObject {
    var fn: (() -> Void)?
    @objc func fire(_ sender: Any?) { fn?() }
}

// One tab: rows of label + control, placed from the top down.
final class FormView: NSView {
    override var isFlipped: Bool { return true }
    let contentWidth: CGFloat
    var y: CGFloat = 14
    var keep: [ClosureTarget] = []
    var refreshers: [() -> Void] = []
    let left: CGFloat = 16
    let labelWidth: CGFloat = 200

    init(width: CGFloat) {
        contentWidth = width
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 10))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func finish() { frame.size.height = y + 16 }

    func refreshAll() { for r in refreshers { r() } }

    private func target(_ fn: @escaping () -> Void) -> ClosureTarget {
        let t = ClosureTarget()
        t.fn = fn
        keep.append(t)
        return t
    }

    func title(_ s: String) {
        let l = NSTextField(labelWithString: s)
        l.font = NSFont.boldSystemFont(ofSize: 13)
        l.frame = NSRect(x: left, y: y, width: contentWidth - 2 * left, height: 18)
        addSubview(l)
        y += 26
    }

    func note(_ s: String) {
        let l = NSTextField(wrappingLabelWithString: s)
        l.font = NSFont.systemFont(ofSize: 11)
        l.textColor = NSColor.secondaryLabelColor
        let h = max(16, CGFloat((s.count / 70) + 1) * 14)
        l.frame = NSRect(x: left, y: y, width: contentWidth - 2 * left, height: h)
        addSubview(l)
        y += h + 6
    }

    func gap(_ h: CGFloat = 10) { y += h }

    func check(_ title: String, get: @escaping () -> Bool, set: @escaping (Bool) -> Void) {
        let b = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        b.frame = NSRect(x: left, y: y, width: contentWidth - 2 * left, height: 20)
        let t = target { set(b.state == .on) }
        b.target = t
        b.action = #selector(ClosureTarget.fire(_:))
        addSubview(b)
        refreshers.append { b.state = get() ? .on : .off }
        b.state = get() ? .on : .off
        y += 26
    }

    func slider(_ label: String, min lo: Double, max hi: Double, get: @escaping () -> Double, set: @escaping (Double) -> Void, suffix: String = "") {
        let l = NSTextField(labelWithString: label)
        l.frame = NSRect(x: left, y: y + 2, width: labelWidth, height: 18)
        addSubview(l)
        let s = NSSlider(value: get(), minValue: lo, maxValue: hi, target: nil, action: nil)
        s.frame = NSRect(x: left + labelWidth + 6, y: y, width: contentWidth - left * 2 - labelWidth - 70, height: 22)
        let v = NSTextField(labelWithString: "")
        v.frame = NSRect(x: contentWidth - left - 56, y: y + 2, width: 56, height: 18)
        let show = { v.stringValue = String(Int(s.doubleValue.rounded())) + suffix }
        let t = target {
            set(s.doubleValue.rounded())
            show()
        }
        s.target = t
        s.action = #selector(ClosureTarget.fire(_:))
        addSubview(s)
        addSubview(v)
        refreshers.append { s.doubleValue = get(); show() }
        show()
        y += 28
    }

    func popup(_ label: String, items: [String], get: @escaping () -> Int, set: @escaping (Int) -> Void) {
        let l = NSTextField(labelWithString: label)
        l.frame = NSRect(x: left, y: y + 3, width: labelWidth, height: 18)
        addSubview(l)
        let p = NSPopUpButton(frame: NSRect(x: left + labelWidth + 6, y: y, width: contentWidth - left * 2 - labelWidth - 6, height: 24), pullsDown: false)
        p.addItems(withTitles: items)
        let t = target { set(p.indexOfSelectedItem) }
        p.target = t
        p.action = #selector(ClosureTarget.fire(_:))
        addSubview(p)
        refreshers.append { p.selectItem(at: Swift.max(0, Swift.min(items.count - 1, get()))) }
        p.selectItem(at: Swift.max(0, Swift.min(items.count - 1, get())))
        y += 30
    }

    func text(_ label: String, get: @escaping () -> String, set: @escaping (String) -> Void) {
        let l = NSTextField(labelWithString: label)
        l.frame = NSRect(x: left, y: y + 3, width: labelWidth, height: 18)
        addSubview(l)
        let f = NSTextField(frame: NSRect(x: left + labelWidth + 6, y: y, width: contentWidth - left * 2 - labelWidth - 6, height: 24))
        f.stringValue = get()
        let t = target { set(f.stringValue) }
        f.target = t
        f.action = #selector(ClosureTarget.fire(_:))
        addSubview(f)
        refreshers.append { f.stringValue = get() }
        y += 30
    }

    // a row with two text boxes (bookmark name + address)
    func pair(_ label: String, get1: @escaping () -> String, get2: @escaping () -> String, set: @escaping (String, String) -> Void) {
        let l = NSTextField(labelWithString: label)
        l.frame = NSRect(x: left, y: y + 3, width: 60, height: 18)
        addSubview(l)
        let f1 = NSTextField(frame: NSRect(x: left + 64, y: y, width: 120, height: 24))
        let f2 = NSTextField(frame: NSRect(x: left + 190, y: y, width: contentWidth - left * 2 - 190, height: 24))
        f1.placeholderString = "name"
        f2.placeholderString = "https://..."
        f1.stringValue = get1()
        f2.stringValue = get2()
        let t = target { set(f1.stringValue, f2.stringValue) }
        for f in [f1, f2] {
            f.target = t
            f.action = #selector(ClosureTarget.fire(_:))
            addSubview(f)
        }
        refreshers.append { f1.stringValue = get1(); f2.stringValue = get2() }
        y += 30
    }

    @discardableResult
    func buttons(_ list: [(String, () -> Void)]) -> [NSButton] {
        var x = left
        var out: [NSButton] = []
        for (title, fn) in list {
            let b = NSButton(title: title, target: nil, action: nil)
            b.bezelStyle = .rounded
            b.sizeToFit()
            let w = b.frame.width + 14
            b.frame = NSRect(x: x, y: y, width: w, height: 26)
            let t = target(fn)
            b.target = t
            b.action = #selector(ClosureTarget.fire(_:))
            addSubview(b)
            out.append(b)
            x += w + 8
        }
        y += 34
        return out
    }
}

final class SettingsWindowController: NSObject, NSWindowDelegate {
    let window: NSWindow
    unowned let app: AppController
    private let settings = Settings.shared
    private var forms: [FormView] = []
    private var hotButtons: [HotAction: NSButton] = [:]
    private var recording: HotAction?
    private var monitor: Any?
    private var pilotPage = 0
    let tabView = NSTabView(frame: NSRect(x: 0, y: 0, width: 600, height: 640))

    init(app: AppController) {
        self.app = app
        window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 640), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "Tac Map Overlay - Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView?.addSubview(tabView)
        tabView.frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 600, height: 640)
        tabView.autoresizingMask = [.width, .height]
        buildGeneral()
        buildMinimized()
        buildHotkeys()
        buildPilot()
        buildTimers()
        buildBrowser()
        window.setContentSize(NSSize(width: 600, height: 640))
    }

    func show() {
        for f in forms { f.refreshAll() }
        refreshHotkeys()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func selectTab(_ i: Int) {
        if i >= 0 && i < tabView.numberOfTabViewItems { tabView.selectTabViewItem(at: i) }
    }

    // snapshot helper for the self-test
    var contentView: NSView? { return window.contentView }

    private func addTab(_ name: String, _ form: FormView) {
        form.finish()
        forms.append(form)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 600))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = form
        let item = NSTabViewItem(identifier: name)
        item.label = name
        item.view = scroll
        tabView.addTabViewItem(item)
    }

    private func changed() { app.applyAll() }

    // ---------------------------------------------------------------- 1 General
    private func buildGeneral() {
        let f = FormView(width: 560)
        f.title("Look and size")
        f.popup("Device", items: ["ATAK tablet", "Pilot display"], get: { [unowned self] in self.settings.layout == "pilot" ? 1 : 0 },
                set: { [unowned self] i in self.app.setLayout(i == 1 ? "pilot" : "atak"); self.refreshAllForms() })
        let names = Themes.all.map { $0.name }
        f.popup("Colour (this device)", items: names, get: { [unowned self] in
            let cur = self.settings.layout == "pilot" ? self.settings.pilotTheme : self.settings.theme
            return names.firstIndex(of: cur) ?? 0
        }, set: { [unowned self] i in
            if self.settings.layout == "pilot" { self.settings.pilotTheme = names[i] } else { self.settings.theme = names[i] }
            self.changed()
        })
        f.slider("Size when open", min: 25, max: 90, get: { Double(Settings.shared.openSize) }, set: { [unowned self] v in
            self.app.setOpenSize(Int(v))
        }, suffix: "%")
        f.slider("Transparency when open", min: 25, max: 100, get: { Double(Settings.shared.opacity) }, set: { [unowned self] v in
            self.settings.opacity = Int(v)
            self.changed()
        }, suffix: "%")
        f.slider("Page width (smaller = bigger text)", min: 500, max: 2400, get: { Double(Settings.shared.pageWidth) }, set: { [unowned self] v in
            self.app.setPageWidth(Int(v))
        })
        f.popup("Where it opens", items: ["Middle of the screen", "Bottom-right corner", "Where I last left it"], get: { [unowned self] in
            switch self.settings.anchor { case "bottomright": return 1; case "custom": return 2; default: return 0 }
        }, set: { [unowned self] i in
            self.settings.anchor = ["center", "bottomright", "custom"][i]
            if i == 2 && self.settings.openOrigin == nil { self.settings.anchor = "center" }
            self.changed()
        })
        f.gap()
        f.check("Open the tablet when the app starts", get: { Settings.shared.showOnStart }, set: { Settings.shared.showOnStart = $0 })
        f.check("Start the app when I log in (macOS 13 or newer)", get: { LoginItem.isOn }, set: { LoginItem.set($0) })
        f.check("Open / close animation", get: { Settings.shared.animate }, set: { [unowned self] in self.settings.animate = $0 })
        f.check("Keep the mouse inside the tablet while it is open", get: { Settings.shared.lockMouse }, set: { [unowned self] in
            self.settings.lockMouse = $0
            self.changed()
        })
        f.check("Only show it while the game is in front", get: { Settings.shared.gameOnly }, set: { [unowned self] in
            self.settings.gameOnly = $0
            self.changed()
        })
        f.text("Game app name contains", get: { Settings.shared.gameProcess }, set: { [unowned self] in self.settings.gameProcess = $0 })
        f.gap()
        f.title("Your own picture")
        f.note("Use your own PNG picture of the device instead of the drawn one (transparent background, same shape as the drawing).")
        f.buttons([
            ("Choose a picture for this device...", { [unowned self] in self.app.chooseSkin(for: self.settings.layout) }),
            ("Use the supplied picture", { [unowned self] in self.app.resetSkin(for: self.settings.layout) })
        ])
        addTab("General", f)
    }

    private func refreshAllForms() { for f in forms { f.refreshAll() } }

    // ---------------------------------------------------------------- 2 Minimized / live
    private func buildMinimized() {
        let f = FormView(width: 560)
        f.title("Live corner view")
        f.note("With this on, minimizing removes the frame and leaves just the screen in the corner of your monitor, so you can keep watching. It does not take mouse clicks, so the game keeps the mouse.")
        f.check("Show the live screen when minimized", get: { Settings.shared.liveMini }, set: { [unowned self] in
            self.app.setLiveMini($0)
        })
        f.slider("Live view size (width of the monitor)", min: 15, max: 60, get: { Double(Settings.shared.livePct) }, set: { [unowned self] v in
            self.settings.livePct = Int(v)
            self.changed()
        }, suffix: "%")
        f.popup("Corner", items: ["Bottom-right", "Bottom-left", "Top-right", "Top-left"], get: { [unowned self] in
            let x = self.settings.liveX != nil, y = self.settings.liveY != nil
            if !x && !y { return 0 }
            if x && !y { return 1 }
            if !x && y { return 2 }
            return 3
        }, set: { [unowned self] i in
            self.settings.liveX = (i == 1 || i == 3) ? 14 : nil
            self.settings.liveY = (i == 2 || i == 3) ? 14 : nil
            self.changed()
        })
        f.slider("Live view transparency", min: 25, max: 100, get: { Double(Settings.shared.dockOpacity) }, set: { [unowned self] v in
            self.settings.dockOpacity = Int(v)
            self.changed()
        }, suffix: "%")
        f.buttons([("Move it by hand...", { [unowned self] in
            self.window.close()
            self.app.moveLiveByHand()
        })])
        f.gap()
        f.title("The little tablet (live view off)")
        f.slider("Width of the little tablet", min: 200, max: 700, get: { Double(Settings.shared.dockWidth) }, set: { [unowned self] v in
            self.settings.dockWidth = Int(v)
            self.changed()
        })
        addTab("Minimized", f)
    }

    // ---------------------------------------------------------------- 3 Shortcuts
    private func buildHotkeys() {
        let f = FormView(width: 560)
        f.title("Shortcuts")
        f.note("They work while the game is in front. Click a button, then press the new keys (use Control, Option, Shift or Command with a key). Esc cancels.")
        for a in HotAction.allCases {
            let l = NSTextField(labelWithString: a.title)
            l.frame = NSRect(x: f.left, y: f.y + 3, width: f.labelWidth + 20, height: 18)
            f.addSubview(l)
            let b = NSButton(title: "", target: nil, action: nil)
            b.bezelStyle = .rounded
            b.frame = NSRect(x: f.left + f.labelWidth + 26, y: f.y, width: 190, height: 26)
            let t = ClosureTarget()
            t.fn = { [unowned self] in self.startRecording(a) }
            f.keep.append(t)
            b.target = t
            b.action = #selector(ClosureTarget.fire(_:))
            f.addSubview(b)
            let x = NSButton(title: "off", target: nil, action: nil)
            x.bezelStyle = .rounded
            x.frame = NSRect(x: b.frame.maxX + 6, y: f.y, width: 46, height: 26)
            let t2 = ClosureTarget()
            t2.fn = { [unowned self] in
                self.settings.setHotkey(a, nil)
                self.app.registerHotKeys(announce: false)
                self.refreshHotkeys()
                self.app.rebuildMenu()
                self.app.refreshUI()
            }
            f.keep.append(t2)
            x.target = t2
            x.action = #selector(ClosureTarget.fire(_:))
            f.addSubview(x)
            hotButtons[a] = b
            f.y += 32
        }
        f.gap()
        f.buttons([("Reset all shortcuts", { [unowned self] in
            self.settings.resetHotkeys()
            self.app.registerHotKeys(announce: true)
            self.refreshHotkeys()
            self.app.rebuildMenu()
            self.app.refreshUI()
        })])
        f.note("Emergency exit that always works: Control + Option + Shift + Q closes the app at once.")
        addTab("Shortcuts", f)
    }

    func refreshHotkeys() {
        for a in HotAction.allCases {
            let spec = settings.hotkey(a)
            if recording == a { hotButtons[a]?.title = "Press the new keys..." } else { hotButtons[a]?.title = HotKeyText.describe(spec) }
        }
    }

    private func startRecording(_ a: HotAction) {
        stopRecording()
        recording = a
        refreshHotkeys()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let act = self.recording else { return event }
            if event.keyCode == 53 {
                self.stopRecording()
                return nil
            }
            let mods = HotKeyText.carbon(from: event.modifierFlags)
            if mods == 0 {
                NSSound.beep()        // a plain key would stop working in the game
                return nil
            }
            self.settings.setHotkey(act, HotSpec(code: Int(event.keyCode), mods: mods))
            self.stopRecording()
            self.app.registerHotKeys(announce: true)
            self.app.rebuildMenu()
            self.app.refreshUI()
            return nil
        }
    }

    private func stopRecording() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        recording = nil
        refreshHotkeys()
    }

    // ---------------------------------------------------------------- 4 Pilot display buttons
    private func buildPilot() {
        let f = FormView(width: 560)
        f.title("Pilot display buttons")
        f.note("The pilot display has 24 buttons around the screen and three pages of them (the PAGE button switches). Choose what each one does.")
        f.check("Show the button names on the screen", get: { Settings.shared.showLabels }, set: { [unowned self] in
            self.settings.showLabels = $0
            self.changed()
        })
        f.check("Shrink the page so it never sits under the button names", get: { Settings.shared.labelInset }, set: { [unowned self] in
            self.settings.labelInset = $0
            self.changed()
        })
        f.popup("Button page", items: ["Page 1", "Page 2", "Page 3"], get: { [unowned self] in self.pilotPage }, set: { [unowned self] i in
            self.pilotPage = i
            self.refreshAllForms()
        })
        let names = PilotActions.list.map { $0.1 }
        for (idx, slot) in PilotActions.slotNames.enumerated() {
            f.popup("Button " + slot, items: names, get: { [unowned self] in
                let pg = self.settings.page(self.pilotPage)
                return PilotActions.list.firstIndex(where: { $0.0 == pg[idx] }) ?? 0
            }, set: { [unowned self] i in
                var pg = self.settings.page(self.pilotPage)
                pg[idx] = PilotActions.list[i].0
                self.settings.setPage(self.pilotPage, pg)
                self.app.refreshUI()
            })
        }
        f.gap()
        f.buttons([("Put all buttons back to the standard layout", { [unowned self] in
            self.settings.resetPages()
            self.refreshAllForms()
            self.app.refreshUI()
        })])
        addTab("Pilot buttons", f)
    }

    // ---------------------------------------------------------------- 5 Timers, bookmarks, presets
    private func buildTimers() {
        let f = FormView(width: 560)
        f.title("Timers and clock")
        f.note("Type a timer as minutes (5), minutes:seconds (5:30) or hours:minutes:seconds (1:05:00).")
        for i in 0..<4 {
            f.text("Timer \(i + 1)", get: { Clockwork.fmtPreset(Settings.shared.timerSecs[i]) }, set: { [unowned self] s in
                let secs = Clockwork.parseDuration(s)
                if secs > 0 { self.app.clock.setPreset(i, secs) }
                self.refreshAllForms()
                self.app.refreshUI()
            })
        }
        f.check("Beep when a timer ends", get: { Settings.shared.alertBeep }, set: { Settings.shared.alertBeep = $0 })
        f.check("Show the clock and timers on the screen", get: { Settings.shared.showPanel }, set: { [unowned self] in
            self.settings.showPanel = $0
            self.app.refreshUI()
        })
        f.check("Clock shows Zulu (UTC) time", get: { Settings.shared.zulu }, set: { [unowned self] in
            self.settings.zulu = $0
            self.app.refreshUI()
        })
        f.gap()
        f.title("Bookmarks (for the BM buttons)")
        for i in 0..<6 {
            f.pair("BM\(i + 1)", get1: {
                let b = Settings.shared.bookmark(i)
                if let bar = b.firstIndex(of: "|") { return String(b[b.startIndex..<bar]) }
                return b
            }, get2: {
                let b = Settings.shared.bookmark(i)
                if let bar = b.firstIndex(of: "|") { return String(b[b.index(after: bar)...]) }
                return ""
            }, set: { [unowned self] name, url in
                let n = name.replacingOccurrences(of: "|", with: " ").trimmingCharacters(in: .whitespaces)
                let u = url.trimmingCharacters(in: .whitespaces)
                self.settings.setBookmark(i, u.isEmpty ? "" : n + "|" + u)
                self.app.refreshUI()
            })
        }
        f.gap()
        f.title("Saved layouts (presets)")
        f.note("A preset remembers the size, place, transparency and zoom. Set the tablet up the way you like, then save it.")
        for i in 0..<3 {
            f.buttons([("Save the current layout as preset \(i + 1)", { [unowned self] in self.app.savePreset(i) }),
                       ("Apply preset \(i + 1)", { [unowned self] in self.app.applyPreset(i) })])
        }
        addTab("Timers & bookmarks", f)
    }

    // ---------------------------------------------------------------- 6 Browser, updates, tools
    private func buildBrowser() {
        let f = FormView(width: 560)
        f.title("Home page and browser")
        f.text("Home page (the map)", get: { Settings.shared.homeURL }, set: { [unowned self] s in
            self.settings.homeURL = s.trimmingCharacters(in: .whitespacesAndNewlines)
            self.changed()
        })
        f.text("Search engine address", get: { Settings.shared.searchURL }, set: { Settings.shared.searchURL = $0.trimmingCharacters(in: .whitespaces) })
        f.check("Block ads and trackers", get: { Settings.shared.adBlock }, set: { [unowned self] in
            self.settings.adBlock = $0
            self.changed()
        })
        f.check("Only allow secure (https) sites", get: { Settings.shared.httpsOnly }, set: { Settings.shared.httpsOnly = $0 })
        f.slider("Map sharpness (0 = automatic)", min: 0, max: 3, get: { Settings.shared.mapPixelRatio }, set: { [unowned self] v in
            self.settings.mapPixelRatio = v
            self.app.notifyPage()
        })
        f.gap()
        f.title("Updates and data")
        f.buttons([("Check for updates", { [unowned self] in self.app.checkUpdates(manual: true) }),
                   ("Clear browsing data...", { [unowned self] in self.app.confirmClearData() })])
        f.buttons([("Export settings...", { [unowned self] in self.app.exportSettings() }),
                   ("Import settings...", { [unowned self] in self.app.importSettings() })])
        f.buttons([("Restart with default settings...", { [unowned self] in self.app.restartInSafeMode() }),
                   ("Show the log file", { [unowned self] in self.app.openLogFolder() })])
        f.gap()
        f.buttons([("Quit the app", { [unowned self] in self.app.forceQuit() }),
                   ("Done", { [unowned self] in self.window.close() })])
        f.note("Tac Map Overlay for Mac is open source (MIT). It needs no special permissions and sends no data about you.")
        addTab("Browser & data", f)
    }

    func windowWillClose(_ notification: Notification) {
        stopRecording()
        app.settingsOpen = false
    }
}
