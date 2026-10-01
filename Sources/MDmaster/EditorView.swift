import SwiftUI
import AppKit

/// Word counts that live outside the text view. "Written" only ever goes up, so
/// deleting a paragraph never lowers a goal you already earned.
@MainActor
final class WritingStats: ObservableObject {
    @Published var words = 0
    @Published var written = 0
    private var lastCount: Int?
    private var pending: Task<Void, Never>?

    static func count(_ text: String) -> Int {
        var n = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in n += 1 }
        return n
    }

    /// Debounced: recounting a long document on every keystroke is wasted work.
    func update(_ text: String) {
        if lastCount == nil { // first call: opening a file is not writing
            let n = Self.count(text)
            words = n; lastCount = n
            return
        }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            let n = Self.count(text)
            if let last = self.lastCount, n > last { self.written += n - last }
            self.lastCount = n
            self.words = n
        }
    }
}

@MainActor
final class WindowState: ObservableObject {
    @Published var writingMode = false
    @Published var chromeVisible = false
    @Published var selectedWords = 0
    /// Toolbar state, filled in by the editor so window-level chrome can reflect it.
    @Published var format = FormatState()
    @Published var words = 0
    @Published var written = 0
    @Published var showGoal = false
    var hideTask: Task<Void, Never>?
}

/// The single-file window opened from Finder or Cmd-O (the DocumentGroup).
struct EditorView: View {
    @Binding var document: MarkdownDocument
    var fileURL: URL?
    @StateObject private var ui = WindowState()

    var body: some View {
        EditorSurface(text: $document.text, fileURL: fileURL, ui: ui, isLibrary: false)
    }
}

/// Editor, status bar and goal line. Shared by document windows and the library's editor pane.
struct EditorSurface: View {
    @Binding var text: String
    var fileURL: URL?
    @ObservedObject var ui: WindowState
    /// In the library the window belongs to the split view, so the editor must not repaint
    /// the title bar, and must not grab focus from the sheet list on every sheet change.
    var isLibrary = false

    @AppStorage(SettingsKey.focusMode) private var focusMode = false
    @AppStorage(SettingsKey.focusScope) private var focusScopeRaw = FocusScope.paragraph.rawValue
    @AppStorage(SettingsKey.showStatusBar) private var showStatusBar = true
    @AppStorage(SettingsKey.fontSize) private var fontSize = 17.0
    @AppStorage(SettingsKey.typewriter) private var typewriter = false
    @AppStorage(SettingsKey.checkSpelling) private var checkSpelling = true
    @AppStorage(SettingsKey.serif) private var serif = false
    @AppStorage(SettingsKey.lineWidth) private var lineWidth = LineWidth.medium.rawValue
    @AppStorage(SettingsKey.goalWords) private var goalWords = 0
    @AppStorage(SettingsKey.goalBasis) private var goalBasisRaw = GoalBasis.session.rawValue

    // @State is a macro in the current SDK and the plugin is missing without Xcode,
    // so per-window UI state lives in an observable object instead.
    @StateObject private var stats = WritingStats()

    private var writingMode: Bool { ui.writingMode }
    private var chromeVisible: Bool { ui.chromeVisible }
    private var selectedWords: Int { ui.selectedWords }

    private var goalProgress: Double {
        guard goalWords > 0 else { return 0 }
        let basis = GoalBasis(rawValue: goalBasisRaw) ?? .session
        let done = basis == .session ? stats.written : stats.words
        return min(1, Double(done) / Double(goalWords))
    }

    private var statusVisible: Bool {
        showStatusBar && !focusMode && (!writingMode || chromeVisible)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            MarkdownTextView(text: $text,
                             fontSize: CGFloat(fontSize),
                             focusMode: focusMode,
                             focusScope: FocusScope(rawValue: focusScopeRaw) ?? .paragraph,
                             typewriter: typewriter,
                             serif: serif,
                             columnWidth: CGFloat(lineWidth),
                             checkSpelling: checkSpelling,
                             selectedWords: $ui.selectedWords,
                             formatState: $ui.format,
                             ownsWindowChrome: !isLibrary,
                             grabsFocus: !isLibrary)
            VStack(spacing: 0) {
                if statusVisible {
                    StatusBar(words: stats.words, text: text,
                              written: stats.written, selectedWords: selectedWords,
                              goal: goalWords, progress: goalProgress)
                        .transition(.opacity)
                }
                // Goal progress stays on in Writing Mode: it is the one piece of chrome
                // that tells you something while you type.
                if goalWords > 0 { GoalHairline(progress: goalProgress) }
            }
        }
        .background(Color(nsColor: Theme.paper))
        .animation(.easeOut(duration: 0.18), value: focusMode)
        .animation(.easeOut(duration: 0.18), value: showStatusBar)
        .animation(.easeOut(duration: 0.25), value: ui.chromeVisible)
        .onContinuousHover { phase in
            if case .active = phase { revealChrome() }
        }
        .onAppear { stats.update(text) }
        .onChange(of: text) { _, new in stats.update(new) }
        .onChange(of: stats.words) { _, n in ui.words = n }
        .onChange(of: stats.written) { _, n in ui.written = n }
        .onDisappear { ui.words = 0; ui.written = 0; ui.format = FormatState() }
        .onChange(of: ui.writingMode) { _, on in setFullScreen(on) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { note in
            // Leaving full screen by the green button or Esc also leaves Writing Mode.
            if (note.object as? NSWindow) === NSApp.keyWindow { ui.writingMode = false }
        }
        .focusedSceneValue(\.editorContext, EditorContext(text: text, fileURL: fileURL))
        .focusedSceneValue(\.writingMode, $ui.writingMode)
    }

    private func revealChrome() {
        guard ui.writingMode else { return }
        ui.chromeVisible = true
        ui.hideTask?.cancel()
        ui.hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { ui.chromeVisible = false }
        }
    }

    private func setFullScreen(_ on: Bool) {
        guard let window = NSApp.keyWindow else { return }
        if on != window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        window.titleVisibility = on ? .hidden : .visible
        ui.chromeVisible = false
    }
}

struct GoalHairline: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color(nsColor: Theme.hairline))
                Rectangle().fill(Color(nsColor: Theme.accent))
                    .frame(width: geo.size.width * progress)
                    .animation(.easeOut(duration: 0.4), value: progress)
            }
        }
        .frame(height: 2)
    }
}

struct StatusBar: View {
    let words: Int
    let text: String
    let written: Int
    let selectedWords: Int
    let goal: Int
    let progress: Double

    private var minutes: Int { words == 0 ? 0 : max(1, Int((Double(words) / 230.0).rounded(.up))) }

    var body: some View {
        HStack(spacing: 0) {
            if selectedWords > 0 {
                Text("\(selectedWords.formatted()) of \(words.formatted()) words")
            } else {
                Text("\(words.formatted()) words")
            }
            sep
            Text("\(text.count.formatted()) characters")
            if minutes > 0 {
                sep
                Text("\(minutes) min read")
            }
            if written > 0 {
                sep
                Text("\(written.formatted()) written")
            }
            Spacer()
            if goal > 0 {
                Text("\(Int((progress * 100).rounded()))% of \(goal.formatted())")
                    .foregroundStyle(Color(nsColor: progress >= 1 ? Theme.accent : Theme.muted))
            }
        }
        .font(.system(size: 11.5, weight: .medium).monospacedDigit())
        .foregroundStyle(Color(nsColor: Theme.muted))
        .padding(.horizontal, 22)
        .padding(.vertical, 7)
        .background(Color(nsColor: Theme.paper))
        .overlay(alignment: .top) {
            Rectangle().fill(Color(nsColor: Theme.hairline)).frame(height: 1)
        }
    }

    private var sep: some View {
        Text("·")
            .foregroundStyle(Color(nsColor: Theme.marker))
            .padding(.horizontal, 7)
    }
}
