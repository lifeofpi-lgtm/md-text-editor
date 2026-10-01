import SwiftUI
import AppKit

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var focusMode: Bool
    var focusScope: FocusScope
    var typewriter: Bool
    var serif: Bool
    var columnWidth: CGFloat
    var checkSpelling: Bool
    @Binding var selectedWords: Int
    @Binding var formatState: FormatState
    var ownsWindowChrome = true
    var grabsFocus = true

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // Build the TextKit 1 stack by hand: temporary attributes and the custom
        // layout manager (code block boxes) both need it.
        let storage = NSTextStorage()
        let layout = CodeBlockLayoutManager()
        layout.allowsNonContiguousLayout = false
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)

        let tv = EditorTextView(frame: .zero, textContainer: container)
        tv.ownsWindowChrome = ownsWindowChrome
        tv.grabsFocus = grabsFocus
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.isRichText = true
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = true
        tv.isGrammarCheckingEnabled = true
        tv.smartInsertDeleteEnabled = false
        tv.drawsBackground = false
        tv.insertionPointColor = Theme.accent
        tv.selectedTextAttributes = [.backgroundColor: Theme.selection]
        tv.linkTextAttributes = [:]
        tv.delegate = context.coordinator
        storage.delegate = context.coordinator

        let scroll = NSScrollView()
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = Theme.paper
        scroll.scrollerStyle = .overlay

        context.coordinator.textView = tv
        context.coordinator.configure(self)
        context.coordinator.replaceText(text)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.parent = self
        c.configure(self)
        if let tv = c.textView, tv.string != text, !c.isEditing {
            c.replaceText(text)
        }
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: MarkdownTextView
        weak var textView: EditorTextView? {
            didSet { observeFocusRequests() }
        }
        var isEditing = false
        private var focusObserver: NSObjectProtocol?

        deinit { if let o = focusObserver { NotificationCenter.default.removeObserver(o) } }

        /// "New Sheet" asks the editor in the key window to take focus.
        private func observeFocusRequests() {
            guard focusObserver == nil else { return }
            focusObserver = NotificationCenter.default.addObserver(forName: .mdFocusEditor, object: nil, queue: .main) { [weak self] _ in
                guard let tv = self?.textView, let window = tv.window, window.isKeyWindow else { return }
                window.makeFirstResponder(tv)
            }
        }

        private var highlighter: MarkdownHighlighter
        private var focusMode = false
        private var typewriter = false
        private var scope: FocusScope = .paragraph
        private var fenceCount = 0
        private var pendingEdit: NSRange?
        private var lastCaretY: CGFloat = -1

        init(_ parent: MarkdownTextView) {
            self.parent = parent
            var h = MarkdownHighlighter(fontSize: parent.fontSize)
            h.serif = parent.serif
            self.highlighter = h
        }

        func configure(_ p: MarkdownTextView) {
            var needsFull = false
            if highlighter.fontSize != p.fontSize || highlighter.serif != p.serif {
                var h = MarkdownHighlighter(fontSize: p.fontSize)
                h.serif = p.serif
                highlighter = h
                needsFull = true
            }
            let focusChanged = focusMode != p.focusMode || scope != p.focusScope
            let typewriterChanged = typewriter != p.typewriter
            focusMode = p.focusMode
            scope = p.focusScope
            typewriter = p.typewriter
            if let tv = textView {
                tv.typewriter = p.typewriter
                if tv.columnWidth != p.columnWidth { tv.columnWidth = p.columnWidth; tv.updateInsets() }
                if tv.isContinuousSpellCheckingEnabled != p.checkSpelling {
                    tv.isContinuousSpellCheckingEnabled = p.checkSpelling
                    tv.isGrammarCheckingEnabled = p.checkSpelling
                }
            }
            if needsFull {
                highlightAll()
                textView?.typingAttributes = highlighter.bodyAttributes
            }
            if focusChanged || needsFull { applyFocus() }
            if typewriterChanged || needsFull {
                lastCaretY = -1
                if typewriter { centerCaret(animated: true) }
            }
        }

        func replaceText(_ text: String) {
            guard let tv = textView, let storage = tv.textStorage else { return }
            storage.beginEditing()
            storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)
            storage.endEditing()
            highlightAll()
            tv.typingAttributes = highlighter.bodyAttributes
            applyFocus()
        }

        func highlightAll() {
            guard let storage = textView?.textStorage else { return }
            fenceCount = MarkdownHighlighter.fenceCount(in: storage.string)
            highlighter.apply(to: storage, target: nil)
        }

        // MARK: NSTextStorageDelegate

        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                         range editedRange: NSRange, changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters) else { return }
            pendingEdit = pendingEdit.map { NSUnionRange($0, editedRange) } ?? editedRange
        }

        // MARK: NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard let tv = textView, let storage = tv.textStorage else { return }
            isEditing = true
            parent.text = tv.string
            isEditing = false

            let newFenceCount = MarkdownHighlighter.fenceCount(in: storage.string)
            if newFenceCount != fenceCount || pendingEdit == nil {
                fenceCount = newFenceCount
                highlighter.apply(to: storage, target: nil)
            } else if let edit = pendingEdit {
                highlighter.apply(to: storage, target: edit)
            }
            pendingEdit = nil
            tv.typingAttributes = highlighter.bodyAttributes
            applyFocus()
            if typewriter { centerCaret(animated: false) }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            reportSelection()
            if focusMode { applyFocus() }
            if typewriter { centerCaret(animated: true) }
        }

        /// Words inside the selection, for the status bar. Deferred because this
        /// can fire while SwiftUI is mid-update.
        private func reportSelection() {
            guard let tv = textView else { return }
            let format = MarkdownFormatDetector.state(in: tv.string as NSString, selection: tv.selectedRange())
            if format != parent.formatState {
                DispatchQueue.main.async { [weak self] in self?.parent.formatState = format }
            }
            let sel = tv.selectedRange()
            var n = 0
            if sel.length > 0 {
                (tv.string as NSString).enumerateSubstrings(in: sel, options: [.byWords, .substringNotRequired]) { _, _, _, _ in n += 1 }
            }
            guard n != parent.selectedWords else { return }
            DispatchQueue.main.async { [weak self] in self?.parent.selectedWords = n }
        }

        /// Spelling and grammar should ignore code, where "foo_bar" is not a typo.
        func textView(_ textView: NSTextView, shouldSetSpellingState value: Int, range affectedCharRange: NSRange) -> Int {
            guard value != 0, let storage = textView.textStorage, NSMaxRange(affectedCharRange) <= storage.length,
                  affectedCharRange.length > 0 else { return value }
            if storage.attribute(MDAttr.codeBlock, at: affectedCharRange.location, effectiveRange: nil) != nil { return 0 }
            if let font = storage.attribute(.font, at: affectedCharRange.location, effectiveRange: nil) as? NSFont,
               font.isFixedPitch { return 0 }
            return value
        }

        // MARK: Focus mode

        /// Dims everything except the current paragraph or sentence using temporary
        /// attributes, so neither the document nor the undo stack is touched.
        func applyFocus() {
            guard let tv = textView, let lm = tv.layoutManager else { return }
            let ns = tv.string as NSString
            let full = NSRange(location: 0, length: ns.length)
            lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
            guard focusMode, ns.length > 0 else { return }

            let sel = tv.selectedRange()
            var keep = ns.paragraphRange(for: NSRange(location: min(sel.location, ns.length), length: 0))
            if scope == .sentence { keep = sentenceRange(in: ns, at: sel.location, within: keep) }

            let before = NSRange(location: 0, length: keep.location)
            let after = NSRange(location: keep.upperBound, length: ns.length - keep.upperBound)
            if before.length > 0 { lm.addTemporaryAttribute(.foregroundColor, value: Theme.dim, forCharacterRange: before) }
            if after.length > 0 { lm.addTemporaryAttribute(.foregroundColor, value: Theme.dim, forCharacterRange: after) }
        }

        private func sentenceRange(in ns: NSString, at loc: Int, within para: NSRange) -> NSRange {
            var result = para
            var found = false
            ns.enumerateSubstrings(in: para, options: [.bySentences, .substringNotRequired]) { _, r, _, stop in
                result = r
                if loc < r.upperBound { found = true; stop.pointee = true }
            }
            _ = found
            return result
        }

        /// Typewriter scrolling: keep the caret's line near the vertical centre.
        func centerCaret(animated: Bool) {
            guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer,
                  let scroll = tv.enclosingScrollView else { return }
            let sel = tv.selectedRange()
            let glyphIndex = lm.glyphIndexForCharacter(at: min(sel.location, max(0, (tv.string as NSString).length)))
            var rect: NSRect
            if lm.numberOfGlyphs == 0 || glyphIndex >= lm.numberOfGlyphs {
                rect = lm.extraLineFragmentRect
                if rect.isEmpty, lm.numberOfGlyphs > 0 {
                    rect = lm.lineFragmentRect(forGlyphAt: lm.numberOfGlyphs - 1, effectiveRange: nil)
                }
            } else {
                rect = lm.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            }
            _ = tc
            let caretY = rect.midY + tv.textContainerInset.height
            guard abs(caretY - lastCaretY) > 1 else { return }
            lastCaretY = caretY
            let clip = scroll.contentView
            let target = max(0, caretY - clip.bounds.height / 2)
            let origin = NSPoint(x: clip.bounds.origin.x, y: target)
            if animated {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    clip.animator().setBoundsOrigin(origin)
                }
            } else {
                clip.setBoundsOrigin(origin)
            }
            scroll.reflectScrolledClipView(clip)
        }
    }
}
