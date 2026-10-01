import SwiftUI

struct EditorPane: View {
    @ObservedObject var store: LibraryStore
    @ObservedObject var session: SheetSession
    @ObservedObject var ui: WindowState

    var body: some View {
        Group {
            if let url = session.url, let kind = session.kind {
                if kind == .rtf {
                    placeholder(icon: "doc.richtext", title: url.deletingPathExtension().lastPathComponent,
                                detail: "Rich text editing arrives in a later phase. The file is untouched.")
                } else {
                    // .id: a new sheet gets a fresh text view, undo stack and goal stats.
                    EditorSurface(text: $session.text, fileURL: url, ui: ui, isLibrary: true)
                        .id(session.openID)
                        .onChange(of: session.text) { _, _ in session.textChanged() }
                }
            } else {
                placeholder(icon: "square.and.pencil", title: "No sheet selected",
                            detail: session.notice ?? "Pick a sheet from the list, or start a new one.")
            }
        }
        .background(Color(nsColor: Theme.paper))
    }

    private func placeholder(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 34, weight: .light)).foregroundStyle(.tertiary)
            Text(title).font(.title3.weight(.medium)).foregroundStyle(.secondary)
            Text(detail).font(.callout).foregroundStyle(.tertiary).multilineTextAlignment(.center).frame(maxWidth: 320)
            if session.url == nil {
                Button("New Sheet") { store.newSheet() }.padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
