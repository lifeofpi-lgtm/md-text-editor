import Foundation
import AppKit

var failures = 0
var checks = 0
func check(_ cond: @autoclosure () -> Bool, _ msg: String, file: String = #file, line: Int = #line) {
    checks += 1
    if !cond() { failures += 1; print("FAIL (line \(line)): \(msg)") }
}

let fm = FileManager.default
let tmp = fm.temporaryDirectory.appendingPathComponent("mdm-harness-\(UUID().uuidString)")
try! fm.createDirectory(at: tmp, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: tmp) }

// MARK: title and excerpt extraction
do {
    let m = SheetMetaExtractor.meta(text: "# My **Big** Plan\n\nSome *styled* text with a [link](http://x.com) and `code`.\n\n- [ ] todo item\n> quoted words\n", kind: .markdown, fallbackTitle: "file")
    check(m.title == "My Big Plan", "heading title stripped, got '\(m.title)'")
    check(m.excerpt == "Some styled text with a link and code. todo item quoted words", "excerpt stripped, got '\(m.excerpt)'")
    check(m.words > 10, "word count \(m.words)")

    let n = SheetMetaExtractor.meta(text: "Just prose with no heading.\nSecond line.", kind: .markdown, fallbackTitle: "notes")
    check(n.title == "notes", "falls back to filename, got '\(n.title)'")
    check(n.excerpt == "Just prose with no heading. Second line.", "plain excerpt '\(n.excerpt)'")

    let fm1 = SheetMetaExtractor.meta(text: "---\ntitle: hidden\ntags: a\n---\n# Real Title\nBody", kind: .markdown, fallbackTitle: "f")
    check(fm1.title == "Real Title", "front matter skipped, got '\(fm1.title)'")
    check(fm1.excerpt == "Body", "front matter not in excerpt '\(fm1.excerpt)'")

    let code = SheetMetaExtractor.meta(text: "# T\n```swift\nlet x = 1\n```\nAfter code", kind: .markdown, fallbackTitle: "f")
    check(code.excerpt == "After code", "fenced code skipped, got '\(code.excerpt)'")

    let snake = SheetMetaExtractor.meta(text: "# T\nuse snake_case_names and 2*3*4 here", kind: .markdown, fallbackTitle: "f")
    check(snake.excerpt == "use snake_case_names and 2*3*4 here", "intraword markers kept, got '\(snake.excerpt)'")

    let tbl = SheetMetaExtractor.meta(text: "# T\n| a | b |\n|---|---|\n---\nReal text", kind: .markdown, fallbackTitle: "f")
    check(tbl.excerpt == "Real text", "tables and rules skipped, got '\(tbl.excerpt)'")

    let empty = SheetMetaExtractor.meta(text: "", kind: .markdown, fallbackTitle: "Untitled")
    check(empty.title == "Untitled" && empty.excerpt == "" && empty.words == 0, "empty file")

    let long = "# H\n" + String(repeating: "word ", count: 400)
    let lm = SheetMetaExtractor.meta(text: long, kind: .markdown, fallbackTitle: "f")
    check(lm.excerpt.count < 260 && lm.words == 401, "excerpt bounded (\(lm.excerpt.count)), words \(lm.words)")
}

// MARK: scanner
let scanner = SheetScanner()
do {
    let lib = tmp.appendingPathComponent("Library")
    for d in ["Work/Clients", "Personal", ".hidden", "Work/Clients/Acme", "Thing.app"] {
        try! fm.createDirectory(at: lib.appendingPathComponent(d), withIntermediateDirectories: true)
    }
    func put(_ rel: String, _ s: String, age: TimeInterval = 0) {
        let u = lib.appendingPathComponent(rel)
        try! s.write(to: u, atomically: true, encoding: .utf8)
        try! fm.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: u.path)
    }
    put("Work/alpha.md", "# Alpha\nfirst note about pricing", age: 300)
    put("Work/beta.markdown", "Beta body mentions Pricing too", age: 100)
    put("Work/gamma.txt", "plain text gamma", age: 200)
    put("Work/ignore.png", "not a sheet")
    put("Work/.dotfile.md", "hidden")
    let rtf = NSAttributedString(string: "Rich words here")
    try! rtf.data(from: NSRange(location: 0, length: rtf.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]).write(to: lib.appendingPathComponent("Work/delta.rtf"))

    let tree = scanner.tree(root: lib)
    check(tree.children.map(\.name) == ["Personal", "Work"], "tree hides dot folders and packages: \(tree.children.map(\.name))")
    let work = tree.children[1]
    check(work.children.map(\.name) == ["Clients"] && work.children[0].children.map(\.name) == ["Acme"], "nested tree")

    let sheets = scanner.sheets(in: lib.appendingPathComponent("Work"))
    check(Set(sheets.map(\.name)) == ["alpha", "beta", "gamma", "delta"], "supported kinds only: \(sheets.map(\.name))")
    let byKind = Dictionary(uniqueKeysWithValues: sheets.map { ($0.name, $0.kind) })
    check(byKind["delta"] == .rtf && byKind["gamma"] == .text && byKind["beta"] == .markdown, "kinds")
    check(sheets.first { $0.name == "alpha" }?.title == "Alpha", "title from heading")
    check(sheets.first { $0.name == "beta" }?.title == "beta", "title falls back to filename")
    check(sheets.first { $0.name == "delta" }?.excerpt == "Rich words here", "rtf excerpt")

    let byDate = SheetScanner.sort(sheets, by: .modified).map(\.name)
    check(byDate.first == "delta", "modified sort newest first (delta just written): \(byDate)")
    check(SheetScanner.sort(sheets, by: .name).map(\.name) == ["alpha", "beta", "delta", "gamma"], "name sort")

    check(Set(SheetScanner.filter(sheets, query: "pricing").map(\.name)) == ["alpha", "beta"], "content search")
    check(SheetScanner.filter(sheets, query: "gamma").map(\.name) == ["gamma"], "name search")
    check(SheetScanner.filter(sheets, query: "pricing note").map(\.name) == ["alpha"], "all terms must match")
    check(SheetScanner.filter(sheets, query: "  ").count == 4, "blank query returns all")

    // Cache: unchanged file is reused, changed file is re-read.
    let again = scanner.sheets(in: lib.appendingPathComponent("Work"))
    check(again.first { $0.name == "alpha" } == sheets.first { $0.name == "alpha" }, "cache hit identical")
    put("Work/alpha.md", "# Alpha Renamed\nchanged body longer", age: 0)
    let changed = scanner.sheets(in: lib.appendingPathComponent("Work"))
    check(changed.first { $0.name == "alpha" }?.title == "Alpha Renamed", "cache invalidated on change")
    try! fm.removeItem(at: lib.appendingPathComponent("Work/gamma.txt"))
    check(scanner.sheets(in: lib.appendingPathComponent("Work")).count == 3, "deleted file disappears")
}

// MARK: file ops
do {
    let dir = tmp.appendingPathComponent("ops")
    try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let a = try! FileOps.createSheet(in: dir, kind: .markdown)
    let b = try! FileOps.createSheet(in: dir, kind: .markdown)
    check(a.lastPathComponent == "Untitled.md" && b.lastPathComponent == "Untitled 2.md", "unique names: \(a.lastPathComponent), \(b.lastPathComponent)")
    let r = try! FileOps.createSheet(in: dir, kind: .rtf)
    check(NSAttributedString(rtf: try! Data(contentsOf: r), documentAttributes: nil) != nil, "new rtf is valid rtf")
    let f = try! FileOps.createFolder(in: dir)
    let f2 = try! FileOps.createFolder(in: dir)
    check(f.lastPathComponent == "New Folder" && f2.lastPathComponent == "New Folder 2", "folder names")
    check(f.hasDirectoryPath, "createFolder returns a trailing-slash URL so it equals tree URLs")

    let renamed = try! FileOps.rename(a, to: "Chapter One")
    check(renamed.lastPathComponent == "Chapter One.md" && fm.fileExists(atPath: renamed.path) && !fm.fileExists(atPath: a.path), "rename keeps extension")
    let rf = try! FileOps.rename(f, to: "Drafts")
    check(rf.lastPathComponent == "Drafts", "folder rename")
    // Same trailing-slash form as the scanner's URLs (compared after resolving the /var symlink).
    let scanned = scanner.tree(root: dir).children.first { $0.name == "Drafts" }?.url
    check(rf.hasDirectoryPath && scanned?.hasDirectoryPath == true
          && rf.resolvingSymlinksInPath().path == scanned?.resolvingSymlinksInPath().path,
          "renamed folder URL has the scanner's trailing-slash form")
    check((try? FileOps.rename(b, to: "Chapter One")) == nil, "collision rejected")
    for bad in ["", "  ", "a/b", "a:b", ".hidden"] { check((try? FileOps.rename(b, to: bad)) == nil, "invalid name '\(bad)' rejected") }
    let cased = try! FileOps.rename(renamed, to: "chapter one")
    check(cased.lastPathComponent == "chapter one.md" && fm.fileExists(atPath: cased.path), "case-only rename")

    try! "keep me".write(to: b, atomically: true, encoding: .utf8)
    do {
        let trashed = try FileOps.trash(b)
        check(!fm.fileExists(atPath: b.path) && fm.fileExists(atPath: trashed.path), "trash moves item")
        try! "new squatter".write(to: b, atomically: true, encoding: .utf8)
        let back = try FileOps.restore(trashed, to: b)
        check(back != b && back.lastPathComponent == "Untitled 2 2.md", "restore avoids overwrite: \(back.lastPathComponent)")
        check((try? SheetIO.read(back)) == "keep me" && (try? SheetIO.read(b)) == "new squatter", "restore content intact, squatter untouched")
    } catch { check(false, "trash/restore threw \(error)") }
}

// MARK: session disk logic
do {
    let u = tmp.appendingPathComponent("s.md")
    try! SheetIO.write("héllo — wörld", to: u)
    check((try? SheetIO.read(u)) == "héllo — wörld", "utf8 round trip")
    let s1 = SheetIO.snapshot(u)
    check(s1 != nil, "snapshot exists")
    check(SheetIO.evaluate(diskText: "a", lastSaved: "a", current: "a") == .none, "unchanged")
    check(SheetIO.evaluate(diskText: "a", lastSaved: "a", current: "a+typing") == .none, "own-write echo with unsaved edits is ignored")
    check(SheetIO.evaluate(diskText: "b", lastSaved: "a", current: "a") == .reload("b"), "clean + external change reloads")
    check(SheetIO.evaluate(diskText: "b", lastSaved: "a", current: "a edited") == .conflict("b"), "dirty + external change conflicts")
    check(SheetIO.evaluate(diskText: nil, lastSaved: "a", current: "a") == .deleted, "deleted")
    try! Data([0xff, 0xfe, 0x00]).write(to: tmp.appendingPathComponent("bad.md"))
    check((try? SheetIO.read(tmp.appendingPathComponent("bad.md"))) == nil, "non-utf8 refused rather than corrupted")
}

// MARK: debounce and watcher (need a running main loop)
var fired = 0
let deb = Debouncer(delay: 0.3) { fired += 1 }
for _ in 0..<5 { deb.schedule(); RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
check(fired == 0, "debounce waits while edits continue")
RunLoop.main.run(until: Date().addingTimeInterval(0.6))
check(fired == 1, "debounce fires exactly once, fired \(fired)")
deb.schedule(); deb.cancel()
RunLoop.main.run(until: Date().addingTimeInterval(0.5))
check(fired == 1, "cancel prevents fire")

let wdir = tmp.appendingPathComponent("watch")
try! fm.createDirectory(at: wdir.appendingPathComponent("sub"), withIntermediateDirectories: true)
var events = 0
let watcher = FolderWatcher(path: wdir.resolvingSymlinksInPath().path, latency: 0.2) { events += 1 }
check(watcher != nil, "watcher starts")
RunLoop.main.run(until: Date().addingTimeInterval(0.3))
try! "x".write(to: wdir.appendingPathComponent("sub/new.md"), atomically: true, encoding: .utf8)
RunLoop.main.run(until: Date().addingTimeInterval(1.5))
check(events > 0, "watcher sees nested file creation (\(events) events)")
let before = events
try! "y".write(to: wdir.appendingPathComponent("sub/new.md"), atomically: true, encoding: .utf8)
RunLoop.main.run(until: Date().addingTimeInterval(1.5))
check(events > before, "watcher sees edit of existing file")
watcher?.stop()

print(failures == 0 ? "ALL \(checks) CHECKS PASSED" : "\(failures) of \(checks) CHECKS FAILED")
exit(failures == 0 ? 0 : 1)
