import Foundation
import AppKit

enum FileOpsError: LocalizedError {
    case invalidName, exists(String), notFound

    var errorDescription: String? {
        switch self {
        case .invalidName: return "That name isn't allowed. Use at least one character and avoid / and :."
        case .exists(let n): return "Something named \(n) already exists here."
        case .notFound: return "That item no longer exists."
        }
    }
}

enum FileOps {
    /// Folder URLs from directory listings carry a trailing slash and URL equality treats
    /// "a/b" and "a/b/" as different, so every folder URL we hand out is normalised to that form.
    static func dirURL(_ url: URL) -> URL { URL(fileURLWithPath: url.path, isDirectory: true) }

    /// "Untitled.md", then "Untitled 2.md", "Untitled 3.md"...
    static func uniqueURL(in dir: URL, stem: String, ext: String) -> URL {
        let fm = FileManager.default
        func make(_ n: Int) -> URL {
            let name = n == 1 ? stem : "\(stem) \(n)"
            return ext.isEmpty ? dir.appendingPathComponent(name)
                               : dir.appendingPathComponent(name).appendingPathExtension(ext)
        }
        var n = 1
        while fm.fileExists(atPath: make(n).path) { n += 1 }
        return make(n)
    }

    @discardableResult
    static func createSheet(in folder: URL, kind: SheetKind) throws -> URL {
        let url = uniqueURL(in: folder, stem: "Untitled", ext: kind.fileExtension)
        switch kind {
        case .markdown, .text:
            try "".write(to: url, atomically: true, encoding: .utf8)
        case .rtf:
            let empty = NSAttributedString(string: "")
            let data = try empty.data(from: NSRange(location: 0, length: 0),
                                      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            try data.write(to: url, options: .atomic)
        }
        return url
    }

    @discardableResult
    static func createFolder(in parent: URL, name: String = "New Folder") throws -> URL {
        let url = uniqueURL(in: parent, stem: name, ext: "")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return dirURL(url)
    }

    /// `newStem` is the name without extension for files; folders use it whole.
    static func rename(_ url: URL, to newStem: String) throws -> URL {
        let name = newStem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), !name.contains(":"), !name.hasPrefix(".") else {
            throw FileOpsError.invalidName
        }
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { throw FileOpsError.notFound }
        var isDir: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isDir)
        let ext = url.pathExtension
        let target = url.deletingLastPathComponent().appendingPathComponent(
            isDir.boolValue || ext.isEmpty ? name : name + "." + ext)
        let result = isDir.boolValue ? dirURL(target) : target
        if target.path == url.path { return result }
        let caseOnly = target.path.lowercased() == url.path.lowercased()
        if fm.fileExists(atPath: target.path), !caseOnly { throw FileOpsError.exists(target.lastPathComponent) }
        if caseOnly {
            // Case-insensitive volumes refuse a direct case-only rename.
            let tmp = url.deletingLastPathComponent().appendingPathComponent(".rename-\(UUID().uuidString)")
            try fm.moveItem(at: url, to: tmp)
            try fm.moveItem(at: tmp, to: target)
        } else {
            try fm.moveItem(at: url, to: target)
        }
        return result
    }

    /// Returns where the item landed in the Trash, which is what undo needs.
    static func trash(_ url: URL) throws -> URL {
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        guard let trashed = result as URL? else { throw FileOpsError.notFound }
        return trashed
    }

    /// Puts a trashed item back. If the original spot is taken, it gets a unique name.
    static func restore(_ trashed: URL, to original: URL) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: trashed.path) else { throw FileOpsError.notFound }
        var dest = original
        if fm.fileExists(atPath: dest.path) {
            dest = uniqueURL(in: original.deletingLastPathComponent(),
                             stem: original.deletingPathExtension().lastPathComponent,
                             ext: original.pathExtension)
        }
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: trashed, to: dest)
        return dest
    }
}
