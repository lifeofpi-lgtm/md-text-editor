import Foundation
import AppKit

enum SheetKind: String {
    case markdown, text, rtf

    init?(url: URL) {
        switch url.pathExtension.lowercased() {
        case "md", "markdown": self = .markdown
        case "txt": self = .text
        case "rtf": self = .rtf
        default: return nil
        }
    }

    var fileExtension: String {
        switch self { case .markdown: "md"; case .text: "txt"; case .rtf: "rtf" }
    }
}

/// What the sheet list shows for one file.
struct SheetMeta: Equatable {
    var title: String
    var excerpt: String
    var words: Int
}

enum SheetMetaExtractor {
    static func countWords(_ text: String) -> Int {
        var n = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in n += 1 }
        return n
    }

    /// Plain text of a file for indexing. RTF is unwrapped to its string.
    static func plainText(of url: URL, kind: SheetKind) -> String? {
        switch kind {
        case .rtf:
            guard let data = try? Data(contentsOf: url) else { return nil }
            return NSAttributedString(rtf: data, documentAttributes: nil)?.string
        case .markdown, .text:
            return try? String(contentsOf: url, encoding: .utf8)
        }
    }

    static func meta(text: String, kind: SheetKind, fallbackTitle: String) -> SheetMeta {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var index = 0
        // YAML front matter is metadata, not prose: keep it out of titles and excerpts.
        if lines.first.map({ trimmed($0) == "---" }) == true,
           let close = lines.dropFirst().prefix(40).firstIndex(where: { trimmed($0) == "---" }) {
            index = close + 1
        }

        var title: String?
        var excerpt = ""
        var inFence = false
        var scanned = 0
        while index < lines.count, scanned < 400 {
            let t = trimmed(lines[index])
            index += 1
            if t.hasPrefix("```") || t.hasPrefix("~~~") { inFence.toggle(); continue }
            if inFence || t.isEmpty { continue }
            scanned += 1
            if title == nil, kind != .rtf, let h = headingText(t) {
                if !h.isEmpty { title = h; continue }
            }
            if excerpt.count < 220 {
                let s = stripLine(t)
                if !s.isEmpty { excerpt += (excerpt.isEmpty ? "" : " ") + s }
            }
            if title != nil, excerpt.count >= 220 { break }
        }
        // One very long line can overshoot the loop's length check; the row shows 2 lines anyway.
        return SheetMeta(title: title ?? fallbackTitle, excerpt: String(excerpt.prefix(240)), words: countWords(text))
    }

    // MARK: Markdown stripping

    private static func trimmed(_ s: Substring) -> String { s.trimmingCharacters(in: .whitespaces) }

    private static let headingRx = try! NSRegularExpression(pattern: #"^#{1,6}\s+(.+?)\s*#*\s*$"#)
    private static let listRx = try! NSRegularExpression(pattern: #"^(?:[-*+]|\d{1,9}[.)])\s+(?:\[[ xX]\]\s+)?"#)
    private static let image = try! NSRegularExpression(pattern: #"!\[([^\]]*)\]\([^)]*\)"#)
    private static let link = try! NSRegularExpression(pattern: #"\[([^\]]*)\]\([^)]*\)"#)
    private static let code = try! NSRegularExpression(pattern: #"`([^`]*)`"#)
    private static let bold = try! NSRegularExpression(pattern: #"(\*\*|__)(.+?)\1"#)
    private static let italic = try! NSRegularExpression(pattern: #"(?<![\w*])(\*|_)(?!\s)(.+?)(?<!\s)\1(?![\w*])"#)
    private static let strike = try! NSRegularExpression(pattern: #"~~(.+?)~~"#)

    private static func headingText(_ line: String) -> String? {
        let ns = line as NSString
        guard let m = headingRx.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return stripInline(ns.substring(with: m.range(at: 1)))
    }

    private static func replace(_ rx: NSRegularExpression, in s: String, with template: String) -> String {
        rx.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: template)
    }

    static func stripInline(_ s: String) -> String {
        var r = s
        r = replace(image, in: r, with: "$1")
        r = replace(link, in: r, with: "$1")
        r = replace(code, in: r, with: "$1")
        r = replace(bold, in: r, with: "$2")
        r = replace(italic, in: r, with: "$2")
        r = replace(strike, in: r, with: "$1")
        return r.trimmingCharacters(in: .whitespaces)
    }

    static func stripLine(_ line: String) -> String {
        var t = line
        if t.hasPrefix("|") || t.hasPrefix("<!--") { return "" }
        // Horizontal rules and setext underlines carry no text.
        if t.count >= 3, Set(t.filter { !$0.isWhitespace }).count == 1, let c = t.first, "-*_=".contains(c) { return "" }
        while t.hasPrefix(">") { t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces) }
        if let h = headingText(t) { return h }
        t = replace(listRx, in: t, with: "")
        return stripInline(t)
    }
}
