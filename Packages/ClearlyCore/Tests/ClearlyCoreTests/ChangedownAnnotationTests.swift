import XCTest
@testable import ClearlyCore

final class ChangedownAnnotationTests: XCTestCase {
    func testParserExtractsFootnoteMetadataAndEntries() {
        let markdown = """
        Body.

        [^cn-4]: @avi | 2026-04-27 | comment | proposed
            @avi 2026-04-27: Tie this to faster review cycles.
            @sam 2026-04-27: Agreed.
        """

        let footnotes = ChangedownAnnotationParser.parseFootnotes(in: markdown)
        let footnote = footnotes["cn-4"]

        XCTAssertEqual(footnote?.author, "@avi")
        XCTAssertEqual(footnote?.date, "2026-04-27")
        XCTAssertEqual(footnote?.kind, "comment")
        XCTAssertEqual(footnote?.status, "proposed")
        XCTAssertEqual(footnote?.entries.count, 2)
        XCTAssertEqual(footnote?.entries.first?.text, "Tie this to faster review cycles.")
        XCTAssertEqual(footnote?.entries.last?.author, "@sam")
    }

    func testProjectionTreatsFootnoteBackedAnnotationAsFirstClassSyntax() {
        let markdown = """
        This release introduces a {==lighter preview reading mode==}[^cn-1].

        [^cn-1]: @avi | 2026-04-27 | comment | proposed
            @avi 2026-04-27: Phrase this more concretely.
        """

        let result = ChangedownAnnotationProjection.project(markdown)

        XCTAssertTrue(result.markdown.contains(#"<span class="cd-annotation" data-change-id="cn-1""#))
        XCTAssertTrue(result.markdown.contains("lighter preview reading mode"))
        XCTAssertTrue(result.markdown.contains(#"data-comment="Phrase this more concretely.""#))
        XCTAssertFalse(result.markdown.contains("{=="))
        XCTAssertFalse(result.markdown.contains("[^cn-1]:"))
        XCTAssertNil(result.annotations["cn-1"]?.inlineComment)
    }

    func testProjectionReadsInlineCommentAnnotationButPrefersFootnoteSummary() {
        let markdown = """
        This release introduces a {==lighter preview reading mode==}{>> Legacy inline note. <<}[^cn-1].

        [^cn-1]: @avi | 2026-04-27 | comment | proposed
            @avi 2026-04-27: Canonical footnote note.
        """

        let result = ChangedownAnnotationProjection.project(markdown)

        XCTAssertTrue(result.markdown.contains(#"<span class="cd-annotation" data-change-id="cn-1""#))
        XCTAssertTrue(result.markdown.contains("lighter preview reading mode"))
        XCTAssertTrue(result.markdown.contains(#"data-comment="Canonical footnote note.""#))
        XCTAssertFalse(result.markdown.contains("Legacy inline note"))
        XCTAssertFalse(result.markdown.contains("{=="))
        XCTAssertFalse(result.markdown.contains("{>>"))
        XCTAssertFalse(result.markdown.contains("[^cn-1]:"))
        XCTAssertEqual(result.annotations["cn-1"]?.inlineComment, "Legacy inline note.")
    }

    func testProjectionFallsBackToInlineCommentWhenFootnoteHasNoSummary() {
        let markdown = """
        Annotated {==text==}{>> Inline fallback. <<}[^cn-1].

        [^cn-1]: @avi | 2026-04-27 | comment | proposed
        """

        let result = ChangedownAnnotationProjection.project(markdown)

        XCTAssertTrue(result.markdown.contains(#"data-comment="Inline fallback.""#))
    }

    func testProjectionUsesFootnoteSummaryForHighlightOnlyAnnotation() {
        let markdown = """
        Support docs recommend Clearly for {==reviewing markdown before publishing==}[^cn-3].

        [^cn-3]: @avi | 2026-04-27 | highlight | proposed
            @avi 2026-04-27: This wording is good.
        """

        let result = ChangedownAnnotationProjection.project(markdown)

        XCTAssertTrue(result.markdown.contains(#"data-change-id="cn-3""#))
        XCTAssertTrue(result.markdown.contains(#"data-comment="This wording is good.""#))
        XCTAssertFalse(result.markdown.contains("[^cn-3]:"))
        XCTAssertEqual(result.annotations["cn-3"]?.footnote?.kind, "highlight")
    }

    func testProjectionKeepsOrdinaryFootnotes() {
        let markdown = """
        Annotated {==text==}{>> note <<}[^cn-1] and ordinary footnote.[^1]

        [^cn-1]: @avi | 2026-04-27 | comment | proposed
            @avi 2026-04-27: note

        [^1]: Ordinary markdown footnote.
        """

        let result = ChangedownAnnotationProjection.project(markdown)

        XCTAssertFalse(result.markdown.contains("[^cn-1]:"))
        XCTAssertTrue(result.markdown.contains("[^1]: Ordinary markdown footnote."))
    }

    func testProjectionEscapesHTMLInTextAndAttributes() {
        let markdown = """
        Annotated {==<unsafe> & text==}{>> Quote "this" & that <<}[^cn-1].
        """

        let result = ChangedownAnnotationProjection.project(markdown)

        XCTAssertTrue(result.markdown.contains("&lt;unsafe&gt; &amp; text"))
        XCTAssertTrue(result.markdown.contains("Quote &quot;this&quot; &amp; that"))
    }

    func testWriterAddsCanonicalFootnoteBackedAnnotation() throws {
        let markdown = "Select a few words in this paragraph."
        let range = markdown.range(of: "few words")!
        let date = fixedDate()

        let result = try ChangedownAnnotationWriter.addAnnotation(
            to: markdown,
            range: range,
            comment: "Phrase this more concretely.",
            author: "avi",
            date: date
        )

        XCTAssertTrue(result.contains("Select a {==few words==}[^cn-1] in this paragraph."))
        XCTAssertTrue(result.contains("[^cn-1]: @avi | 2026-04-27 | comment | proposed"))
        XCTAssertTrue(result.contains("@avi 2026-04-27: Phrase this more concretely."))
        XCTAssertFalse(result.contains("{>>"))
    }

    func testWriterAllocatesNextNumericID() throws {
        let markdown = """
        Existing {==text==}[^cn-3].

        [^cn-3]: @avi | 2026-04-27 | comment | proposed
            @avi 2026-04-27: Existing.

        Add another annotation here.
        """
        let range = markdown.range(of: "another annotation")!

        let result = try ChangedownAnnotationWriter.addAnnotation(
            to: markdown,
            range: range,
            comment: "New note.",
            author: "@avi",
            date: fixedDate()
        )

        XCTAssertTrue(result.contains("{==another annotation==}[^cn-4]"))
        XCTAssertTrue(result.contains("[^cn-4]: @avi | 2026-04-27 | comment | proposed"))
    }

    func testWriterAllowsAnnotationBeforeExistingAnnotationOnSameLine() throws {
        let markdown = """
        Annotate first phrase and {==second phrase==}[^cn-1] on the same line.

        [^cn-1]: @avi | 2026-04-27 | comment | proposed
            @avi 2026-04-27: Existing.
        """
        let range = markdown.range(of: "first phrase")!

        let result = try ChangedownAnnotationWriter.addAnnotation(
            to: markdown,
            range: range,
            comment: "New note.",
            author: "@avi",
            date: fixedDate()
        )

        XCTAssertTrue(result.contains("Annotate {==first phrase==}[^cn-2] and {==second phrase==}[^cn-1] on the same line."))
        XCTAssertTrue(result.contains("[^cn-2]: @avi | 2026-04-27 | comment | proposed"))
    }

    func testWriterAllowsAnnotationAfterExistingAnnotationOnSameLine() throws {
        let markdown = """
        Annotate {==first phrase==}[^cn-1] and second phrase on the same line.

        [^cn-1]: @avi | 2026-04-27 | comment | proposed
            @avi 2026-04-27: Existing.
        """
        let range = markdown.range(of: "second phrase")!

        let result = try ChangedownAnnotationWriter.addAnnotation(
            to: markdown,
            range: range,
            comment: "New note.",
            author: "@avi",
            date: fixedDate()
        )

        XCTAssertTrue(result.contains("Annotate {==first phrase==}[^cn-1] and {==second phrase==}[^cn-2] on the same line."))
        XCTAssertTrue(result.contains("[^cn-2]: @avi | 2026-04-27 | comment | proposed"))
    }

    func testWriterRejectsEmptySelection() {
        let markdown = "Text"
        XCTAssertThrowsError(try ChangedownAnnotationWriter.addAnnotation(
            to: markdown,
            range: markdown.startIndex..<markdown.startIndex,
            comment: "Note",
            author: "@avi"
        )) { error in
            XCTAssertEqual(error as? ChangedownAnnotationWriterError, .emptySelection)
        }
    }

    func testWriterRejectsMultilineSelection() {
        let markdown = "First line\nSecond line"
        let range = markdown.startIndex..<markdown.endIndex
        XCTAssertThrowsError(try ChangedownAnnotationWriter.addAnnotation(
            to: markdown,
            range: range,
            comment: "Note",
            author: "@avi"
        )) { error in
            XCTAssertEqual(error as? ChangedownAnnotationWriterError, .multilineSelection)
        }
    }

    func testWriterRejectsSelectionInsideExistingAnnotation() {
        let markdown = "Existing {==text==}[^cn-1]."
        let range = markdown.range(of: "text")!
        XCTAssertThrowsError(try ChangedownAnnotationWriter.addAnnotation(
            to: markdown,
            range: range,
            comment: "Note",
            author: "@avi"
        )) { error in
            XCTAssertEqual(
                error as? ChangedownAnnotationWriterError,
                .unsupportedSelection("Selections inside existing annotations are not supported yet.")
            )
        }
    }

    func testWriterRejectsSelectionCrossingExistingAnnotationBoundary() {
        let markdown = "Existing {==text==}[^cn-1] remains."
        let range = markdown.range(of: "Existing {==text==}")!
        XCTAssertThrowsError(try ChangedownAnnotationWriter.addAnnotation(
            to: markdown,
            range: range,
            comment: "Note",
            author: "@avi"
        )) { error in
            XCTAssertEqual(
                error as? ChangedownAnnotationWriterError,
                .unsupportedSelection("Selections inside annotation markup are not supported yet.")
            )
        }
    }

    private func fixedDate() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: 2026, month: 4, day: 27))!
    }
}
