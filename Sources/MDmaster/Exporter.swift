import AppKit
import WebKit
import UniformTypeIdentifiers

enum ExportKind { case html, pdf, docx }

enum Exporter {
    /// Optional user script that takes `input.md output.docx`. Lets a user apply their own
    /// templates; when unset, DOCX export falls back to plain pandoc.
    static var customConverter: String {
        UserDefaults.standard.string(forKey: SettingsKey.md2docxPath) ?? ""
    }

    // Finder-launched apps get a minimal PATH; pandoc usually lives in Homebrew.
    private static let toolPath = "/opt/homebrew/bin:/usr/local/bin"

    private static var pandocPath: String? {
        toolPath.split(separator: ":").map { "\($0)/pandoc" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func export(_ kind: ExportKind, context: EditorContext) {
        let (type, ext): (UTType, String) = {
            switch kind {
            case .html: return (.html, "html")
            case .pdf: return (.pdf, "pdf")
            case .docx: return (UTType(filenameExtension: "docx") ?? .data, "docx")
            }
        }()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = context.suggestedName + "." + ext
        panel.directoryURL = context.fileURL?.deletingLastPathComponent()
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            switch kind {
            case .html:
                try MarkdownHTML.document(context.text, title: context.suggestedName)
                    .write(to: url, atomically: true, encoding: .utf8)
            case .pdf:
                PDFRenderer.render(html: MarkdownHTML.document(context.text, title: context.suggestedName), to: url) { error in
                    if let error { fail("Could not create the PDF.", error.localizedDescription) }
                }
            case .docx:
                try exportDocx(context.text, to: url)
            }
        } catch {
            fail("Export failed.", error.localizedDescription)
        }
    }

    private static func exportDocx(_ text: String, to url: URL) throws {
        let custom = customConverter
        let executable: String
        let arguments: (_ input: String, _ output: String) -> [String]
        if !custom.isEmpty {
            guard FileManager.default.isExecutableFile(atPath: custom) else {
                fail("DOCX converter not found.", "Expected it at \(custom). Check Preferences > Export."); return
            }
            executable = "/bin/bash"
            arguments = { [custom, $0, $1] }
        } else if let pandoc = pandocPath {
            executable = pandoc
            arguments = { [$0, "-f", "gfm", "-o", $1] }
        } else {
            fail("DOCX export needs pandoc.", "Install it with \"brew install pandoc\", or set your own converter in Preferences > Export."); return
        }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("MDmaster-\(UUID().uuidString)").appendingPathExtension("md")
        try text.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments(tmp.path, url.path)
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = toolPath + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        p.environment = env
        let errPipe = Pipe()
        p.standardError = errPipe
        p.standardOutput = Pipe()
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let msg = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            fail("DOCX export returned an error.", msg.isEmpty ? "Exit code \(p.terminationStatus)" : msg)
        }
    }

    static func fail(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.runModal()
    }
}

/// Loads the HTML in an offscreen WKWebView and prints it to a paginated PDF.
final class PDFRenderer: NSObject, WKNavigationDelegate {
    private static var active: [PDFRenderer] = []
    private let webView: WKWebView
    private let window: NSWindow
    private let url: URL
    private let done: (Error?) -> Void

    static func render(html: String, to url: URL, done: @escaping (Error?) -> Void) {
        let r = PDFRenderer(html: html, url: url, done: done)
        active.append(r)
    }

    private init(html: String, url: URL, done: @escaping (Error?) -> Void) {
        let frame = NSRect(x: 0, y: 0, width: 612, height: 792)
        webView = WKWebView(frame: frame)
        // WKWebView prints blank unless it lives in a window, even an invisible one.
        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = webView
        self.url = url
        self.done = done
        super.init()
        webView.navigationDelegate = self
        webView.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [self] in
            let info = NSPrintInfo(dictionary: NSPrintInfo.shared.dictionary() as! [NSPrintInfo.AttributeKey: Any])
            info.jobDisposition = .save
            info.dictionary().setObject(url, forKey: NSPrintInfo.AttributeKey.jobSavingURL.rawValue as NSString)
            info.topMargin = 54; info.bottomMargin = 54; info.leftMargin = 58; info.rightMargin = 58
            info.horizontalPagination = .fit
            info.verticalPagination = .automatic
            info.isHorizontallyCentered = false
            info.isVerticallyCentered = false
            let op = webView.printOperation(with: info)
            op.showsPrintPanel = false
            op.showsProgressPanel = false
            op.view?.frame = NSRect(origin: .zero, size: info.paperSize)
            op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
            // runModal returns before the file is flushed on some systems; poll briefly.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
                let ok = FileManager.default.fileExists(atPath: url.path)
                done(ok ? nil : NSError(domain: "MDmaster", code: 1,
                                        userInfo: [NSLocalizedDescriptionKey: "The PDF file was not written."]))
                Self.active.removeAll { $0 === self }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        done(error)
        Self.active.removeAll { $0 === self }
    }
}
