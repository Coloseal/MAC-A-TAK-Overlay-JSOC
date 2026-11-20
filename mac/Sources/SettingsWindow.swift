// The settings window (opened from the tablet's gear or the menu-bar icon).
import Cocoa

// A plain window that also closes when Esc is pressed.
final class SettingsWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        if attachedSheet == nil { close() } else { super.cancelOperation(sender) }
    }
}

final class SettingsWindowController: NSObject, NSWindowDelegate {
    let window: NSWindow
    var onApply: (() -> Void)?
    var onClose: (() -> Void)?
    var onClearData: (() -> Void)?
    var onCheckUpdate: (() -> Void)?
    var onChooseSkin: (() -> Void)?
    var onResetSkin: (() -> Void)?
    var onQuit: (() -> Void)?

    private let settings = Settings.shared
    private let height: CGFloat = 540
    private var urlField = NSTextField()
    private var themePopup = NSPopUpButton()
    private var sizeSlider = NSSlider()
    private var opacitySlider = NSSlider()
    private var sizeLabel = NSTextField()
    private var opacityLabel = NSTextField()
    private var lockCheck = NSButton()
    private var adCheck = NSButton()
    private var httpsCheck = NSButton()
    private var animCheck = NSButton()
    private var recorder = NSButton()
    private var monitor: Any?

    override init() {
        window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 470, height: 540),
                          styleMask: [.titled, .closable],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "Tac Map Overlay - Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        build()
    }

    func show() {
        refresh()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // ---- building the window ----
    private func topY(_ top: CGFloat, _ h: CGFloat) -> CGFloat { return height - top - h }

    private func label(_ text: String, top: CGFloat, bold: Bool = false) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = bold ? NSFont.boldSystemFont(ofSize: 12) : NSFont.systemFont(ofSize: 12)
        l.frame = NSRect(x: 20, y: topY(top, 18), width: 300, height: 18)
        window.contentView?.addSubview(l)
        return l
    }

    private func button(_ title: String, x: CGFloat, top: CGFloat, w: CGFloat, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.frame = NSRect(x: x, y: topY(top, 28), width: w, height: 28)
        window.contentView?.addSubview(b)
        return b
    }

    private func check(_ title: String, top: CGFloat, action: Selector) -> NSButton {
        let c = NSButton(checkboxWithTitle: title, target: self, action: action)
        c.frame = NSRect(x: 20, y: topY(top, 20), width: 420, height: 20)
        window.contentView?.addSubview(c)
        return c
    }

    private func build() {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
        _ = label("Tac Map Overlay for Mac   (v\(version))", top: 14, bold: true)

        _ = label("Map address (home page)", top: 48)
        urlField = NSTextField(frame: NSRect(x: 20, y: topY(70, 24), width: 340, height: 24))
        window.contentView?.addSubview(urlField)
        _ = button("Apply", x: 370, top: 68, w: 80, action: #selector(applyURL))

        _ = label("Theme", top: 108)
        themePopup = NSPopUpButton(frame: NSRect(x: 120, y: topY(104, 26), width: 200, height: 26), pullsDown: false)
        for t in Themes.all { themePopup.addItem(withTitle: t.name) }
        themePopup.target = self
        themePopup.action = #selector(themeChanged)
        window.contentView?.addSubview(themePopup)

        _ = label("Size", top: 150)
        sizeSlider = NSSlider(value: settings.sizePct, minValue: 25, maxValue: 90, target: self, action: #selector(sizeChanged))
        sizeSlider.frame = NSRect(x: 120, y: topY(146, 24), width: 270, height: 24)
        window.contentView?.addSubview(sizeSlider)
        sizeLabel = NSTextField(labelWithString: "")
        sizeLabel.frame = NSRect(x: 400, y: topY(150, 18), width: 60, height: 18)
        window.contentView?.addSubview(sizeLabel)

        _ = label("Transparency", top: 186)
        opacitySlider = NSSlider(value: settings.opacity, minValue: 25, maxValue: 100, target: self, action: #selector(opacityChanged))
        opacitySlider.frame = NSRect(x: 120, y: topY(182, 24), width: 270, height: 24)
        window.contentView?.addSubview(opacitySlider)
        opacityLabel = NSTextField(labelWithString: "")
        opacityLabel.frame = NSRect(x: 400, y: topY(186, 18), width: 60, height: 18)
        window.contentView?.addSubview(opacityLabel)

        lockCheck = check("Lock the mouse inside the tablet while it is open", top: 224, action: #selector(togglesChanged))
        adCheck = check("Block ads and trackers", top: 250, action: #selector(togglesChanged))
        httpsCheck = check("Only allow secure (https) sites", top: 276, action: #selector(togglesChanged))
        animCheck = check("Open / close animation", top: 302, action: #selector(togglesChanged))

        _ = label("Shortcut to open / minimize", top: 340)
        recorder = NSButton(title: "", target: self, action: #selector(startRecording))
        recorder.bezelStyle = .rounded
        recorder.frame = NSRect(x: 220, y: topY(334, 28), width: 230, height: 28)
        window.contentView?.addSubview(recorder)

        _ = label("Tablet picture (PNG with a transparent background, same shape)", top: 382)
        _ = button("Choose picture...", x: 20, top: 404, w: 160, action: #selector(chooseSkin))
        _ = button("Use supplied case", x: 190, top: 404, w: 170, action: #selector(resetSkin))

        _ = button("Clear browsing data", x: 20, top: 450, w: 160, action: #selector(clearData))
        _ = button("Check for updates", x: 190, top: 450, w: 170, action: #selector(checkUpdate))

        _ = button("Quit app", x: 20, top: 494, w: 120, action: #selector(quitApp))
        let done = button("Done", x: 340, top: 494, w: 110, action: #selector(doneTapped))
        done.keyEquivalent = "\r"
    }

    func refresh() {
        urlField.stringValue = settings.homeURL
        themePopup.selectItem(withTitle: settings.theme)
        sizeSlider.doubleValue = settings.sizePct
        opacitySlider.doubleValue = settings.opacity
        sizeLabel.stringValue = "\(Int(settings.sizePct))%"
        opacityLabel.stringValue = "\(Int(settings.opacity))%"
        lockCheck.state = settings.lockMouse ? .on : .off
        adCheck.state = settings.adBlock ? .on : .off
        httpsCheck.state = settings.httpsOnly ? .on : .off
        animCheck.state = settings.animate ? .on : .off
        recorder.title = HotKeyText.describe(code: settings.hotKeyCode, mods: settings.hotKeyMods) + "    (click to change)"
    }

    // ---- actions ----
    @objc private func applyURL() {
        settings.homeURL = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        onApply?()
    }

    @objc private func themeChanged() {
        if let t = themePopup.titleOfSelectedItem { settings.theme = t }
        onApply?()
    }

    @objc private func sizeChanged() {
        settings.sizePct = sizeSlider.doubleValue.rounded()
        sizeLabel.stringValue = "\(Int(settings.sizePct))%"
        onApply?()
    }

    @objc private func opacityChanged() {
        settings.opacity = opacitySlider.doubleValue.rounded()
        opacityLabel.stringValue = "\(Int(settings.opacity))%"
        onApply?()
    }

    @objc private func togglesChanged() {
        settings.lockMouse = lockCheck.state == .on
        settings.adBlock = adCheck.state == .on
        settings.httpsOnly = httpsCheck.state == .on
        settings.animate = animCheck.state == .on
        onApply?()
    }

    @objc private func startRecording() {
        recorder.title = "Press the new shortcut...  (Esc cancels)"
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if event.keyCode == 53 {
                self.stopRecording()
                return nil
            }
            let mods = HotKeyText.carbon(from: event.modifierFlags)
            if mods == 0 {
                NSSound.beep()    // a plain key would stop it working in the game
                return nil
            }
            self.settings.hotKeyCode = Int(event.keyCode)
            self.settings.hotKeyMods = mods
            self.stopRecording()
            self.onApply?()
            return nil
        }
    }

    private func stopRecording() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        refresh()
    }

    @objc private func chooseSkin() { onChooseSkin?() }
    @objc private func resetSkin() { onResetSkin?() }
    @objc private func clearData() { onClearData?() }
    @objc private func checkUpdate() { onCheckUpdate?() }
    @objc private func quitApp() { onQuit?() }
    @objc private func doneTapped() { window.close() }

    func windowWillClose(_ notification: Notification) {
        stopRecording()
        onClose?()
    }
}
