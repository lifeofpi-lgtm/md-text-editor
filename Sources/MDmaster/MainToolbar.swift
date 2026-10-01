import SwiftUI
import AppKit

/// The library window's toolbar. `toolbar(id:)` plus per-item ids is what lets macOS offer
/// "Customize Toolbar…" and remember the result. Every control is its own item so it has a real
/// name in the palette and for VoiceOver, and can be moved or removed alone. Kept quiet: system
/// symbols, system materials, and the terracotta accent only for active states.
struct MainToolbar: CustomizableToolbarContent {
    @ObservedObject var store: LibraryStore
    @ObservedObject var session: SheetSession
    @ObservedObject var ui: WindowState

    var body: some CustomizableToolbarContent {
        LeftToolbarItems(store: store)
        FormatToolbarItems(format: ui.format, enabled: session.isEditable)
        RightToolbarItems(store: store, session: session, ui: ui)
    }
}

struct LeftToolbarItems: CustomizableToolbarContent {
    let store: LibraryStore

    var body: some CustomizableToolbarContent {
        ToolbarItem(id: "newSheet", placement: .navigation) {
            Menu {
                Button("Markdown Sheet") { store.newSheet(.markdown) }
                Button("Rich Text Sheet") { store.newSheet(.rtf) }
            } label: {
                Label("New Sheet", systemImage: "square.and.pencil")
            }
            .help("New Sheet  (⌘N, rich text ⌥⌘N)")
        }
        ToolbarItem(id: "newFolder", placement: .navigation) {
            Button { store.newFolder() } label: { Label("New Folder", systemImage: "folder.badge.plus") }
                .help("New Folder")
        }
    }
}

/// The formatting buttons. Each calls the same editor action the Format menu calls, so there is
/// one implementation of each format. Active formats get the accent colour.
struct FormatToolbarItems: CustomizableToolbarContent {
    let format: FormatState
    let enabled: Bool

    var body: some CustomizableToolbarContent {
        item("bold", "Bold", "bold", "⌘B", format.bold, #selector(EditorTextView.mdBold(_:)))
        item("italic", "Italic", "italic", "⌘I", format.italic, #selector(EditorTextView.mdItalic(_:)))
        item("strike", "Strikethrough", "strikethrough", "⇧⌘X", format.strike, #selector(EditorTextView.mdStrike(_:)))
        ToolbarItem(id: "heading", placement: .automatic) {
            Menu {
                headingItem("Heading 1", 1, #selector(EditorTextView.mdHeading1(_:)))
                headingItem("Heading 2", 2, #selector(EditorTextView.mdHeading2(_:)))
                headingItem("Heading 3", 3, #selector(EditorTextView.mdHeading3(_:)))
            } label: {
                Label("Heading", systemImage: "textformat.size")
                    .foregroundStyle(tint(format.heading > 0))
            }
            .disabled(!enabled)
            .help("Heading")
        }
        item("bullet", "Bulleted List", "list.bullet", "⇧⌘8", format.bullet, #selector(EditorTextView.mdBulletList(_:)))
        item("numbered", "Numbered List", "list.number", "⇧⌘7", format.numbered, #selector(EditorTextView.mdNumberedList(_:)))
        item("checkbox", "Checkbox", "checklist", "⇧⌘L", format.checkbox, #selector(EditorTextView.mdCheckbox(_:)))
        item("link", "Link", "link", "⌘K", format.link, #selector(EditorTextView.mdLink(_:)))
        item("code", "Inline Code", "chevron.left.forwardslash.chevron.right", "⇧⌘C", format.code, #selector(EditorTextView.mdCode(_:)))
        item("quote", "Quote", "text.quote", "", format.quote, #selector(EditorTextView.mdQuote(_:)))
    }

    /// The system's own primary style for inactive buttons: an explicit Color.primary would stop
    /// disabled buttons from dimming.
    private func tint(_ active: Bool) -> AnyShapeStyle {
        active ? AnyShapeStyle(Color(nsColor: Theme.accent)) : AnyShapeStyle(.primary)
    }

    private func item(_ id: String, _ title: String, _ icon: String, _ shortcut: String, _ active: Bool,
                      _ sel: Selector) -> some CustomizableToolbarContent {
        ToolbarItem(id: id, placement: .automatic) {
            // A toggle button is the system's own on/off state for toolbars; foreground colours
            // on a plain toolbar button are ignored. Tapping always performs the editor action,
            // and the state is read back from the caret, so the toggle never drifts.
            Toggle(isOn: Binding(get: { active }, set: { _ in EditorActions.perform(sel) })) {
                Label(title, systemImage: icon)
            }
            .toggleStyle(.button)
            .tint(Color(nsColor: Theme.accent))
            .disabled(!enabled)
            .help(shortcut.isEmpty ? title : "\(title)  (\(shortcut))")
        }
    }

    private func headingItem(_ title: String, _ level: Int, _ sel: Selector) -> some View {
        Button { EditorActions.perform(sel) } label: {
            if format.heading == level { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }
}

struct RightToolbarItems: CustomizableToolbarContent {
    let store: LibraryStore
    @ObservedObject var session: SheetSession
    @ObservedObject var ui: WindowState
    @AppStorage(SettingsKey.goalWords) private var goalWords = 0
    @AppStorage(SettingsKey.goalBasis) private var goalBasisRaw = GoalBasis.session.rawValue

    private var goalProgress: Double {
        guard goalWords > 0 else { return 0 }
        let basis = GoalBasis(rawValue: goalBasisRaw) ?? .session
        return min(1, Double(basis == .session ? ui.written : ui.words) / Double(goalWords))
    }

    var body: some CustomizableToolbarContent {
        ToolbarItem(id: "goal", placement: .primaryAction) {
            Button { ui.showGoal.toggle() } label: {
                Label { Text("Word Goal") } icon: { GoalRing(progress: goalProgress, hasGoal: goalWords > 0, size: 16) }
            }
            .help(goalWords > 0 ? "Word goal: \(Int(goalProgress * 100))%" : "Set a word goal")
            .popover(isPresented: $ui.showGoal, arrowEdge: .bottom) { WordGoalPopover(ui: ui) }
        }
        ToolbarItem(id: "writingMode", placement: .primaryAction) {
            Button { ui.writingMode.toggle() } label: {
                Label("Writing Mode", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .help("Writing Mode  (⇧⌘F)")
            .disabled(!session.isEditable)
        }
        ToolbarItem(id: "export", placement: .primaryAction) {
            Menu {
                Button("HTML…") { export(.html) }
                Button("PDF…") { export(.pdf) }
                Button("Word (.docx)…") { export(.docx) }
                    .disabled(session.kind == .rtf) // DOCX goes through md2docx, which reads markdown
            } label: {
                Label("Export", systemImage: "square.and.arrow.down")
            }
            .disabled(session.url == nil)
            .help("Export")
        }
        ToolbarItem(id: "share", placement: .primaryAction) {
            if let url = session.url {
                ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                    // Make sure what is shared is what is on screen.
                    .simultaneousGesture(TapGesture().onEnded { session.flush() })
                    .help("Share")
            } else {
                Button {} label: { Label("Share", systemImage: "square.and.arrow.up") }.disabled(true)
            }
        }
    }

    private func export(_ kind: ExportKind) {
        guard let url = session.url else { return }
        session.flush()
        Exporter.export(kind, context: EditorContext(text: session.text, fileURL: url))
    }
}

struct GoalRing: View {
    let progress: Double
    let hasGoal: Bool
    var size: CGFloat = 16
    var line: CGFloat = 2.5

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.35), lineWidth: line)
            if hasGoal {
                Circle().trim(from: 0, to: max(0.02, progress))
                    .stroke(Color(nsColor: Theme.accent), style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.3), value: progress)
    }
}

struct WordGoalPopover: View {
    @ObservedObject var ui: WindowState
    @AppStorage(SettingsKey.goalWords) private var goalWords = 0
    @AppStorage(SettingsKey.goalBasis) private var goalBasisRaw = GoalBasis.session.rawValue

    private var basis: GoalBasis { GoalBasis(rawValue: goalBasisRaw) ?? .session }
    private var done: Int { basis == .session ? ui.written : ui.words }
    private var progress: Double { goalWords > 0 ? min(1, Double(done) / Double(goalWords)) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    GoalRing(progress: progress, hasGoal: goalWords > 0, size: 64, line: 6)
                    Text(goalWords > 0 ? "\(Int((progress * 100).rounded()))%" : "Off")
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(goalWords > 0 ? "\(done.formatted()) of \(goalWords.formatted())" : "No goal set")
                        .font(.headline)
                    Text(basis == .session ? "words written this session" : "words in this sheet")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                ForEach([0, 250, 500, 1000, 2000], id: \.self) { n in
                    Button(n == 0 ? "Off" : n.formatted()) { goalWords = n }
                        .buttonStyle(.bordered)
                        .tint(goalWords == n ? Color(nsColor: Theme.accent) : nil)
                        .controlSize(.small)
                }
            }
            TextField("Custom goal", value: $goalWords, format: .number)
                .textFieldStyle(.roundedBorder)
            Picker("Counts", selection: $goalBasisRaw) {
                ForEach(GoalBasis.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
        }
        .padding(16)
        .frame(width: 280)
    }
}
