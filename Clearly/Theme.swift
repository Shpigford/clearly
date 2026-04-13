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
            ? NSColor(red: 0.196, green: 0.196, blue: 0.21, alpha: 1)  // #323236
            : NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1)
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

    static let highlightColor = NSColor(name: "themeHighlight") { appearance in
        appearance.isDark
            ? NSColor(red: 0.9, green: 0.8, blue: 0.3, alpha: 1)
            : NSColor(red: 0.6, green: 0.5, blue: 0.0, alpha: 1)
    }

    static let highlightBackgroundColor = NSColor(name: "themeHighlightBg") { appearance in
        appearance.isDark
            ? NSColor(red: 0.9, green: 0.8, blue: 0.3, alpha: 0.15)
            : NSColor(red: 1.0, green: 0.9, blue: 0.0, alpha: 0.25)
    }

    static let footnoteColor = NSColor(name: "themeFootnote") { appearance in
        appearance.isDark
            ? NSColor(red: 0.6, green: 0.7, blue: 0.9, alpha: 1)
            : NSColor(red: 0.3, green: 0.4, blue: 0.7, alpha: 1)
    }

    static let htmlTagColor = NSColor(name: "themeHTMLTag") { appearance in
        appearance.isDark
            ? NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
            : NSColor(red: 0.55, green: 0.55, blue: 0.55, alpha: 1)
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

    // MARK: - Accent Color

    static let accentColor = NSColor(name: "themeAccent") { appearance in
        appearance.isDark
            ? NSColor(red: 0.353, green: 0.604, blue: 1.0, alpha: 1)    // #5A9AFF
            : NSColor(red: 0.231, green: 0.482, blue: 0.965, alpha: 1)  // #3B7BF6
    }

    static var accentColorSwiftUI: Color { Color(nsColor: accentColor) }

    // MARK: - Panel Backgrounds

    static let sidebarBackground = NSColor(name: "themeSidebar") { appearance in
        appearance.isDark
            ? NSColor(red: 0.157, green: 0.157, blue: 0.169, alpha: 1)  // #28282B
            : NSColor(red: 0.945, green: 0.945, blue: 0.95, alpha: 1)   // #F1F1F2
    }

    static var sidebarBackgroundSwiftUI: Color { Color(nsColor: sidebarBackground) }

    static let outlinePanelBackground = NSColor(name: "themeOutlinePanel") { appearance in
        appearance.isDark
            ? NSColor(red: 0.157, green: 0.157, blue: 0.169, alpha: 1)  // #28282B — match sidebar
            : NSColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1)     // #FAFAFA
    }

    static var outlinePanelBackgroundSwiftUI: Color { Color(nsColor: outlinePanelBackground) }

    // MARK: - Separators

    static let separatorOpacity: Double = 0.06
    static let separatorOpacityDark: Double = 0.10
    static let structuralSeparatorOpacity: Double = 0.10
    static let structuralSeparatorOpacityDark: Double = 0.15

    // MARK: - Hover & Selection

    static let hoverOpacity: Double = 0.06
    static let hoverOpacityDark: Double = 0.08
    static let selectionOpacity: Double = 0.15
    static let selectionOpacityDark: Double = 0.22

    // MARK: - Folder Colors

    static let folderColorPalette: [(name: String, color: NSColor)] = [
        ("red",    NSColor(red: 0.90, green: 0.30, blue: 0.28, alpha: 1)),
        ("orange", NSColor(red: 0.92, green: 0.55, blue: 0.22, alpha: 1)),
        ("yellow", NSColor(red: 0.88, green: 0.75, blue: 0.20, alpha: 1)),
        ("green",  NSColor(red: 0.35, green: 0.75, blue: 0.40, alpha: 1)),
        ("teal",   NSColor(red: 0.25, green: 0.70, blue: 0.70, alpha: 1)),
        ("blue",   NSColor(red: 0.30, green: 0.55, blue: 0.90, alpha: 1)),
        ("purple", NSColor(red: 0.60, green: 0.40, blue: 0.85, alpha: 1)),
        ("pink",   NSColor(red: 0.85, green: 0.40, blue: 0.60, alpha: 1)),
    ]

    static func folderColor(named name: String) -> NSColor? {
        folderColorPalette.first { $0.name == name }?.color
    }

    // MARK: - Motion Presets

    enum Motion {
        /// Quick feedback: button hovers, toggle states
        static let snappy = Animation.spring(response: 0.25, dampingFraction: 0.85)
        /// Primary transitions: segmented control slide, panel show/hide
        static let smooth = Animation.spring(response: 0.35, dampingFraction: 0.75)
        /// Ambient: empty state pulse, section expand
        static let gentle = Animation.spring(response: 0.50, dampingFraction: 0.80)
        /// Hover backgrounds — instant-feeling
        static let hover = Animation.easeOut(duration: 0.15)
    }
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
