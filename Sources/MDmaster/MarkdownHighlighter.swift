import AppKit

/// Line-based markdown styler over an NSTextStorage. The text stays raw markdown;
/// we only change fonts, colours and paragraph metrics. Runs fully on first load,
/// then only over the edited paragraphs (fence state is always re-scanned from the
/// top because a ``` toggles everything below it).
struct MarkdownHighlighter {
    let fontSize: CGFloat
    var serif = false

    /// New York is the system serif; same optical sizing and italics as SF.
    private func text(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard serif, let d = base.fontDescriptor.withDesign(.serif),
              let f = NSFont(descriptor: d, size: size) else { return base }
        return f
    }

    // MARK: Fonts

    var body: NSFont { text(fontSize, .regular) }
    var mono: NSFont { .monospacedSystemFont(ofSize: (fontSize * 0.88).rounded(), weight: .regular) }

    func heading(_ level: Int) -> NSFont {
        switch level {
        case 1: return text((fontSize * 1.85).rounded(), .bold)
        case 2: return text((fontSize * 1.45).rounded(), .bold)
        case 3: return text((fontSize * 1.2).rounded(), .semibold)
        default: return text(fontSize, .semibold)
        }
    }

    // MARK: Paragraph styles

    var bodyParagraph: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = (fontSize * 0.45).rounded()
        p.paragraphSpacing = (fontSize * 0.7).rounded()
        return p
    }

    func headingParagraph(_ level: Int) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = (fontSize * 0.2).rounded()
        p.paragraphSpacingBefore = (fontSize * (level == 1 ? 1.4 : 1.1)).rounded()
        p.paragraphSpacing = (fontSize * 0.35).rounded()
        return p
    }

    func listParagraph(firstIndent: CGFloat, textIndent: CGFloat) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = (fontSize * 0.45).rounded()
        p.paragraphSpacing = (fontSize * 0.25).rounded()
        p.firstLineHeadIndent = firstIndent
        p.headIndent = textIndent
        return p
    }

    var quoteParagraph: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = (fontSize * 0.45).rounded()
        p.paragraphSpacing = (fontSize * 0.5).rounded()
        p.firstLineHeadIndent = (fontSize * 1.2).rounded()
        p.headIndent = (fontSize * 1.2).rounded()
        return p
    }

    var codeParagraph: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = (fontSize * 0.22).rounded()
        p.paragraphSpacing = 0
        p.firstLineHeadIndent = 14
        p.headIndent = 14
        p.tailIndent = -14
        return p
    }

    var tableParagraph: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = (fontSize * 0.25).rounded()
        p.paragraphSpacing = 0
        return p
    }

    var bodyAttributes: [NSAttributedString.Key: Any] {
        [.font: body, .foregroundColor: Theme.ink, .paragraphStyle: bodyParagraph]
    }

    // MARK: Regexes

    private static func rx(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [])
    }

    static let fenceRx    = rx(#"^[ \t]{0,3}(```|~~~)"#)
    static let headingRx  = rx(#"^(#{1,6})[ \t]+"#)
    static let quoteRx    = rx(#"^[ \t]{0,3}(>)[ \t]?"#)
    static let listRx     = rx(#"^([ \t]*)([-*+]|\d{1,9}[.)])([ \t]+)(\[[ xX]\][ \t]+)?"#)
    static let hrRx       = rx(#"^[ \t]{0,3}([-*_])([ \t]*\1){2,}[ \t]*$"#)
    static let tableRx    = rx(#"^[ \t]*\|.*\|[ \t]*$"#)
    static let codeRx     = rx(#"(`+)([^`\n]+?)\1"#)
    static let boldRx     = rx(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    static let italicRx   = rx(#"(?<![\w*])(\*|_)(?=[^\s*_])(.+?)(?<=[^\s*_])\1(?![\w*])"#)
    static let strikeRx   = rx(#"(~~)(?=\S)(.+?)(?<=\S)\1"#)
    static let linkRx     = rx(#"(!?\[)([^\]\n]*)(\]\()([^)\n]*)(\))"#)
    static let fenceCountRx = rx(#"(?m)^[ \t]{0,3}(```|~~~)"#)

    // MARK: Apply

    /// - Parameter target: character range whose paragraphs need restyling, or nil for everything.
    func apply(to storage: NSTextStorage, target: NSRange?) {
        let ns = storage.string as NSString
        let length = ns.length
        let full = NSRange(location: 0, length: length)
        let scope: NSRange = target.map { ns.paragraphRange(for: NSIntersectionRange($0, full)) } ?? full

        storage.beginEditing()
        defer { storage.endEditing() }

        storage.setAttributes(bodyAttributes, range: scope)
        guard length > 0 else { return }

        var inFence = false
        var loc = 0
        while loc < length {
            let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
            loc = lineRange.upperBound
            let content = Self.contentRange(of: lineRange, in: ns)
            let touches = NSIntersectionRange(lineRange, scope).length > 0
                || (lineRange.length == 0 && lineRange.location == scope.location)

            let line = ns.substring(with: content)
            let lineNS = line as NSString
            let lineAll = NSRange(location: 0, length: lineNS.length)

            if Self.fenceRx.firstMatch(in: line, range: lineAll) != nil {
                if touches {
                    storage.addAttributes([.font: mono, .foregroundColor: Theme.marker,
                                           .paragraphStyle: codeParagraph,
                                           MDAttr.codeBlock: true], range: lineRange)
                }
                inFence.toggle()
                continue
            }
            if inFence {
                if touches {
                    storage.addAttributes([.font: mono, .foregroundColor: Theme.codeInk,
                                           .paragraphStyle: codeParagraph,
                                           MDAttr.codeBlock: true], range: lineRange)
                }
                continue
            }
            guard touches else { continue }

            func shift(_ r: NSRange) -> NSRange { NSRange(location: content.location + r.location, length: r.length) }

            var inlineRange = lineAll
            var skipInline = false

            if let m = Self.headingRx.firstMatch(in: line, range: lineAll) {
                let level = m.range(at: 1).length
                storage.addAttribute(.font, value: heading(level), range: content)
                // Display sizes want tighter tracking than body text.
                if level <= 2 { storage.addAttribute(.kern, value: -(heading(level).pointSize * 0.02), range: content) }
                storage.addAttribute(.paragraphStyle, value: headingParagraph(level), range: lineRange)
                storage.addAttribute(.foregroundColor, value: Theme.marker, range: shift(m.range))
                inlineRange = NSRange(location: m.range.length, length: lineAll.length - m.range.length)
            } else if Self.hrRx.firstMatch(in: line, range: lineAll) != nil {
                storage.addAttribute(.foregroundColor, value: Theme.marker, range: content)
                skipInline = true
            } else if Self.tableRx.firstMatch(in: line, range: lineAll) != nil {
                storage.addAttributes([.font: mono, .foregroundColor: Theme.codeInk,
                                       .paragraphStyle: tableParagraph], range: lineRange)
                skipInline = true
            } else if let m = Self.quoteRx.firstMatch(in: line, range: lineAll) {
                storage.addAttribute(.paragraphStyle, value: quoteParagraph, range: lineRange)
                storage.addAttribute(.foregroundColor, value: Theme.muted, range: content)
                storage.addAttribute(.foregroundColor, value: Theme.accent, range: shift(m.range(at: 1)))
                addTrait(.italic, to: storage, in: content)
                inlineRange = NSRange(location: m.range.length, length: lineAll.length - m.range.length)
            } else if let m = Self.listRx.firstMatch(in: line, range: lineAll) {
                let leading = lineNS.substring(with: m.range(at: 1))
                let markerText = lineNS.substring(with: NSRange(location: m.range(at: 2).location,
                                                                 length: m.range.length - m.range(at: 2).location))
                let leadWidth = (leading as NSString).size(withAttributes: [.font: body]).width
                let markerWidth = (markerText as NSString).size(withAttributes: [.font: body]).width
                storage.addAttribute(.paragraphStyle,
                                     value: listParagraph(firstIndent: leadWidth, textIndent: leadWidth + markerWidth),
                                     range: lineRange)
                storage.addAttribute(.foregroundColor, value: Theme.accent, range: shift(m.range(at: 2)))
                if m.range(at: 4).location != NSNotFound {
                    storage.addAttribute(.foregroundColor, value: Theme.accent, range: shift(m.range(at: 4)))
                }
                inlineRange = NSRange(location: m.range.length, length: lineAll.length - m.range.length)
            }

            guard !skipInline, inlineRange.length > 0 else { continue }
            applyInline(to: storage, line: line, range: inlineRange, shift: shift)
        }
    }

    private func applyInline(to storage: NSTextStorage, line: String, range: NSRange, shift: (NSRange) -> NSRange) {
        // Code spans first; anything inside them is literal, so remember them and
        // skip emphasis matches that overlap.
        var codeRanges: [NSRange] = []
        Self.codeRx.enumerateMatches(in: line, range: range) { m, _, _ in
            guard let m else { return }
            codeRanges.append(m.range)
            storage.addAttributes([.font: mono, .foregroundColor: Theme.codeInk,
                                   .backgroundColor: Theme.codeBg], range: shift(m.range(at: 2)))
            storage.addAttribute(.foregroundColor, value: Theme.marker, range: shift(m.range(at: 1)))
            let close = NSRange(location: m.range.upperBound - m.range(at: 1).length, length: m.range(at: 1).length)
            storage.addAttribute(.foregroundColor, value: Theme.marker, range: shift(close))
        }
        func inCode(_ r: NSRange) -> Bool { codeRanges.contains { NSIntersectionRange($0, r).length > 0 } }

        Self.linkRx.enumerateMatches(in: line, range: range) { m, _, _ in
            guard let m, !inCode(m.range) else { return }
            storage.addAttribute(.foregroundColor, value: Theme.marker, range: shift(m.range(at: 1)))
            storage.addAttribute(.foregroundColor, value: Theme.accent, range: shift(m.range(at: 2)))
            storage.addAttribute(.foregroundColor, value: Theme.marker, range: shift(m.range(at: 3)))
            storage.addAttribute(.foregroundColor, value: Theme.marker, range: shift(m.range(at: 4)))
            storage.addAttribute(.foregroundColor, value: Theme.marker, range: shift(m.range(at: 5)))
        }
        Self.boldRx.enumerateMatches(in: line, range: range) { m, _, _ in
            guard let m, !inCode(m.range) else { return }
            addTrait(.bold, to: storage, in: shift(m.range(at: 2)))
            markDelimiters(m, storage: storage, shift: shift)
        }
        Self.italicRx.enumerateMatches(in: line, range: range) { m, _, _ in
            guard let m, !inCode(m.range) else { return }
            addTrait(.italic, to: storage, in: shift(m.range(at: 2)))
            markDelimiters(m, storage: storage, shift: shift)
        }
        Self.strikeRx.enumerateMatches(in: line, range: range) { m, _, _ in
            guard let m, !inCode(m.range) else { return }
            storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                   .foregroundColor: Theme.muted], range: shift(m.range(at: 2)))
            markDelimiters(m, storage: storage, shift: shift)
        }
    }

    private func markDelimiters(_ m: NSTextCheckingResult, storage: NSTextStorage, shift: (NSRange) -> NSRange) {
        let open = m.range(at: 1)
        let close = NSRange(location: m.range.upperBound - open.length, length: open.length)
        storage.addAttribute(.foregroundColor, value: Theme.marker, range: shift(open))
        storage.addAttribute(.foregroundColor, value: Theme.marker, range: shift(close))
    }

    private func addTrait(_ trait: NSFontDescriptor.SymbolicTraits, to storage: NSTextStorage, in range: NSRange) {
        storage.enumerateAttribute(.font, in: range, options: []) { value, r, _ in
            guard let f = value as? NSFont else { return }
            let desc = f.fontDescriptor.withSymbolicTraits(f.fontDescriptor.symbolicTraits.union(trait))
            if let nf = NSFont(descriptor: desc, size: f.pointSize) {
                storage.addAttribute(.font, value: nf, range: r)
            }
        }
    }

    /// The line without its trailing newline.
    static func contentRange(of lineRange: NSRange, in ns: NSString) -> NSRange {
        var end = lineRange.upperBound
        while end > lineRange.location {
            let c = ns.character(at: end - 1)
            if c == 0x0A || c == 0x0D { end -= 1 } else { break }
        }
        return NSRange(location: lineRange.location, length: end - lineRange.location)
    }

    static func fenceCount(in text: String) -> Int {
        fenceCountRx.numberOfMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }
}
