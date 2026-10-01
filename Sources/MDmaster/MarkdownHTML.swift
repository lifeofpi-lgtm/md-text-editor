import Foundation

/// Small GFM-flavoured markdown to HTML converter covering exactly what the editor
/// styles: headings, paragraphs, emphasis, code, links, images, lists with
/// checkboxes, blockquotes, tables and rules. No third-party dependency.
enum MarkdownHTML {
    static func document(_ markdown: String, title: String) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(escape(title))</title>
        <style>\(css)</style>
        </head>
        <body><main>
        \(body(markdown))
        </main></body>
        </html>
        """
    }

    static let css = """
    :root{color-scheme:light dark;--paper:#FBF9F4;--ink:#23211D;--muted:#857F74;--accent:#B4573E;--codebg:#F1EDE4;--rule:#E3DED2}
    @media (prefers-color-scheme:dark){:root{--paper:#1B1A18;--ink:#E7E3DA;--muted:#8F897D;--accent:#E28B71;--codebg:#25241F;--rule:#33312C}}
    *{box-sizing:border-box}
    body{margin:0;background:var(--paper);color:var(--ink);font:17px/1.6 -apple-system,BlinkMacSystemFont,"SF Pro Text","Helvetica Neue",Helvetica,Arial,sans-serif;-webkit-font-smoothing:antialiased}
    main{max-width:42rem;margin:0 auto;padding:4rem 1.5rem 6rem}
    h1,h2,h3,h4,h5,h6{font-weight:700;line-height:1.2;letter-spacing:-0.015em}
    h1{font-size:2.05rem;margin:0 0 1.2rem}
    h2{font-size:1.5rem;margin:2.4rem 0 .7rem}
    h3{font-size:1.2rem;font-weight:600;margin:1.9rem 0 .5rem}
    h4,h5,h6{font-size:1rem;font-weight:600;margin:1.5rem 0 .4rem}
    p{margin:0 0 1.05em}
    a{color:var(--accent);text-decoration:none;border-bottom:1px solid rgba(180,87,62,.35)}
    code{font-family:ui-monospace,"SF Mono",Menlo,monospace;font-size:.88em;background:var(--codebg);padding:.12em .38em;border-radius:4px}
    pre{background:var(--codebg);padding:1rem 1.15rem;border-radius:8px;overflow-x:auto;margin:0 0 1.25em;line-height:1.5}
    pre code{background:none;padding:0;font-size:.85em}
    blockquote{margin:0 0 1.05em;padding:.05em 0 .05em 1.1em;border-left:2px solid var(--accent);color:var(--muted);font-style:italic}
    blockquote p:last-child{margin-bottom:0}
    ul,ol{padding-left:1.45em;margin:0 0 1.05em}
    li{margin:.22em 0}
    li.task{list-style:none;margin-left:-1.45em}
    li.task input{margin:0 .55em 0 0;accent-color:var(--accent);vertical-align:-1px}
    hr{border:0;border-top:1px solid var(--rule);margin:2.6rem 0}
    table{border-collapse:collapse;margin:0 0 1.25em;font-size:.95em;width:100%}
    th,td{text-align:left;padding:.5em .7em;border-bottom:1px solid var(--rule);vertical-align:top}
    th{font-weight:600;border-bottom:1.5px solid var(--ink)}
    img{max-width:100%;height:auto;border-radius:4px}
    del{color:var(--muted)}
    @media print{:root{--paper:#fff}body{font-size:11.5pt}main{max-width:none;padding:0}a{border:0;color:inherit}pre{white-space:pre-wrap}h1,h2,h3{page-break-after:avoid}pre,blockquote,table{page-break-inside:avoid}}
    """

    // MARK: Block level

    private static func rx(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }
    private static let fenceRx    = rx(#"^[ \t]{0,3}(```|~~~)[ \t]*([\w+#.-]*)"#)
    private static let headingRx  = rx(#"^(#{1,6})[ \t]+(.*?)[ \t]*#*[ \t]*$"#)
    private static let hrRx       = rx(#"^[ \t]{0,3}([-*_])([ \t]*\1){2,}[ \t]*$"#)
    private static let quoteRx    = rx(#"^[ \t]{0,3}>[ ]?(.*)$"#)
    private static let listRx     = rx(#"^( *)([-*+]|\d{1,9}[.)])[ \t]+(.*)$"#)
    private static let taskRx     = rx(#"^\[([ xX])\][ \t]+(.*)$"#)
    private static let tableSepRx = rx(#"^[ \t]*\|?[ \t]*:?-+:?[ \t]*(\|[ \t]*:?-+:?[ \t]*)*\|?[ \t]*$"#)

    private static func first(_ r: NSRegularExpression, _ s: String) -> NSTextCheckingResult? {
        r.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length))
    }
    private static func group(_ m: NSTextCheckingResult, _ i: Int, _ s: String) -> String {
        let r = m.range(at: i)
        return r.location == NSNotFound ? "" : (s as NSString).substring(with: r)
    }
    private static func isBlockStart(_ line: String) -> Bool {
        first(headingRx, line) != nil || first(fenceRx, line) != nil || first(hrRx, line) != nil
            || first(quoteRx, line) != nil || first(listRx, line) != nil
    }

    static func body(_ markdown: String) -> String {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\t", with: "    ")
            .components(separatedBy: "\n")
        var out: [String] = []
        var i = 0
        func blank(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespaces).isEmpty }

        while i < lines.count {
            let line = lines[i]
            if blank(line) { i += 1; continue }

            if let m = first(fenceRx, line) {
                let lang = group(m, 2, line)
                var code: [String] = []
                i += 1
                while i < lines.count, first(fenceRx, lines[i]) == nil { code.append(lines[i]); i += 1 }
                i += 1
                let cls = lang.isEmpty ? "" : " class=\"language-\(escape(lang))\""
                out.append("<pre><code\(cls)>\(escape(code.joined(separator: "\n")))</code></pre>")
                continue
            }
            if let m = first(headingRx, line) {
                let level = m.range(at: 1).length
                out.append("<h\(level)>\(inline(group(m, 2, line)))</h\(level)>")
                i += 1; continue
            }
            if first(hrRx, line) != nil { out.append("<hr>"); i += 1; continue }

            if first(quoteRx, line) != nil {
                var inner: [String] = []
                while i < lines.count, let m = first(quoteRx, lines[i]) { inner.append(group(m, 1, lines[i])); i += 1 }
                out.append("<blockquote>\(body(inner.joined(separator: "\n")))</blockquote>")
                continue
            }
            if line.contains("|"), i + 1 < lines.count, first(tableSepRx, lines[i + 1]) != nil, lines[i + 1].contains("-") {
                let header = cells(line)
                let aligns = cells(lines[i + 1]).map { c -> String in
                    let l = c.hasPrefix(":"), r = c.hasSuffix(":")
                    return l && r ? "center" : r ? "right" : "left"
                }
                i += 2
                var rows: [[String]] = []
                while i < lines.count, !blank(lines[i]), lines[i].contains("|") { rows.append(cells(lines[i])); i += 1 }
                var t = "<table><thead><tr>"
                for (k, h) in header.enumerated() { t += "<th style=\"text-align:\(aligns[safe: k] ?? "left")\">\(inline(h))</th>" }
                t += "</tr></thead><tbody>"
                for row in rows {
                    t += "<tr>"
                    for k in 0..<header.count { t += "<td style=\"text-align:\(aligns[safe: k] ?? "left")\">\(inline(row[safe: k] ?? ""))</td>" }
                    t += "</tr>"
                }
                out.append(t + "</tbody></table>")
                continue
            }
            if first(listRx, line) != nil {
                var items: [(indent: Int, ordered: Bool, text: String)] = []
                while i < lines.count, !blank(lines[i]) {
                    if let m = first(listRx, lines[i]) {
                        let marker = group(m, 2, lines[i])
                        items.append((m.range(at: 1).length, marker.first!.isNumber, group(m, 3, lines[i])))
                    } else if lines[i].hasPrefix(" "), !items.isEmpty {
                        items[items.count - 1].text += " " + lines[i].trimmingCharacters(in: .whitespaces)
                    } else { break }
                    i += 1
                }
                out.append(renderList(items))
                continue
            }

            var para: [String] = []
            while i < lines.count, !blank(lines[i]), (para.isEmpty || !isBlockStart(lines[i])) {
                para.append(lines[i]); i += 1
            }
            let joined = para.map { $0.hasSuffix("  ") ? inline(String($0.dropLast(2))) + "<br>" : inline($0) }
                .joined(separator: "\n")
            out.append("<p>\(joined)</p>")
        }
        return out.joined(separator: "\n")
    }

    private static func renderList(_ items: [(indent: Int, ordered: Bool, text: String)]) -> String {
        var out = ""
        var stack: [(indent: Int, ordered: Bool)] = []
        func close(_ ordered: Bool) -> String { ordered ? "</ol>" : "</ul>" }
        for item in items {
            if stack.isEmpty || item.indent > stack.last!.indent {
                out += item.ordered ? "<ol>" : "<ul>"
                stack.append((item.indent, item.ordered))
            } else {
                while stack.count > 1, item.indent < stack.last!.indent {
                    out += "</li>" + close(stack.removeLast().ordered)
                }
                out += "</li>"
            }
            if let m = first(taskRx, item.text) {
                let checked = group(m, 1, item.text).lowercased() == "x" ? " checked" : ""
                out += "<li class=\"task\"><input type=\"checkbox\" disabled\(checked)>\(inline(group(m, 2, item.text)))"
            } else {
                out += "<li>\(inline(item.text))"
            }
        }
        while let last = stack.popLast() { out += "</li>" + close(last.ordered) }
        return out
    }

    private static func cells(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        return s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: Inline

    private static let codeSpanRx = rx(#"(`+)([^`]+?)\1"#)
    private static let imageRx    = rx(#"!\[([^\]]*)\]\(([^)\s]+)\)"#)
    private static let linkRx     = rx(#"\[([^\]]+)\]\(([^)\s]+)\)"#)
    private static let autoRx     = rx(#"(?<![\"'>=\w])(https?://[^\s<>()\[\]]+[^\s<>()\[\].,;:!?'\"])"#)
    private static let boldRx     = rx(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let italicRx   = rx(#"(?<![\w*])(\*|_)(?=[^\s*_])(.+?)(?<=[^\s*_])\1(?![\w*])"#)
    private static let strikeRx   = rx(#"~~(?=\S)(.+?)(?<=\S)~~"#)

    static func inline(_ raw: String) -> String {
        var t = escape(raw)
        var codes: [String] = []
        t = replace(codeSpanRx, in: t) { m, s in
            codes.append("<code>\(s.substring(with: m.range(at: 2)))</code>")
            return "\u{1}\(codes.count - 1)\u{1}"
        }
        t = replace(imageRx, in: t) { m, s in
            "<img alt=\"\(s.substring(with: m.range(at: 1)))\" src=\"\(s.substring(with: m.range(at: 2)))\">"
        }
        t = replace(linkRx, in: t) { m, s in
            "<a href=\"\(s.substring(with: m.range(at: 2)))\">\(s.substring(with: m.range(at: 1)))</a>"
        }
        t = replace(autoRx, in: t) { m, s in
            let u = s.substring(with: m.range(at: 1)); return "<a href=\"\(u)\">\(u)</a>"
        }
        t = replace(boldRx, in: t) { m, s in "<strong>\(s.substring(with: m.range(at: 2)))</strong>" }
        t = replace(italicRx, in: t) { m, s in "<em>\(s.substring(with: m.range(at: 2)))</em>" }
        t = replace(strikeRx, in: t) { m, s in "<del>\(s.substring(with: m.range(at: 1)))</del>" }
        for (k, c) in codes.enumerated() { t = t.replacingOccurrences(of: "\u{1}\(k)\u{1}", with: c) }
        return t
    }

    private static func replace(_ r: NSRegularExpression, in s: String,
                                _ f: (NSTextCheckingResult, NSString) -> String) -> String {
        let ns = s as NSString
        let matches = r.matches(in: s, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return s }
        let result = NSMutableString(string: s)
        for m in matches.reversed() { result.replaceCharacters(in: m.range, with: f(m, ns)) }
        return result as String
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
