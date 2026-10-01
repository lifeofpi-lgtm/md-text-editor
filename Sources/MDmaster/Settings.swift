import SwiftUI

enum SettingsKey {
    static let focusMode = "focusMode"
    static let focusScope = "focusScope"
    static let showStatusBar = "showStatusBar"
    static let fontSize = "fontSize"
    static let typewriter = "typewriter"
    static let checkSpelling = "checkSpelling"
    static let serif = "serifBody"
    static let lineWidth = "lineWidth"
    static let goalWords = "goalWords"
    static let goalBasis = "goalBasis"
    static let md2docxPath = "md2docxPath"
    static let libraryRoot = "libraryRoot"
    static let libraryFolder = "libraryFolder"
    static let librarySheet = "librarySheet"
    static let libraryExpanded = "libraryExpanded"
    static let librarySort = "librarySort"
    static let libraryColumns = "libraryColumns"
}

extension Notification.Name {
    /// Asks the editor in the key window to take keyboard focus (after New Sheet).
    static let mdFocusEditor = Notification.Name("MDmaster.focusEditor")
}

/// Goals count what you typed this session by default: deleting never lowers
/// progress, and a long existing file does not start the day already "done".
enum GoalBasis: String, CaseIterable, Identifiable {
    case session, document
    var id: String { rawValue }
    var label: String { self == .session ? "Words written this session" : "Total words in document" }
}

enum LineWidth: Double, CaseIterable, Identifiable {
    case narrow = 560, medium = 680, wide = 820
    var id: Double { rawValue }
    var label: String {
        switch self { case .narrow: "Narrow"; case .medium: "Medium"; case .wide: "Wide" }
    }
}

enum FocusScope: String, CaseIterable, Identifiable {
    case paragraph, sentence
    var id: String { rawValue }
    var label: String { self == .paragraph ? "Paragraph" : "Sentence" }
}

/// What the menu commands need from the frontmost editor.
struct EditorContext {
    var text: String
    var fileURL: URL?

    var suggestedName: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }
}

private struct EditorContextKey: FocusedValueKey {
    typealias Value = EditorContext
}

private struct WritingModeKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

private struct LibraryKey: FocusedValueKey {
    typealias Value = LibraryStore
}

extension FocusedValues {
    var library: LibraryStore? {
        get { self[LibraryKey.self] }
        set { self[LibraryKey.self] = newValue }
    }

    var writingMode: Binding<Bool>? {
        get { self[WritingModeKey.self] }
        set { self[WritingModeKey.self] = newValue }
    }

    var editorContext: EditorContext? {
        get { self[EditorContextKey.self] }
        set { self[EditorContextKey.self] = newValue }
    }
}
