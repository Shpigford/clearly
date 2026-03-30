import AppKit
import SwiftUI

enum Theme {
    // MARK: - Editor Font
    static var editorFontSize: CGFloat {
        let size = UserDefaults.standard.double(forKey: "editorFontSize")
        return size > 0 ? CGFloat(size) : 16
    }
    static var editorFont: NSFont { NSFont.monospacedSystemFont(ofSize: editorFontSize, weight: .regular) }
    static var editorFontSwiftUI: Font { Font.system(size: editorFontSize, design: .monospaced) }

    // MARK: - Margins
    static let editorInsetX: CGFloat = 60
    static let editorInsetTop: CGFloat = 10
    static let editorInsetBottom: CGFloat = 40

    // MARK: - Line Spacing
    static let lineSpacing: CGFloat = 8

    /// Desired line height = font natural height + lineSpacing
    static var editorLineHeight: CGFloat {
        let font = editorFont
        return ceil(font.ascender - font.descender + font.leading) + lineSpacing
    }

    /// Baseline offset to vertically center text within the line height
    static var editorBaselineOffset: CGFloat {
        let font = editorFont
        let naturalHeight = ceil(font.ascender - font.descender + font.leading)
        return (editorLineHeight - naturalHeight) / 2
    }

    // MARK: - Dynamic Colors (auto-resolve for light/dark)

    static let backgroundColor = NSColor(name: "themeBackground") { appearance in
        appearance.isDark
            ? NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
            : NSColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1)
    }

    static let textColor = NSColor(name: "themeText") { appearance in
        appearance.isDark
            ? NSColor(red: 0.878, green: 0.878, blue: 0.878, alpha: 1)
            : NSColor(red: 0.133, green: 0.133, blue: 0.133, alpha: 1)
    }

    static let syntaxColor = NSColor(name: "themeSyntax") { appearance in
        appearance.isDark
            ? NSColor(red: 0.45, green: 0.45, blue: 0.45, alpha: 1)
            : NSColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1)
    }

    static let headingColor = NSColor(name: "themeHeading") { appearance in
        appearance.isDark
            ? NSColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1)
            : NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
    }

    static let boldColor = NSColor(name: "themeBold") { appearance in
        appearance.isDark
            ? NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1)
            : NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1)
    }

    static let italicColor = NSColor(name: "themeItalic") { appearance in
        appearance.isDark
            ? NSColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1)
            : NSColor(red: 0.25, green: 0.25, blue: 0.25, alpha: 1)
    }

    static let codeColor = NSColor(name: "themeCode") { appearance in
        appearance.isDark
            ? NSColor(red: 0.9, green: 0.45, blue: 0.45, alpha: 1)
            : NSColor(red: 0.75, green: 0.2, blue: 0.2, alpha: 1)
    }

    static let linkColor = NSColor(name: "themeLink") { appearance in
        appearance.isDark
            ? NSColor(red: 0.4, green: 0.6, blue: 0.9, alpha: 1)
            : NSColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 1)
    }

    static let mathColor = NSColor(name: "themeMath") { appearance in
        appearance.isDark
            ? NSColor(red: 0.7, green: 0.5, blue: 0.9, alpha: 1)
            : NSColor(red: 0.5, green: 0.25, blue: 0.7, alpha: 1)
    }

    static let blockquoteColor = NSColor(name: "themeBlockquote") { appearance in
        appearance.isDark
            ? NSColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1)
            : NSColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1)
    }

    static let frontmatterColor = NSColor(name: "themeFrontmatter") { appearance in
        appearance.isDark
            ? NSColor(red: 0.55, green: 0.55, blue: 0.65, alpha: 1)
            : NSColor(red: 0.35, green: 0.35, blue: 0.5, alpha: 1)
    }

    static let findHighlightColor = NSColor(name: "themeFindHighlight") { appearance in
        appearance.isDark
            ? NSColor(red: 0.6, green: 0.5, blue: 0.0, alpha: 0.3)
            : NSColor(red: 1.0, green: 0.9, blue: 0.0, alpha: 0.4)
    }

    static let findCurrentHighlightColor = NSColor(name: "themeFindCurrentHighlight") { appearance in
        appearance.isDark
            ? NSColor(red: 0.8, green: 0.6, blue: 0.0, alpha: 0.5)
            : NSColor(red: 1.0, green: 0.7, blue: 0.0, alpha: 0.6)
    }

    static var backgroundColorSwiftUI: Color { Color(nsColor: backgroundColor) }
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
