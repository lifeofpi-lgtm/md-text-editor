import Foundation

/// The one sheet open in the editor pane: its text, autosave, and reaction to outside edits.
@MainActor
final class SheetSession: ObservableObject {
    @Published private(set) var url: URL?
    @Published private(set) var kind: SheetKind?
    /// Changes only when a different sheet is opened, so renaming the open file does
    /// not rebuild the editor and lose the caret and undo history.
    @Published private(set) var openID = UUID()
    @Published var text = ""
    /// Disk text waiting for the user's choice when both sides changed.
    @Published var pendingDisk: String?
    @Published var notice: String?

    private(set) var lastSaved = ""
    private var snapshot: DiskSnapshot?
    private var debouncer: Debouncer!
    /// Called after every successful save so the list can refresh its excerpt.
    var onSaved: (() -> Void)?

    init(autosaveDelay: TimeInterval = 1.0) {
        debouncer = Debouncer(delay: autosaveDelay) { [weak self] in self?.save() }
    }

    var isDirty: Bool { url != nil && text != lastSaved }
    /// RTF arrives in a later phase; until then it is shown but never written back.
    var isEditable: Bool { url != nil && kind != .rtf }

    func open(_ newURL: URL?) {
        flush()
        pendingDisk = nil
        notice = nil
        guard let newURL, let k = SheetKind(url: newURL) else { clear(); return }
        if k == .rtf {
            url = newURL; kind = k; lastSaved = ""; text = ""; snapshot = nil; openID = UUID()
            return
        }
        do {
            let loaded = try SheetIO.read(newURL)
            lastSaved = loaded
            snapshot = SheetIO.snapshot(newURL)
            url = newURL; kind = k; text = loaded; openID = UUID()
        } catch {
            clear()
            notice = "Couldn't open \(newURL.lastPathComponent). It may not be UTF-8 text."
        }
    }

    private func clear() {
        url = nil; kind = nil; lastSaved = ""; text = ""; snapshot = nil; openID = UUID()
    }

    func textChanged() {
        if isDirty && isEditable { debouncer.schedule() } else { debouncer.cancel() }
    }

    func save() {
        debouncer.cancel()
        // Never overwrite the disk while the user still has to choose in a conflict.
        guard let url, isEditable, pendingDisk == nil, text != lastSaved else { return }
        write(to: url)
    }

    private func write(to url: URL) {
        do {
            try SheetIO.write(text, to: url)
            lastSaved = text
            snapshot = SheetIO.snapshot(url)
            onSaved?()
        } catch {
            notice = "Couldn't save \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Autosave points: sheet switch, window close, quit.
    func flush() {
        debouncer.cancel()
        save()
    }

    /// The file was renamed or moved; keep editing it under its new name.
    func relocate(to newURL: URL) {
        url = newURL
        snapshot = SheetIO.snapshot(newURL)
    }

    /// Called from the folder watcher on every file event.
    func diskChanged() {
        guard let url, isEditable else { return }
        let now = SheetIO.snapshot(url)
        if now == snapshot { return } // our own write, or an unrelated file
        let disk = (try? SheetIO.read(url))
        switch SheetIO.evaluate(diskText: disk, lastSaved: lastSaved, current: text) {
        case .none:
            snapshot = now
        case .reload(let t):
            lastSaved = t; snapshot = now; text = t
        case .conflict(let t):
            pendingDisk = t
        case .deleted:
            // Clean: the store closes the sheet. Dirty: keep the text; the next save recreates the file.
            if !isDirty { clear() }
        }
    }

    func resolveConflict(keepMine: Bool) {
        guard let disk = pendingDisk, let url else { return }
        pendingDisk = nil
        if keepMine {
            write(to: url)
        } else {
            lastSaved = disk; snapshot = SheetIO.snapshot(url); text = disk
        }
    }
}
