import SwiftUI
import AppKit

/// Which panes are visible. Maps onto NavigationSplitView's visibility.
enum ColumnMode: String {
    case all, list, editor

    var visibility: NavigationSplitViewVisibility {
        switch self { case .all: .all; case .list: .doubleColumn; case .editor: .detailOnly }
    }
    init(_ v: NavigationSplitViewVisibility) {
        switch v {
        case .detailOnly: self = .editor
        case .doubleColumn: self = .list
        default: self = .all
        }
    }
}

struct TrashEntry {
    let original: URL
    let trashed: URL
    let wasSheet: Bool
}

/// Everything the three panes share: where the library is, what is selected, and the
/// file operations. Files on disk stay the source of truth; this only mirrors them.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var root: URL?
    @Published private(set) var tree: FolderNode?
    @Published private(set) var sheets: [SheetItem] = []

    @Published var selectedFolder: URL? {
        didSet { guard oldValue?.path != selectedFolder?.path else { return }; persist(); reload() }
    }
    @Published var selectedSheet: URL? {
        didSet {
            guard oldValue != selectedSheet else { return }
            persist()
            if !suppressOpen { session.open(selectedSheet) }
        }
    }
    @Published var search = ""
    @Published var sort: SheetSort { didSet { UserDefaults.standard.set(sort.rawValue, forKey: SettingsKey.librarySort) } }
    @Published var columns: ColumnMode { didSet { UserDefaults.standard.set(columns.rawValue, forKey: SettingsKey.libraryColumns) } }
    @Published var expanded: Set<String> { didSet { UserDefaults.standard.set(Array(expanded), forKey: SettingsKey.libraryExpanded) } }

    @Published var renaming: URL?
    @Published var renameText = ""
    @Published var errorMessage: String?
    @Published var toast: String?
    @Published private(set) var trashStack: [TrashEntry] = []

    let session = SheetSession()
    private let scanner = SheetScanner()
    private let queue = DispatchQueue(label: "MDmaster.library.scan", qos: .userInitiated)
    private var watcher: FolderWatcher?
    private var toastTask: Task<Void, Never>?
    private var terminateObserver: NSObjectProtocol?
    /// Set while a rename re-points the selection at the same file under a new name.
    private var suppressOpen = false
    #if DEBUG
    weak var debugUI: WindowState?
    #endif

    init() {
        let d = UserDefaults.standard
        sort = SheetSort(rawValue: d.string(forKey: SettingsKey.librarySort) ?? "") ?? .modified
        columns = ColumnMode(rawValue: d.string(forKey: SettingsKey.libraryColumns) ?? "") ?? .all
        expanded = Set(d.stringArray(forKey: SettingsKey.libraryExpanded) ?? [])

        session.onSaved = { [weak self] in self?.reload() }
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.session.flush() }
        }

        #if DEBUG
        installDebugHook()
        #endif
        if let path = d.string(forKey: SettingsKey.libraryRoot), Self.isDirectory(path) {
            // Read everything first: assigning selectedFolder runs persist(), which would
            // overwrite the saved sheet path before we got to read it.
            let savedFolder = d.string(forKey: SettingsKey.libraryFolder)
            let savedSheet = d.string(forKey: SettingsKey.librarySheet)
            let rootURL = URL(fileURLWithPath: path)
            root = rootURL
            selectedFolder = savedFolder.flatMap { Self.isDirectory($0) ? URL(fileURLWithPath: $0) : nil } ?? rootURL
            if let s = savedSheet, FileManager.default.fileExists(atPath: s) {
                selectedSheet = URL(fileURLWithPath: s) // didSet opens it in the session
            }
            startWatching()
            reload()
        }
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    private func persist() {
        let d = UserDefaults.standard
        d.set(selectedFolder?.path, forKey: SettingsKey.libraryFolder)
        d.set(selectedSheet?.path, forKey: SettingsKey.librarySheet)
    }

    // MARK: Root folder

    func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose Library Folder"
        panel.message = "Pick the folder that holds your writing. Sheets and folders stay as normal files inside it."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setRoot(url)
    }

    func setRoot(_ url: URL) {
        session.flush()
        selectedSheet = nil
        root = url
        UserDefaults.standard.set(url.path, forKey: SettingsKey.libraryRoot)
        selectedFolder = url
        expanded = []
        startWatching()
        reload()
    }

    private func startWatching() {
        watcher?.stop()
        guard let root else { watcher = nil; return }
        watcher = FolderWatcher(path: root.resolvingSymlinksInPath().path) { [weak self] in self?.reload() }
    }

    // MARK: Reading

    var filteredSheets: [SheetItem] {
        SheetScanner.filter(SheetScanner.sort(sheets, by: sort), query: search)
    }

    func reload() {
        guard let root else { return }
        let folder = selectedFolder ?? root
        let scanner = self.scanner
        queue.async {
            let tree = scanner.tree(root: root)
            let items = scanner.sheets(in: folder)
            DispatchQueue.main.async { [weak self] in self?.apply(tree: tree, sheets: items, folder: folder) }
        }
        session.diskChanged()
    }

    private func apply(tree: FolderNode, sheets items: [SheetItem], folder: URL) {
        self.tree = tree
        guard folder.path == (selectedFolder ?? root)?.path else { return } // selection moved while scanning
        sheets = items
        if let f = selectedFolder, !Self.isDirectory(f.path) { selectedFolder = root }
        if let s = selectedSheet, !FileManager.default.fileExists(atPath: s.path), !session.isDirty {
            selectedSheet = nil
        }
        // Invariant: the editor shows the selected sheet. Seen disagree once on a first launch
        // (list highlighted one sheet, editor held another; not reproducible in 5 relaunches),
        // so re-sync cheaply instead of trusting every path that sets the selection.
        if let s = selectedSheet, session.url != s, !session.isDirty { session.open(s) }
    }

    // MARK: Creating

    private var targetFolder: URL? { selectedFolder ?? root }

    func newSheet(_ kind: SheetKind = .markdown) {
        guard let folder = targetFolder else { return }
        do {
            let url = try FileOps.createSheet(in: folder, kind: kind)
            search = ""
            selectedSheet = url
            reload()
            // After the editor for the new sheet exists.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NotificationCenter.default.post(name: .mdFocusEditor, object: nil)
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func newFolder() {
        guard let parent = targetFolder else { return }
        do {
            let url = try FileOps.createFolder(in: parent)
            expanded.insert(parent.path)
            selectedFolder = url
            beginRename(url)
            reload()
        } catch { errorMessage = error.localizedDescription }
    }

    // MARK: Renaming

    func beginRename(_ url: URL) {
        renameText = Self.isDirectory(url.path) ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        renaming = url
    }

    func cancelRename() { renaming = nil }

    func commitRename() {
        guard let url = renaming else { return }
        renaming = nil
        let name = renameText
        let current = Self.isDirectory(url.path) ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        guard name.trimmingCharacters(in: .whitespaces) != current else { return }
        do {
            let new = try FileOps.rename(url, to: name)
            remap(from: url, to: new)
            reload()
        } catch { errorMessage = error.localizedDescription }
    }

    /// A rename moves every path beneath it; keep selection, open file and expansion pointing at them.
    private func remap(from old: URL, to new: URL) {
        // Path comparison: "a/b" and "a/b/" are unequal URLs but the same folder.
        func moved(_ u: URL?) -> URL? {
            guard let u else { return nil }
            if u.path == old.path { return new }
            let prefix = old.path + "/"
            guard u.path.hasPrefix(prefix) else { return u }
            let path = new.path + "/" + u.path.dropFirst(prefix.count)
            return URL(fileURLWithPath: path, isDirectory: Self.isDirectory(path))
        }
        expanded = Set(expanded.map { moved(URL(fileURLWithPath: $0))?.path ?? $0 })
        if let s = selectedSheet, let m = moved(s), m.path != s.path {
            session.relocate(to: m)
            suppressOpen = true
            selectedSheet = m
            suppressOpen = false
        }
        if let f = selectedFolder, let m = moved(f), m.path != f.path { selectedFolder = m }
    }

    // MARK: Trash

    func trash(_ url: URL) {
        let isFolder = Self.isDirectory(url.path)
        let openSheetInside = selectedSheet.map { $0.path == url.path || $0.path.hasPrefix(url.path + "/") } ?? false
        if openSheetInside { session.flush() }
        do {
            let trashed = try FileOps.trash(url)
            trashStack.append(TrashEntry(original: url, trashed: trashed, wasSheet: !isFolder))
            if openSheetInside { selectedSheet = nil }
            if let f = selectedFolder, f.path == url.path || f.path.hasPrefix(url.path + "/") { selectedFolder = FileOps.dirURL(url.deletingLastPathComponent()) }
            showToast("Moved \"\(url.lastPathComponent)\" to the Trash")
            reload()
        } catch { errorMessage = error.localizedDescription }
    }

    func undoTrash() {
        guard let entry = trashStack.popLast() else { return }
        do {
            let restored = try FileOps.restore(entry.trashed, to: entry.original)
            if entry.wasSheet, restored.deletingLastPathComponent().path == selectedFolder?.path { selectedSheet = restored }
            showToast("Restored \"\(restored.lastPathComponent)\"")
            reload()
        } catch { errorMessage = error.localizedDescription }
    }

    func dismissToast() { toast = nil }

    private func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
}
