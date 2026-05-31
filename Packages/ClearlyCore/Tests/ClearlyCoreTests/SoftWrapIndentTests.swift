import Testing
import Foundation
@testable import ClearlyCore

/// Tests for `MarkdownSyntaxHighlighter.indentValues(from:)` — the frontmatter
/// parsing that drives soft-wrap continuation indent.
struct SoftWrapIndentTests {

    @Test func noFrontmatterReturnsNil() {
        #expect(MarkdownSyntaxHighlighter.indentValues(from: "# Hello\n\nplain body") == nil)
    }

    @Test func frontmatterWithoutIndentKeysReturnsNil() {
        let doc = """
        ---
        title: Notes
        author: Me
        ---
        body
        """
        #expect(MarkdownSyntaxHighlighter.indentValues(from: doc) == nil)
    }

    @Test func wrapIndentOnly() {
        let doc = """
        ---
        wrapIndent: 4
        ---
        body
        """
        let values = MarkdownSyntaxHighlighter.indentValues(from: doc)
        #expect(values?.head.value == 4)
        #expect(values?.head.unit == .em) // bare number defaults to em
        #expect(values?.firstLine.value == 0)
    }

    @Test func firstLineIndentOnly() {
        let doc = """
        ---
        firstLineIndent: 2
        ---
        body
        """
        let values = MarkdownSyntaxHighlighter.indentValues(from: doc)
        #expect(values?.head.value == 0)
        #expect(values?.firstLine.value == 2)
    }

    @Test func bothIndentsTogether() {
        let doc = """
        ---
        title: Notes
        wrapIndent: 4
        firstLineIndent: 1
        ---
        body
        """
        let values = MarkdownSyntaxHighlighter.indentValues(from: doc)
        #expect(values?.head.value == 4)
        #expect(values?.firstLine.value == 1)
    }

    @Test func zeroIsAValidExplicitValue() {
        let doc = """
        ---
        wrapIndent: 0
        ---
        body
        """
        let values = MarkdownSyntaxHighlighter.indentValues(from: doc)
        #expect(values?.head.value == 0)
        #expect(values?.firstLine.value == 0)
    }

    @Test func negativeValueIsIgnored() {
        let doc = """
        ---
        wrapIndent: -3
        ---
        body
        """
        // wrapIndent rejected as negative; no other key → feature off.
        #expect(MarkdownSyntaxHighlighter.indentValues(from: doc) == nil)
    }

    @Test func nonNumericValueIsIgnored() {
        let doc = """
        ---
        wrapIndent: lots
        firstLineIndent: 3
        ---
        body
        """
        let values = MarkdownSyntaxHighlighter.indentValues(from: doc)
        // wrapIndent unparseable → falls back to 0, but only because the valid
        // firstLineIndent keeps the feature on (both unparseable would return nil).
        #expect(values?.head.value == 0)
        #expect(values?.firstLine.value == 3)
    }

    @Test func fractionalValueIsAccepted() {
        let doc = """
        ---
        wrapIndent: 2.5
        ---
        body
        """
        let values = MarkdownSyntaxHighlighter.indentValues(from: doc)
        #expect(values?.head.value == 2.5)
    }

    // MARK: - Explicit units

    @Test func explicitUnitsAreParsed() {
        let doc = """
        ---
        wrapIndent: 2ch
        firstLineIndent: 24px
        ---
        body
        """
        let values = MarkdownSyntaxHighlighter.indentValues(from: doc)
        #expect(values?.head.value == 2)
        #expect(values?.head.unit == .ch)
        #expect(values?.firstLine.value == 24)
        #expect(values?.firstLine.unit == .px)
    }

    @Test func emAndPtUnitsAreParsed() {
        #expect(IndentLength.parse("2em") == IndentLength(value: 2, unit: .em))
        #expect(IndentLength.parse("12pt") == IndentLength(value: 12, unit: .pt))
        #expect(IndentLength.parse("3.5ch") == IndentLength(value: 3.5, unit: .ch))
        #expect(IndentLength.parse("  5  ") == IndentLength(value: 5, unit: .em)) // bare → em
    }

    @Test func invalidUnitInputReturnsNil() {
        #expect(IndentLength.parse("") == nil)
        #expect(IndentLength.parse("abc") == nil)
        #expect(IndentLength.parse("-2em") == nil) // negative rejected
    }

    @Test func pointsResolutionPerUnit() {
        // em scales with font size, ch with character width, px/pt are absolute.
        #expect(IndentLength(value: 2, unit: .em).points(fontSize: 12, characterWidth: 7) == 24)
        #expect(IndentLength(value: 2, unit: .ch).points(fontSize: 12, characterWidth: 7) == 14)
        #expect(IndentLength(value: 20, unit: .px).points(fontSize: 12, characterWidth: 7) == 20)
        #expect(IndentLength(value: 20, unit: .pt).points(fontSize: 12, characterWidth: 7) == 20)
    }

    @Test func cssStringDropsTrailingZero() {
        #expect(IndentLength(value: 4, unit: .em).css == "4em")
        #expect(IndentLength(value: 2.5, unit: .ch).css == "2.5ch")
        #expect(IndentLength(value: -4, unit: .px).css == "-4px")
    }

    // MARK: - Frontmatter region length (live re-highlight gate)

    /// The incremental highlighter only re-reads the indent config when the edit
    /// falls within `frontmatterRegionLength`. Driving `highlightAll`/`highlightAround`
    /// end-to-end isn't possible under `swift test` (Theme color assets aren't
    /// loaded), so the gate is verified at the region-length level instead.

    @Test func regionLengthIsZeroWithoutFrontmatter() {
        #expect(MarkdownSyntaxHighlighter.frontmatterRegionLength(of: "# Just a body\n\ntext") == 0)
    }

    /// Regression: the region length must be reported even when the frontmatter
    /// has no indent keys yet. Before the fix it was left at 0 in that case, so
    /// adding `wrapIndent` later fell outside the in-region check and the change
    /// only took effect after reopening the document.
    @Test func regionLengthCoversFrontmatterWithoutIndentKeys() {
        let doc = "---\ntitle: x\n---\nbody"
        let length = MarkdownSyntaxHighlighter.frontmatterRegionLength(of: doc)
        // Region spans "---\ntitle: x\n---\n" (17 chars); body "body" excluded.
        #expect(length == (doc as NSString).length - ("body" as NSString).length)
        #expect(length > 0)

        // The location where one would insert "wrapIndent: 4" (just after the
        // title line) is inside the region, so the edit would be detected.
        let insertLocation = 12
        #expect(insertLocation < length)
    }

    @Test func regionLengthCoversFrontmatterWithIndentKeys() {
        let doc = "---\nwrapIndent: 4\n---\nbody text here"
        let length = MarkdownSyntaxHighlighter.frontmatterRegionLength(of: doc)
        #expect(length == (doc as NSString).length - ("body text here" as NSString).length)
    }

    // MARK: - Structural region length (keeps indent alive mid-edit)

    /// Regression: while typing a new field, a line is briefly invalid (a key with
    /// no colon yet), so `FrontmatterSupport.extract` fails and the field-based
    /// region length is 0. The structural length (delimiters only) must still be
    /// non-zero, so the indent cache and the in-region edit gate survive the
    /// transient state instead of permanently dropping the body indent.
    @Test func structuralLengthSurvivesHalfTypedField() {
        let doc = "---\nwrapIndent: 4\ndate\n---\nbody"   // `date` has no colon yet
        #expect(MarkdownSyntaxHighlighter.frontmatterRegionLength(of: doc) == 0)
        #expect(MarkdownSyntaxHighlighter.structuralFrontmatterRegionLength(of: doc) > 0)
    }

    @Test func structuralLengthIsZeroWithoutDelimiters() {
        #expect(MarkdownSyntaxHighlighter.structuralFrontmatterRegionLength(of: "# Heading\n\nbody") == 0)
    }

    @Test func structuralLengthMatchesValidFrontmatter() {
        let doc = "---\nwrapIndent: 4\n---\nbody"
        // Valid frontmatter: structural length covers the leading `--- ... ---\n` span.
        #expect(MarkdownSyntaxHighlighter.structuralFrontmatterRegionLength(of: doc) > 0)
    }
}
