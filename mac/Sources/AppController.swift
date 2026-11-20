// The heart of the app: the see-through window with the tablet, opening / minimizing, the frameless live corner view, the
// mouse lock, the menu-bar icon, the web view rules and the glue to settings, shortcuts and updates.
// (What the buttons DO is in AppActions.swift.)
import Cocoa
import WebKit
import QuartzCore

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return false }
}

enum TabletState {
    case docked      // minimized: the little tablet in the corner
    case open        // expanded
    case live        // minimized with the live view on: no frame, just the screen in the corner
}

final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    let settings = Settings.shared
    var window: OverlayWindow!
    var tablet: TabletView!
    var web: WKWebView!
    var ruleList: WKContentRuleList?
    var statusItem: NSStatusItem?
    var settingsController: SettingsWindowController?
    let clock = Clockwork()
    var notesPanel: NotesPanel!
    var toolsPanel: ToolsPanel!

    var state: TabletState = .docked
    var animating = false
    var settingsOpen = false
    var busy = 0
    var busySince = Date()
    var hotKeyWorks = false
    var shownAt = Date.distantPast
    var previousApp: NSRunningApplication?
    var pendingUpdate: UpdateInfo?
    var lockTimer: Timer?
    var infoTimer: Timer?
    var gameTimer: Timer?
    var liveDragTimer: Timer?
    var liveDrag = false
    var notesVisible = false
    var toolsVisible = false
    var toolsTab = 0
    var softPage = 0
    var peekActive = false
    var pendingPeekClose = false
    var focusNotesOnOpen = false
    var gameHidden = false
    var lastSig = ""
    var toastText: String?
    var toastTimer: Timer?
    var lastHome = ""
    var lastAdBlock = true
    var noSave = false
    let selftestDir = ProcessInfo.processInfo.environment["TACOVERLAY_SELFTEST"]

    var layoutDef: Layout { return Layout.named(settings.layout) }
    var currentTheme: Theme { return Themes.named(settings.layout == "pilot" ? settings.pilotTheme : settings.theme) }
    var testing: Bool { return selftestDir != nil }

    // ---------------------------------------------------------------- start up
    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("starting v\(Updater.current)")
        CrashGuard.start()
        var safeMode = false
        if CrashGuard.previousRunEndedBadly && !testing {
            // last time the app did not close properly: start with the risky extras off
            Log.write("previous run ended badly - safe start")
            safeMode = true
            settings.setSkinPath(nil, for: "atak")
            settings.setSkinPath(nil, for: "pilot")
            settings.lockMouse = false
        }
        buildMainMenu()

        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.preferences.isFraudulentWebsiteWarningEnabled = true
        config.mediaTypesRequiringUserActionForPlayback = []
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 300), configuration: config)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = false
        web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        web.underPageBackgroundColor = NSColor(srgbRed: 0.05, green: 0.06, blue: 0.045, alpha: 1.0)

        notesPanel = NotesPanel()
        notesPanel.onClose = { [weak self] in self?.setNotes(false) }
        notesPanel.onEsc = { [weak self] in self?.focusPage() }
        toolsPanel = ToolsPanel()
        toolsPanel.onClose = { [weak self] in self?.showTools(false) }
        toolsPanel.onEsc = { [weak self] in self?.focusPage() }

        tablet = TabletView(web: web)
        tablet.layoutDef = layoutDef
        tablet.theme = currentTheme
        tablet.pageWidthCSS = settings.pageWidth
        tablet.hud.clock = clock
        tablet.onDockClick = { [weak self] in self?.expand() }
        tablet.onDockMoved = { [weak self] in self?.dockWasMoved() }
        tablet.onAction = { [weak self] id in self?.press(id) }
        tablet.hud.onAction = { [weak self] id in self?.press(id) }
        tablet.dragCatcher.onFinish = { [weak self] in self?.endLiveDrag() }
        tablet.bar.onBack = { [weak self] in self?.web.goBack() }
        tablet.bar.onForward = { [weak self] in self?.web.goForward() }
        tablet.bar.onReload = { [weak self] in self?.web.reload() }
        tablet.bar.onHome = { [weak self] in self?.loadHome() }
        tablet.bar.onGo = { [weak self] text in self?.go(text) }
        loadSkin()

        let screen = currentScreen()
        window = OverlayWindow(contentRect: dockFrame(on: screen), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = NSColor.clear
        window.hasShadow = false
        window.level = NSWindow.Level.screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = tablet
        tablet.showContent(false)
        applyWindowAlpha()
        window.orderFrontRegardless()

        clock.onAlert = { [weak self] i in self?.timerAlert(i) }
        HotKeyCenter.shared.onEvent = { [weak self] id, pressed in self?.handleHotKey(id: id, pressed: pressed) }
        HotKeyCenter.shared.onEmergency = { [weak self] in self?.forceQuit() }
        HotKeyCenter.shared.registerEmergency()
        registerHotKeys(announce: true)

        lastHome = settings.homeURL
        lastAdBlock = settings.adBlock
        registerScripts()
        applyAdBlock { [weak self] in self?.loadHome() }

        buildStatusItem()

        lockTimer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.lockTick() }
        RunLoop.main.add(lockTimer!, forMode: .common)
        infoTimer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.infoTick() }
        RunLoop.main.add(infoTimer!, forMode: .common)
        gameTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.gameTick() }
        RunLoop.main.add(gameTimer!, forMode: .common)

        // once a second: tell the watchdog the app is alive, and never stay stuck in a dialog for more than 3 minutes
        let beat = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            CrashGuard.heartbeat()
            guard let self = self else { return }
            if self.busy > 0 && Date().timeIntervalSince(self.busySince) > 180 {
                Log.write("a dialog was open for 3 minutes - closing it")
                NSApp.abortModal()
            }
        }
        RunLoop.main.add(beat, forMode: .common)
        CrashGuard.startWatchdog()
        refreshUI()

        if !testing {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in self?.checkUpdates(manual: false) }
        }

        if safeMode {
            let a = NSAlert()
            a.messageText = "The app did not close properly last time"
            a.informativeText = "To be safe it started with your custom tablet pictures and the mouse lock turned off. You can turn them back on in Settings.\n\n" +
                "If the app ever gets stuck: press Control + Option + Shift + Q to close it instantly."
            a.addButton(withTitle: "OK")
            present(a)
        }

        if !settings.firstRunDone && !testing {
            settings.firstRunDone = true
            let a = NSAlert()
            a.messageText = "Tac Map Overlay is running"
            a.informativeText = "A small tablet is in the bottom-right corner of your screen and there is a map icon in the menu bar at the top.\n\n" +
                "Press \(HotKeyText.describe(settings.hotkey(.toggle))) (or click the small tablet) to open it, and press it again to minimize it. " +
                "You can change the shortcuts, size and more in Settings (the gear on the tablet or the menu-bar icon).\n\n" +
                "While the tablet is open your mouse stays inside it. If that ever gets in your way, use the shortcut to minimize it."
            a.addButton(withTitle: "Open the tablet")
            present(a)
            expand()
        } else if settings.showOnStart && !testing {
            expand()
        } else if settings.liveMini && !testing {
            enterLive()
        }

        if let dir = selftestDir { SelfTest.begin(app: self, dir: dir) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        expand()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        notesPanel.save()
        toolsPanel.saveAll()
        HotKeyCenter.shared.unregisterAll()
        CrashGuard.cleanExit()
    }

    // Closes the app right now, no matter what it is doing (menu "Quit", Settings "Quit app", Control+Option+Shift+Q).
    func forceQuit() {
        Log.write("quit")
        notesPanel?.save()
        toolsPanel?.saveAll()
        HotKeyCenter.shared.unregisterAll()
        CrashGuard.cleanExit()
        exit(0)
    }

    // ---------------------------------------------------------------- menus
    func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit Tac Map Overlay", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        editItem.submenu = edit
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(NSMenuItem.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = main
    }

    func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let url = Bundle.main.resourceURL?.appendingPathComponent("AppIcon.png"), let img = NSImage(contentsOf: url) {
                img.size = NSSize(width: 18, height: 18)
                img.isTemplate = false
                button.image = img
            } else if let img = NSImage(systemSymbolName: "map", accessibilityDescription: "Tac Map Overlay") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "TAK"
            }
        }
        statusItem = item
        rebuildMenu()
    }

    func rebuildMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()
        func add(_ title: String, _ sel: Selector, checked: Bool = false) {
            let m = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            m.target = self
            if checked { m.state = .on }
            menu.addItem(m)
        }
        if let u = pendingUpdate {
            add("Update available: v\(u.latest) - install", #selector(menuUpdate))
            menu.addItem(NSMenuItem.separator())
        }
        add("Open / minimize tablet     \(HotKeyText.describe(settings.hotkey(.toggle)))", #selector(menuToggle))
        add("Notes pad", #selector(menuNotes), checked: notesVisible)
        add("Live corner view", #selector(menuLive), checked: settings.liveMini)
        add("Go to the map (home)", #selector(menuHome))
        add("Settings...", #selector(menuSettings))
        add("Check for updates", #selector(menuCheck))
        menu.addItem(NSMenuItem.separator())
        add("Quit", #selector(menuQuit))
        item.menu = menu
    }

    @objc func menuToggle() { toggle() }
    @objc func menuNotes() { notesHotkey() }
    @objc func menuLive() { setLiveMini(!settings.liveMini) }
    @objc func menuHome() { loadHome(); expand() }
    @objc func menuSettings() { openSettings() }
    @objc func menuCheck() { checkUpdates(manual: true) }
    @objc func menuQuit() { forceQuit() }
    @objc func menuUpdate() { runUpdate() }

    // ---------------------------------------------------------------- helpers
    @discardableResult
    func present(_ alert: NSAlert) -> NSApplication.ModalResponse {
        busy += 1
        busySince = Date()
        NSApp.activate(ignoringOtherApps: true)
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)
        let r = alert.runModal()
        busy -= 1
        return r
    }

    func currentScreen() -> NSScreen {
        let p = NSEvent.mouseLocation
        for s in NSScreen.screens where NSMouseInRect(p, s.frame, false) { return s }
        if let w = window, let s = w.screen { return s }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    func clampInto(_ r: NSRect, _ area: NSRect) -> NSRect {
        var o = r
        o.origin.x = max(area.minX, min(o.origin.x, area.maxX - o.width))
        o.origin.y = max(area.minY, min(o.origin.y, area.maxY - o.height))
        return o
    }

    func openFrame(on screen: NSScreen) -> NSRect {
        let L = layoutDef
        let vf = screen.visibleFrame
        var w = vf.width * CGFloat(settings.openSize) / 100.0
        var h = L.height(forWidth: w)
        let maxH = vf.height * 0.95
        if h > maxH {
            h = maxH
            w = h * L.logical.width / L.logical.height
        }
        w = w.rounded()
        h = h.rounded()
        var r = NSRect(x: (vf.midX - w / 2).rounded(), y: (vf.midY - h / 2).rounded(), width: w, height: h)
        switch settings.anchor {
        case "bottomright":
            r.origin = NSPoint(x: vf.maxX - w - 16, y: vf.minY + 16)
        case "custom":
            if let o = settings.openOrigin {
                let mid = NSPoint(x: o.x + w / 2, y: o.y + h / 2)
                for s in NSScreen.screens where NSMouseInRect(mid, s.frame, false) { r.origin = o }
            }
        default:
            break
        }
        return clampInto(r, vf)
    }

    func dockFrame(on screen: NSScreen) -> NSRect {
        let vf = screen.visibleFrame
        let w = CGFloat(settings.dockWidth)
        let h = layoutDef.height(forWidth: w).rounded()
        var r = NSRect(x: vf.maxX - w - 16, y: vf.minY + 16, width: w, height: h)
        if let dx = settings.dockX, let dy = settings.dockY {
            r.origin = NSPoint(x: screen.frame.minX + CGFloat(dx), y: screen.frame.maxY - CGFloat(dy) - h)
            r = clampInto(r, screen.frame)
        }
        return r
    }

    func liveFrame(on screen: NSScreen) -> NSRect {
        let L = layoutDef
        let f = screen.frame
        var w = f.width * CGFloat(settings.livePct) / 100.0
        var h = L.height(forWidth: w)
        let maxH = f.height * 0.6
        if h > maxH {
            h = maxH
            w = h * L.logical.width / L.logical.height
        }
        w = w.rounded()
        h = h.rounded()
        var x = screen.visibleFrame.maxX - w
        var y = screen.visibleFrame.minY
        if let lx = settings.liveX { x = f.minX + CGFloat(lx) }
        if let ly = settings.liveY { y = f.maxY - CGFloat(ly) - h }
        return clampInto(NSRect(x: x, y: y, width: w, height: h), f)
    }

    // where the tablet goes when it is minimized
    func minimizedFrame(on screen: NSScreen) -> NSRect {
        return settings.liveMini ? liveFrame(on: screen) : dockFrame(on: screen)
    }

    func applyWindowAlpha() {
        let pct = state == .open ? settings.opacity : settings.dockOpacity
        window.alphaValue = CGFloat(max(25, min(100, pct))) / 100.0
    }

    func animateFrame(to frame: NSRect, completion: @escaping () -> Void) {
        if !settings.animate {
            window.setFrame(frame, display: true)
            completion()
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.26
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.window.animator().setFrame(frame, display: true)
        }, completionHandler: {
            completion()
        })
    }

    func loadSkin() {
        let L = layoutDef
        if let p = settings.skinPath(for: settings.layout), let img = AppController.readSkin(p) {
            tablet.skin = img
            tablet.opening = OpeningDetector.detect(img, logical: L.logical, key: p)
            return
        }
        // the supplied tablet case picture is the default look of the ATAK tablet
        if settings.layout == "atak", let url = Bundle.main.resourceURL?.appendingPathComponent("default-tablet.png"),
           let img = AppController.readSkin(url.path) {
            tablet.skin = PhotoTheme.themed(img, name: currentTheme.name, screen: Layout.atak.screen, logical: Layout.atak.logical)
            tablet.opening = OpeningDetector.detect(img, logical: L.logical, key: url.path)
        } else {
            tablet.skin = nil
            tablet.opening = nil
        }
    }

    func syncLayout() {
        if tablet.layoutDef.id != layoutDef.id { tablet.layoutDef = layoutDef }
        tablet.theme = currentTheme
        loadSkin()
    }

    static func readSkin(_ path: String) -> NSImage? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? NSNumber, size.intValue > 0, size.intValue < 12_000_000 else { return nil }
        guard let img = NSImage(contentsOfFile: path), img.isValid else { return nil }
        let s = img.size
        if s.width < 50 || s.height < 20 || s.width > 8000 || s.height > 8000 { return nil }
        return img
    }

    // ---------------------------------------------------------------- open / minimize / live
    func toggle() {
        if animating { return }
        if state == .open { minimize() } else { expand() }
    }

    func expand() {
        if animating || state == .open { return }
        let me = NSRunningApplication.current
        if let f = NSWorkspace.shared.frontmostApplication, f.processIdentifier != me.processIdentifier {
            previousApp = f
        }
        if gameHidden { gameHidden = false }
        let target = openFrame(on: currentScreen())
        let fromLive = (state == .live)
        animating = true
        if fromLive {
            // coming out of the live view: draw the frame over it first (same size and place), then expand from there
            liveDrag = false
            tablet.dragActive = false
            window.ignoresMouseEvents = false
        }
        state = .open
        tablet.isExpanded = false
        tablet.mode = .art
        tablet.showContent(false)
        syncLayout()
        applyWindowAlpha()
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        if fromLive { notifyPage() }
        refreshUI()
        animateFrame(to: target) { [weak self] in self?.finishOpen() }
    }

    func finishOpen() {
        animating = false
        shownAt = Date()
        tablet.isExpanded = true
        tablet.pageWidthCSS = settings.pageWidth
        applySidePanel()
        tablet.showContent(true)
        window.makeKeyAndOrderFront(nil)
        if focusNotesOnOpen && notesVisible {
            focusNotesOnOpen = false
            notesPanel.focusBox()
        } else {
            window.makeFirstResponder(web)
        }
        refreshUI()
        notifyPage()
        if pendingPeekClose {
            pendingPeekClose = false
            DispatchQueue.main.async { [weak self] in self?.minimize() }
        }
    }

    func minimize() {
        if animating || state != .open { return }
        saveOpenPosition()
        let screen = window.screen ?? currentScreen()
        animating = true
        state = .docked
        tablet.isExpanded = false
        tablet.showContent(false)
        applyWindowAlpha()
        refreshUI()
        animateFrame(to: minimizedFrame(on: screen)) { [weak self] in self?.finishClose() }
    }

    func finishClose() {
        animating = false
        if settings.liveMini { enterLive() } else { applyWindowAlpha() }
        if let prev = previousApp {
            prev.activate(options: [])
            previousApp = nil
        }
        refreshUI()
        notifyPage()
    }

    // the little minimized tablet was dragged somewhere: remember the place
    func dockWasMoved() {
        guard state == .docked, !animating else { return }
        let f = window.frame
        let screen = window.screen ?? currentScreen()
        settings.dockX = Double(f.minX - screen.frame.minX)
        settings.dockY = Double(screen.frame.maxY - f.maxY)
    }

    func saveOpenPosition() {
        settings.openOrigin = window.frame.origin
    }

    // minimized + live view on: no frame, only the screen in the corner (click-through: the game keeps the mouse)
    func enterLive() {
        if state == .open || animating { return }
        state = .live
        let screen = window.screen ?? currentScreen()
        tablet.isExpanded = false
        tablet.mode = .live
        window.setFrame(liveFrame(on: screen), display: true)
        tablet.pageWidthCSS = settings.pageWidth
        tablet.showContent(true)
        window.ignoresMouseEvents = !liveDrag
        applyWindowAlpha()
        window.orderFrontRegardless()
        refreshUI()
        notifyPage()
        if pendingLiveMove { pendingLiveMove = false; setLiveDrag(true) }
    }

    // back from the live view to the little tablet (the live setting was switched off)
    func leaveLive() {
        if state != .live { return }
        liveDrag = false
        tablet.dragActive = false
        window.ignoresMouseEvents = false
        state = .docked
        tablet.mode = .art
        tablet.showContent(false)
        syncLayout()
        window.setFrame(dockFrame(on: window.screen ?? currentScreen()), display: true)
        applyWindowAlpha()
        refreshUI()
        notifyPage()
    }

    func setLiveMini(_ on: Bool) {
        if settings.liveMini == on { return }
        settings.liveMini = on
        rebuildMenu()
        if state != .open && !animating {
            if on { enterLive() } else { leaveLive() }
        }
        refreshUI()
        if on && state == .open { showToast("Live screen is ON: minimize the tablet and the screen stays in the corner, without the frame.") }
    }

    // ---- moving the live view by hand
    func setLiveDrag(_ on: Bool) {
        if on && !(state == .live && !animating) { return }
        liveDrag = on
        tablet.dragActive = on
        window.ignoresMouseEvents = !on
        liveDragTimer?.invalidate()
        if on {
            liveDragTimer = Timer.scheduledTimer(withTimeInterval: 12.0, repeats: false) { [weak self] _ in self?.setLiveDrag(false) }
        }
        refreshUI()
    }

    func toggleLiveDrag() {
        if !settings.liveMini { showToast("Switch the LIVE view on first."); return }
        if state == .open { showToast("Minimize the tablet first, then move the live view."); return }
        setLiveDrag(!liveDrag)
    }

    func endLiveDrag() {
        guard state == .live else { return }
        let f = window.frame
        let screen = window.screen ?? currentScreen()
        let b = screen.frame
        // snaps to the corner / bottom when dropped near it
        settings.liveX = f.maxX >= b.maxX - 30 ? nil : Double(f.minX - b.minX)
        settings.liveY = f.minY <= screen.visibleFrame.minY + 30 ? nil : Double(b.maxY - f.maxY)
        setLiveDrag(false)
        window.setFrame(liveFrame(on: screen), display: true)
    }

    // Settings > "Move it by hand"
    func moveLiveByHand() {
        if !settings.liveMini { setLiveMini(true) }
        if state == .open && !animating {
            pendingLiveMove = true
            minimize()
        } else if state == .live {
            setLiveDrag(true)
        }
    }
    var pendingLiveMove = false

    func windowDidMove(_ notification: Notification) {
        if state == .open && !animating && tablet.isExpanded {
            settings.openOrigin = window.frame.origin
            settings.anchor = "custom"
        }
    }

    // Clicking the game (another app) while the mouse is free minimizes the tablet so it never covers the game.
    func applicationDidResignActive(_ notification: Notification) {
        if busy > 0 { return }
        peekActive = false
        // the Settings window never stays around once you go to another app (unless a file chooser is open on it)
        if settingsOpen, let sw = settingsController?.window, sw.attachedSheet == nil {
            sw.close()
        }
        if state == .open && !animating && !settingsOpen && Date().timeIntervalSince(shownAt) > 0.8 {
            minimize()
        }
    }

    // ---------------------------------------------------------------- mouse lock
    func lockTick() {
        if state != .open || animating || settingsOpen || busy > 0 { return }
        if !settings.lockMouse || !hotKeyWorks || !NSApp.isActive { return }
        let p = NSEvent.mouseLocation
        let r = window.frame.insetBy(dx: 2, dy: 2)
        if r.contains(p) { return }
        let cx = min(max(p.x, r.minX), r.maxX - 1)
        let cy = min(max(p.y, r.minY), r.maxY - 1)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        _ = CGWarpMouseCursorPosition(CGPoint(x: cx, y: primaryHeight - cy))
    }

    // ---------------------------------------------------------------- game-aware: only show while the game is in front
    func gameTick() {
        if !settings.gameOnly || state == .open || animating {
            if gameHidden { gameHidden = false; window.orderFrontRegardless() }
            return
        }
        var isGame = true
        let want = settings.gameProcess.lowercased()
        if !want.isEmpty, let f = NSWorkspace.shared.frontmostApplication, f.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            let name = (f.localizedName ?? "").lowercased()
            let bid = (f.bundleIdentifier ?? "").lowercased()
            let exe = (f.executableURL?.lastPathComponent ?? "").lowercased()
            isGame = name.contains(want) || bid.contains(want) || exe.contains(want)
        }
        if !isGame && !gameHidden {
            gameHidden = true
            window.orderOut(nil)
        } else if isGame && gameHidden {
            gameHidden = false
            window.orderFrontRegardless()
        }
    }

    // ---------------------------------------------------------------- shortcuts
    func registerHotKeys(announce: Bool) {
        var failed: [String] = []
        for a in HotAction.allCases {
            if let spec = settings.hotkey(a) {
                let ok = HotKeyCenter.shared.register(id: a.id, code: spec.code, modifiers: spec.mods)
                if !ok { failed.append(a.title + "  " + HotKeyText.describe(spec)) }
                if a == .toggle { hotKeyWorks = ok }
            } else {
                HotKeyCenter.shared.unregister(id: a.id)
                if a == .toggle { hotKeyWorks = false }
            }
        }
        if !failed.isEmpty && announce && !testing {
            let a = NSAlert()
            a.alertStyle = .warning
            a.messageText = "Some shortcuts can't be used"
            a.informativeText = "These are already taken by another app:\n\n" + failed.joined(separator: "\n") +
                "\n\nPick different ones in Settings. You can always open the tablet from the map icon in the menu bar. " +
                "The mouse lock is switched off while the open / minimize shortcut does not work."
            a.addButton(withTitle: "OK")
            present(a)
        }
    }

    func handleHotKey(id: UInt32, pressed: Bool) {
        guard let a = HotAction.allCases.first(where: { $0.id == id }) else { return }
        switch a {
        case .peek:
            if pressed { peekPressed() } else { peekReleased() }
        case .toggle:
            if pressed { toggle() }
        case .size:
            if pressed { cycleSize() }
        case .opacity:
            if pressed { cycleOpacity() }
        case .notes:
            if pressed { notesHotkey() }
        case .live:
            if pressed { setLiveMini(!settings.liveMini) }
        case .drag:
            if pressed { toggleLiveDrag() }
        case .timer1:
            if pressed { clock.pressTimer(0); refreshUI() }
        case .timer2:
            if pressed { clock.pressTimer(1); refreshUI() }
        case .stopwatch:
            if pressed { clock.pressStopwatch(); refreshUI() }
        }
    }

    // HOLD-to-peek: the shortcut opens the tablet; letting go of it minimizes again.
    func peekPressed() {
        if state == .open || animating { return }
        peekActive = true
        pendingPeekClose = false
        expand()
    }

    func peekReleased() {
        if !peekActive { return }
        peekActive = false
        if animating { pendingPeekClose = true } else if state == .open { minimize() }
    }

    func notesHotkey() {
        if state != .open && !animating {
            notesVisible = true
            toolsVisible = false
            focusNotesOnOpen = true
            expand()
        } else {
            setNotes(!notesVisible)
        }
    }

    // ---------------------------------------------------------------- timers
    func timerAlert(_ i: Int) {
        if settings.alertBeep { playAlarm() }
        showToast("TIMER \(i + 1) (" + Clockwork.fmtPreset(clock.timers[i].preset) + ") is up")
        refreshUI()
    }

    func playAlarm() {
        for n in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(n) * 0.4) {
                if let s = NSSound(named: NSSound.Name("Ping")) { s.stop(); s.play() } else { NSSound.beep() }
            }
        }
    }

    func showToast(_ text: String) {
        toastText = text
        tablet.hud.toast = text
        tablet.hud.needsDisplay = true
        if let b = statusItem?.button { b.title = " " + text }
        toastTimer?.invalidate()
        toastTimer = Timer.scheduledTimer(withTimeInterval: 2.2, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.toastText = nil
            self.tablet.hud.toast = nil
            self.tablet.hud.needsDisplay = true
            self.statusItem?.button?.title = ""
        }
        if testing { Log.write("toast: " + text) }
    }

    // ---------------------------------------------------------------- what is shown on the tablet
    func keyText(_ id: String) -> (String, Int) {
        switch id {
        case "NONE": return ("", 0)
        case "MAP": return ("MAP", 0)
        case "PAGE": return ("PAGE \(softPage + 1)/3", 0)
        case "PG1", "PG2", "PG3":
            let n = Int(String(id.suffix(1))) ?? 1
            return ("PAGE \(n)", softPage == n - 1 ? 1 : 0)
        case "BM1", "BM2", "BM3", "BM4", "BM5", "BM6":
            let n = Int(String(id.suffix(1))) ?? 1
            let nm = bookmarkName(n - 1)
            return nm.isEmpty ? ("BM\(n) -", 2) : (nm, 0)
        case "LOG": return ("LOG +", 0)
        case "LOGV": return ("COPY LOG", 0)
        case "CALC": return ("BRG/DIST", toolsVisible && toolsTab == 0 ? 1 : 0)
        case "N9L": return ("9-LINE", toolsVisible && toolsTab == 1 ? 1 : 0)
        case "CHK": return ("CHECKLIST", toolsVisible && toolsTab == 2 ? 1 : 0)
        case "PR1", "PR2", "PR3":
            let n = Int(String(id.suffix(1))) ?? 1
            return ("PRESET \(n)", settings.preset(n - 1).isEmpty ? 2 : 0)
        case "SET": return ("SETTINGS", 0)
        case "UPD": return ("UPDATE", 0)
        case "CLRD": return ("CLEAR DATA", 0)
        case "ZM+": return ("ZOOM +", 0)
        case "ZM-": return ("ZOOM -", 0)
        case "SZ+": return ("SIZE +", 0)
        case "SZ-": return ("SIZE -", 0)
        case "DRAG": return ("MOVE LIVE", liveDrag ? 1 : 0)
        case "WEB": return ("WEB", tablet.barVisible ? 1 : 0)
        case "NOTE": return ("NOTE", notesVisible ? 1 : 0)
        case "TIME": return ("TIME", settings.showPanel ? 1 : 0)
        case "LIVE": return (settings.liveMini ? "LIVE ON" : "LIVE OFF", settings.liveMini ? 1 : 0)
        case "TM1", "TM2", "TM3", "TM4":
            let i = (Int(String(id.suffix(1))) ?? 1) - 1
            let t = clock.timers[i]
            if t.done { return ("TMR\(i + 1) DONE", 3) }
            if t.running { return ("TMR\(i + 1) " + Clockwork.fmt(t.endMs - clock.nowMs + 999), 1) }
            return ("TMR\(i + 1) " + Clockwork.fmtPreset(t.preset), 0)
        case "STW":
            if !clock.stwUsed { return ("STOPWATCH", 0) }
            return ("STW " + Clockwork.fmt(clock.stwMs), clock.stwRunning ? 1 : 2)
        case "BACK": return ("BACK", web.canGoBack ? 0 : 2)
        case "FWD": return ("FWD", web.canGoForward ? 0 : 2)
        case "RFSH": return ("REFRESH", 0)
        case "ADS": return (settings.adBlock ? "ADS ON" : "ADS OFF", settings.adBlock ? 1 : 2)
        case "XPAR": return ("XPAR \(settings.opacity)", 0)
        case "LOCK": return (settings.lockMouse ? "LOCK" : "FREE", settings.lockMouse ? 1 : 2)
        case "MSN":
            if !clock.msnUsed { return ("MSN CLK", 0) }
            return ("MSN " + Clockwork.fmt(clock.msnMs), clock.msnRunning ? 1 : 2)
        case "MRST": return ("MSN RST", 0)
        case "UTC": return (settings.zulu ? "ZULU" : "LOCAL", 0)
        case "CPY": return ("COPY URL", 0)
        case "SHOT": return ("SCREENSHOT", 0)
        case "ZRST": return ("ZOOM " + String(Int((1050.0 * 100.0 / Double(max(1, settings.pageWidth))).rounded())), 0)
        default: return (id, 0)
        }
    }

    func bookmarkName(_ i: Int) -> String {
        let b = settings.bookmark(i)
        if b.isEmpty { return "" }
        var n = b
        if let bar = b.firstIndex(of: "|") { n = String(b[b.startIndex..<bar]) }
        n = n.trimmingCharacters(in: .whitespaces)
        return n.count > 11 ? String(n.prefix(11)) : n
    }

    // the action behind a soft-key slot on the page that is showing
    func actionAt(slot: String) -> String {
        guard let idx = PilotActions.slotNames.firstIndex(of: slot) else { return "NONE" }
        let pg = settings.page(softPage)
        return idx < pg.count && !pg[idx].isEmpty ? pg[idx] : "NONE"
    }

    func hudLabelCount() -> Int { return tablet.hud.labels.count }

    func refreshUI() {
        guard tablet != nil else { return }
        if tablet.layoutDef.id != layoutDef.id { tablet.layoutDef = layoutDef }
        tablet.statusKey = HotKeyText.describe(settings.hotkey(.toggle))
        tablet.statusInfo = clock.dockInfo() ?? clock.clockText(seconds: false)
        tablet.lockMouse = settings.lockMouse && hotKeyWorks
        tablet.alert = clock.anyAlert && clock.flashOn
        tablet.liveOn = settings.liveMini
        tablet.notesOn = notesVisible || toolsVisible
        tablet.timerLit = clock.anyRunning
        tablet.needsDisplay = true
        let hud = tablet.hud
        hud.clock = clock
        hud.showPanel = settings.showPanel
        hud.showLabels = settings.showLabels
        if layoutDef.isPilot {
            hud.labels = layoutDef.softKeys.map { k -> HUDLabel in
                let t = keyText(actionAt(slot: k.id))
                return HUDLabel(id: k.id, text: t.0, state: t.1)
            }
        } else {
            hud.labels = []
        }
        hud.needsDisplay = true
    }

    // a few times a second: look at the timers and redraw only when something on screen would look different
    func infoTick() {
        clock.tick()
        var sig = "\(state)\(animating)\(clock.anyAlert && clock.flashOn)"
        switch state {
        case .open:
            if settings.showPanel { sig += clock.panelLines().map { $0.text }.joined(separator: "|") }
            if layoutDef.isPilot && settings.showLabels {
                for k in layoutDef.softKeys { let t = keyText(actionAt(slot: k.id)); sig += t.0 + "\(t.1)|" }
            }
        case .docked:
            sig += (clock.dockInfo() ?? "") + clock.clockText(seconds: false)
        case .live:
            sig += clock.anyAlert ? "A" : ""
        }
        sig += (toastText ?? "")
        if sig == lastSig { return }
        lastSig = sig
        refreshUI()
    }

    // ---------------------------------------------------------------- the page
    func homeHost() -> String {
        var s = settings.homeURL.trimmingCharacters(in: .whitespaces)
        if !s.contains("://") { s = "https://" + s }
        return URL(string: s)?.host?.lowercased() ?? ""
    }

    // the sharpness the map site is told it has: the real value of the open tablet, between 1 and 2
    func mapPixelRatio() -> Double {
        if settings.mapPixelRatio >= 0.5 { return max(0.5, min(3.0, settings.mapPixelRatio)) }
        let L = layoutDef
        let screen = window?.screen ?? currentScreen()
        let openW = openFrame(on: screen).width
        let holePts = tablet.screenRect.width * openW / L.logical.width
        let eff = holePts * screen.backingScaleFactor / CGFloat(max(300, settings.pageWidth))
        return Double(max(1.0, min(2.0, eff)))
    }

    func buildHomeScript() -> String? {
        let host = homeHost()
        if host.isEmpty { return nil }
        let L = layoutDef
        let live = (state == .live)
        let vw = settings.pageWidth
        let sr = tablet.screenRect
        var vh = Int(CGFloat(vw) * sr.height / sr.width)
        if live, let w = window, w.frame.width > 0 { vh = Int(CGFloat(vw) * w.frame.height / w.frame.width) }
        return PageScript.home(host: host, tag: L.pageTag, aspect: Double(sr.width / sr.height),
                               mode: live ? "mini" : "full", vw: vw, vh: vh, dpr: mapPixelRatio())
    }

    // scripts that run in every new page
    func registerScripts() {
        let ucc = web.configuration.userContentController
        ucc.removeAllUserScripts()
        if let hs = buildHomeScript() {
            ucc.addUserScript(WKUserScript(source: hs, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        if settings.adBlock {
            ucc.addUserScript(WKUserScript(source: PageScript.youTube, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
    }

    // the mode / layout changed: tell the page that is already open (your map site only)
    func notifyPage() {
        registerScripts()
        if let hs = buildHomeScript() {
            web.evaluateJavaScript(hs + ";window.dispatchEvent(new Event('resize'));", completionHandler: nil)
        }
    }

    func applyAdBlock(then: (() -> Void)?) {
        let ucc = web.configuration.userContentController
        if let l = ruleList {
            ucc.remove(l)
            ruleList = nil
        }
        if !settings.adBlock {
            then?()
            return
        }
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "TacBlockList", encodedContentRuleList: WebSupport.contentRuleJSON()) { [weak self] list, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let list = list {
                    self.web.configuration.userContentController.add(list)
                    self.ruleList = list
                    Log.write("ad block rules loaded")
                } else {
                    Log.write("ad block rules failed: \(String(describing: error))")
                }
                then?()
            }
        }
    }

    func loadHome() {
        registerScripts()      // the map site's address may have changed: the scripts must match it
        if let u = WebSupport.resolveInput(settings.homeURL, search: settings.searchURL) {
            web.load(URLRequest(url: u))
        }
    }

    func go(_ text: String) {
        if let u = WebSupport.resolveInput(text, search: settings.searchURL) {
            web.load(URLRequest(url: u))
            focusPage()
        } else {
            NSSound.beep()
        }
    }

    func focusPage() {
        if state == .open && !animating { window.makeFirstResponder(web) }
    }

    // ---- navigation rules (the "secure browser" part)
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        let scheme = (url.scheme ?? "").lowercased()
        let isMain = navigationAction.targetFrame?.isMainFrame ?? true
        if !isMain {
            decisionHandler(.allow)
            return
        }
        if scheme == "http" {
            if settings.httpsOnly, let host = url.host, !WebSupport.isLocalHost(host) {
                var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
                comps?.scheme = "https"
                if let upgraded = comps?.url {
                    decisionHandler(.cancel)
                    webView.load(URLRequest(url: upgraded))
                    return
                }
            }
            decisionHandler(.allow)
            return
        }
        if scheme == "https" || scheme == "about" || scheme == "blob" {
            decisionHandler(.allow)
            return
        }
        Log.write("blocked navigation to scheme: \(scheme)")
        decisionHandler(.cancel)
    }

    // files that would be downloaded are not accepted (nothing gets saved to the Mac)
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.canShowMIMEType {
            decisionHandler(.allow)
        } else {
            Log.write("blocked a download")
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let u = webView.url, let s = u.scheme, s != "about" {
            tablet.bar.field.stringValue = u.absoluteString
        }
        refreshUI()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshUI()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showError(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showError(error)
    }

    func showError(_ error: Error) {
        let ns = error as NSError
        if ns.code == NSURLErrorCancelled { return }
        var text = ns.localizedDescription
        text = text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        let html = "<html><body style='background:#0d0f0b;color:#cdd6bd;font-family:-apple-system,sans-serif;padding:40px'>" +
            "<h2>This page could not be opened</h2><p>\(text)</p><p>Check the address or your connection, then press reload.</p></body></html>"
        web.loadHTMLString(html, baseURL: nil)
    }

    // links that want a new window just open in this one; scripts cannot open windows on their own
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let u = navigationAction.request.url,
           let s = u.scheme?.lowercased(), s == "https" || s == "http" {
            webView.load(URLRequest(url: u))
        }
        return nil
    }

    // the page may not use the camera or microphone
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.deny)
    }

    // ---- the page's own message boxes (alert / confirm / prompt) and file chooser
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = NSAlert()
        a.messageText = "Message from the page"
        a.informativeText = message
        a.addButton(withTitle: "OK")
        present(a)
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = NSAlert()
        a.messageText = "The page asks"
        a.informativeText = message
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Cancel")
        completionHandler(present(a) == .alertFirstButtonReturn)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let a = NSAlert()
        a.messageText = "The page asks"
        a.informativeText = prompt
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultText ?? ""
        a.accessoryView = field
        completionHandler(present(a) == .alertFirstButtonReturn ? field.stringValue : nil)
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        NSApp.activate(ignoringOtherApps: true)
        panel.beginSheetModal(for: window) { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }
}
