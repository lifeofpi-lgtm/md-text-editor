import Foundation

var failures = 0, checks = 0
func check(_ cond: @autoclosure () -> Bool, _ msg: String, line: Int = #line) {
    checks += 1
    if !cond() { failures += 1; print("FAIL (line \(line)): \(msg)") }
}
typealias B = MarkdownBlocks

// MARK: parse / render round trips
check(B.parse("# Title").kind == .heading(1) && B.parse("# Title").body == "Title", "h1")
check(B.parse("### Deep").kind == .heading(3), "h3")
check(B.parse("####### seven").kind == .none, "7 hashes is not a heading")
check(B.parse("#hashtag").kind == .none, "no space is not a heading")
check(B.parse("- item").kind == .bullet && B.parse("* item").kind == .bullet && B.parse("+ item").kind == .bullet, "bullet markers")
check(B.parse("  - nested").indent == "  " && B.parse("  - nested").body == "nested", "nested bullet keeps indent")
check(B.parse("- [ ] todo").kind == .checkbox && !B.parse("- [ ] todo").checked, "open checkbox")
check(B.parse("- [x] done").checked, "checked checkbox")
check(B.parse("3. third").kind == .numbered(3), "numbered")
check(B.parse("---").kind == .none && B.parse("***").kind == .none, "rules are not bullets")
check(B.parse("> quoted").quoted && B.parse("> quoted").body == "quoted", "quote")
check(B.parse("> - list in quote").quoted && B.parse("> - list in quote").kind == .bullet, "list inside quote")
check(B.parse("plain text").kind == .none && !B.parse("plain text").quoted, "plain")
for l in ["# T", "- a", "  - a", "- [x] d", "- [ ] d", "> q", "> - a", "1. a", "plain", "  indented"] {
    check(B.render(B.parse(l), number: 1) == l, "round trip '\(l)' got '\(B.render(B.parse(l), number: 1))'")
}

// MARK: toggling block formats
check(B.apply(.heading(2), to: ["Hello"]) == ["## Hello"], "add h2")
check(B.apply(.heading(2), to: ["## Hello"]) == ["Hello"], "toggle h2 off")
check(B.apply(.heading(1), to: ["## Hello"]) == ["# Hello"], "switch h2 to h1")
check(B.apply(.heading(3), to: ["- item"]) == ["### item"], "heading replaces bullet")
check(B.apply(.heading(1), to: ["  indented"]) == ["# indented"], "heading drops indent")
check(B.apply(.bullet, to: ["one", "two"]) == ["- one", "- two"], "bullets on two lines")
check(B.apply(.bullet, to: ["- one", "- two"]) == ["one", "two"], "bullets off when all are bullets")
check(B.apply(.bullet, to: ["- one", "two"]) == ["- one", "- two"], "mixed becomes all bullets")
check(B.apply(.bullet, to: ["1. a", "2. b"]) == ["- a", "- b"], "numbered to bullets")
check(B.apply(.numbered, to: ["a", "b", "c"]) == ["1. a", "2. b", "3. c"], "numbering")
check(B.apply(.numbered, to: ["1. a", "2. b"]) == ["a", "b"], "numbering off")
check(B.apply(.numbered, to: ["a", "", "c"]) == ["1. a", "", "2. c"], "numbering skips blank lines and stays sequential")
check(B.apply(.numbered, to: ["- a", "- b"]) == ["1. a", "2. b"], "bullets to numbered")
check(B.apply(.checkbox, to: ["a"]) == ["- [ ] a"], "checkbox on")
check(B.apply(.checkbox, to: ["- [ ] a"]) == ["a"], "checkbox off")
check(B.apply(.checkbox, to: ["- a"]) == ["- [ ] a"], "bullet to checkbox")
check(B.apply(.checkbox, to: ["- [x] a"]) == ["a"], "checked checkbox off")
check(B.apply(.quote, to: ["a", "b"]) == ["> a", "> b"], "quote on")
check(B.apply(.quote, to: ["> a", "> b"]) == ["a", "b"], "quote off")
check(B.apply(.quote, to: ["- a"]) == ["> - a"], "quote keeps the list inside")
check(B.apply(.bullet, to: ["> a"]) == ["> - a"], "bullet keeps the quote")
check(B.apply(.bullet, to: [""]) == ["- "], "lone blank line starts a list")
check(B.apply(.bullet, to: ["", ""]) == ["", ""], "all blank multi-line is a no-op")
check(B.apply(.bullet, to: ["  a", "  b"]) == ["  - a", "  - b"], "indent preserved on list")

// MARK: state detection
func st(_ text: String, at marker: String = "|") -> FormatState {
    // The "|" marks the caret; "|" twice would mark a selection start and end.
    let parts = text.components(separatedBy: marker)
    let clean = parts.joined()
    let loc = (parts[0] as NSString).length
    let len = parts.count == 3 ? (parts[1] as NSString).length : 0
    return MarkdownFormatDetector.state(in: clean as NSString, selection: NSRange(location: loc, length: len))
}
check(st("Hello **bo|ld** word").bold, "caret inside bold")
check(!st("Hel|lo **bold** word").bold, "caret outside bold")
check(!st("Hello |**bold** word").bold, "caret before the opening markers is not bold")
check(st("Hello **|bold|** word").bold, "selection of bold content")
check(st("Hello |**bold**| word").bold, "selection covering whole bold span")
check(st("an _it|alic_ one").italic && !st("an _it|alic_ one").bold, "italic only")
check(st("snake_ca|se_name here").italic == false, "intraword underscores are not italic")
check(st("two ~~str|uck~~ out").strike, "strike")
check(st("use `co|de` here").code, "inline code")
check(!st("use `**no|t bold**` here").bold, "emphasis inside code is ignored")
check(st("a [li|nk](http://x.com) b").link, "link")
check(st("# Hea|ding").heading == 1, "heading level 1")
check(st("### Hea|ding").heading == 3, "heading level 3")
check(st("- it|em").bullet && !st("- it|em").checkbox, "bullet state")
check(st("- [ ] it|em").checkbox && !st("- [ ] it|em").bullet, "checkbox state")
check(st("4. it|em").numbered, "numbered state")
check(st("> qu|ote").quote, "quote state")
check(st("> - a **b|old** in a quoted list").quote && st("> - a **b|old** in a quoted list").bullet && st("> - a **b|old** in a quoted list").bold, "combined states")
check(st("```\nlet **x|** = 1\n```").code && !st("```\nlet **x|** = 1\n```").bold, "inside fenced block is code only")
check(st("```\ncode\n```\nouts|ide **bold**") == FormatState(), "after a closed fence is normal")
check(MarkdownFormatDetector.state(in: "" as NSString, selection: NSRange(location: 0, length: 0)) == FormatState(), "empty doc")
check(st("line one\nline **tw|o** here").bold, "state comes from the caret's own line")
check(!st("**bold** on line one\nplain li|ne two").bold, "other lines do not leak")

print(failures == 0 ? "ALL \(checks) CHECKS PASSED" : "\(failures) of \(checks) CHECKS FAILED")
exit(failures == 0 ? 0 : 1)
