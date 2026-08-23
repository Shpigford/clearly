import XCTest
@testable import ClearlyCore

final class MarkdownMathTests: XCTestCase {
    // MARK: - Currency-like prose must NOT render as math (issue #200)

    func testGroceryCurrencyIsNotMath() {
        let html = MarkdownRenderer.renderHTML(
            "They went to a grocery store and spent $5.12 on soda and $4.42 on sweets."
        )
        XCTAssertFalse(html.contains("math-inline"), "currency sentence rendered as math: \(html)")
        XCTAssertTrue(html.contains("$5.12"))
        XCTAssertTrue(html.contains("$4.42"))
    }

    func testPandocTwentyThousandExampleIsNotMath() {
        let html = MarkdownRenderer.renderHTML("I paid $20,000 for it and $30,000 for repairs.")
        XCTAssertFalse(html.contains("math-inline"), html)
    }

    func testAsymmetricCurrencyIsNotMath() {
        let html = MarkdownRenderer.renderHTML("I paid $5 and got $3 back.")
        XCTAssertFalse(html.contains("math-inline"), html)
    }

    func testLoneDollarSignIsNotMath() {
        let html = MarkdownRenderer.renderHTML("Just a $ sign alone.")
        XCTAssertFalse(html.contains("math-inline"), html)
    }

    func testEscapedInlineMathDelimiterStaysLiteral() {
        let html = MarkdownRenderer.renderHTML(#"Escaped inline math: \$x$ should stay literal."#)
        XCTAssertFalse(html.contains("math-inline"), html)
        XCTAssertTrue(html.contains("$x$"), html)
    }

    func testBackslashEscapedCurrencyStaysLiteral() {
        let html = MarkdownRenderer.renderHTML(#"Price: \$5 and \$10."#)
        XCTAssertFalse(html.contains("math-inline"), html)
        XCTAssertTrue(html.contains("$5"), html)
        XCTAssertTrue(html.contains("$10"), html)
    }

    // MARK: - Legitimate inline math MUST still render

    func testSimpleInlineMathRenders() {
        let html = MarkdownRenderer.renderHTML("$x^2$")
        XCTAssertTrue(html.contains(#"<span class="math-inline">"#), html)
    }

    func testEulerIdentityRenders() {
        let html = MarkdownRenderer.renderHTML(#"$e^{i\pi} + 1 = 0$"#)
        XCTAssertTrue(html.contains(#"<span class="math-inline">"#), html)
    }

    func testFractionRenders() {
        let html = MarkdownRenderer.renderHTML(#"$\frac{a}{b}$"#)
        XCTAssertTrue(html.contains(#"<span class="math-inline">"#), html)
    }

    func testQuadraticFormulaFromDemoRenders() {
        let html = MarkdownRenderer.renderHTML(
            #"$x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}$"#
        )
        XCTAssertTrue(html.contains(#"<span class="math-inline">"#), html)
    }

    func testInlineMathInProseRenders() {
        let html = MarkdownRenderer.renderHTML(
            #"Inline math flows with your prose: $e^{i\pi} + 1 = 0$ still feels like magic."#
        )
        XCTAssertTrue(html.contains(#"<span class="math-inline">"#), html)
    }

    // MARK: - Display math and code protection

    func testDisplayMathBlockRenders() {
        let html = MarkdownRenderer.renderHTML(
            """
            $$
            \\int_{-\\infty}^{\\infty} e^{-x^2} \\, dx = \\sqrt{\\pi}
            $$
            """
        )
        XCTAssertTrue(html.contains(#"<div class="math-block">"#), html)
    }

    // MARK: - Math source must survive later post-processors (issue #389)

    func testCaretsInInlineMathAreNotSuperscripted() {
        let html = MarkdownRenderer.renderHTML(#"$\int\frac{x^2}{x^2 + 1} dx$"#)
        XCTAssertTrue(html.contains(#"<span class="math-inline">"#), html)
        XCTAssertFalse(html.contains("<sup>"), html)
        XCTAssertTrue(html.contains(#"\frac{x^2}{x^2 + 1}"#), html)
    }

    func testCaretsInDisplayMathAreNotSuperscripted() {
        let html = MarkdownRenderer.renderHTML(
            """
            $$
            \\frac{1 + x^3}{x^3}
            $$
            """
        )
        XCTAssertTrue(html.contains(#"<div class="math-block">"#), html)
        XCTAssertFalse(html.contains("<sup>"), html)
    }

    func testSuperscriptOutsideMathStillWorks() {
        let html = MarkdownRenderer.renderHTML("E = mc^2^ and $x^2$")
        XCTAssertTrue(html.contains("<sup>2</sup>"), html)
        XCTAssertTrue(html.contains(#"<span class="math-inline">x^2</span>"#), html)
    }

    func testDollarsInsideInlineCodeStayLiteral() {
        let html = MarkdownRenderer.renderHTML("`I paid $5 and $10.`")
        XCTAssertFalse(html.contains("math-inline"), html)
        XCTAssertTrue(html.contains("$5"))
        XCTAssertTrue(html.contains("$10"))
    }

    func testDollarsInsideFencedCodeBlockStayLiteral() {
        let html = MarkdownRenderer.renderHTML(
            """
            ```
            price = $5.12 + $4.42
            ```
            """
        )
        XCTAssertFalse(html.contains("math-inline"), html)
    }
}
