import SwiftUI

public enum Theme {
    // MARK: - Editor Font
    public static var editorFontSize: CGFloat {
        let size = UserDefaults.standard.double(forKey: "editorFontSize")
        return size > 0 ? CGFloat(size) : 12
    }

    public static var editorFont: PlatformFont {
        PlatformFont.clearlyMonospacedSystemFont(ofSize: editorFontSize, weight: .regular)
    }

    public static var editorFontSwiftUI: Font { Font.system(size: editorFontSize, design: .monospaced) }

    // MARK: - Margins
    public static let editorInsetX: CGFloat = 60
    public static let editorInsetTop: CGFloat = 10
    public static let editorInsetBottom: CGFloat = 40

    // MARK: - Line Spacing
    public static let lineSpacing: CGFloat = 8

    /// Desired line height = font natural height + lineSpacing
    public static var editorLineHeight: CGFloat {
        let font = editorFont
        return ceil(font.ascender - font.descender + font.leading) + lineSpacing
    }

    /// Baseline offset to vertically center text within the line height
    public static var editorBaselineOffset: CGFloat {
        let font = editorFont
        let naturalHeight = ceil(font.ascender - font.descender + font.leading)
        return (editorLineHeight - naturalHeight) / 2
    }

    // MARK: - Dynamic Colors (auto-resolve for light/dark)

    public static let backgroundColor = PlatformColor.clearlyDynamic(
        name: "themeBackground",
        light: (1.0, 1.0, 1.0, 1),
        dark: (0.196, 0.196, 0.21, 1)
    )

    public static let textColor = PlatformColor.clearlyDynamic(
        name: "themeText",
        light: (0.133, 0.133, 0.133, 1),
        dark: (0.878, 0.878, 0.878, 1)
    )

    public static let syntaxColor = PlatformColor.clearlyDynamic(
        name: "themeSyntax",
        light: (0.6, 0.6, 0.6, 1),
        dark: (0.45, 0.45, 0.45, 1)
    )

    public static let headingColor = PlatformColor.clearlyDynamic(
        name: "themeHeading",
        light: (0.1, 0.1, 0.1, 1),
        dark: (0.95, 0.95, 0.95, 1)
    )

    public static let boldColor = PlatformColor.clearlyDynamic(
        name: "themeBold",
        light: (0.15, 0.15, 0.15, 1),
        dark: (0.9, 0.9, 0.9, 1)
    )

    public static let italicColor = PlatformColor.clearlyDynamic(
        name: "themeItalic",
        light: (0.25, 0.25, 0.25, 1),
        dark: (0.8, 0.8, 0.8, 1)
    )

    public static let codeColor = PlatformColor.clearlyDynamic(
        name: "themeCode",
        light: (0.75, 0.2, 0.2, 1),
        dark: (0.9, 0.45, 0.45, 1)
    )

    public static let linkColor = PlatformColor.clearlyDynamic(
        name: "themeLink",
        light: (0.2, 0.4, 0.7, 1),
        dark: (0.4, 0.6, 0.9, 1)
    )

    public static let mathColor = PlatformColor.clearlyDynamic(
        name: "themeMath",
        light: (0.5, 0.25, 0.7, 1),
        dark: (0.7, 0.5, 0.9, 1)
    )

    public static let blockquoteColor = PlatformColor.clearlyDynamic(
        name: "themeBlockquote",
        light: (0.4, 0.4, 0.4, 1),
        dark: (0.6, 0.6, 0.6, 1)
    )

    public static let frontmatterColor = PlatformColor.clearlyDynamic(
        name: "themeFrontmatter",
        light: (0.35, 0.35, 0.5, 1),
        dark: (0.55, 0.55, 0.65, 1)
    )

    public static let highlightColor = PlatformColor.clearlyDynamic(
        name: "themeHighlight",
        light: (0.6, 0.5, 0.0, 1),
        dark: (0.9, 0.8, 0.3, 1)
    )

    public static let highlightBackgroundColor = PlatformColor.clearlyDynamic(
        name: "themeHighlightBg",
        light: (1.0, 0.9, 0.0, 0.25),
        dark: (0.9, 0.8, 0.3, 0.15)
    )

    public static let footnoteColor = PlatformColor.clearlyDynamic(
        name: "themeFootnote",
        light: (0.3, 0.4, 0.7, 1),
        dark: (0.6, 0.7, 0.9, 1)
    )

    public static let wikiLinkColor = PlatformColor.clearlyDynamic(
        name: "themeWikiLink",
        light: (0.2, 0.55, 0.35, 1),
        dark: (0.35, 0.75, 0.50, 1)
    )

    public static let wikiLinkBrokenColor = PlatformColor.clearlyDynamic(
        name: "themeWikiLinkBroken",
        light: (0.7, 0.35, 0.25, 1),
        dark: (0.85, 0.45, 0.35, 1)
    )

    public static let tagColor = PlatformColor.clearlyDynamic(
        name: "themeTag",
        light: (0.25, 0.45, 0.70, 1),
        dark: (0.55, 0.70, 0.85, 1)
    )

    public static let htmlTagColor = PlatformColor.clearlyDynamic(
        name: "themeHTMLTag",
        light: (0.55, 0.55, 0.55, 1),
        dark: (0.5, 0.5, 0.5, 1)
    )

    public static let findHighlightColor = PlatformColor.clearlyDynamic(
        name: "themeFindHighlight",
        light: (1.0, 0.9, 0.0, 0.4),
        dark: (0.6, 0.5, 0.0, 0.3)
    )

    public static let findCurrentHighlightColor = PlatformColor.clearlyDynamic(
        name: "themeFindCurrentHighlight",
        light: (1.0, 0.7, 0.0, 0.6),
        dark: (0.8, 0.6, 0.0, 0.5)
    )

    public static var backgroundColorSwiftUI: Color { Color(platformColor: backgroundColor) }

    // MARK: - Accent Color

    public static let accentColor = PlatformColor.clearlyDynamic(
        name: "themeAccent",
        light: (0.231, 0.482, 0.965, 1),
        dark: (0.353, 0.604, 1.0, 1)
    )

    public static var accentColorSwiftUI: Color { Color(platformColor: accentColor) }

    // MARK: - Panel Backgrounds

    public static let sidebarBackground = PlatformColor.clearlyDynamic(
        name: "themeSidebar",
        light: (0.945, 0.945, 0.95, 1),
        dark: (0.157, 0.157, 0.169, 1)
    )

    public static var sidebarBackgroundSwiftUI: Color { Color(platformColor: sidebarBackground) }

    public static let outlinePanelBackground = PlatformColor.clearlyDynamic(
        name: "themeOutlinePanel",
        light: (0.98, 0.98, 0.98, 1),
        dark: (0.157, 0.157, 0.169, 1)
    )

    public static var outlinePanelBackgroundSwiftUI: Color { Color(platformColor: outlinePanelBackground) }

    // MARK: - Separators

    public static let separatorOpacity: Double = 0.06
    public static let separatorOpacityDark: Double = 0.10
    public static let structuralSeparatorOpacity: Double = 0.10
    public static let structuralSeparatorOpacityDark: Double = 0.15

    // MARK: - Hover & Selection

    public static let hoverOpacity: Double = 0.06
    public static let hoverOpacityDark: Double = 0.08
    public static let selectionOpacity: Double = 0.15
    public static let selectionOpacityDark: Double = 0.22

    // MARK: - Folder Colors

    public static let folderColorPalette: [(name: String, color: PlatformColor)] = [
        ("red",    PlatformColor.clearlyColor(red: 0.90, green: 0.30, blue: 0.28, alpha: 1)),
        ("orange", PlatformColor.clearlyColor(red: 0.92, green: 0.55, blue: 0.22, alpha: 1)),
        ("yellow", PlatformColor.clearlyColor(red: 0.88, green: 0.75, blue: 0.20, alpha: 1)),
        ("green",  PlatformColor.clearlyColor(red: 0.35, green: 0.75, blue: 0.40, alpha: 1)),
        ("teal",   PlatformColor.clearlyColor(red: 0.25, green: 0.70, blue: 0.70, alpha: 1)),
        ("blue",   PlatformColor.clearlyColor(red: 0.30, green: 0.55, blue: 0.90, alpha: 1)),
        ("purple", PlatformColor.clearlyColor(red: 0.60, green: 0.40, blue: 0.85, alpha: 1)),
        ("pink",   PlatformColor.clearlyColor(red: 0.85, green: 0.40, blue: 0.60, alpha: 1)),
    ]

    public static func folderColor(named name: String) -> PlatformColor? {
        folderColorPalette.first { $0.name == name }?.color
    }

    // MARK: - Motion Presets

    public enum Motion {
        /// Quick feedback: button hovers, toggle states
        public static let snappy = Animation.spring(response: 0.25, dampingFraction: 0.85)
        /// Primary transitions: segmented control slide, panel show/hide
        public static let smooth = Animation.spring(response: 0.35, dampingFraction: 0.75)
        /// Ambient: empty state pulse, section expand
        public static let gentle = Animation.spring(response: 0.50, dampingFraction: 0.80)
        /// Hover backgrounds — instant-feeling
        public static let hover = Animation.easeOut(duration: 0.15)
    }
}
