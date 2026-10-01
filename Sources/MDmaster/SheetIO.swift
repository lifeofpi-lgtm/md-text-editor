import Foundation

struct DiskSnapshot: Equatable {
    var modified: Date
    var size: Int
}

enum ExternalChange: Equatable {
    case none
    case reload(String)
    case conflict(String)
    case deleted
}

/// Disk access for one open sheet, kept free of UI so it can be tested headlessly.
enum SheetIO {
    static func read(_ url: URL) throws -> String {
        // UTF-8 only: guessing another encoding would silently rewrite the file on save.
        try String(contentsOf: url, encoding: .utf8)
    }

    static func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Uses FileManager, not URL.resourceValues: a URL object caches its resource values, so the
    /// open file's URL would keep reporting the old modification date and outside edits would
    /// never be noticed.
    static func snapshot(_ url: URL) -> DiskSnapshot? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let m = attrs[.modificationDate] as? Date else { return nil }
        return DiskSnapshot(modified: m, size: (attrs[.size] as? Int) ?? 0)
    }

    /// `diskText` nil means the file is gone or unreadable.
    static func evaluate(diskText: String?, lastSaved: String, current: String) -> ExternalChange {
        guard let disk = diskText else { return .deleted }
        if disk == lastSaved { return .none }
        return current == lastSaved ? .reload(disk) : .conflict(disk)
    }
}
