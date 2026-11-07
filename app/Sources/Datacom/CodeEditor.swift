import AppKit
import SwiftUI

/// A Python editor: NSTextView with highlighting, line numbers, auto-indent, Tab / Shift-Tab,
/// ⌘/ to comment and ⌘↩ to run. Every edit goes through the text view, so undo works.
struct CodeEditor: NSViewRepresentable {
    let text: String
    /// The editor reloads `text` only when this changes (another problem, Reset, Import).
    let key: String
    var onChange: (String) -> Void
    var onRun: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = Editor.background

        let view = CodeTextView(frame: .zero)
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.usesFindBar = true
        view.isIncrementalSearchingEnabled = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isGrammarCheckingEnabled = false
        view.smartInsertDeleteEnabled = false
        view.font = Editor.font
        view.textColor = Editor.ink
        view.backgroundColor = Editor.background
        view.drawsBackground = true
        view.insertionPointColor = .white
        view.selectedTextAttributes = [.backgroundColor: NSColor(red: 0.39, green: 0.40, blue: 0.95, alpha: 0.45)]
        view.textContainerInset = NSSize(width: 8, height: 10)
        view.typingAttributes = [.font: Editor.font, .foregroundColor: Editor.ink]
        // No wrapping: code scrolls sideways like any editor.
        view.isHorizontallyResizable = true
        view.isVerticallyResizable = true
        view.autoresizingMask = [.width, .height]
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.delegate = context.coordinator
        view.onRun = { context.coordinator.onRun() }
        scroll.documentView = view

        let ruler = LineNumberRuler(textView: view)
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        context.coordinator.textView = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.onChange = onChange
        c.onRun = onRun
        guard c.loaded != key, let view = c.textView else { return }
        c.loaded = key
        c.applying = true
        view.string = text
        view.undoManager?.removeAllActions()
        Editor.highlight(view)
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.scrollToBeginningOfDocument(nil)
        c.applying = false
        scroll.verticalRulerView?.needsDisplay = true
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: CodeTextView?
        var loaded = ""
        var applying = false
        var onChange: (String) -> Void = { _ in }
        var onRun: () -> Void = {}

        func textDidChange(_ notification: Notification) {
            guard let view = textView, !applying else { return }
            Editor.highlight(view)
            view.enclosingScrollView?.verticalRulerView?.needsDisplay = true
            onChange(view.string)
        }
    }
}

enum Editor {
    static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    static let background = NSColor(red: 0.059, green: 0.078, blue: 0.141, alpha: 1)
    static let ink = NSColor(red: 0.89, green: 0.91, blue: 0.96, alpha: 1)
    static let comment = NSColor(red: 0.47, green: 0.52, blue: 0.62, alpha: 1)
    static let string = NSColor(red: 0.65, green: 0.89, blue: 0.63, alpha: 1)
    static let keyword = NSColor(red: 0.98, green: 0.46, blue: 0.62, alpha: 1)
    static let builtin = NSColor(red: 0.46, green: 0.80, blue: 0.96, alpha: 1)
    static let number = NSColor(red: 0.98, green: 0.76, blue: 0.43, alpha: 1)
    static let function = NSColor(red: 0.77, green: 0.65, blue: 1.0, alpha: 1)

    private static let keywords = "False|None|True|and|as|assert|async|await|break|class|continue|def|del|elif|else|except|finally|for|from|global|if|import|in|is|lambda|nonlocal|not|or|pass|raise|return|try|while|with|yield|match|case"
    private static let builtins = "abs|all|any|bin|bool|bytes|callable|chr|dict|dir|divmod|enumerate|filter|float|format|frozenset|getattr|hasattr|hash|hex|id|input|int|isinstance|issubclass|iter|len|list|map|max|min|next|object|open|ord|pow|print|range|repr|reversed|round|set|setattr|slice|sorted|str|sum|super|tuple|type|zip|self|cls"
    private static let rules: [(NSRegularExpression, NSColor, Int)] = [
        (try! NSRegularExpression(pattern: "\\b(?:\\d+\\.?\\d*(?:[eE][-+]?\\d+)?|0[xX][0-9a-fA-F]+)\\b"), number, 0),
        (try! NSRegularExpression(pattern: "\\b(?:\(keywords))\\b"), keyword, 0),
        (try! NSRegularExpression(pattern: "\\b(?:\(builtins))\\b"), builtin, 0),
        (try! NSRegularExpression(pattern: "\\b(?:def|class)\\s+([A-Za-z_]\\w*)"), function, 1),
        (try! NSRegularExpression(pattern: "^\\s*(@[\\w.]+)", options: [.anchorsMatchLines]), function, 1),
    ]
    // Strings and comments in one left-to-right pass, so a # inside a string isn't a comment.
    private static let stringsAndComments = try! NSRegularExpression(
        pattern: "([rRbBuUfF]{0,2}(?:\"\"\"[\\s\\S]*?(?:\"\"\"|\\z)|'''[\\s\\S]*?(?:'''|\\z)|\"(?:\\\\.|[^\"\\\\\\n])*\"?|'(?:\\\\.|[^'\\\\\\n])*'?))|(#[^\\n]*)")

    @MainActor
    static func highlight(_ view: NSTextView) {
        guard let storage = view.textStorage else { return }
        let text = storage.string
        let all = NSRange(location: 0, length: (text as NSString).length)
        storage.beginEditing()
        storage.setAttributes([.font: font, .foregroundColor: ink], range: all)
        for (re, color, group) in rules {
            for m in re.matches(in: text, range: all) {
                let r = m.range(at: group)
                if r.location != NSNotFound { storage.addAttribute(.foregroundColor, value: color, range: r) }
            }
        }
        for m in stringsAndComments.matches(in: text, range: all) {
            if m.range(at: 1).location != NSNotFound {
                storage.addAttribute(.foregroundColor, value: string, range: m.range(at: 1))
            } else if m.range(at: 2).location != NSNotFound {
                storage.addAttribute(.foregroundColor, value: comment, range: m.range(at: 2))
            }
        }
        storage.endEditing()
    }
}

final class CodeTextView: NSTextView {
    var onRun: () -> Void = {}
    private let unit = "    "

    private var ns: NSString { string as NSString }

    private func lineRange(_ range: NSRange) -> NSRange { ns.lineRange(for: range) }

    /// Replaces a range through the text system so the change is undoable.
    private func replace(_ range: NSRange, with text: String, select: NSRange? = nil) {
        guard shouldChangeText(in: range, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
        if let select { setSelectedRange(select) }
    }

    override func insertNewline(_ sender: Any?) {
        let sel = selectedRange()
        let line = lineRange(NSRange(location: sel.location, length: 0))
        let before = ns.substring(with: NSRange(location: line.location, length: sel.location - line.location))
        var indent = String(before.prefix(while: { $0 == " " || $0 == "\t" }))
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        if let last = trimmed.last, ":([{".contains(last) {
            indent += unit
        } else if trimmed.range(of: "^(return|pass|break|continue|raise)\\b", options: .regularExpression) != nil {
            indent = String(indent.dropLast(min(4, indent.count)))
        }
        insertText("\n" + indent, replacementRange: sel)
        scrollRangeToVisible(selectedRange())
    }

    override func insertTab(_ sender: Any?) {
        let sel = selectedRange()
        if sel.length > 0 && ns.substring(with: sel).contains("\n") {
            shiftLines(dedent: false)
            return
        }
        let line = lineRange(NSRange(location: sel.location, length: 0))
        let col = sel.location - line.location
        insertText(String(repeating: " ", count: 4 - col % 4), replacementRange: sel)
    }

    override func insertBacktab(_ sender: Any?) { shiftLines(dedent: true) }

    /// Backspace inside leading spaces removes back to the previous indent stop.
    override func deleteBackward(_ sender: Any?) {
        let sel = selectedRange()
        if sel.length == 0, sel.location > 0 {
            let line = lineRange(NSRange(location: sel.location, length: 0))
            let before = ns.substring(with: NSRange(location: line.location, length: sel.location - line.location))
            if !before.isEmpty, before.allSatisfy({ $0 == " " }) {
                let n = before.count % 4 == 0 ? 4 : before.count % 4
                replace(NSRange(location: sel.location - n, length: n), with: "",
                        select: NSRange(location: sel.location - n, length: 0))
                return
            }
        }
        super.deleteBackward(sender)
    }

    func shiftLines(dedent: Bool) {
        let sel = selectedRange()
        var range = lineRange(sel)
        if range.length > 0, sel.length > 0, ns.character(at: NSMaxRange(sel) - 1) == 10, NSMaxRange(range) > NSMaxRange(sel) {
            range = lineRange(NSRange(location: sel.location, length: sel.length - 1))
        }
        let block = ns.substring(with: range)
        let hasNewline = block.hasSuffix("\n")
        var lines = (hasNewline ? String(block.dropLast()) : block).components(separatedBy: "\n")
        lines = lines.map { line in
            if dedent {
                let n = min(4, line.prefix(while: { $0 == " " }).count)
                return String(line.dropFirst(n))
            }
            return line.isEmpty ? line : unit + line
        }
        let out = lines.joined(separator: "\n") + (hasNewline ? "\n" : "")
        replace(range, with: out, select: NSRange(location: range.location, length: (out as NSString).length - (hasNewline ? 1 : 0)))
    }

    func toggleComment() {
        let sel = selectedRange()
        let range = lineRange(sel)
        let block = ns.substring(with: range)
        let hasNewline = block.hasSuffix("\n")
        let lines = (hasNewline ? String(block.dropLast()) : block).components(separatedBy: "\n")
        let code = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let uncomment = !code.isEmpty && code.allSatisfy { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        let pad = code.map { $0.prefix(while: { $0 == " " }).count }.min() ?? 0
        let out = lines.map { line -> String in
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return line }
            if uncomment {
                return line.replacingOccurrences(of: "^(\\s*)# ?", with: "$1", options: .regularExpression)
            }
            let i = line.index(line.startIndex, offsetBy: pad)
            return String(line[..<i]) + "# " + String(line[i...])
        }.joined(separator: "\n") + (hasNewline ? "\n" : "")
        replace(range, with: out, select: NSRange(location: range.location, length: (out as NSString).length - (hasNewline ? 1 : 0)))
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "/" {
            toggleComment()
            return true
        }
        if flags == .command, event.keyCode == 36 || event.keyCode == 76 {
            onRun()
            return true
        }
        if flags == .command, event.charactersIgnoringModifiers == "]" { shiftLines(dedent: false); return true }
        if flags == .command, event.charactersIgnoringModifiers == "[" { shiftLines(dedent: true); return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// Line numbers in the editor's left margin.
final class LineNumberRuler: NSRulerView {
    private weak var textView: NSTextView?
    private let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 40
        NotificationCenter.default.addObserver(self, selector: #selector(redraw), name: NSView.boundsDidChangeNotification,
                                               object: textView.enclosingScrollView?.contentView)
        textView.enclosingScrollView?.contentView.postsBoundsChangedNotifications = true
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func redraw() { needsDisplay = true }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        Editor.background.setFill()
        bounds.fill()
        NSColor(white: 1, alpha: 0.06).setFill()
        NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill()
        let text = tv.string as NSString
        let visible = tv.visibleRect
        let glyphs = lm.glyphRange(forBoundingRect: visible, in: tc)
        let chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        var line = 1
        text.enumerateSubstrings(in: NSRange(location: 0, length: chars.location), options: [.byLines, .substringNotRequired]) { _, _, _, _ in line += 1 }
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(red: 0.35, green: 0.38, blue: 0.48, alpha: 1)]
        let inset = tv.textContainerInset.height
        let offset = convert(NSPoint.zero, from: tv).y
        func draw(_ n: Int, _ y: CGFloat, _ height: CGFloat) {
            let label = "\(n)" as NSString
            let size = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: ruleThickness - size.width - 8, y: y + inset + offset + (height - size.height) / 2), withAttributes: attrs)
        }
        var index = chars.location
        while index < NSMaxRange(chars) {
            let lineRange = text.lineRange(for: NSRange(location: index, length: 0))
            let glyph = lm.glyphRange(forCharacterRange: NSRange(location: lineRange.location, length: 0), actualCharacterRange: nil)
            let frag = lm.lineFragmentRect(forGlyphAt: glyph.location, effectiveRange: nil)
            draw(line, frag.minY, frag.height)
            line += 1
            index = NSMaxRange(lineRange)
        }
        if text.length == 0 || text.hasSuffix("\n") {
            let extra = lm.extraLineFragmentRect
            if extra.height > 0 && extra.intersects(visible) { draw(line, extra.minY, extra.height) }
        }
    }
}
