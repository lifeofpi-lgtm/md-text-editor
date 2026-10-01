import SwiftUI

@main
struct MDmasterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The library is the primary window. There is only ever one.
        Window("MDmaster", id: "library") {
            LibraryWindow()
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            LibraryCommands()
            FormatCommands()
            ExportCommands()
            ViewCommands()
        }


        // Files opened from Finder or Cmd-O outside the library keep their own window.
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            EditorView(document: file.$document, fileURL: file.fileURL)
        }
        .defaultSize(width: 780, height: 920)

        Settings { PreferencesView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var didFinishLaunching = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.didFinishLaunching = true
        // A bare SwiftPM executable can launch as a background process; make sure
        // we show up in the Dock and take focus like a normal document app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // SwiftUI's DocumentGroup opens an empty Untitled document at launch regardless of
        // applicationShouldOpenUntitledFile. The library is the front door, so close it if untouched.
        DispatchQueue.main.async {
            for doc in NSDocumentController.shared.documents where doc.fileURL == nil && !doc.isDocumentEdited {
                doc.close()
            }
            NSApp.windows.first { $0.title == "MDmaster" }?.makeKeyAndOrderFront(nil)
        }
    }

    /// The library window is the front door, so don't also open an empty Untitled document.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
}
