import Foundation

/// Which formats are active at the caret. Drives the toolbar buttons' highlighted state.
struct FormatState: Equatable {
    var bold = false, italic = false, strike = false, code = false, link = false
    var heading = 0
    var bullet = false, numbered = false, checkbox = false, quote = false
}

/// Line-level markdown: parsing a line into its block parts, and toggling those parts.
/// Pure string logic so it can be tested without a text view.
enum MarkdownBlocks {
    enum Kind: Equatable { case none, heading(Int), bullet, checkbox, numbered(Int) }
    enum Target: Equatable { case heading(Int), bullet, checkbox, numbered, quote }

    struct Parsed: Equatable {
        var quoted = false
        var indent = ""
        var kind: Kind = .none
        var checked = false
        var body = ""
    }

    private static let quoteRx = try! NSRegularExpression(pattern: #"^ {0,3}>[ ]?"#)
    private static let headingRx = try! NSRegularExpression(pattern: #"^(#{1,6})[ \t]+(.*)$"#)
    private static let checkboxRx = try! NSRegularExpression(pattern: #"^([ \t]*)[-*+][ \t]+\[([ xX])\](?:[ \t]+(.*))?$"#)
    private static let bulletRx = try! NSRegularExpression(pattern: #"^([ \t]*)[-*+](?:[ \t]+(.*))?$"#)
    private static let numberedRx = try! NSRegularExpression(pattern: #"^([ \t]*)(\d{1,9})[.)](?:[ \t]+(.*))?$"#)

    private static func group(_ m: NSTextCheckingResult, _ i: Int, in s: NSString) -> String? {
        m.range(at: i).location == NSNotFound ? nil : s.substring(with: m.range(at: i))
    }

    static func parse(_ line: String) -> Parsed {
        var p = Parsed()
        var rest = line as NSString
        if let m = quoteRx.firstMatch(in: line, range: NSRange(location: 0, length: rest.length)) {
            p.quoted = true
            rest = rest.substring(from: m.range.length) as NSString
        }
        let s = rest as String
        let full = NSRange(location: 0, length: rest.length)
        if let m = headingRx.firstMatch(in: s, range: full) {
            p.kind = .heading(m.range(at: 1).length)
            p.body = group(m, 2, in: rest) ?? ""
        } else if let m = checkboxRx.firstMatch(in: s, range: full) {
            p.kind = .checkbox
            p.indent = group(m, 1, in: rest) ?? ""
            p.checked = (group(m, 2, in: rest) ?? " ") != " "
            p.body = group(m, 3, in: rest) ?? ""
        } else if let m = numberedRx.firstMatch(in: s, range: full) {
            p.kind = .numbered(Int(group(m, 2, in: rest) ?? "1") ?? 1)
            p.indent = group(m, 1, in: rest) ?? ""
            p.body = group(m, 3, in: rest) ?? ""
        } else if let m = bulletRx.firstMatch(in: s, range: full), !s.hasPrefix("---"), !s.hasPrefix("***") {
            p.kind = .bullet
            p.indent = group(m, 1, in: rest) ?? ""
            p.body = group(m, 2, in: rest) ?? ""
        } else {
            let ws = s.prefix { $0 == " " || $0 == "\t" }
            p.indent = String(ws)
            p.body = String(s.dropFirst(ws.count))
        }
        return p
    }

    static func render(_ p: Parsed, number: Int = 1) -> String {
        let q = p.quoted ? "> " : ""
        switch p.kind {
        case .heading(let n): return q + String(repeating: "#", count: n) + " " + p.body
        case .bullet: return q + p.indent + "- " + p.body
        case .checkbox: return q + p.indent + "- [" + (p.checked ? "x" : " ") + "] " + p.body
        case .numbered: return q + p.indent + "\(number). " + p.body
        case .none: return q + p.indent + p.body
        }
    }

    /// Applies `target` to every line, or removes it if every line already has it.
    /// Blank lines in a multi-line selection are left alone; a lone blank line is formatted
    /// so that "click the bullet button on an empty line" starts a list.
    static func apply(_ target: Target, to lines: [String]) -> [String] {
        let parsed = lines.map(parse)
        let active: [Int] = lines.count == 1 ? [0] : lines.indices.filter { !lines[$0].trimmingCharacters(in: .whitespaces).isEmpty }
        guard !active.isEmpty else { return lines }

        func has(_ p: Parsed) -> Bool {
            switch (target, p.kind) {
            case (.heading(let a), .heading(let b)): return a == b
            case (.bullet, .bullet), (.checkbox, .checkbox): return true
            case (.numbered, .numbered): return true
            case (.quote, _): return p.quoted
            default: return false
            }
        }
        let removing = active.allSatisfy { has(parsed[$0]) }

        var out = lines
        var n = 0
        for i in active {
            var p = parsed[i]
            switch target {
            case .quote:
                p.quoted = !removing
            case .heading(let level):
                p.kind = removing ? .none : .heading(level)
                if !removing { p.indent = "" } // headings cannot be indented in markdown
            case .bullet:
                p.kind = removing ? .none : .bullet
            case .checkbox:
                p.kind = removing ? .none : .checkbox
            case .numbered:
                p.kind = removing ? .none : .numbered(1)
            }
            n += 1
            out[i] = render(p, number: n)
        }
        return out
    }
}

/// Inline and block state at a caret or selection.
enum MarkdownFormatDetector {
    private static let code = try! NSRegularExpression(pattern: #"`[^`\n]+`"#)
    private static let bold = try! NSRegularExpression(pattern: #"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let italic = try! NSRegularExpression(pattern: #"(?<![\w*_])(\*|_)(?=[^\s*_])(.+?)(?<=[^\s*_])\1(?![\w*_])"#)
    private static let strike = try! NSRegularExpression(pattern: #"~~(?=\S)(.+?)(?<=\S)~~"#)
    private static let link = try! NSRegularExpression(pattern: #"\[[^\]\n]*\]\([^)\n]*\)"#)

    static func state(in text: NSString, selection: NSRange) -> FormatState {
        guard text.length > 0 else { return FormatState() }
        let caret = min(selection.location, text.length)
        let para = text.paragraphRange(for: NSRange(location: caret, length: 0))
        var line = text.substring(with: para)
        while line.hasSuffix("\n") || line.hasSuffix("\r") { line.removeLast() }
        var s = FormatState()

        // Inside a fenced block everything is literal code.
        var fences = 0
        text.substring(to: para.location).enumerateLines { l, _ in
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") || t.hasPrefix("~~~") { fences += 1 }
        }
        let t = line.trimmingCharacters(in: .whitespaces)
        if fences % 2 == 1 || t.hasPrefix("```") || t.hasPrefix("~~~") { s.code = true; return s }

        let parsed = MarkdownBlocks.parse(line)
        s.quote = parsed.quoted
        switch parsed.kind {
        case .heading(let n): s.heading = n
        case .bullet: s.bullet = true
        case .checkbox: s.checkbox = true
        case .numbered: s.numbered = true
        case .none: break
        }

        // Mask code spans with spaces (same length, offsets stay valid) so their contents
        // are not read as emphasis.
        var masked = line as NSString
        let full = NSRange(location: 0, length: masked.length)
        var selStart = caret - para.location
        var selEnd = min(NSMaxRange(selection), NSMaxRange(para)) - para.location
        selStart = max(0, min(selStart, masked.length)); selEnd = max(selStart, min(selEnd, masked.length))

        func inside(_ rx: NSRegularExpression, in str: NSString, marker: Int) -> Bool {
            rx.matches(in: str as String, range: NSRange(location: 0, length: str.length)).contains { m in
                let r = m.range
                if selStart == r.location && selEnd == r.upperBound { return true } // whole span selected
                return selStart >= r.location + marker && selEnd <= r.upperBound - marker
            }
        }
        s.code = inside(code, in: masked, marker: 1)
        for m in code.matches(in: line, range: full).reversed() {
            masked = masked.replacingCharacters(in: m.range, with: String(repeating: " ", count: m.range.length)) as NSString
        }
        s.bold = inside(bold, in: masked, marker: 2)
        s.italic = inside(italic, in: masked, marker: 1)
        s.strike = inside(strike, in: masked, marker: 2)
        s.link = inside(link, in: masked, marker: 0)
        return s
    }
}
