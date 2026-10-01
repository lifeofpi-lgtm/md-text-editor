import SwiftUI

struct PreferencesView: View {
    @AppStorage(SettingsKey.serif) private var serif = false
    @AppStorage(SettingsKey.lineWidth) private var lineWidth = LineWidth.medium.rawValue
    @AppStorage(SettingsKey.fontSize) private var fontSize = 17.0
    @AppStorage(SettingsKey.focusScope) private var focusScopeRaw = FocusScope.paragraph.rawValue
    @AppStorage(SettingsKey.goalWords) private var goalWords = 0
    @AppStorage(SettingsKey.goalBasis) private var goalBasisRaw = GoalBasis.session.rawValue
    @AppStorage(SettingsKey.md2docxPath) private var md2docxPath = ""

    var body: some View {
        Form {
            Section("Page") {
                Picker("Typeface", selection: $serif) {
                    Text("Sans (SF Pro)").tag(false)
                    Text("Serif (New York)").tag(true)
                }
                Picker("Line width", selection: $lineWidth) {
                    ForEach(LineWidth.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Stepper("Text size: \(Int(fontSize)) pt", value: $fontSize, in: 12...28)
                Picker("Dim scope", selection: $focusScopeRaw) {
                    ForEach(FocusScope.allCases) { Text($0.label).tag($0.rawValue) }
                }
            }
            Section("Goal") {
                TextField("Word goal (0 is off)", value: $goalWords, format: .number)
                Picker("Counts", selection: $goalBasisRaw) {
                    ForEach(GoalBasis.allCases) { Text($0.label).tag($0.rawValue) }
                }
            }
            Section("Export") {
                TextField("Custom DOCX converter", text: $md2docxPath,
                          prompt: Text("Optional script path"))
                Text("Leave empty to use pandoc. A custom script is called as: script input.md output.docx")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
