import SwiftUI

struct FolderTreeView: View {
    @ObservedObject var store: LibraryStore

    var body: some View {
        List(selection: $store.selectedFolder) {
            if let tree = store.tree {
                FolderRow(node: tree, store: store, isRoot: true)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button { store.newFolder() } label: { Label("New Folder", systemImage: "folder.badge.plus") }
                    .buttonStyle(.borderless)
                    .labelStyle(.iconOnly)
                    .help("New Folder")
                Spacer()
                Button { store.chooseRoot() } label: { Image(systemName: "ellipsis.circle") }
                    .buttonStyle(.borderless)
                    .help("Choose a different library folder")
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }
}

struct FolderRow: View {
    let node: FolderNode
    @ObservedObject var store: LibraryStore
    var isRoot = false

    private var isExpanded: Binding<Bool> {
        Binding(get: { isRoot || store.expanded.contains(node.url.path) },
                set: { open in
                    if open { store.expanded.insert(node.url.path) } else { store.expanded.remove(node.url.path) }
                })
    }

    var body: some View {
        if node.children.isEmpty && !isRoot {
            label.tag(node.url)
        } else {
            DisclosureGroup(isExpanded: isExpanded) {
                ForEach(node.children) { child in
                    FolderRow(node: child, store: store)
                }
            } label: {
                label.tag(node.url)
            }
        }
    }

    @ViewBuilder private var label: some View {
        HStack(spacing: 6) {
            Image(systemName: isRoot ? "books.vertical" : "folder")
                .foregroundStyle(.secondary)
            if store.renaming == node.url {
                RenameField(store: store)
            } else {
                Text(node.name).lineLimit(1)
            }
        }
        .contextMenu {
            Button("New Folder Inside") {
                store.selectedFolder = node.url
                store.newFolder()
            }
            Button("New Sheet Here") {
                store.selectedFolder = node.url
                store.newSheet()
            }
            Divider()
            if !isRoot { Button("Rename") { store.beginRename(node.url) } }
            Button("Reveal in Finder") { store.reveal(node.url) }
            if !isRoot {
                Divider()
                Button("Move to Trash", role: .destructive) { store.trash(node.url) }
            }
        }
    }
}

/// Inline rename used by folders and sheets. Return commits, Esc cancels, and clicking
/// away commits too (like Finder).
struct RenameField: View {
    @ObservedObject var store: LibraryStore
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Name", text: $store.renameText)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onSubmit { store.commitRename() }
            .onExitCommand { store.cancelRename() }
            .onAppear { focused = true }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { store.commitRename() }
            }
    }
}
