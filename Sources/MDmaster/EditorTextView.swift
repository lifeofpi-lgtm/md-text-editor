import AppKit

/// NSTextView tuned for markdown: centred measure, plain-text paste, list
/// continuation on Return, and ⌘B/⌘I style wrapping actions.
final class EditorTextView: NSTextView {
    var columnWidth: CGFloat = 680
    /// Document windows let the editor paint the title bar; the library window does not.
    var ownsWindowChrome = true
    var grabsFocus = true
    /// In focus mode the text sits lower so the current line can stay near centre.
    var typewriter = false { didSet { updateInsets() } }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        if grabsFocus { window.makeFirstResponder(self) }
        guard ownsWindowChrome else { return }
        // Let the title bar sit on the same sheet of paper as the text, so the
        // only chrome left is the traffic lights and the file name.
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Theme.paper
        window.isOpaque = true
    }

    /// Quiet prompt on an empty document; disappears with the first character.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, let font = typingAttributes[.font] as? NSFont else { return }
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Theme.marker]
        let origin = NSPoint(x: textContainerInset.width, y: textContainerInset.height)
        ("Start writing" as NSString).draw(at: origin, withAttributes: attrs)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateInsets()
    }

    func updateInsets() {
        let w = frame.width
        guard w > 0 else { return }
        let column = min(columnWidth, max(240, w - 48))
        let x = max(24, ((w - column) / 2).rounded())
        let visibleH = enclosingScrollView?.contentSize.height ?? 600
        let y = typewriter ? (visibleH * 0.42).rounded() : 56
        let inset = NSSize(width: x, height: y)
        if textContainerInset != inset { textContainerInset = inset }
    }

    // Rich text stays on so we can style, but nothing should ever come in styled.
    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }

    // MARK: Return continues lists and quotes

    private static let continuationRx = try! NSRegularExpression(
        pattern: #"^([ \t]*)(?:([-*+])|(\d{1,9})([.)])|(>))([ \t]+)(\[[ xX]\][ \t]+)?"#)

    override func insertNewline(_ sender: Any?) {
        let sel = selectedRange()
        let ns = string as NSString
        guard sel.length == 0, sel.location <= ns.length else { super.insertNewline(sender); return }
        let para = ns.paragraphRange(for: sel)
        let content = MarkdownHighlighter.contentRange(of: para, in: ns)
        let line = ns.substring(with: content)
        let lineNS = line as NSString
        guard let m = Self.continuationRx.firstMatch(in: line, range: NSRange(location: 0, length: lineNS.length)) else {
            super.insertNewline(sender); return
        }
        let rest = lineNS.substring(from: m.range.length).trimmingCharacters(in: .whitespaces)
        let caretAtEnd = sel.location >= content.upperBound
        if rest.isEmpty && caretAtEnd {
            // Empty item: Return ends the list instead of adding another bullet.
            insertText("", replacementRange: NSRange(location: para.location, length: m.range.length))
            return
        }
        let indent = lineNS.substring(with: m.range(at: 1))
        let gap = lineNS.substring(with: m.range(at: 6))
        var next = indent
        if m.range(at: 2).location != NSNotFound {
            next += lineNS.substring(with: m.range(at: 2)) + gap
        } else if m.range(at: 3).location != NSNotFound {
            let n = (Int(lineNS.substring(with: m.range(at: 3))) ?? 0) + 1
            next += "\(n)" + lineNS.substring(with: m.range(at: 4)) + gap
        } else {
            next += ">" + gap
        }
        if m.range(at: 7).location != NSNotFound { next += "[ ] " }
        insertText("\n" + next, replacementRange: sel)
    }

    // MARK: Formatting actions (wired to the Format menu)

    /// NSTextView merges consecutive edits into one undo step. A format action must be its own
    /// step, or Cmd-Z after a toolbar click would also undo the typing before it.
    private func undoStep(_ body: () -> Void) {
        breakUndoCoalescing()
        body()
        breakUndoCoalescing()
    }

    @objc func mdBold(_ sender: Any?)   { undoStep { wrapSelection(with: "**") } }
    @objc func mdItalic(_ sender: Any?) { undoStep { wrapSelection(with: "_") } }
    @objc func mdCode(_ sender: Any?)   { undoStep { wrapSelection(with: "`") } }
    @objc func mdStrike(_ sender: Any?) { undoStep { wrapSelection(with: "~~") } }

    @objc func mdLink(_ sender: Any?) { undoStep { insertLink() } }

    private func insertLink() {
        let sel = selectedRange()
        let ns = string as NSString
        let inner = ns.substring(with: sel)
        let looksLikeURL = inner.hasPrefix("http://") || inner.hasPrefix("https://")
        let replacement = looksLikeURL ? "[](\(inner))" : "[\(inner)](url)"
        insertText(replacement, replacementRange: sel)
        if looksLikeURL {
            setSelectedRange(NSRange(location: sel.location + 1, length: 0))
        } else {
            let urlLoc = sel.location + 1 + (inner as NSString).length + 2
            setSelectedRange(NSRange(location: urlLoc, length: 3))
        }
    }

    @objc func mdHeading1(_ sender: Any?) { applyBlock(.heading(1)) }
    @objc func mdHeading2(_ sender: Any?) { applyBlock(.heading(2)) }
    @objc func mdHeading3(_ sender: Any?) { applyBlock(.heading(3)) }
    @objc func mdBulletList(_ sender: Any?) { applyBlock(.bullet) }
    @objc func mdNumberedList(_ sender: Any?) { applyBlock(.numbered) }
    @objc func mdCheckbox(_ sender: Any?) { applyBlock(.checkbox) }
    @objc func mdQuote(_ sender: Any?) { applyBlock(.quote) }

    /// Applies a line-level format to every line the selection touches, as one undoable edit.
    private func applyBlock(_ target: MarkdownBlocks.Target) { undoStep { applyBlockNow(target) } }

    private func applyBlockNow(_ target: MarkdownBlocks.Target) {
        let ns = string as NSString
        let sel = selectedRange()
        // A selection that ends right after a newline must not drag the next line in.
        let endProbe = sel.length > 0 ? max(sel.location, sel.upperBound - 1) : sel.location
        let first = ns.paragraphRange(for: NSRange(location: min(sel.location, ns.length), length: 0))
        let last = ns.paragraphRange(for: NSRange(location: min(endProbe, ns.length), length: 0))
        let content = MarkdownHighlighter.contentRange(of: NSUnionRange(first, last), in: ns)
        let old = ns.substring(with: content)
        let new = MarkdownBlocks.apply(target, to: old.components(separatedBy: "\n")).joined(separator: "\n")
        guard new != old else { return }
        insertText(new, replacementRange: content)
        let newLen = (new as NSString).length
        if sel.length == 0 {
            let delta = newLen - (old as NSString).length
            setSelectedRange(NSRange(location: max(content.location, min(sel.location + delta, content.location + newLen)), length: 0))
        } else {
            setSelectedRange(NSRange(location: content.location, length: newLen))
        }
    }

    @objc func mdHeadingCycle(_ sender: Any?) { undoStep { cycleHeading() } }

    private func cycleHeading() {
        let ns = string as NSString
        let para = ns.paragraphRange(for: selectedRange())
        let content = MarkdownHighlighter.contentRange(of: para, in: ns)
        let line = ns.substring(with: content)
        let hashes = line.prefix { $0 == "#" }.count
        let stripped = line.drop { $0 == "#" }.drop { $0 == " " }
        let nextLevel = hashes >= 3 ? 0 : hashes + 1
        let prefix = nextLevel == 0 ? "" : String(repeating: "#", count: nextLevel) + " "
        insertText(prefix + stripped, replacementRange: content)
    }

    private func wrapSelection(with delim: String) {
        let sel = selectedRange()
        let ns = string as NSString
        let d = delim as NSString
        let inner = ns.substring(with: sel)

        // Already wrapped just outside the selection: unwrap.
        let outer = NSRange(location: sel.location - d.length, length: sel.length + 2 * d.length)
        if outer.location >= 0, outer.upperBound <= ns.length,
           ns.substring(with: NSRange(location: outer.location, length: d.length)) == delim,
           ns.substring(with: NSRange(location: sel.upperBound, length: d.length)) == delim {
            insertText(inner, replacementRange: outer)
            setSelectedRange(NSRange(location: outer.location, length: sel.length))
            return
        }
        // Wrapped inside the selection: unwrap.
        if inner.hasPrefix(delim), inner.hasSuffix(delim), (inner as NSString).length >= 2 * d.length {
            let stripped = (inner as NSString).substring(with: NSRange(location: d.length, length: (inner as NSString).length - 2 * d.length))
            insertText(stripped, replacementRange: sel)
            setSelectedRange(NSRange(location: sel.location, length: (stripped as NSString).length))
            return
        }
        insertText(delim + inner + delim, replacementRange: sel)
        setSelectedRange(NSRange(location: sel.location + d.length, length: sel.length))
    }
}

/// Paints one rounded box behind each fenced code block, full column width.
final class CodeBlockLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        if let storage = textStorage, let container = textContainers.first, storage.length > 0 {
            let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
            var drawn = Set<Int>()
            storage.enumerateAttribute(MDAttr.codeBlock, in: charRange, options: []) { value, range, _ in
                guard value != nil else { return }
                var run = NSRange()
                _ = storage.attribute(MDAttr.codeBlock, at: range.location, longestEffectiveRange: &run,
                                      in: NSRange(location: 0, length: storage.length))
                guard drawn.insert(run.location).inserted else { return }
                ensureLayout(forCharacterRange: run)
                let glyphs = glyphRange(forCharacterRange: run, actualCharacterRange: nil)
                var union = NSRect.null
                enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in
                    union = union.union(rect)
                }
                guard !union.isNull else { return }
                let pad: CGFloat = 6
                let box = NSRect(x: origin.x, y: origin.y + union.minY - pad,
                                 width: container.size.width, height: union.height + pad * 2)
                Theme.codeBg.setFill()
                NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8).fill()
            }
        }
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }
}

/// Finds the editor from a window, for toolbar buttons and menu items. Going through the
/// responder chain alone fails when keyboard focus is in the sheet list.
enum EditorActions {
    static func editor(in window: NSWindow? = NSApp.keyWindow ?? NSApp.mainWindow) -> EditorTextView? {
        guard let root = window?.contentView?.superview ?? window?.contentView else { return nil }
        return find(in: root)
    }

    private static func find(in view: NSView) -> EditorTextView? {
        if let tv = view as? EditorTextView { return tv }
        for sub in view.subviews { if let tv = find(in: sub) { return tv } }
        return nil
    }

    static func perform(_ selector: Selector, in window: NSWindow? = NSApp.keyWindow ?? NSApp.mainWindow) {
        guard let tv = editor(in: window) else { NSSound.beep(); return }
        if tv.window?.firstResponder !== tv { tv.window?.makeFirstResponder(tv) }
        tv.perform(selector, with: nil)
    }
}
