import Foundation

struct FolderNode: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let name: String
    var children: [FolderNode]
}

struct SheetItem: Identifiable, Equatable {
    var id: URL { url }
    let url: URL
    let kind: SheetKind
    let name: String          // file name without extension
    let title: String
    let excerpt: String
    let words: Int
    let modified: Date
    let size: Int
    /// Lowercased body for content search; bounded so a huge file cannot bloat memory.
    let searchText: String
}

enum SheetSort: String, CaseIterable, Identifiable {
    case modified, name
    var id: String { rawValue }
    var label: String { self == .modified ? "Date Modified" : "Name" }
}

/// Reads the library off disk. One instance is used from one serial queue only, so the
/// cache needs no locking.
final class SheetScanner {
    private var cache: [URL: SheetItem] = [:]
    static let maxDepth = 12

    func tree(root: URL) -> FolderNode {
        FolderNode(url: root, name: root.lastPathComponent, children: children(of: root, depth: 0))
    }

    private func children(of dir: URL, depth: Int) -> [FolderNode] {
        guard depth < Self.maxDepth else { return [] }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return urls.compactMap { url -> FolderNode? in
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  v.isDirectory == true, v.isPackage != true, v.isSymbolicLink != true else { return nil }
            return FolderNode(url: url, name: url.lastPathComponent, children: children(of: url, depth: depth + 1))
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func sheets(in folder: URL) -> [SheetItem] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        var items: [SheetItem] = []
        var seen = Set<URL>()
        for url in urls {
            guard let kind = SheetKind(url: url),
                  let v = try? url.resourceValues(forKeys: Set(keys)), v.isDirectory != true else { continue }
            let modified = v.contentModificationDate ?? .distantPast
            let size = v.fileSize ?? 0
            seen.insert(url)
            if let hit = cache[url], hit.modified == modified, hit.size == size {
                items.append(hit); continue
            }
            let name = url.deletingPathExtension().lastPathComponent
            let text = SheetMetaExtractor.plainText(of: url, kind: kind) ?? ""
            let meta = SheetMetaExtractor.meta(text: text, kind: kind, fallbackTitle: name)
            let item = SheetItem(url: url, kind: kind, name: name, title: meta.title, excerpt: meta.excerpt,
                                 words: meta.words, modified: modified, size: size,
                                 searchText: String(text.prefix(200_000)).lowercased())
            cache[url] = item
            items.append(item)
        }
        // Forget files that left this folder so the cache cannot grow forever.
        for key in cache.keys where key.deletingLastPathComponent() == folder && !seen.contains(key) {
            cache[key] = nil
        }
        return items
    }

    static func sort(_ items: [SheetItem], by order: SheetSort) -> [SheetItem] {
        switch order {
        case .modified: return items.sorted { $0.modified > $1.modified }
        case .name: return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    /// Every term must appear in the file name or the body.
    static func filter(_ items: [SheetItem], query: String) -> [SheetItem] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return items }
        return items.filter { item in
            let name = item.name.lowercased()
            return terms.allSatisfy { name.contains($0) || item.searchText.contains($0) }
        }
    }
}
