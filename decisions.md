# Decisions

## 2026-08-21 Initial scoping

**Editing model: live styled markdown** (iA Writer style) over WYSIWYG or split preview.
Why: the file is always exactly what you see, no markdown round-trip bugs, closest to
the "simple like TextEdit" feel while still being markdown-native.

**Stack: native SwiftUI + NSTextView.** Rejected Electron/Tauri and browser web app.
Why: autosave, Versions, dark mode, system Open/Save, and Quick Look come free from the
macOS document architecture. Xcode already installed. Electron never feels like a Mac app.

**Scope: single document editor, one window per file.** Rejected notes library with
sidebar for v1.
Why: small and finishable. Library can be v2 if wanted.

**Must-haves confirmed:** word count + focus mode; export to PDF/HTML/DOCX; GFM extras
(tables, checkboxes, code blocks).
Not needed: opening .rtf as rich text.

**DOCX export routes to the existing md2docx tool** rather than building a DOCX writer.
Why: it already exists and carries the brand templates.

**No third-party editor dependencies in v1.** Hand-rolled highlighter over NSTextStorage.
Why: keeps the app small and the styling fully under our control. Revisit if the
highlighter gets slow on very large files.

## 2026-08-21 Open questions resolved

**App name: MDmaster.**

**Default body font: SF Pro (system sans), 17pt, line height ~1.55.** User asked for
"whatever is more modern". Sans is the current default in Bear, Craft, Notion, Apple Notes.
Serif (New York) offered as a toggle later if wanted. Headings same family, heavier weight.

**Focus mode: paragraph dim by default, sentence dim as an option in the View menu.**
User asked for whatever studies support. Direct studies comparing sentence vs paragraph
dimming in writing apps are sparse; the most relevant evidence is writing-process research
(Flower and Hayes, later drafting studies) showing that suppressing premature re-reading
and editing improves drafting flow, which argues for dimming at all, and reading research
that comprehension depends on surrounding-sentence context, which argues against hiding the
whole paragraph by default. Paragraph keeps context, sentence is the stricter option.
Both are the same code path with a different range, so offering both costs nothing.

**Build system: Swift Package + shell script that assembles MDmaster.app.** No Xcode.app
on this machine, only Command Line Tools, so no xcodeproj. `swift build` against the CLT
macOS SDK compiles SwiftUI fine. If Xcode gets installed later, `swift package
generate-xcodeproj` is gone but Xcode can open Package.swift directly.

## 2026-08-21 Session 2: QA, polish, icon

**QA done headlessly where possible.** Highlighter, HTML and PDF renderers were compiled
into small harnesses against the real source files instead of driving the GUI.
Why: Stage Manager plus the user being active on the machine made scripted keystrokes
and screenshots unreliable and intrusive. Remaining visual checks are listed in
handoff.md for a quick manual pass.

**Title bar made transparent and painted paper colour.** Done from
EditorTextView.viewDidMoveToWindow rather than a custom window class.
Why: DocumentGroup owns the NSWindow; this is the smallest hook that still runs per window.

**Empty-document placeholder "Start writing" drawn in EditorTextView.draw.**
Why: cheaper and more reliable than an overlay view, and it disappears with the first key.

**Heading tracking: -0.02em on H1 and H2 only.** Matches the "tight tracking" note in
.impeccable.md without touching body or H3+.

**App icon generated in CoreGraphics from the logo spec** (Resources/AppIcon.icns),
rather than wrapping the delivered PNGs directly.
Why: the README asked for Apple's squircle and the 824/1024 inset with shadow; drawing
from the spec gives both, plus a thicker caret and no rule at 16/32 px for legibility.
The generator lives in the session scratchpad; the SVG zip in Sources/ is the source of
truth if it needs regenerating.

**Icon stays as delivered (violet/gold)** even though the editor accent is terracotta.
Irshad confirmed: the brand mark and the UI accent can differ.

**Undo left on the default shared undo manager.** Irshad tested ⌘Z/⌘⇧Z manually and it
works fine, so no private UndoManager for the text view.

**Repo initialised with git** this session per the global handoff protocol.

## 2026-08-22 Session close

**v1 declared feature-complete for now.** Improvement ideas recorded in handoff.md as a
backlog rather than started, so the next session begins from a clean choice.
Recommended first three: link ⌘-click, checkbox toggle, heading navigator.
Why: they make the editor behave like markdown rather than just render it, and none of
them touch the document model or the file format.

## 2026-09-30 Session 3: writing features

**Direction: distraction-free writing alongside markdown, inspired by Ulysses.** Keep plain
.md files as the source of truth (Ulysses's hidden library is the thing we are not copying).

**Proofreading in tiers: A (Apple checker) now, B (own offline rules) next, C (LanguageTool)
only if needed.** Why: A is nearly free; B stays dependency-free and private; C either sends
text to a third party or needs Java and hundreds of MB, against the small native brief.

**Shortcuts reassigned:** Writing Mode takes Cmd-Shift-F; dimming moved to Cmd-Shift-D;
typewriter is Cmd-Shift-T. Why: full-screen writing is now the headline feature, dimming is
an option inside it.

**Goals count words written this session by default** (increase only, never lowered by
deleting). Why: matches how writers track a day's work and ignores opening a long file.

**Per-window UI state via ObservableObject, not @State.** Why: SwiftUI's @State macro plugin
is missing without Xcode.app.

**No library/sidebar yet.** Revisit as a folder-as-library of real .md files after using
this round for a while.

## 2026-09-30 v2 scope: library, toolbar, rich text

This reverses three v1 decisions. Each reason is below.

**Library = a folder of real files on disk, no hidden database.** Reverses "no sidebar or
notes library for v1" (2026-08-21). Why: v1 was a single-file editor and needed to stay
small; it is now in daily use for writing, and long pieces need navigation between files.
Keeping the library as plain folders means Finder, Git and other editors keep working and
there is no lock-in, which is the thing we did not want to copy from Ulysses.

**Toolbar = the standard always-visible macOS toolbar, hidden in Writing Mode.** Reverses
"no WYSIWYG toolbar" and the one-line-chrome rule. Why: formatting and sheet actions should
be discoverable without memorising shortcuts. Writing Mode still removes all chrome, so the
distraction-free case is unchanged. The buttons drive the same Format commands as the menus,
so no formatting logic is duplicated.

**Rich text supported as .rtf alongside .md.** Reverses "not needed: opening .rtf as rich
text". Why: some writing (and files received from others) is rich text. .rtf sheets use a
real rich-text editor and save as RTF; .md stays plain markdown. One formatting protocol has
two implementations so the toolbar works on both. Conversion between the two always writes a
new file and never overwrites the original.

**Window model: library WindowGroup plus the existing DocumentGroup.** Why: files opened
from Finder or Cmd-O outside the library must keep working in their own windows, so nothing
from v1 breaks.

**Out of scope for v2:** glue/split sheets, notes and keywords, hiding markdown symbols,
the Tier B style checker, sync, manual drag-reorder of sheets.

## 2026-09-30 v2 Phase 1 build decisions

**Editor-only mode collapses the middle column through AppKit, not SwiftUI.** Why:
NavigationSplitView on macOS refuses `.detailOnly` (it reverts to `.all`) because the middle
column cannot be hidden through visibility. SwiftUI is told "two columns" to hide the sidebar and
SplitViewSupport collapses the list item of the underlying NSSplitViewController. Writing Mode
uses this, so it needs to be exact; transitions were tested in every order.

**Folder URLs are normalised (trailing slash) and compared by path.** Why: directory listings
return "a/b/" while a freshly made URL is "a/b"; they are unequal, which broke selection after a
rename.

**Files are read as UTF-8 only.** A non-UTF-8 file refuses to open with a notice instead of being
guessed and silently rewritten on save.

**Autosave never overwrites while a disk conflict is unresolved.** Keep My Version or Reload from
Disk is an explicit choice. A sheet deleted on disk closes if clean and is recreated on the next
save if it has unsaved edits.

**Verification uses an in-app snapshot and a debug command hook, not screencapture or synthetic
keystrokes.** Why: Stage Manager parks windows as thumbnails and the machine is in active use; the
hook is compiled out of release builds. Real key and click behaviour stays on the manual list.

**Trash undo is a toast plus File > Undo Move to Trash** (a small stack), not the system undo,
because Cmd-Z belongs to the text view while the editor has focus.

## 2026-09-30 v2 Phase 2 build decisions

**Each toolbar control is its own customizable item.** Why: grouping the format buttons in one item
gave them no accessibility names and made them impossible to move or remove one by one. Cost: they
sit right-aligned over the editor column instead of centred.

**Format state is shown with toggle buttons tinted terracotta.** Why: toolbar icons ignore custom
foreground colours, and a toggle is the system's own on/off state. The state is read back from the
caret, so the button can never drift from the text.

**Toolbar and menus call one set of editor actions through EditorActions.** Why: the responder chain
alone fails when focus is in the sheet list, and one implementation per format avoids drift. This
is the seam Phase 3 replaces with the formatter protocol (markdown and RTF implementations).

**Block formats are line-level and pure (MarkdownBlocks).** Toggling is "all lines already have it
-> remove, otherwise apply to all"; blank lines in a multi-line selection are skipped; quote is a
separate layer so a list can sit inside a quote; headings drop indentation. Why: predictable,
testable, and matches Notes and Ulysses.

**Every format action is its own undo step** (breakUndoCoalescing around it). Why: NSTextView merges
consecutive edits, which would fold a toolbar click into the typing before it.

**Toolbar hides in Writing Mode via `.toolbar(.hidden, for: .windowToolbar)`.** Verified by reading
NSToolbar.isVisible.

## 2026-10-01 Preparing for a public repo

**DOCX export defaults to pandoc; the md2docx path is now an optional custom converter.** Why: the
hardcoded Shape & Scale template path only exists on one machine. Setting it in Preferences >
Export keeps the branded output. Reverses "DOCX export routes to the existing md2docx tool"
(2026-08-21) as the default, not as a capability.

**MIT license; CLAUDE.md and handoff.md untracked and gitignored.** Why: they hold local paths and
working notes. decisions.md stays as the public design log. The files remain on disk for the
handoff protocol, but they are no longer committed, so they will not travel with the repo.

## 2026-10-01. Fresh repo for the public release instead of rewriting history
Decided: publish from a new repo with a single initial commit, and archive the old history locally.
**Why:** the old history held two personal author emails and the old CLAUDE.md and handoff.md with local
paths. Only a fresh repo clears all of it in one step. The project had no stars, forks or issues to lose.
**Rejected:** rewriting authors with filter-branch and force-pushing. It would keep commit messages but leave
the old internal notes in history unless those were stripped too, and it was riskier.

## 2026-10-01. Delete the old GitHub repo rather than rename it to an archive
Decided: delete `md-text-editor` and recreate it, relying on the local archive for history.
**Why:** a renamed private repo would keep the emails on GitHub, which defeats the cleanup.
**Rejected:** renaming to `md-text-editor-archive` as a remote backup.

## 2026-10-01. Keep the bundle ID co.shapeandscale.MDmaster
**Why:** it is invisible to users, uses a domain Irshad controls, and changing it would reset saved
preferences, toolbar layout and the last library folder.
**Rejected:** a personal ID such as com.lifeofpi.MDmaster. Can be changed before notarisation.

## 2026-10-01. Include the logo zip in the public repo
Decided: ship `Sources/MDmaster Logo Design.zip` under the repo's MIT license.
**Why:** Irshad confirmed they hold the rights.

## 2026-10-01. Public profile README lists only projects that are already public
Decided: create `lifeofpi-lgtm/lifeofpi-lgtm`, list MissionQuit first, add MDmaster once public (done the same
session). Wording was Irshad's own line, not embellished.
**Why:** a link to a private repo would 404 for visitors.

## 2026-10-01. New commits use the GitHub noreply address; old MissionQuit emails left alone
Decided: set the noreply address as the repo-local git email for repos touched this session. Irshad chose not
to rewrite MissionQuit's six existing commits, which show the Gmail address.
**Why:** avoids adding new personal-email commits. A MissionQuit history reset would break its already-public URL.

## 2026-10-02. Push handoff commits to the public repo at session end
Decided: decisions.md is public, so each session-end docs commit is pushed to origin/main after a check that it
holds no emails, local paths or client data. handoff.md stays gitignored and never published.
**Why:** a public design log that lags the work is misleading, and the check keeps the private notes private.
**Rejected:** leaving docs commits local until a release. The log would fall behind with no benefit.
