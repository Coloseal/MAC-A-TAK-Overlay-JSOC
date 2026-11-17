// The heart of the app: the see-through window with the tablet, opening / minimizing, the mouse lock, the menu-bar icon,
// the web view rules and the glue to settings, hotkey and updates.
import Cocoa
import WebKit
import QuartzCore

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return false }
}

final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    private let settings = Settings.shared
    private var window: OverlayWindow!
    private var tablet: TabletView!
    private var web: WKWebView!
    private var ruleList: WKContentRuleList?
    private var statusItem: NSStatusItem?
    private var settingsController: SettingsWindowController?

    private var expanded = false
    private var animating = false
    private var settingsOpen = false
    private var busy = 0
    private var hotKeyWorks = false
    private var shownAt = Date.distantPast
    private var previousApp: NSRunningApplication?
    private var pendingUpdate: UpdateInfo?
    private var lockTimer: Timer?
    private let smoke = ProcessInfo.processInfo.environment["TACOVERLAY_SMOKE"] != nil

    private var lastHome = ""
    private var lastAdBlock = true
    private var lastKeyCode = -1
    private var lastKeyMods = -1

    // ---------------------------------------------------------------- start up
    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("starting v\(Updater.current)")
        buildMainMenu()

        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.preferences.isFraudulentWebsiteWarningEnabled = true
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 300), configuration: config)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = false
        web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        web.underPageBackgroundColor = NSColor(srgbRed: 0.05, green: 0.06, blue: 0.045, alpha: 1.0)

        tablet = TabletView(web: web)
        tablet.theme = Themes.named(settings.theme)
        loadSkin()
        tablet.onDockClick = { [weak self] in self?.expand() }
        tablet.onGear = { [weak self] in self?.openSettings() }
        tablet.onGlobe = { [weak self] in self?.toggleBar() }
        tablet.bar.onBack = { [weak self] in self?.web.goBack() }
        tablet.bar.onForward = { [weak self] in self?.web.goForward() }
        tablet.bar.onReload = { [weak self] in self?.web.reload() }
        tablet.bar.onHome = { [weak self] in self?.loadHome() }
        tablet.bar.onGo = { [weak self] text in self?.go(text) }

        let screen = currentScreen()
        window = OverlayWindow(contentRect: dockedFrame(on: screen), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = NSColor.clear
        window.hasShadow = false
        window.level = NSWindow.Level.screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = tablet
        window.alphaValue = CGFloat(max(25.0, min(100.0, settings.opacity)) / 100.0)
        tablet.showContent(false)
        window.orderFrontRegardless()

        HotKeyCenter.shared.onPress = { [weak self] in self?.toggle() }
        registerHotKey(announce: true)
        lastKeyCode = settings.hotKeyCode
        lastKeyMods = settings.hotKeyMods

        lastHome = settings.homeURL
        lastAdBlock = settings.adBlock
        applyAdBlock { [weak self] in self?.loadHome() }

        buildStatusItem()

        lockTimer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.lockTick() }
        RunLoop.main.add(lockTimer!, forMode: .common)

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in self?.checkUpdates(manual: false) }

        if smoke { smokeTest() }

        if !settings.firstRunDone && !smoke {
            settings.firstRunDone = true
            let a = NSAlert()
            a.messageText = "Tac Map Overlay is running"
            a.informativeText = "A small tablet is in the bottom-right corner of your screen and there is a map icon in the menu bar at the top.\n\n" +
                "Press \(HotKeyText.describe(code: settings.hotKeyCode, mods: settings.hotKeyMods)) (or click the small tablet) to open it, and press it again to minimize it. " +
                "You can change the shortcut, size and more in Settings (the gear on the tablet or the menu-bar icon).\n\n" +
                "While the tablet is open your mouse stays inside it. If that ever gets in your way, use the shortcut to minimize it."
            a.addButton(withTitle: "Open the tablet")
            present(a)
            expand()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        expand()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyCenter.shared.unregister()
    }

    // Used by the automatic build check on GitHub only: opens the tablet, logs what happened, quits.
    private func smokeTest() {
        Log.write("smoke: start")
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in self?.expand() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
            guard let self = self else { return }
            Log.write("smoke: expanded=\(self.expanded) frame=\(self.window.frame) url=\(self.web.url?.absoluteString ?? "none") loading=\(self.web.isLoading) hotkey=\(self.hotKeyWorks) rules=\(self.ruleList != nil)")
            self.web.evaluateJavaScript("document.title") { result, error in
                Log.write("smoke: title=\(String(describing: result)) error=\(String(describing: error))")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) { [weak self] in
            self?.minimize()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 17.0) {
            Log.write("smoke: done")
            NSApp.terminate(nil)
        }
    }

    // ---------------------------------------------------------------- menus
    private func buildMainMenu() {
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

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let img = NSImage(systemSymbolName: "map", accessibilityDescription: "Tac Map Overlay") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "TAK"
            }
        }
        statusItem = item
        rebuildMenu()
    }

    private func rebuildMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()
        if let u = pendingUpdate {
            let m = NSMenuItem(title: "Update available: v\(u.latest) - download", action: #selector(openUpdatePage), keyEquivalent: "")
            m.target = self
            menu.addItem(m)
            menu.addItem(NSMenuItem.separator())
        }
        let keyText = HotKeyText.describe(code: settings.hotKeyCode, mods: settings.hotKeyMods)
        let t = NSMenuItem(title: "Open / minimize tablet     \(keyText)", action: #selector(menuToggle), keyEquivalent: "")
        t.target = self
        menu.addItem(t)
        let h = NSMenuItem(title: "Go to the map (home)", action: #selector(menuHome), keyEquivalent: "")
        h.target = self
        menu.addItem(h)
        let s = NSMenuItem(title: "Settings...", action: #selector(menuSettings), keyEquivalent: "")
        s.target = self
        menu.addItem(s)
        let c = NSMenuItem(title: "Check for updates", action: #selector(menuCheck), keyEquivalent: "")
        c.target = self
        menu.addItem(c)
        menu.addItem(NSMenuItem.separator())
        let q = NSMenuItem(title: "Quit", action: #selector(menuQuit), keyEquivalent: "")
        q.target = self
        menu.addItem(q)
        item.menu = menu
    }

    @objc private func menuToggle() { toggle() }
    @objc private func menuHome() { loadHome(); expand() }
    @objc private func menuSettings() { openSettings() }
    @objc private func menuCheck() { checkUpdates(manual: true) }
    @objc private func menuQuit() { NSApp.terminate(nil) }
    @objc private func openUpdatePage() {
        if let u = pendingUpdate, let url = URL(string: u.url) { NSWorkspace.shared.open(url) }
    }

    // ---------------------------------------------------------------- helpers
    @discardableResult
    private func present(_ alert: NSAlert) -> NSApplication.ModalResponse {
        busy += 1
        NSApp.activate(ignoringOtherApps: true)
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)
        let r = alert.runModal()
        busy -= 1
        return r
    }

    private func currentScreen() -> NSScreen {
        let p = NSEvent.mouseLocation
        for s in NSScreen.screens where NSMouseInRect(p, s.frame, false) { return s }
        if let w = window, let s = w.screen { return s }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    private func expandedSize(on screen: NSScreen) -> NSSize {
        let vf = screen.visibleFrame
        var w = vf.width * CGFloat(settings.sizePct / 100.0)
        var h = w * TabletView.logical.height / TabletView.logical.width
        let maxH = vf.height * 0.95
        if h > maxH {
            h = maxH
            w = h * TabletView.logical.width / TabletView.logical.height
        }
        return NSSize(width: w.rounded(), height: h.rounded())
    }

    private func expandedFrame(on screen: NSScreen) -> NSRect {
        let size = expandedSize(on: screen)
        if let o = settings.openOrigin {
            let r = NSRect(origin: o, size: size)
            let mid = NSPoint(x: r.midX, y: r.midY)
            for s in NSScreen.screens where NSMouseInRect(mid, s.frame, false) { return r }
        }
        let vf = screen.visibleFrame
        return NSRect(x: (vf.midX - size.width / 2).rounded(), y: (vf.midY - size.height / 2).rounded(), width: size.width, height: size.height)
    }

    private func dockedFrame(on screen: NSScreen) -> NSRect {
        let vf = screen.visibleFrame
        let w = CGFloat(max(200.0, min(700.0, settings.dockWidth)))
        let h = (w * TabletView.logical.height / TabletView.logical.width).rounded()
        return NSRect(x: vf.maxX - w - 16, y: vf.minY + 16, width: w, height: h)
    }

    private func animateFrame(to frame: NSRect, completion: @escaping () -> Void) {
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

    // ---------------------------------------------------------------- open / minimize
    private func toggle() {
        if animating { return }
        if expanded { minimize() } else { expand() }
    }

    private func expand() {
        if animating || expanded { return }
        let me = NSRunningApplication.current
        if let f = NSWorkspace.shared.frontmostApplication, f.processIdentifier != me.processIdentifier {
            previousApp = f
        }
        let target = expandedFrame(on: currentScreen())
        animating = true
        tablet.isExpanded = false
        tablet.showContent(false)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        animateFrame(to: target) { [weak self] in
            guard let self = self else { return }
            self.expanded = true
            self.animating = false
            self.shownAt = Date()
            self.tablet.isExpanded = true
            self.tablet.showContent(true)
            self.window.makeKeyAndOrderFront(nil)
            self.window.makeFirstResponder(self.web)
        }
    }

    private func minimize() {
        if animating || !expanded { return }
        settings.openOrigin = window.frame.origin
        let screen = window.screen ?? currentScreen()
        animating = true
        expanded = false
        tablet.isExpanded = false
        tablet.showContent(false)
        animateFrame(to: dockedFrame(on: screen)) { [weak self] in
            guard let self = self else { return }
            self.animating = false
            if let prev = self.previousApp {
                prev.activate(options: [])
                self.previousApp = nil
            }
        }
    }

    func windowDidMove(_ notification: Notification) {
        if expanded && !animating {
            settings.openOrigin = window.frame.origin
        }
    }

    // Clicking the game (another app) while the mouse is free minimizes the tablet so it never covers the game.
    func applicationDidResignActive(_ notification: Notification) {
        if expanded && !animating && !settingsOpen && busy == 0 && Date().timeIntervalSince(shownAt) > 0.8 {
            minimize()
        }
    }

    // ---------------------------------------------------------------- mouse lock
    private func lockTick() {
        if !expanded || animating || settingsOpen || busy > 0 { return }
        if !settings.lockMouse || !hotKeyWorks || !NSApp.isActive { return }
        let p = NSEvent.mouseLocation
        let r = window.frame.insetBy(dx: 2, dy: 2)
        if r.contains(p) { return }
        let cx = min(max(p.x, r.minX), r.maxX - 1)
        let cy = min(max(p.y, r.minY), r.maxY - 1)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        _ = CGWarpMouseCursorPosition(CGPoint(x: cx, y: primaryHeight - cy))
    }

    // ---------------------------------------------------------------- settings glue
    private func registerHotKey(announce: Bool) {
        let ok = HotKeyCenter.shared.register(keyCode: settings.hotKeyCode, modifiers: settings.hotKeyMods)
        hotKeyWorks = ok
        if !ok && announce {
            let a = NSAlert()
            a.alertStyle = .warning
            a.messageText = "That shortcut can't be used"
            a.informativeText = "\(HotKeyText.describe(code: settings.hotKeyCode, mods: settings.hotKeyMods)) is already taken by another app. " +
                "Pick a different one in Settings. Until then, open the tablet from the map icon in the menu bar. The mouse lock is switched off while there is no working shortcut."
            a.addButton(withTitle: "OK")
            present(a)
        }
    }

    private func loadSkin() {
        if let p = settings.skinPath, let img = NSImage(contentsOfFile: p) {
            tablet.skin = img
        } else {
            tablet.skin = nil
        }
    }

    private func openSettings() {
        if settingsController == nil {
            let c = SettingsWindowController()
            c.onApply = { [weak self] in self?.applyAll() }
            c.onClose = { [weak self] in self?.settingsOpen = false }
            c.onClearData = { [weak self] in self?.clearData() }
            c.onCheckUpdate = { [weak self] in self?.checkUpdates(manual: true) }
            c.onChooseSkin = { [weak self] in self?.chooseSkin() }
            c.onResetSkin = { [weak self] in
                self?.settings.skinPath = nil
                self?.loadSkin()
            }
            c.onQuit = { NSApp.terminate(nil) }
            settingsController = c
        }
        settingsOpen = true
        settingsController?.show()
    }

    private func applyAll() {
        tablet.theme = Themes.named(settings.theme)
        window.alphaValue = CGFloat(max(25.0, min(100.0, settings.opacity)) / 100.0)
        if settings.homeURL != lastHome {
            lastHome = settings.homeURL
            loadHome()
        }
        if settings.adBlock != lastAdBlock {
            lastAdBlock = settings.adBlock
            applyAdBlock(then: nil)
        }
        if settings.hotKeyCode != lastKeyCode || settings.hotKeyMods != lastKeyMods {
            lastKeyCode = settings.hotKeyCode
            lastKeyMods = settings.hotKeyMods
            registerHotKey(announce: true)
            rebuildMenu()
        }
        if expanded && !animating {
            let size = expandedSize(on: window.screen ?? currentScreen())
            if abs(window.frame.width - size.width) > 1.0 {
                let f = window.frame
                let nf = NSRect(x: (f.midX - size.width / 2).rounded(), y: (f.midY - size.height / 2).rounded(), width: size.width, height: size.height)
                window.setFrame(nf, display: true)
            }
        }
    }

    private func clearData() {
        let store = WKWebsiteDataStore.default()
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: Date(timeIntervalSince1970: 0)) { [weak self] in
            DispatchQueue.main.async {
                let a = NSAlert()
                a.messageText = "Browsing data cleared"
                a.informativeText = "Cookies, saved logins and site data were removed."
                a.addButton(withTitle: "OK")
                self?.present(a)
            }
        }
    }

    private func chooseSkin() {
        busy += 1
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.message = "Choose a PNG picture of a tablet (transparent background)"
        panel.allowedFileTypes = ["png"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)
        if panel.runModal() == .OK, let url = panel.url {
            settings.skinPath = url.path
            loadSkin()
        }
        busy -= 1
    }

    private func checkUpdates(manual: Bool) {
        Updater.check { [weak self] info in
            guard let self = self else { return }
            if let info = info {
                self.pendingUpdate = info
                self.rebuildMenu()
                if manual {
                    let a = NSAlert()
                    a.messageText = "Update available: v\(info.latest)"
                    a.informativeText = (info.notes.isEmpty ? "" : info.notes + "\n\n") + "You have v\(Updater.current). Open the download page?"
                    a.addButton(withTitle: "Open download page")
                    a.addButton(withTitle: "Later")
                    if self.present(a) == .alertFirstButtonReturn, let u = URL(string: info.url) {
                        NSWorkspace.shared.open(u)
                    }
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

    // ---------------------------------------------------------------- web
    private func applyAdBlock(then: (() -> Void)?) {
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

    private func loadHome() {
        if let u = WebSupport.resolveInput(settings.homeURL, search: settings.searchURL) {
            web.load(URLRequest(url: u))
        }
    }

    private func go(_ text: String) {
        if let u = WebSupport.resolveInput(text, search: settings.searchURL) {
            web.load(URLRequest(url: u))
            window.makeFirstResponder(web)
        } else {
            NSSound.beep()
        }
    }

    private func toggleBar() {
        tablet.barVisible = !tablet.barVisible
        if tablet.barVisible {
            window.makeFirstResponder(tablet.bar.field)
        } else {
            window.makeFirstResponder(web)
        }
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
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showError(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showError(error)
    }

    private func showError(_ error: Error) {
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
}
