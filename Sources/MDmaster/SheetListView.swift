import SwiftUI

struct SheetListView: View {
    @ObservedObject var store: LibraryStore

    var body: some View {
        let items = store.filteredSheets
        VStack(spacing: 0) {
            SearchField(text: $store.search)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 6)
            if items.isEmpty {
                emptyState
            } else {
                List(items, selection: $store.selectedSheet) { item in
                    SheetRow(item: item, store: store).tag(item.url)
                }
                .listStyle(.inset)
            }
        }
        .overlay(alignment: .bottom) { toast }
        .safeAreaInset(edge: .bottom) { footer(count: items.count) }
        .navigationTitle(store.selectedFolder?.lastPathComponent ?? "Library")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text(store.search.isEmpty ? "No sheets here yet" : "No matches")
                .foregroundStyle(.secondary)
            if store.search.isEmpty {
                Button("New Sheet") { store.newSheet() }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func footer(count: Int) -> some View {
        HStack(spacing: 10) {
            Text(count == 1 ? "1 sheet" : "\(count) sheets")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Picker("Sort By", selection: $store.sort) {
                    ForEach(SheetSort.allCases) { Text($0.label).tag($0) }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Sort sheets")
            Button { store.newSheet() } label: { Image(systemName: "square.and.pencil") }
                .buttonStyle(.borderless)
                .help("New Sheet")
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder private var toast: some View {
        if let message = store.toast {
            HStack(spacing: 10) {
                Text(message).font(.caption).lineLimit(1)
                if !store.trashStack.isEmpty {
                    Button("Undo") { store.undoTrash() }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Color(nsColor: Theme.accent))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, 44)
            .transition(.opacity)
        }
    }
}

struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
    }
}

struct SheetRow: View {
    let item: SheetItem
    @ObservedObject var store: LibraryStore

    private static func dateText(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return d.formatted(date: .omitted, time: .shortened) }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        if cal.isDate(d, equalTo: .now, toGranularity: .year) { return d.formatted(.dateTime.month(.abbreviated).day()) }
        return d.formatted(.dateTime.year().month(.abbreviated).day())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if store.renaming == item.url {
                RenameField(store: store)
            } else {
                HStack(spacing: 4) {
                    Text(item.title).font(.headline).lineLimit(1)
                    if item.kind == .rtf {
                        Text("RTF").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 4).background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                    }
                }
            }
            if !item.excerpt.isEmpty {
                Text(item.excerpt)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                Text(Self.dateText(item.modified))
                Text("·")
                Text("\(item.words.formatted()) words")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("New Sheet") { store.newSheet() }
            Divider()
            Button("Rename") { store.beginRename(item.url) }
            Button("Reveal in Finder") { store.reveal(item.url) }
            Divider()
            Button("Move to Trash", role: .destructive) { store.trash(item.url) }
        }
    }
}
