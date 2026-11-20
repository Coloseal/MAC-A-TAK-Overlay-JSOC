// The notes pad and the tools panel (bearing / distance, 9-line, checklist) that slide in beside the page.
import Cocoa

enum AppFiles {
    // ~/Library/Application Support/TacMapOverlay/notes   (tests can point TACOVERLAY_DATA somewhere else)
    static var notesDir: String {
        if let d = ProcessInfo.processInfo.environment["TACOVERLAY_DATA"], !d.isEmpty { return d + "/notes" }
        return NSHomeDirectory() + "/Library/Application Support/TacMapOverlay/notes"
    }

    static func read(_ name: String) -> String? {
        return try? String(contentsOfFile: notesDir + "/" + name, encoding: .utf8)
    }

    static func write(_ name: String, _ text: String) {
        try? FileManager.default.createDirectory(atPath: notesDir, withIntermediateDirectories: true)
        try? text.write(toFile: notesDir + "/" + name, atomically: true, encoding: .utf8)
    }

    static func exists(_ name: String) -> Bool { return FileManager.default.fileExists(atPath: notesDir + "/" + name) }
}

enum PanelStyle {
    static func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { return NSColor(srgbRed: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: 1) }
    static let bg = c(24, 27, 22)
    static let btnBg = c(40, 45, 36)
    static let activeBg = c(52, 60, 42)
    static let field = c(14, 17, 12)
    static let fg = c(205, 215, 190)
    static let green = c(150, 205, 90)
    static let dim = c(130, 140, 115)
    static let warn = c(255, 150, 40)
    static func bold(_ size: CGFloat) -> NSFont { return NSFont.monospacedSystemFont(ofSize: size, weight: .bold) }
    static func regular(_ size: CGFloat) -> NSFont { return NSFont.monospacedSystemFont(ofSize: size, weight: .regular) }
}

// a flat dark button
final class FlatButton: NSButton {
    var fgColor = PanelStyle.fg
    var bgColor = PanelStyle.btnBg

    convenience init(label: String, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 3
        setLabel(label)
    }

    func setLabel(_ t: String, color: NSColor? = nil, bg: NSColor? = nil, size: CGFloat = 11) {
        if let c = color { fgColor = c }
        if let b = bg { bgColor = b }
        attributedTitle = NSAttributedString(string: t, attributes: [.foregroundColor: fgColor, .font: PanelStyle.bold(size)])
        layer?.backgroundColor = bgColor.cgColor
    }
}

class SidePanelBase: NSView {
    var uiScale: CGFloat = 1.0 { didSet { needsLayout = true } }
    var onClose: (() -> Void)?
    var onEsc: (() -> Void)?
    override var isFlipped: Bool { return true }

    var rowHeight: CGFloat { return max(24, min(44, (10.5 * uiScale).rounded())) }
    var padding: CGFloat { return max(3, (rowHeight / 7).rounded()) }
    var uiFontSize: CGFloat { return max(10, rowHeight * 0.44) }
    var boxFontSize: CGFloat { return max(12, (6.6 * uiScale).rounded()) }

    override func draw(_ dirtyRect: NSRect) {
        PanelStyle.bg.setFill()
        bounds.fill()
    }

    func makeField() -> NSTextField {
        let f = NSTextField(frame: .zero)
        f.isBezeled = false
        f.isBordered = true
        f.drawsBackground = true
        f.backgroundColor = PanelStyle.field
        f.textColor = PanelStyle.fg
        f.focusRingType = .none
        return f
    }
}

// a text view that tells us when Esc is pressed
final class EscTextView: NSTextView {
    var onEsc: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onEsc?() }
}

func makeScrollText(onEsc: @escaping () -> Void) -> (NSScrollView, EscTextView) {
    let scroll = NSScrollView(frame: .zero)
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = true
    scroll.backgroundColor = PanelStyle.field
    let tv = EscTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
    tv.minSize = NSSize(width: 0, height: 0)
    tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    tv.isVerticallyResizable = true
    tv.isHorizontallyResizable = false
    tv.autoresizingMask = [.width]
    tv.textContainer?.containerSize = NSSize(width: 200, height: CGFloat.greatestFiniteMagnitude)
    tv.textContainer?.widthTracksTextView = true
    tv.backgroundColor = PanelStyle.field
    tv.textColor = PanelStyle.fg
    tv.insertionPointColor = PanelStyle.green
    tv.isRichText = false
    tv.allowsUndo = true
    tv.isAutomaticQuoteSubstitutionEnabled = false
    tv.isAutomaticDashSubstitutionEnabled = false
    tv.isAutomaticSpellingCorrectionEnabled = false
    tv.onEsc = onEsc
    scroll.documentView = tv
    return (scroll, tv)
}

// ---------------------------------------------------------------- notes pad
final class NotesPanel: SidePanelBase, NSTextViewDelegate {
    private var txt: [String] = ["", "", "", ""]
    private var page = 0
    private var loading = false
    private var pgButtons: [FlatButton] = []
    private let copyButton: FlatButton
    private let clearButton: FlatButton
    private let closeButton: FlatButton
    private var noteScroll: NSScrollView
    private var box: EscTextView
    private var saveTimer: Timer?
    private var clearArmed = false

    init() {
        copyButton = FlatButton(label: "COPY", target: nil, action: nil)
        clearButton = FlatButton(label: "CLEAR", target: nil, action: nil)
        closeButton = FlatButton(label: "\u{2715}", target: nil, action: nil)
        var esc: () -> Void = {}
        let made = makeScrollText(onEsc: { esc() })
        noteScroll = made.0
        box = made.1
        super.init(frame: .zero)
        esc = { [weak self] in self?.onEsc?() }
        box.onEsc = { [weak self] in self?.onEsc?() }
        box.delegate = self
        for i in 0..<4 {
            txt[i] = AppFiles.read("notes\(i + 1).txt") ?? ""
            let b = FlatButton(label: i == 3 ? "LOG" : String(i + 1), target: self, action: #selector(pageTapped(_:)))
            b.tag = i
            pgButtons.append(b)
            addSubview(b)
        }
        for (b, sel) in [(copyButton, #selector(copyTapped)), (clearButton, #selector(clearTapped)), (closeButton, #selector(closeTapped))] {
            b.target = self
            b.action = sel
            addSubview(b)
        }
        addSubview(noteScroll)
        showPage()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func showPage() {
        loading = true
        box.string = txt[page]
        loading = false
        for i in 0..<4 {
            pgButtons[i].setLabel(i == 3 ? "LOG" : String(i + 1), color: i == page ? PanelStyle.green : PanelStyle.fg,
                                  bg: i == page ? PanelStyle.activeBg : PanelStyle.btnBg, size: uiFontSize)
        }
        copyButton.setLabel("COPY", color: PanelStyle.fg, bg: PanelStyle.btnBg, size: uiFontSize)
        closeButton.setLabel("\u{2715}", color: PanelStyle.fg, bg: PanelStyle.btnBg, size: uiFontSize)
        resetClear()
    }

    private func resetClear() {
        clearArmed = false
        clearButton.setLabel("CLEAR", color: PanelStyle.fg, bg: PanelStyle.btnBg, size: uiFontSize)
    }

    @objc private func pageTapped(_ s: NSButton) { switchPage(s.tag) }
    @objc private func copyTapped() {
        if box.string.isEmpty { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(box.string, forType: .string)
    }
    @objc private func clearTapped() {
        if !clearArmed {
            clearArmed = true
            clearButton.setLabel("SURE?", color: PanelStyle.warn, bg: PanelStyle.btnBg, size: uiFontSize)
            return
        }
        resetClear()
        box.string = ""
        txt[page] = ""
        scheduleSave()
    }
    @objc private func closeTapped() { save(); onClose?() }

    private func switchPage(_ i: Int) {
        save()
        page = i
        showPage()
        window?.makeFirstResponder(box)
    }

    func gotoPage(_ i: Int) { if i != page { switchPage(i) } }

    func textDidChange(_ notification: Notification) {
        if loading { return }
        txt[page] = box.string
        scheduleSave()
    }

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in self?.save() }
    }

    func save() {
        saveTimer?.invalidate()
        for i in 0..<4 where !txt[i].isEmpty || AppFiles.exists("notes\(i + 1).txt") {
            AppFiles.write("notes\(i + 1).txt", txt[i])
        }
    }

    func focusBox() {
        window?.makeFirstResponder(box)
        box.setSelectedRange(NSRange(location: (box.string as NSString).length, length: 0))
    }

    // page 4 is the mission log: add a line (usually a time stamp) at the end
    func appendLog(_ line: String) {
        var t = txt[3]
        if !t.isEmpty && !t.hasSuffix("\n") { t += "\n" }
        txt[3] = t + line
        if page == 3 {
            loading = true
            box.string = txt[3]
            loading = false
            box.setSelectedRange(NSRange(location: (box.string as NSString).length, length: 0))
            box.scrollRangeToVisible(NSRange(location: (box.string as NSString).length, length: 0))
        }
        scheduleSave()
    }

    var logText: String { return txt[3] }
    var currentText: String { return box.string }
    var currentPage: Int { return page }

    override func layout() {
        super.layout()
        let row = rowHeight, p = padding
        let bs = row - 2 * p
        let fs = uiFontSize
        var x = p
        for i in 0..<4 {
            let w: CGFloat = i == 3 ? bs * 2 : bs
            pgButtons[i].frame = NSRect(x: x, y: p, width: w, height: bs)
            pgButtons[i].setLabel(i == 3 ? "LOG" : String(i + 1), color: i == page ? PanelStyle.green : PanelStyle.fg,
                                  bg: i == page ? PanelStyle.activeBg : PanelStyle.btnBg, size: fs)
            x += w + p
        }
        closeButton.frame = NSRect(x: bounds.width - p - bs, y: p, width: bs, height: bs)
        let cw = bs * 2.3, pw = bs * 1.9
        clearButton.frame = NSRect(x: closeButton.frame.minX - p - cw, y: p, width: cw, height: bs)
        copyButton.frame = NSRect(x: clearButton.frame.minX - p - pw, y: p, width: pw, height: bs)
        copyButton.setLabel("COPY", size: fs)
        closeButton.setLabel("\u{2715}", size: fs)
        clearButton.setLabel(clearArmed ? "SURE?" : "CLEAR", size: fs)
        noteScroll.frame = NSRect(x: p, y: row + p, width: max(20, bounds.width - 2 * p), height: max(20, bounds.height - row - 2 * p))
        box.font = PanelStyle.regular(boxFontSize)
    }
}

// ---------------------------------------------------------------- bearing / distance maths
enum ToolsMath {
    // "123456" or "123 456" -> east / north in metres (6 digits = 100 m squares, 8 = 10 m)
    static func parseGrid(_ s: String) -> (Double, Double)? {
        let t = s.trimmingCharacters(in: .whitespaces).components(separatedBy: CharacterSet(charactersIn: " ,;/")).filter { !$0.isEmpty }
        var a = ""
        var b = ""
        if t.count == 2 {
            a = t[0]
            b = t[1]
        } else if t.count == 1 && t[0].count >= 2 && t[0].count % 2 == 0 {
            let chars = Array(t[0])
            a = String(chars[0..<(chars.count / 2)])
            b = String(chars[(chars.count / 2)...])
        } else {
            return nil
        }
        if a.count != b.count || a.count < 1 || a.count > 5 { return nil }
        for ch in a + b where !("0"..."9").contains(ch) { return nil }
        guard let ea = Double(a), let nb = Double(b) else { return nil }
        let unit = pow(10.0, Double(5 - a.count))
        return (ea * unit, nb * unit)
    }

    static let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

    static func compute(from: String, to: String) -> String {
        guard let f = parseGrid(from), let t = parseGrid(to) else { return "" }
        let de = t.0 - f.0, dn = t.1 - f.1
        let dist = (de * de + dn * dn).squareRoot()
        var brg = atan2(de, dn) * 180.0 / Double.pi
        if brg < 0 { brg += 360.0 }
        if dist < 0.5 { brg = 0 }
        let back = (brg + 180.0).truncatingRemainder(dividingBy: 360.0)
        func mils(_ d: Double) -> String { return String(format: "%04d", Int((d * 6400.0 / 360.0).rounded()) % 6400) }
        func deg(_ d: Double) -> String { return String(format: "%03d", Int(d.rounded()) % 360) }
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.locale = Locale(identifier: "en_US")
        nf.maximumFractionDigits = 0
        let distText = nf.string(from: NSNumber(value: Int(dist.rounded()))) ?? "\(Int(dist.rounded()))"
        return "DISTANCE  " + distText + " m   (" + String(format: "%.2f", dist / 1000.0) + " km)\n" +
               "BEARING   " + deg(brg) + " deg   " + mils(brg) + " mils   " + points[Int((brg / 45.0).rounded()) % 8] + "\n" +
               "BACK AZ   " + deg(back) + " deg   " + mils(back) + " mils"
    }
}

// ---------------------------------------------------------------- tools panel
final class ToolsPanel: SidePanelBase, NSTextFieldDelegate {
    static let nineLabels = ["1 IP / BP", "2 HEADING", "3 DISTANCE", "4 TGT ELEV", "5 TGT DESC", "6 TGT LOC", "7 MARK", "8 FRIENDLIES", "9 EGRESS", "REMARKS"]
    static let defaultItems = ["Radio check done", "Weapons and ammo loaded", "Medical kit", "Map and route loaded", "Brief understood (task, ROE)",
                               "Comms plan / frequencies", "Rally and extraction points known", "Vehicle / aircraft pre-checks"]

    private(set) var tab = 0
    private var tabButtons: [FlatButton] = []
    private let closeButton: FlatButton

    // tab 0
    private let lFrom = NSTextField(labelWithString: "FROM GRID")
    private let lTo = NSTextField(labelWithString: "TO GRID")
    private let lHelp = NSTextField(wrappingLabelWithString: "Type grids like 123456 or 123 456 (digits are split in half). 6 digits = 100 m squares, 8 = 10 m.")
    let tFrom: NSTextField
    let tTo: NSTextField
    private let tRes: NSTextField
    private let bCopyRes: FlatButton

    // tab 1
    private var nl: [NSTextField] = []
    var nt: [NSTextField] = []
    private let bCopyNine: FlatButton
    private let bClearNine: FlatButton
    private var clearArmed = false

    // tab 2
    private var items: [String] = []
    private var checks: [NSButton] = []
    private let listScroll = NSScrollView(frame: .zero)
    private let listDoc = FlippedView(frame: .zero)
    private let bEdit: FlatButton
    private let bReset: FlatButton
    private var editScroll: NSScrollView
    private var editBox: EscTextView
    private var editing = false

    private var saveTimer: Timer?

    init() {
        closeButton = FlatButton(label: "\u{2715}", target: nil, action: nil)
        bCopyRes = FlatButton(label: "COPY", target: nil, action: nil)
        bCopyNine = FlatButton(label: "COPY 9-LINE", target: nil, action: nil)
        bClearNine = FlatButton(label: "CLEAR", target: nil, action: nil)
        bEdit = FlatButton(label: "EDIT LIST", target: nil, action: nil)
        bReset = FlatButton(label: "UNTICK ALL", target: nil, action: nil)
        tFrom = NSTextField(frame: .zero)
        tTo = NSTextField(frame: .zero)
        tRes = NSTextField(frame: .zero)
        var esc: () -> Void = {}
        let made = makeScrollText(onEsc: { esc() })
        editScroll = made.0
        editBox = made.1
        super.init(frame: .zero)
        esc = { [weak self] in self?.onEsc?() }

        let names = ["BRG/DIST", "9-LINE", "CHECKLIST"]
        for i in 0..<3 {
            let b = FlatButton(label: names[i], target: self, action: #selector(tabTapped(_:)))
            b.tag = i
            tabButtons.append(b)
            addSubview(b)
        }
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        addSubview(closeButton)

        for f in [tFrom, tTo] {
            styleField(f)
            f.delegate = self
            addSubview(f)
        }
        styleField(tRes)
        tRes.isEditable = false
        tRes.isSelectable = true
        tRes.textColor = PanelStyle.green
        tRes.maximumNumberOfLines = 0
        tRes.cell?.wraps = true
        addSubview(tRes)
        for l in [lFrom, lTo, lHelp] {
            l.textColor = PanelStyle.dim
            addSubview(l)
        }
        bCopyRes.target = self
        bCopyRes.action = #selector(copyResTapped)
        addSubview(bCopyRes)

        var saved: [String] = Array(repeating: "", count: 10)
        if let s = AppFiles.read("nineline.txt") {
            let ln = s.components(separatedBy: "\n")
            for i in 0..<10 where i < ln.count { saved[i] = ln[i] }
        }
        for i in 0..<10 {
            let l = NSTextField(labelWithString: ToolsPanel.nineLabels[i])
            l.textColor = PanelStyle.dim
            let f = NSTextField(frame: .zero)
            styleField(f)
            f.stringValue = saved[i]
            f.delegate = self
            nl.append(l)
            nt.append(f)
            addSubview(l)
            addSubview(f)
        }
        bCopyNine.target = self
        bCopyNine.action = #selector(copyNineTapped)
        bClearNine.target = self
        bClearNine.action = #selector(clearNineTapped)
        addSubview(bCopyNine)
        addSubview(bClearNine)

        listScroll.hasVerticalScroller = true
        listScroll.drawsBackground = true
        listScroll.backgroundColor = PanelStyle.field
        listScroll.documentView = listDoc
        addSubview(listScroll)
        editScroll.isHidden = true
        addSubview(editScroll)
        bEdit.target = self
        bEdit.action = #selector(editTapped)
        bReset.target = self
        bReset.action = #selector(resetChecksTapped)
        addSubview(bEdit)
        addSubview(bReset)
        loadChecklist()
        selectTab(0)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func styleField(_ f: NSTextField) {
        f.isBezeled = false
        f.isBordered = true
        f.drawsBackground = true
        f.backgroundColor = PanelStyle.field
        f.textColor = PanelStyle.fg
        f.focusRingType = .none
    }

    // Esc in a text field goes back to the page
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            onEsc?()
            return true
        }
        return false
    }

    func controlTextDidChange(_ obj: Notification) {
        compute()
        scheduleSave()
    }

    @objc private func tabTapped(_ s: NSButton) { selectTab(s.tag) }
    @objc private func closeTapped() { saveAll(); onClose?() }
    @objc private func copyResTapped() {
        if tRes.stringValue.isEmpty { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(tRes.stringValue.replacingOccurrences(of: "\n", with: "  |  "), forType: .string)
    }
    @objc private func copyNineTapped() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(nineLineText(), forType: .string)
    }
    @objc private func clearNineTapped() {
        if !clearArmed {
            clearArmed = true
            bClearNine.setLabel("SURE?", color: PanelStyle.warn, size: uiFontSize)
            return
        }
        clearArmed = false
        bClearNine.setLabel("CLEAR", color: PanelStyle.fg, size: uiFontSize)
        for f in nt { f.stringValue = "" }
        scheduleSave()
    }
    @objc private func editTapped() { toggleEdit() }
    @objc private func resetChecksTapped() {
        for c in checks { c.state = .off }
        saveChecks()
    }
    @objc private func checkTapped(_ s: NSButton) { saveChecks() }

    func selectTab(_ i: Int) {
        tab = i
        clearArmed = false
        bClearNine.setLabel("CLEAR", color: PanelStyle.fg, size: uiFontSize)
        for k in 0..<3 {
            tabButtons[k].setLabel(["BRG/DIST", "9-LINE", "CHECKLIST"][k], color: k == i ? PanelStyle.green : PanelStyle.fg,
                                   bg: k == i ? PanelStyle.activeBg : PanelStyle.btnBg, size: uiFontSize)
        }
        for v in [lFrom, lTo, lHelp, tFrom, tTo, tRes, bCopyRes] as [NSView] { v.isHidden = i != 0 }
        for k in 0..<10 { nl[k].isHidden = i != 1; nt[k].isHidden = i != 1 }
        bCopyNine.isHidden = i != 1
        bClearNine.isHidden = i != 1
        listScroll.isHidden = !(i == 2 && !editing)
        editScroll.isHidden = !(i == 2 && editing)
        bEdit.isHidden = i != 2
        bReset.isHidden = i != 2
        needsLayout = true
        if i == 0 { window?.makeFirstResponder(tFrom) } else if i == 1 { window?.makeFirstResponder(nt[0]) }
    }

    // ---- bearing / distance
    private func compute() { tRes.stringValue = ToolsMath.compute(from: tFrom.stringValue, to: tTo.stringValue) }

    func setGrids(from: String, to: String) {
        tFrom.stringValue = from
        tTo.stringValue = to
        compute()
    }

    var resultText: String { return tRes.stringValue }

    // ---- 9-line
    func nineLineText() -> String {
        var s = "9-LINE CAS\n"
        for i in 0..<10 {
            let t = nt[i].stringValue.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { s += "LINE " + ToolsPanel.nineLabels[i] + ": " + t + "\n" }
        }
        return s
    }

    // ---- checklist
    private func loadChecklist() {
        var list = ToolsPanel.defaultItems
        if let s = AppFiles.read("checklist.txt") {
            let l = s.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if !l.isEmpty { list = l }
        }
        var ticked = Set<Int>()
        if let s = AppFiles.read("checklist_state.txt") {
            for p in s.components(separatedBy: ",") { if let v = Int(p) { ticked.insert(v) } }
        }
        items = list
        for c in checks { c.removeFromSuperview() }
        checks = []
        for (i, it) in list.enumerated() {
            let b = NSButton(checkboxWithTitle: it, target: self, action: #selector(checkTapped(_:)))
            b.attributedTitle = NSAttributedString(string: it, attributes: [.foregroundColor: PanelStyle.fg, .font: PanelStyle.regular(12)])
            b.state = ticked.contains(i) ? .on : .off
            checks.append(b)
            listDoc.addSubview(b)
        }
        needsLayout = true
    }

    var checklistCount: Int { return checks.count }
    func tickFirst() { if let c = checks.first { c.state = .on; saveChecks() } }

    private func saveChecks() {
        var idx: [String] = []
        for (i, c) in checks.enumerated() where c.state == .on { idx.append(String(i)) }
        AppFiles.write("checklist_state.txt", idx.joined(separator: ","))
    }

    private func toggleEdit() {
        if !editing {
            editBox.string = items.joined(separator: "\n") + "\n"
            editing = true
            bEdit.setLabel("SAVE LIST", size: uiFontSize)
            listScroll.isHidden = true
            editScroll.isHidden = false
            window?.makeFirstResponder(editBox)
        } else {
            AppFiles.write("checklist.txt", editBox.string)
            AppFiles.write("checklist_state.txt", "")
            editing = false
            bEdit.setLabel("EDIT LIST", size: uiFontSize)
            loadChecklist()
            editScroll.isHidden = true
            listScroll.isHidden = false
        }
    }

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in self?.saveAll() }
    }

    func saveAll() {
        saveTimer?.invalidate()
        AppFiles.write("nineline.txt", nt.map { $0.stringValue.replacingOccurrences(of: "\n", with: " ") }.joined(separator: "\n"))
        saveChecks()
    }

    // ---- layout
    override func layout() {
        super.layout()
        let row = rowHeight, p = padding
        let fs = uiFontSize
        let bs = row - 2 * p
        let boxFont = PanelStyle.regular(boxFontSize)
        let labFont = PanelStyle.bold(max(9, fs * 0.9))
        var x = p
        for i in 0..<3 {
            let w = CGFloat([8, 6, 9][i]) * fs * 0.62 + 14
            tabButtons[i].frame = NSRect(x: x, y: p, width: w, height: bs)
            tabButtons[i].setLabel(["BRG/DIST", "9-LINE", "CHECKLIST"][i], color: i == tab ? PanelStyle.green : PanelStyle.fg,
                                   bg: i == tab ? PanelStyle.activeBg : PanelStyle.btnBg, size: fs)
            x += w + p
        }
        closeButton.frame = NSRect(x: bounds.width - p - bs, y: p, width: bs, height: bs)
        closeButton.setLabel("\u{2715}", size: fs)
        let top = row + p
        let cw = max(40, bounds.width - 2 * p)
        let fh = max(22, (boxFontSize * 1.9).rounded())
        for l in [lFrom, lTo, lHelp] { l.font = labFont }
        let resFont = max(10, boxFontSize * 0.85)
        for f in [tFrom, tTo] { f.font = boxFont }
        tRes.font = PanelStyle.regular(resFont)

        // bearing / distance
        lFrom.frame = NSRect(x: p, y: top, width: cw, height: fs * 1.5)
        tFrom.frame = NSRect(x: p, y: lFrom.frame.maxY + 2, width: cw, height: fh)
        lTo.frame = NSRect(x: p, y: tFrom.frame.maxY + p * 2, width: cw, height: fs * 1.5)
        tTo.frame = NSRect(x: p, y: lTo.frame.maxY + 2, width: cw, height: fh)
        tRes.frame = NSRect(x: p, y: tTo.frame.maxY + p * 2, width: cw, height: resFont * 1.5 * 4 + 8)
        bCopyRes.frame = NSRect(x: p, y: tRes.frame.maxY + p, width: fs * 4.4 + 16, height: bs)
        bCopyRes.setLabel("COPY", size: fs)
        lHelp.frame = NSRect(x: p, y: bCopyRes.frame.maxY + p * 2, width: cw, height: max(20, bounds.height - bCopyRes.frame.maxY - p * 3))

        // 9-line
        let lw = cw * 0.36
        let rh = max(16, (bounds.height - top - p) / 11)          // ten lines and the button row always fit
        let nineFont = PanelStyle.regular(min(boxFontSize, max(9, (rh - 4) * 0.62)))
        let nineLab = PanelStyle.bold(min(max(9, fs * 0.9), max(8, (rh - 4) * 0.6)))
        for i in 0..<10 {
            let y = top + CGFloat(i) * rh
            nl[i].font = nineLab
            nl[i].frame = NSRect(x: p, y: y + 1, width: lw, height: rh - 2)
            nt[i].font = nineFont
            nt[i].frame = NSRect(x: p + lw, y: y, width: cw - lw, height: rh - 2)
        }
        let by = top + 10 * rh + p
        let nineBtn = min(bs, max(16, rh - 2))
        bCopyNine.frame = NSRect(x: p, y: by, width: fs * 7.5 + 16, height: nineBtn)
        bCopyNine.setLabel("COPY 9-LINE", size: fs)
        bClearNine.frame = NSRect(x: bCopyNine.frame.maxX + p, y: by, width: fs * 3.6 + 16, height: nineBtn)
        bClearNine.setLabel(clearArmed ? "SURE?" : "CLEAR", size: fs)

        // checklist
        let cb = bounds.height - bs - p * 2
        let listFrame = NSRect(x: p, y: top, width: cw, height: max(30, cb - top))
        listScroll.frame = listFrame
        editScroll.frame = listFrame
        editBox.font = boxFont
        let itemH = max(20, (boxFontSize * 1.7).rounded())
        listDoc.frame = NSRect(x: 0, y: 0, width: listFrame.width, height: max(listFrame.height, CGFloat(checks.count) * itemH + 6))
        let checkFont = PanelStyle.regular(max(9, min(12, boxFontSize * 0.85)))
        for (i, c) in checks.enumerated() {
            c.frame = NSRect(x: 6, y: 3 + CGFloat(i) * itemH, width: listFrame.width - 12, height: itemH)
            if i < items.count {
                c.attributedTitle = NSAttributedString(string: items[i], attributes: [.foregroundColor: PanelStyle.fg, .font: checkFont])
            }
        }
        bEdit.frame = NSRect(x: p, y: cb + p, width: fs * 6.2 + 16, height: bs)
        bEdit.setLabel(editing ? "SAVE LIST" : "EDIT LIST", size: fs)
        bReset.frame = NSRect(x: bEdit.frame.maxX + p, y: cb + p, width: fs * 7 + 16, height: bs)
        bReset.setLabel("UNTICK ALL", size: fs)
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { return true }
}
