#if DEBUG
import AppKit

/// Debug builds only. Lets Harness/debugcmd drive the library from a script (select, rename,
/// trash, columns...) so UI states can be screenshotted without synthesising keystrokes into
/// whatever app the user is actually using. Compiled out of release builds.
extension LibraryStore {
    func installDebugHook() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("MDmaster.debug"), object: nil, queue: .main) { [weak self] note in
            guard let cmd = note.userInfo?["cmd"] as? String else { return }
            MainActor.assumeIsolated { self?.runDebug(cmd) }
        }
    }

    private var libraryWindow: NSWindow? {
        NSApp.windows.first { $0.contentView != nil && $0.frame.width > 600 && !($0 is NSPanel) }
    }

    /// Renders the window's own views to a PNG. Works while the window sits in a Stage Manager
    /// strip or the screen is locked, unlike screencapture.
    private func snapshotWindow(to path: String) {
        guard let view = libraryWindow?.contentView?.superview ?? libraryWindow?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { print("no window to snapshot"); return }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: URL(fileURLWithPath: path)) }
    }

    private func sheetURL(_ name: String) -> URL? { sheets.first { $0.name == name }?.url }

    private func folderURL(_ name: String) -> URL? {
        func walk(_ n: FolderNode) -> URL? {
            if n.name == name { return n.url }
            for c in n.children { if let u = walk(c) { return u } }
            return nil
        }
        return tree.flatMap(walk)
    }

    private func runDebug(_ cmd: String) {
        let p = cmd.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        switch p[0] {
        case "newSheet": newSheet(p.count > 1 && p[1] == "rtf" ? .rtf : .markdown)
        case "newFolder": newFolder()
        case "select": selectedSheet = sheetURL(p[1])
        case "folder": selectedFolder = folderURL(p[1])
        case "search": search = p[1]
        case "sort": sort = SheetSort(rawValue: p[1]) ?? .modified
        case "columns": columns = ColumnMode(rawValue: p[1]) ?? .all
        case "rename":
            if let u = sheetURL(p[1]) ?? folderURL(p[1]) { beginRename(u); renameText = p[2]; commitRename() }
        case "trash": if let u = sheetURL(p[1]) ?? folderURL(p[1]) { trash(u) }
        case "undoTrash": undoTrash()
        case "type": session.text += p[1]; session.textChanged()
        case "reload": reload()
        case "keepMine": session.resolveConflict(keepMine: true)
        case "takeDisk": session.resolveConflict(keepMine: false)
        case "writing": debugUI?.writingMode.toggle()
        case "appearance": libraryWindow?.appearance = p[1] == "dark" ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
        case "snapshot": snapshotWindow(to: p[1])
        case "setdoc": session.text = p[1].replacingOccurrences(of: "\\n", with: "\n"); session.textChanged()
        case "find":
            // find|needle|offset|length: put the caret (or a selection) relative to the first match
            guard let tv = EditorActions.editor(in: libraryWindow) else { return }
            let r = (tv.string as NSString).range(of: p[1])
            if r.location != NSNotFound {
                tv.setSelectedRange(NSRange(location: r.location + (Int(p[2]) ?? 0), length: Int(p.count > 3 ? p[3] : "0") ?? 0))
            } else { print("find: not found \(p[1])") }
        case "format":
            let map: [String: Selector] = [
                "bold": #selector(EditorTextView.mdBold(_:)), "italic": #selector(EditorTextView.mdItalic(_:)),
                "strike": #selector(EditorTextView.mdStrike(_:)), "code": #selector(EditorTextView.mdCode(_:)),
                "link": #selector(EditorTextView.mdLink(_:)), "h1": #selector(EditorTextView.mdHeading1(_:)),
                "h2": #selector(EditorTextView.mdHeading2(_:)), "h3": #selector(EditorTextView.mdHeading3(_:)),
                "bullet": #selector(EditorTextView.mdBulletList(_:)), "numbered": #selector(EditorTextView.mdNumberedList(_:)),
                "checkbox": #selector(EditorTextView.mdCheckbox(_:)), "quote": #selector(EditorTextView.mdQuote(_:)),
            ]
            if let sel = map[p[1]] { EditorActions.perform(sel, in: libraryWindow) } else { print("unknown format \(p[1])") }
        case "typeview":
            // Types through the text view (like keystrokes), so undo and coalescing behave for real.
            if let tv = EditorActions.editor(in: libraryWindow) { tv.insertText(p[1], replacementRange: tv.selectedRange()) }
        case "closeSheet": selectedSheet = nil
        case "goal": UserDefaults.standard.set(Int(p[1]) ?? 0, forKey: SettingsKey.goalWords)
        case "undo": EditorActions.editor(in: libraryWindow)?.undoManager?.undo()
        case "redo": EditorActions.editor(in: libraryWindow)?.undoManager?.redo()
        case "divider":
            libraryWindow?.contentView.flatMap(SplitFinder.first)?.setPosition(CGFloat(Double(p[1]) ?? 240), ofDividerAt: Int(p[2]) ?? 0)
        case "collapse":
            guard let split = libraryWindow?.contentView.flatMap(SplitFinder.first),
                  let vc = split.delegate as? NSSplitViewController else { print("no split view controller: \(String(describing: libraryWindow?.contentView.flatMap(SplitFinder.first)?.delegate))"); return }
            for item in vc.splitViewItems.dropLast() { item.animator().isCollapsed = p[1] == "on" }
        case "dump":
            let split = libraryWindow.flatMap { $0.contentView.flatMap(SplitFinder.first) }
            let tv = EditorActions.editor(in: libraryWindow)
            let tb = libraryWindow?.toolbar
            let f = debugUI?.format ?? FormatState()
            let state: [String: Any] = [
                "editorText": tv?.string ?? "",
                "selection": tv.map { [$0.selectedRange().location, $0.selectedRange().length] } ?? [],
                "format": ["bold": f.bold, "italic": f.italic, "strike": f.strike, "code": f.code, "link": f.link,
                           "heading": f.heading, "bullet": f.bullet, "numbered": f.numbered, "checkbox": f.checkbox, "quote": f.quote],
                "toolbarVisible": tb?.isVisible ?? false,
                "toolbarId": tb?.identifier ?? "",
                "toolbarCustomizable": tb?.allowsUserCustomization ?? false,
                "toolbarAutosaves": tb?.autosavesConfiguration ?? false,
                "toolbarItems": tb?.items.map { $0.itemIdentifier.rawValue } ?? [],
                "toolbarEnabled": Dictionary(uniqueKeysWithValues: (tb?.items ?? []).map { ($0.itemIdentifier.rawValue, $0.isEnabled) }),
                "goalWords": UserDefaults.standard.integer(forKey: SettingsKey.goalWords),
                "showGoal": debugUI?.showGoal ?? false, "uiWords": debugUI?.words ?? 0, "uiWritten": debugUI?.written ?? 0,
                "splitSubviewWidths": split?.arrangedSubviews.map { Int($0.frame.width) } ?? [],
                "splitCollapsed": split?.arrangedSubviews.map { split?.isSubviewCollapsed($0) ?? false } ?? [],
                "selectedSheet": selectedSheet?.lastPathComponent ?? "",
                "selectedFolder": selectedFolder?.lastPathComponent ?? "",
                "sessionURL": session.url?.lastPathComponent ?? "",
                "sessionText": String(session.text.prefix(200)),
                "dirty": session.isDirty,
                "conflict": session.pendingDisk != nil,
                "toast": toast ?? "",
                "trashStack": trashStack.count,
                "columns": columns.rawValue,
                "sheets": filteredSheets.map(\.name),
                "renaming": renaming?.lastPathComponent ?? "",
                "error": errorMessage ?? "",
                "writingMode": debugUI?.writingMode ?? false,
            ]
            if let d = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]) { try? d.write(to: URL(fileURLWithPath: p[1])) }
        default: print("unknown debug command \(cmd)")
        }
    }
}
enum SplitFinder {
    static func first(_ v: NSView) -> NSSplitView? {
        if let s = v as? NSSplitView { return s }
        for sub in v.subviews { if let s = first(sub) { return s } }
        return nil
    }
}
#endif
