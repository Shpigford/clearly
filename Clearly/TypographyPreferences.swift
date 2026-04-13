import AppKit

struct EditorTypography {
    let font: NSFont
    let lineHeight: CGFloat
    let baselineOffset: CGFloat

    var paragraphStyle: NSParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = lineHeight
        paragraphStyle.maximumLineHeight = lineHeight
        return paragraphStyle
    }

    var typingAttributes: [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: Theme.textColor,
            .paragraphStyle: paragraphStyle,
            .baselineOffset: baselineOffset
        ]
    }

    var headingFont: NSFont {
        TypographyPreferences.convert(font: font, size: font.pointSize + 4, bold: true)
    }

    var boldFont: NSFont {
        TypographyPreferences.convert(font: font, size: font.pointSize, bold: true)
    }

    var italicFont: NSFont {
        TypographyPreferences.convert(font: font, size: font.pointSize, italic: true)
    }

    var boldItalicFont: NSFont {
        TypographyPreferences.convert(font: font, size: font.pointSize, bold: true, italic: true)
    }
}

struct EditorFontChoice: Identifiable, Equatable {
    let id: String
    let storedFontName: String?
    let displayName: String
}

enum TypographyPreferences {
    enum FontTarget {
        case editor
        case preview

        var storageKey: String {
            switch self {
            case .editor:
                return "editorFontName"
            case .preview:
                return "previewFontName"
            }
        }

        var defaultDisplayName: String {
            switch self {
            case .editor:
                return "System Monospaced"
            case .preview:
                return "System"
            }
        }
    }

    static let editorFontNameKey = FontTarget.editor.storageKey
    static let previewFontNameKey = FontTarget.preview.storageKey
    static let defaultEditorFontChoiceID = "default-editor-font"
    static let defaultEditorFontChoice = EditorFontChoice(
        id: defaultEditorFontChoiceID,
        storedFontName: nil,
        displayName: FontTarget.editor.defaultDisplayName
    )

    static func storedFontName(for target: FontTarget, defaults: UserDefaults = .standard) -> String? {
        let value = defaults.string(forKey: target.storageKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    static func setStoredFontName(_ fontName: String?, for target: FontTarget, defaults: UserDefaults = .standard) {
        guard let fontName = fontName?.trimmingCharacters(in: .whitespacesAndNewlines), !fontName.isEmpty else {
            defaults.removeObject(forKey: target.storageKey)
            return
        }

        guard let font = NSFont(name: fontName, size: Theme.editorFontSize) else {
            defaults.removeObject(forKey: target.storageKey)
            return
        }

        if target == .editor && !font.isFixedPitch {
            defaults.removeObject(forKey: target.storageKey)
            return
        }

        defaults.set(fontName, forKey: target.storageKey)
    }

    static func clearStoredFontName(for target: FontTarget, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: target.storageKey)
    }

    static func defaultEditorFont(size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static func editorFontChoices() -> [EditorFontChoice] {
        cachedEditorFontChoices
    }

    static func editorTypography(
        size: CGFloat = Theme.editorFontSize,
        storedFontName: String? = nil,
        defaults: UserDefaults = .standard
    ) -> EditorTypography {
        let font = resolvedFont(for: .editor, size: size, storedFontName: storedFontName, defaults: defaults)
        let naturalHeight = ceil(font.ascender - font.descender + font.leading)
        let lineHeight = naturalHeight + Theme.lineSpacing
        let baselineOffset = (lineHeight - naturalHeight) / 2

        return EditorTypography(font: font, lineHeight: lineHeight, baselineOffset: baselineOffset)
    }

    static func previewTypography(
        storedFontName: String? = nil,
        defaults: UserDefaults = .standard
    ) -> PreviewTypography {
        guard let resolvedFont = resolvedStoredFont(for: .preview, size: Theme.editorFontSize, storedFontName: storedFontName, defaults: defaults),
              let familyName = resolvedFont.familyName else {
            return .default
        }

        return PreviewTypography(
            bodyFontFamily: cssFontFamily(primaryFamilyName: familyName, fallback: PreviewTypography.defaultBodyFontFamily),
            headingFontFamily: cssFontFamily(primaryFamilyName: familyName, fallback: PreviewTypography.defaultHeadingFontFamily)
        )
    }

    static func pickerFont(
        for target: FontTarget,
        size: CGFloat = Theme.editorFontSize,
        storedFontName: String? = nil,
        defaults: UserDefaults = .standard
    ) -> NSFont {
        resolvedFont(for: target, size: size, storedFontName: storedFontName, defaults: defaults)
    }

    static func displayName(
        for target: FontTarget,
        size: CGFloat = Theme.editorFontSize,
        storedFontName: String? = nil,
        defaults: UserDefaults = .standard
    ) -> String {
        guard let resolvedFont = resolvedStoredFont(for: target, size: size, storedFontName: storedFontName, defaults: defaults) else {
            return target.defaultDisplayName
        }

        return resolvedFont.familyName ?? resolvedFont.displayName ?? resolvedFont.fontName
    }

    static func normalizedStoredFontName(from font: NSFont, size: CGFloat) -> String {
        guard let familyName = font.familyName else {
            return font.fontName
        }

        let descriptor = NSFontDescriptor(fontAttributes: [.family: familyName])
        return NSFont(descriptor: descriptor, size: size)?.fontName ?? font.fontName
    }

    static func convert(font baseFont: NSFont, size: CGFloat, bold: Bool = false, italic: Bool = false) -> NSFont {
        var convertedFont = baseFont.withSize(size)

        if bold {
            convertedFont = NSFontManager.shared.convert(convertedFont, toHaveTrait: .boldFontMask)
        }

        if italic {
            convertedFont = NSFontManager.shared.convert(convertedFont, toHaveTrait: .italicFontMask)
        }

        return convertedFont.withSize(size)
    }

    static func cssFontFamily(primaryFamilyName: String, fallback: String) -> String {
        "\"\(escapedCSSFontFamilyName(primaryFamilyName))\", \(fallback)"
    }

    private static let cachedEditorFontChoices: [EditorFontChoice] = {
        var choicesByStoredFontName: [String: EditorFontChoice] = [:]
        let fontManager = NSFontManager.shared
        let size = Theme.editorFontSize

        for familyName in fontManager.availableFontFamilies {
            let descriptor = NSFontDescriptor(fontAttributes: [.family: familyName])
            guard let font = NSFont(descriptor: descriptor, size: size), font.isFixedPitch else { continue }

            let storedFontName = normalizedStoredFontName(from: font, size: size)
            guard let resolvedFont = NSFont(name: storedFontName, size: size), resolvedFont.isFixedPitch else { continue }

            let displayName = resolvedFont.familyName ?? resolvedFont.displayName ?? familyName
            choicesByStoredFontName[storedFontName] = EditorFontChoice(
                id: storedFontName,
                storedFontName: storedFontName,
                displayName: displayName
            )
        }

        let installedChoices = choicesByStoredFontName.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }

        return [defaultEditorFontChoice] + installedChoices
    }()

    private static func resolvedStoredFont(
        for target: FontTarget,
        size: CGFloat,
        storedFontName: String?,
        defaults: UserDefaults
    ) -> NSFont? {
        let fontName = storedFontName ?? self.storedFontName(for: target, defaults: defaults)
        guard let fontName,
              let font = NSFont(name: fontName, size: size),
              isAllowedStoredFont(font, for: target) else {
            return nil
        }

        return font
    }

    private static func resolvedFont(
        for target: FontTarget,
        size: CGFloat,
        storedFontName: String?,
        defaults: UserDefaults
    ) -> NSFont {
        resolvedStoredFont(for: target, size: size, storedFontName: storedFontName, defaults: defaults) ?? defaultFont(for: target, size: size)
    }

    private static func isAllowedStoredFont(_ font: NSFont, for target: FontTarget) -> Bool {
        switch target {
        case .editor:
            return font.isFixedPitch
        case .preview:
            return true
        }
    }

    private static func defaultFont(for target: FontTarget, size: CGFloat) -> NSFont {
        switch target {
        case .editor:
            return defaultEditorFont(size: size)
        case .preview:
            return NSFont.systemFont(ofSize: size)
        }
    }

    private static func escapedCSSFontFamilyName(_ familyName: String) -> String {
        var escaped = ""

        for scalar in familyName.unicodeScalars {
            switch scalar {
            case "\\":
                escaped += "\\\\"
            case "\"":
                escaped += "\\\""
            case "\n", "\r", "\t", "\u{000C}":
                escaped += " "
            case "<", ">", "&":
                escaped += String(format: "\\%X ", scalar.value)
            default:
                escaped.unicodeScalars.append(scalar)
            }
        }

        return escaped
    }
}

@MainActor
final class TypographyFontPanelController: NSObject, ObservableObject {
    private var target: TypographyPreferences.FontTarget?
    private var fontSize: CGFloat = Theme.editorFontSize
    private var storedFontName: String?

    func chooseFont(for target: TypographyPreferences.FontTarget, size: CGFloat, storedFontName: String?) {
        self.target = target
        self.fontSize = size
        self.storedFontName = storedFontName

        let fontManager = NSFontManager.shared
        fontManager.target = self
        fontManager.action = #selector(changeFont(_:))

        let currentFont = TypographyPreferences.pickerFont(for: target, size: size, storedFontName: storedFontName)
        fontManager.setSelectedFont(currentFont, isMultiple: false)

        let fontPanel = fontManager.fontPanel(true)
        fontPanel?.setPanelFont(currentFont, isMultiple: false)
        fontPanel?.makeKeyAndOrderFront(nil)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(fontPanelWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: fontPanel
        )

        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func fontPanelWillClose(_ notification: Notification) {
        let fontManager = NSFontManager.shared
        if fontManager.target === self {
            fontManager.target = nil
        }
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: notification.object)
    }

    @objc func changeFont(_ sender: NSFontManager?) {
        guard let target else { return }

        let fontManager = sender ?? NSFontManager.shared
        let currentFont = TypographyPreferences.pickerFont(for: target, size: fontSize, storedFontName: storedFontName)
        let convertedFont = fontManager.convert(currentFont)
        let normalizedFontName = TypographyPreferences.normalizedStoredFontName(from: convertedFont, size: fontSize)

        TypographyPreferences.setStoredFontName(normalizedFontName, for: target)
        storedFontName = normalizedFontName
    }
}
