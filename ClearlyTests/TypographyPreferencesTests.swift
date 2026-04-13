import AppKit
import XCTest
@testable import Clearly

final class TypographyPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ClearlyTypographyPreferencesTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsUseCurrentTypography() {
        let editorTypography = TypographyPreferences.editorTypography(size: 16, defaults: defaults)

        XCTAssertEqual(editorTypography.font.fontName, TypographyPreferences.defaultEditorFont(size: 16).fontName)
        XCTAssertEqual(editorTypography.font.pointSize, 16, accuracy: 0.001)
        XCTAssertEqual(TypographyPreferences.previewTypography(defaults: defaults), .default)
    }

    func testNonMonospacedEditorFontFallsBackToDefault() throws {
        let proportionalFont = try XCTUnwrap(NSFont(name: "Helvetica", size: 18))
        XCTAssertFalse(proportionalFont.isFixedPitch)

        let storedFontName = TypographyPreferences.normalizedStoredFontName(from: proportionalFont, size: 18)
        TypographyPreferences.setStoredFontName(storedFontName, for: .editor, defaults: defaults)

        XCTAssertNil(TypographyPreferences.storedFontName(for: .editor, defaults: defaults))

        let editorTypography = TypographyPreferences.editorTypography(size: 18, storedFontName: storedFontName, defaults: defaults)
        XCTAssertEqual(editorTypography.font.fontName, TypographyPreferences.defaultEditorFont(size: 18).fontName)
    }

    func testResetClearsStoredFontPreferences() throws {
        let storedFontName = try installedPreviewStoredFontName()

        TypographyPreferences.setStoredFontName(storedFontName, for: .editor, defaults: defaults)
        TypographyPreferences.setStoredFontName(storedFontName, for: .preview, defaults: defaults)
        TypographyPreferences.clearStoredFontName(for: .editor, defaults: defaults)
        TypographyPreferences.clearStoredFontName(for: .preview, defaults: defaults)

        XCTAssertNil(TypographyPreferences.storedFontName(for: .editor, defaults: defaults))
        XCTAssertNil(TypographyPreferences.storedFontName(for: .preview, defaults: defaults))
    }

    func testPreviewTypographyUsesResolvedFamilyFallbackChain() throws {
        let storedFontName = try installedPreviewStoredFontName()
        let resolvedFamilyName = try resolvedFamilyName(for: storedFontName)

        let previewTypography = TypographyPreferences.previewTypography(storedFontName: storedFontName, defaults: defaults)

        XCTAssertTrue(previewTypography.bodyFontFamily.hasPrefix(cssQuotedFamilyName(resolvedFamilyName)))
        XCTAssertTrue(previewTypography.headingFontFamily.hasPrefix(cssQuotedFamilyName(resolvedFamilyName)))
    }

    func testPreviewCSSKeepsCodeMonospacedWithCustomPreviewFont() throws {
        let storedFontName = try installedPreviewStoredFontName()
        let previewTypography = TypographyPreferences.previewTypography(storedFontName: storedFontName, defaults: defaults)

        let css = PreviewCSS.css(fontSize: 18, typography: previewTypography)

        XCTAssertTrue(css.contains("font-family: \(previewTypography.bodyFontFamily);"))
        XCTAssertTrue(css.contains("font-family: \"SF Mono\", SFMono-Regular, Menlo, monospace;"))
    }

    func testEditorFontChoicesOnlyIncludeFixedPitchFonts() throws {
        let choices = TypographyPreferences.editorFontChoices(size: 18)

        XCTAssertEqual(choices.first?.id, TypographyPreferences.defaultEditorFontChoiceID)
        XCTAssertFalse(choices.dropFirst().isEmpty)

        for choice in choices.dropFirst() {
            let storedFontName = try XCTUnwrap(choice.storedFontName)
            let font = try XCTUnwrap(NSFont(name: storedFontName, size: 18))
            XCTAssertTrue(font.isFixedPitch, "Expected fixed-pitch font for \(choice.displayName)")
        }
    }

    func testCSSFontFamilyEscapesHTMLSensitiveCharacters() {
        let cssFontFamily = TypographyPreferences.cssFontFamily(
            primaryFamilyName: "Mono </style> & Test",
            fallback: "monospace"
        )

        XCTAssertFalse(cssFontFamily.contains("</style>"))
        XCTAssertFalse(cssFontFamily.contains("<"))
        XCTAssertFalse(cssFontFamily.contains("&"))
        XCTAssertTrue(cssFontFamily.contains("\\3C /style\\3E "))
        XCTAssertTrue(cssFontFamily.contains("\\26 "))
    }

    private func installedPreviewStoredFontName() throws -> String {
        let candidateFonts: [NSFont?] = [
            NSFont(name: "Menlo-Regular", size: 18),
            NSFont(name: "Helvetica", size: 18),
            TypographyPreferences.defaultEditorFont(size: 18),
            NSFontManager.shared.availableFontFamilies.compactMap { familyName in
                NSFont(descriptor: NSFontDescriptor(fontAttributes: [.family: familyName]), size: 18)
            }.first
        ]

        let font = try XCTUnwrap(candidateFonts.compactMap { $0 }.first)
        return TypographyPreferences.normalizedStoredFontName(from: font, size: 18)
    }

    private func resolvedFamilyName(for storedFontName: String) throws -> String {
        let font = try XCTUnwrap(NSFont(name: storedFontName, size: 18))
        return font.familyName ?? font.displayName ?? font.fontName
    }

    private func cssQuotedFamilyName(_ familyName: String) -> String {
        let escapedFamilyName = familyName
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escapedFamilyName)\""
    }
}
