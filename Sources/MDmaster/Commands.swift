import SwiftUI
import AppKit

private func send(_ selector: Selector) {
    EditorActions.perform(selector)
}

struct FormatCommands: Commands {
    var body: some Commands {
        CommandMenu("Format") {
            Button("Bold") { send(#selector(EditorTextView.mdBold(_:))) }
                .keyboardShortcut("b", modifiers: .command)
            Button("Italic") { send(#selector(EditorTextView.mdItalic(_:))) }
                .keyboardShortcut("i", modifiers: .command)
            Button("Strikethrough") { send(#selector(EditorTextView.mdStrike(_:))) }
                .keyboardShortcut("x", modifiers: [.command, .shift])
            Button("Inline Code") { send(#selector(EditorTextView.mdCode(_:))) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Divider()
            Button("Link") { send(#selector(EditorTextView.mdLink(_:))) }
                .keyboardShortcut("k", modifiers: .command)
            Button("Cycle Heading") { send(#selector(EditorTextView.mdHeadingCycle(_:))) }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Menu("Heading") {
                Button("Heading 1") { send(#selector(EditorTextView.mdHeading1(_:))) }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Button("Heading 2") { send(#selector(EditorTextView.mdHeading2(_:))) }
                    .keyboardShortcut("2", modifiers: [.command, .option])
                Button("Heading 3") { send(#selector(EditorTextView.mdHeading3(_:))) }
                    .keyboardShortcut("3", modifiers: [.command, .option])
            }
            Divider()
            Button("Bulleted List") { send(#selector(EditorTextView.mdBulletList(_:))) }
                .keyboardShortcut("8", modifiers: [.command, .shift])
            Button("Numbered List") { send(#selector(EditorTextView.mdNumberedList(_:))) }
                .keyboardShortcut("7", modifiers: [.command, .shift])
            Button("Checkbox") { send(#selector(EditorTextView.mdCheckbox(_:))) }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Quote") { send(#selector(EditorTextView.mdQuote(_:))) }
        }
    }
}

struct ExportCommands: Commands {
    @FocusedValue(\.editorContext) private var context

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Divider()
            Menu("Export") {
                Button("HTML…") { if let c = context { Exporter.export(.html, context: c) } }
                Button("PDF…") { if let c = context { Exporter.export(.pdf, context: c) } }
                Button("Word (.docx)…") { if let c = context { Exporter.export(.docx, context: c) } }
            }
            .disabled(context == nil)
        }
    }
}

struct ViewCommands: Commands {
    @FocusedBinding(\.writingMode) private var writingMode
    @AppStorage(SettingsKey.typewriter) private var typewriter = false
    @AppStorage(SettingsKey.checkSpelling) private var checkSpelling = true
    @AppStorage(SettingsKey.goalWords) private var goalWords = 0
    @AppStorage(SettingsKey.focusMode) private var focusMode = false
    @AppStorage(SettingsKey.focusScope) private var focusScopeRaw = FocusScope.paragraph.rawValue
    @AppStorage(SettingsKey.showStatusBar) private var showStatusBar = true
    @AppStorage(SettingsKey.fontSize) private var fontSize = 17.0

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Toggle("Writing Mode", isOn: Binding(get: { writingMode ?? false }, set: { writingMode = $0 }))
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(writingMode == nil)
            Toggle("Typewriter Scrolling", isOn: $typewriter)
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Toggle("Dim Everything But Current", isOn: $focusMode)
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Picker("Dim Scope", selection: $focusScopeRaw) {
                ForEach(FocusScope.allCases) { Text($0.label).tag($0.rawValue) }
            }
            Divider()
            Picker("Word Goal", selection: $goalWords) {
                Text("Off").tag(0)
                ForEach([250, 500, 1000, 1500, 2000], id: \.self) { Text($0.formatted()).tag($0) }
                if ![0, 250, 500, 1000, 1500, 2000].contains(goalWords) { Text("\(goalWords.formatted()) (custom)").tag(goalWords) }
            }
            Toggle("Show Word Count", isOn: $showStatusBar)
            Toggle("Check Spelling and Grammar", isOn: $checkSpelling)
            Divider()
            Button("Bigger Text") { fontSize = min(28, fontSize + 1) }
                .keyboardShortcut("=", modifiers: .command)
            Button("Smaller Text") { fontSize = max(12, fontSize - 1) }
                .keyboardShortcut("-", modifiers: .command)
            Button("Default Text Size") { fontSize = 17 }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
        }
    }
}

/// File and layout commands for the library. Replaces the default New/Open group so
/// Cmd-N means "new sheet" while the standalone document keeps a home on Shift-Cmd-N.
struct LibraryCommands: Commands {
    @FocusedValue(\.library) private var library
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Sheet") { library?.newSheet(.markdown) ?? openWindow(id: "library") }
                .keyboardShortcut("n", modifiers: .command)
            Button("New Rich Text Sheet") { library?.newSheet(.rtf) ?? openWindow(id: "library") }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Button("New Folder") { library?.newFolder() }
                .disabled(library == nil)
            Divider()
            Button("New Document") { NSDocumentController.shared.newDocument(nil) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Open…") { NSDocumentController.shared.openDocument(nil) }
                .keyboardShortcut("o", modifiers: .command)
            Menu("Open Recent") {
                // NSDocumentController.shared must not be touched while SwiftUI is still building
                // the menu at launch: it would create a plain controller before SwiftUI installs its own.
                ForEach(AppDelegate.didFinishLaunching ? NSDocumentController.shared.recentDocumentURLs : [], id: \.self) { url in
                    Button(url.lastPathComponent) {
                        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
                    }
                }
            }
            Divider()
            Button("Choose Library Folder…") { library?.chooseRoot() }
                .disabled(library == nil)
            Button("Undo Move to Trash") { library?.undoTrash() }
                .disabled(library?.trashStack.isEmpty ?? true)
        }
        CommandGroup(before: .sidebar) {
            Button("Show Library") { library?.columns = .all }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(library == nil)
            Button("Show Sheet List") { library?.columns = .list }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(library == nil)
            Button("Editor Only") { library?.columns = .editor }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(library == nil)
            Divider()
        }
    }
}
