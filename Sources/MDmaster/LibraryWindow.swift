import SwiftUI
import AppKit

struct LibraryWindow: View {
    @StateObject private var store = LibraryStore()
    @StateObject private var ui = WindowState()
    /// Columns to restore when Writing Mode ends.
    @StateObject private var memory = ColumnMemory()

    private var visibility: Binding<NavigationSplitViewVisibility> {
        // SwiftUI only manages the sidebar. In editor-only mode it is told "two columns" (sidebar
        // hidden) and SplitViewSupport collapses the middle column itself; SwiftUI's echoes of
        // that are ignored rather than taken as a user choice.
        Binding(get: { store.columns == .editor ? .doubleColumn : store.columns.visibility },
                set: { if store.columns != .editor { store.columns = ColumnMode($0) } })
    }

    var body: some View {
        Group {
            if store.root == nil {
                EmptyLibraryView(store: store)
            } else {
                NavigationSplitView(columnVisibility: visibility) {
                    FolderTreeView(store: store)
                        .navigationSplitViewColumnWidth(min: 170, ideal: 220, max: 320)
                } content: {
                    SheetListView(store: store)
                        .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 460)
                } detail: {
                    EditorPane(store: store, session: store.session, ui: ui)
                }
                .background(SplitViewSupport(name: "MDmasterLibrarySplit", mode: store.columns))
                .toolbar(id: "mdmaster.library") {
                    MainToolbar(store: store, session: store.session, ui: ui)
                }
                // Writing Mode hides every bit of chrome; the toolbar comes back when it ends.
                .toolbar(ui.writingMode ? .hidden : .visible, for: .windowToolbar)
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .focusedSceneValue(\.library, store)
        .onChange(of: ui.writingMode) { _, on in
            // Writing Mode hides every pane; leaving it brings back what was open.
            if on { memory.saved = store.columns; store.columns = .editor }
            else if let m = memory.saved { store.columns = m; memory.saved = nil }
        }
        .onDisappear { store.session.flush() }
        #if DEBUG
        .onAppear { store.debugUI = ui }
        #endif
        .alert("Something went wrong", isPresented: Binding(get: { store.errorMessage != nil },
                                                          set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(store.errorMessage ?? "") }
        .alert("This sheet changed on disk", isPresented: Binding(get: { store.session.pendingDisk != nil }, set: { _ in })) {
            Button("Reload from Disk") { store.session.resolveConflict(keepMine: false) }
            Button("Keep My Version", role: .cancel) { store.session.resolveConflict(keepMine: true) }
        } message: {
            Text("Another app edited this file while you had unsaved changes here. Reload to take the disk version, or keep yours and overwrite it.")
        }
    }
}

@MainActor
final class ColumnMemory: ObservableObject {
    var saved: ColumnMode?
}

struct EmptyLibraryView: View {
    @ObservedObject var store: LibraryStore

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "books.vertical")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text("Choose a library folder")
                .font(.title3.weight(.semibold))
            Text("Your sheets and folders stay as ordinary files inside it, so Finder and other apps keep working.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            Button("Choose Library Folder") { store.chooseRoot() }
                .buttonStyle(.borderedProminent)
                .tint(Color(nsColor: Theme.accent))
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: Theme.paper))
    }
}

/// Two jobs on the window's NSSplitView, because SwiftUI cannot do either:
/// 1. an autosave name so AppKit remembers divider positions;
/// 2. "editor only". NavigationSplitView refuses `.detailOnly` on macOS (it reverts to `.all`
///    because the middle column cannot be hidden through visibility), so the middle column is
///    collapsed directly while SwiftUI hides the sidebar.
struct SplitViewSupport: NSViewRepresentable {
    let name: String
    let mode: ColumnMode

    final class Probe: NSView {
        var name = ""
        var mode: ColumnMode = .all
        private var applied: ColumnMode?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }

        private var split: NSSplitView? { window?.contentView.flatMap(Self.firstSplitView) }

        private func attach() {
            guard let split else { return }
            if split.autosaveName != name { split.autosaveName = name }
            apply()
        }

        /// Only acts when the mode changes, so a divider the user dragged is never overridden.
        func apply() {
            guard applied != mode, let vc = split?.delegate as? NSSplitViewController,
                  vc.splitViewItems.count == 3 else { return }
            applied = mode
            vc.splitViewItems[1].animator().isCollapsed = mode == .editor
        }

        static func firstSplitView(in view: NSView) -> NSSplitView? {
            if let s = view as? NSSplitView { return s }
            for sub in view.subviews { if let s = firstSplitView(in: sub) { return s } }
            return nil
        }
    }

    func makeNSView(context: Context) -> Probe { let p = Probe(); p.name = name; p.mode = mode; return p }
    func updateNSView(_ nsView: Probe, context: Context) {
        nsView.mode = mode
        DispatchQueue.main.async { nsView.apply() }
    }
}
