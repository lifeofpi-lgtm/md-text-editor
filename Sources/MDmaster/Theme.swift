import AppKit

/// Warm paper-and-ink palette. Every colour is dynamic so the editor follows the
/// system appearance without a redraw pass on our side.
enum Theme {
    static func dynamic(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha)
    }

    static let paper     = dynamic(rgb(0xFBF9F4), rgb(0x1B1A18))
    static let ink       = dynamic(rgb(0x23211D), rgb(0xE7E3DA))
    static let muted     = dynamic(rgb(0x857F74), rgb(0x8F897D))
    static let marker    = dynamic(rgb(0xBDB6A8), rgb(0x5C5850))
    static let accent    = dynamic(rgb(0xB4573E), rgb(0xE28B71))
    static let codeInk   = dynamic(rgb(0x4A463F), rgb(0xCFCAC0))
    static let codeBg    = dynamic(rgb(0xF1EDE4), rgb(0x25241F))
    static let hairline  = dynamic(rgb(0xE8E3D8), rgb(0x2C2A26))
    static let dim       = dynamic(rgb(0xCFCABF), rgb(0x4A4740))
    static let selection = dynamic(rgb(0xB4573E, 0.18), rgb(0xE28B71, 0.26))
}

enum MDAttr {
    /// Marks every character inside a fenced code block so the layout manager can
    /// paint one continuous box behind it.
    static let codeBlock = NSAttributedString.Key("MDmaster.codeBlock")
}
