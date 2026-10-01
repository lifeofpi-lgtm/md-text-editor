import Foundation
import AppKit

var failures = 0
var checks = 0
@MainActor func check(_ cond: @autoclosure @MainActor () -> Bool, _ msg: String, line: Int = #line) {
    checks += 1
    if !cond() { failures += 1; print("FAIL (line \(line)): \(msg)") }
}
func spin(_ s: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
func disk(_ u: URL) -> String? { try? SheetIO.read(u) }

@MainActor func runAll() {
let fm = FileManager.default
let tmp = fm.temporaryDirectory.appendingPathComponent("mdm-session-\(UUID().uuidString)")
try! fm.createDirectory(at: tmp, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: tmp) }
func make(_ name: String, _ text: String) -> URL {
    let u = tmp.appendingPathComponent(name)
    try! text.write(to: u, atomically: true, encoding: .utf8)
    return u
}

let s = SheetSession(autosaveDelay: 0.3)
var savedCount = 0
s.onSaved = { savedCount += 1 }

// open, edit, autosave after idle
let a = make("a.md", "# A\nbody")
s.open(a)
check(s.text == "# A\nbody" && s.url == a && s.kind == .markdown && !s.isDirty, "open loads text")
s.text += " more"; s.textChanged()
check(s.isDirty, "dirty after edit")
spin(0.1); check(disk(a) == "# A\nbody", "not saved while still inside the idle window")
s.text += " and more"; s.textChanged()     // typing again resets the timer
spin(0.2); check(disk(a) == "# A\nbody", "timer restarted by more typing")
spin(0.4)
check(disk(a) == "# A\nbody more and more" && !s.isDirty && savedCount == 1, "autosaved once after idle (saves: \(savedCount))")

// flush on sheet switch
let b = make("b.md", "bee")
s.text += "!"; s.textChanged()
s.open(b)
check(disk(a) == "# A\nbody more and more!", "switching sheets saves the old one immediately")
check(s.text == "bee" && s.url == b, "new sheet loaded")

// reopening a sheet picks up a fresh editor identity
let id1 = s.openID; s.open(a); check(s.openID != id1, "openID changes per open")

// external change while clean reloads; own write does not
s.open(b)
try! "bee changed elsewhere".write(to: b, atomically: true, encoding: .utf8)
s.diskChanged()
check(s.text == "bee changed elsewhere" && !s.isDirty && s.pendingDisk == nil, "clean + external edit reloads")
let savesBefore = savedCount
s.text += "!"; s.save()
check(savedCount == savesBefore + 1, "own save counted")
s.diskChanged()
check(s.text == "bee changed elsewhere!" && s.pendingDisk == nil, "own write echo does not reload or conflict")

// external change while dirty -> conflict, never silently overwritten
s.text += " mine"; s.textChanged()
try! "theirs".write(to: b, atomically: true, encoding: .utf8)
try! fm.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: b.path)
s.diskChanged()
check(s.pendingDisk == "theirs", "dirty + external edit raises conflict")
spin(0.6)
check(disk(b) == "theirs", "autosave holds off during an unresolved conflict")
s.resolveConflict(keepMine: true)
check(disk(b) == "bee changed elsewhere! mine" && s.pendingDisk == nil && !s.isDirty, "keep mine overwrites disk")

s.text += " again"; s.textChanged()
try! "round two".write(to: b, atomically: true, encoding: .utf8)
try! fm.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: b.path)
s.diskChanged()
s.resolveConflict(keepMine: false)
check(s.text == "round two" && disk(b) == "round two" && !s.isDirty, "reload takes disk version")

// rename of the open file keeps editing it
let renamed = tmp.appendingPathComponent("b renamed.md")
try! fm.moveItem(at: b, to: renamed)
let idBefore = s.openID
s.relocate(to: renamed)
s.text += "!"; s.save()
check(s.openID == idBefore && disk(renamed) == "round two!", "relocate keeps identity and saves to new name")

// deleted while clean closes the sheet
try! fm.removeItem(at: renamed)
s.diskChanged()
check(s.url == nil && s.text == "", "deleted + clean closes the sheet")

// deleted while dirty keeps the text and recreates the file on save
let c = make("c.md", "cee")
s.open(c)
s.text = "cee edited"; s.textChanged()
try! fm.removeItem(at: c)
s.diskChanged()
check(s.url == c && s.text == "cee edited", "deleted + dirty keeps the user's text")
s.save()
check(disk(c) == "cee edited", "save recreates the file")

// flush with nothing dirty writes nothing; empty selection clears
let n = savedCount; s.flush(); check(savedCount == n, "flush is a no-op when clean")
s.open(nil); check(s.url == nil && s.text == "", "open(nil) clears")

// rtf is displayed but never written back
let rtf = tmp.appendingPathComponent("r.rtf")
let att = NSAttributedString(string: "rich")
try! att.data(from: NSRange(location: 0, length: 4), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]).write(to: rtf)
let before = try! Data(contentsOf: rtf)
s.open(rtf)
s.text = "plain overwrite attempt"; s.textChanged(); s.save(); spin(0.5); s.flush()
check((try! Data(contentsOf: rtf)) == before && !s.isEditable, "rtf file untouched in phase 1")

// unreadable (non UTF-8) file refuses to open and explains
let bad = tmp.appendingPathComponent("bad.md"); try! Data([0xff, 0xfe, 0x00]).write(to: bad)
s.open(bad)
check(s.url == nil && s.notice != nil, "non-utf8 shows a notice, does not open")
}
MainActor.assumeIsolated { runAll() }
print(failures == 0 ? "ALL \(checks) CHECKS PASSED" : "\(failures) of \(checks) CHECKS FAILED")
exit(failures == 0 ? 0 : 1)
