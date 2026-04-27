import XCTest
@testable import ClearlyCore

final class PreviewCSSTests: XCTestCase {
    // MARK: - Structural invariants

    func testRootBlockDeclaresAllTokensForLightPalette() {
        let block = PreviewCSS.rootBlock(for: .light)
        let required = [
            "--c-text", "--c-heading-secondary", "--c-bg", "--c-link",
            "--c-wiki", "--c-wiki-border", "--c-wiki-broken", "--c-wiki-broken-border",
            "--c-tag", "--c-tag-bg", "--c-tag-bg-hover",
            "--c-code-bg", "--c-code-fg", "--c-code-filename-bg", "--c-code-filename-fg",
            "--c-pre-bg", "--c-pre-fg",
            "--c-btn-bg", "--c-btn-bg-hover", "--c-btn-bg-active", "--c-btn-fg", "--c-btn-success",
            "--c-blockquote-bg", "--c-blockquote-fg",
            "--c-border-subtle", "--c-border-strong", "--c-th-hover-bg", "--c-row-hover-bg",
            "--c-caption", "--c-hr-border", "--c-mark-bg",
            "--c-annotation-bg", "--c-annotation-border", "--c-annotation-hover-bg",
            "--c-callout-default", "--c-callout-tip", "--c-callout-important",
            "--c-callout-warning", "--c-callout-caution", "--c-callout-abstract",
            "--c-callout-example", "--c-callout-quote", "--c-callout-question",
            "--c-toc-bg", "--c-anchor",
            "--c-popover-bg", "--c-popover-code-bg", "--c-popover-shadow-1", "--c-popover-shadow-2",
            "--c-frontmatter-bg", "--c-lightbox-bg",
        ]
        for token in required {
            XCTAssertTrue(block.contains("\(token):"), "missing token \(token) in light :root block")
        }
    }

    func testRuleBodiesContainNoHexOrRgbaLiterals() {
        let sheet = PreviewCSS.css()
        let paletteRange = sheet.range(of: "* {")
        XCTAssertNotNil(paletteRange, "stylesheet should include universal reset marker")
        guard let start = paletteRange?.lowerBound else { return }
        let rules = String(sheet[start...])
        // After the palette blocks, no `#RRGGBB` or `rgba(...)` should remain.
        let hexRegex = try! NSRegularExpression(pattern: "#[0-9A-Fa-f]{6}", options: [])
        let rgbaRegex = try! NSRegularExpression(pattern: "rgba?\\([^)]+\\)", options: [])
        let nsrules = rules as NSString
        let hexHits = hexRegex.matches(in: rules, range: NSRange(location: 0, length: nsrules.length))
        let rgbaHits = rgbaRegex.matches(in: rules, range: NSRange(location: 0, length: nsrules.length))
        XCTAssertTrue(hexHits.isEmpty, "unexpected hex literals in rule bodies: \(hexHits.map { nsrules.substring(with: $0.range) })")
        XCTAssertTrue(rgbaHits.isEmpty, "unexpected rgba literals in rule bodies: \(rgbaHits.map { nsrules.substring(with: $0.range) })")
    }

    func testStylesheetEmitsLightDarkAndPrintRootBlocks() {
        let sheet = PreviewCSS.css()
        XCTAssertTrue(sheet.contains(":root {"), "should emit base :root block")
        XCTAssertTrue(sheet.contains("@media (prefers-color-scheme: dark) {"), "should emit dark media query")
        XCTAssertTrue(sheet.contains("@media print {"), "should emit print media query")
        // Print :root block should appear inside the print media query.
        let printQueryRange = sheet.range(of: "@media print {")!
        let tailAfterPrintQuery = sheet[printQueryRange.upperBound...]
        XCTAssertTrue(tailAfterPrintQuery.contains(":root {"),
                      "print media query should contain a :root block")
    }

    // MARK: - Palette value checks (ensures light/dark/print match pre-tokenization values)

    func testLightPaletteValuesMatchPreTokenizationPreview() {
        let p = PreviewPalette.light
        XCTAssertEqual(p.text, "#1D1D1F")
        XCTAssertEqual(p.background, "#FFFFFF")
        XCTAssertEqual(p.link, "#0071E3")
        XCTAssertEqual(p.wiki, "#34855A")
        XCTAssertEqual(p.wikiBroken, "#B35C3A")
        XCTAssertEqual(p.tag, "#3A6EA5")
        XCTAssertEqual(p.preBg, "#F5F5F7")
        XCTAssertEqual(p.codeFilenameBg, "#EDEDF0")
        XCTAssertEqual(p.btnSuccess, "#34C759")
        XCTAssertEqual(p.markBg, "rgba(255, 212, 0, 0.3)")
    }

    func testDarkPaletteValuesMatchPreTokenizationPreview() {
        let p = PreviewPalette.dark
        XCTAssertEqual(p.text, "#F5F5F7")
        XCTAssertEqual(p.background, "#323236")
        XCTAssertEqual(p.link, "#0A84FF")
        XCTAssertEqual(p.wiki, "#5ABF80")
        XCTAssertEqual(p.popoverBg, "#2C2C2E")
        XCTAssertEqual(p.btnSuccess, "#30D158")
        XCTAssertEqual(p.markBg, "rgba(255, 214, 0, 0.25)")
    }

    func testPrintPaletteDiffersFromLightInTagBgAndMarkBg() {
        let light = PreviewPalette.light
        let print = PreviewPalette.print
        XCTAssertEqual(print.tagBg, "rgba(58, 110, 165, 0.06)")
        XCTAssertEqual(print.markBg, "rgba(255, 212, 0, 0.4)")
        // Everything else should match light.
        XCTAssertEqual(print.text, light.text)
        XCTAssertEqual(print.background, light.background)
        XCTAssertEqual(print.link, light.link)
        XCTAssertEqual(print.wiki, light.wiki)
    }

    // MARK: - forExport inlines print palette

    func testForExportInlinesPrintPaletteInBaseRoot() {
        let sheet = PreviewCSS.css(forExport: true)
        // The base :root block should carry the print tag-bg (not light's 0.08 value).
        // Find the FIRST :root { ... } occurrence and extract up to the closing brace.
        let rootStart = sheet.range(of: ":root {")!.upperBound
        let rootEnd = sheet.range(of: "\n}", range: rootStart..<sheet.endIndex)!.lowerBound
        let baseRoot = String(sheet[rootStart..<rootEnd])
        XCTAssertTrue(baseRoot.contains("--c-tag-bg: rgba(58, 110, 165, 0.06);"),
                      "forExport should inline print tag-bg into base :root")
        XCTAssertTrue(baseRoot.contains("--c-mark-bg: rgba(255, 212, 0, 0.4);"),
                      "forExport should inline print mark-bg into base :root")
    }

    func testForExportIncludesStructuralOverrides() {
        let sheet = PreviewCSS.css(forExport: true)
        XCTAssertTrue(sheet.contains(".code-copy-btn { display: none !important; }"))
        XCTAssertTrue(sheet.contains(".wiki-link, .wiki-link-broken { border-bottom: none !important; }"))
    }

    // MARK: - iOS mobile surface additions

    func testBodyUsesWebkitTextSizeAdjust() {
        let sheet = PreviewCSS.css()
        XCTAssertTrue(sheet.contains("-webkit-text-size-adjust: 100%"))
    }

    func testBodyUsesEnvSafeAreaInsetPadding() {
        let sheet = PreviewCSS.css()
        XCTAssertTrue(sheet.contains("env(safe-area-inset-top)"))
        XCTAssertTrue(sheet.contains("env(safe-area-inset-right)"))
        XCTAssertTrue(sheet.contains("env(safe-area-inset-bottom)"))
        XCTAssertTrue(sheet.contains("env(safe-area-inset-left)"))
    }

    // MARK: - cssHexString helper

    func testCssHexStringProducesHexForOpaqueColor() {
        let red = PlatformColor.clearlyColor(red: 1, green: 0, blue: 0, alpha: 1)
        XCTAssertEqual(red.cssHexString(for: .light), "#FF0000")
    }

    func testCssHexStringProducesRgbaForTranslucentColor() {
        let halfBlack = PlatformColor.clearlyColor(red: 0, green: 0, blue: 0, alpha: 0.5)
        XCTAssertEqual(halfBlack.cssHexString(for: .light), "rgba(0, 0, 0, 0.5)")
    }

    // Asset-catalog resolution is exercised at runtime by the app + QuickLook targets; `swift test`
    // from the CLI can't load Bundle.module xcassets, so we verify asset-driven hex resolution via
    // Xcode test bundles rather than SPM.
}
