import Foundation

/// Semantic color tokens used by the preview/export HTML. A `PreviewPalette` carries one value per token;
/// `PreviewCSS.css(...)` emits three palettes as `:root` blocks (base, dark, print) and rule bodies reference
/// tokens exclusively via `var(--c-*)` — no hex/rgba literals live in selectors.
public struct PreviewPalette: Sendable {
    public var text: String
    public var headingSecondary: String
    public var background: String
    public var link: String
    public var wiki: String
    public var wikiBorder: String
    public var wikiBroken: String
    public var wikiBrokenBorder: String
    public var tag: String
    public var tagBg: String
    public var tagBgHover: String
    public var codeBg: String
    public var codeFg: String
    public var codeFilenameBg: String
    public var codeFilenameFg: String
    public var preBg: String
    public var preFg: String
    public var btnBg: String
    public var btnBgHover: String
    public var btnBgActive: String
    public var btnFg: String
    public var btnSuccess: String
    public var blockquoteBg: String
    public var blockquoteFg: String
    public var borderSubtle: String
    public var borderStrong: String
    public var thHoverBg: String
    public var rowHoverBg: String
    public var caption: String
    public var hrBorder: String
    public var markBg: String
    public var annotationBg: String
    public var annotationBorder: String
    public var annotationHoverBg: String
    public var calloutDefault: String
    public var calloutTip: String
    public var calloutImportant: String
    public var calloutWarning: String
    public var calloutCaution: String
    public var calloutAbstract: String
    public var calloutExample: String
    public var calloutQuote: String
    public var calloutQuestion: String
    public var tocBg: String
    public var anchor: String
    public var popoverBg: String
    public var popoverCodeBg: String
    public var popoverShadow1: String
    public var popoverShadow2: String
    public var frontmatterBg: String
    public var lightboxBg: String

    public init(
        text: String,
        headingSecondary: String,
        background: String,
        link: String,
        wiki: String,
        wikiBorder: String,
        wikiBroken: String,
        wikiBrokenBorder: String,
        tag: String,
        tagBg: String,
        tagBgHover: String,
        codeBg: String,
        codeFg: String,
        codeFilenameBg: String,
        codeFilenameFg: String,
        preBg: String,
        preFg: String,
        btnBg: String,
        btnBgHover: String,
        btnBgActive: String,
        btnFg: String,
        btnSuccess: String,
        blockquoteBg: String,
        blockquoteFg: String,
        borderSubtle: String,
        borderStrong: String,
        thHoverBg: String,
        rowHoverBg: String,
        caption: String,
        hrBorder: String,
        markBg: String,
        annotationBg: String,
        annotationBorder: String,
        annotationHoverBg: String,
        calloutDefault: String,
        calloutTip: String,
        calloutImportant: String,
        calloutWarning: String,
        calloutCaution: String,
        calloutAbstract: String,
        calloutExample: String,
        calloutQuote: String,
        calloutQuestion: String,
        tocBg: String,
        anchor: String,
        popoverBg: String,
        popoverCodeBg: String,
        popoverShadow1: String,
        popoverShadow2: String,
        frontmatterBg: String,
        lightboxBg: String
    ) {
        self.text = text
        self.headingSecondary = headingSecondary
        self.background = background
        self.link = link
        self.wiki = wiki
        self.wikiBorder = wikiBorder
        self.wikiBroken = wikiBroken
        self.wikiBrokenBorder = wikiBrokenBorder
        self.tag = tag
        self.tagBg = tagBg
        self.tagBgHover = tagBgHover
        self.codeBg = codeBg
        self.codeFg = codeFg
        self.codeFilenameBg = codeFilenameBg
        self.codeFilenameFg = codeFilenameFg
        self.preBg = preBg
        self.preFg = preFg
        self.btnBg = btnBg
        self.btnBgHover = btnBgHover
        self.btnBgActive = btnBgActive
        self.btnFg = btnFg
        self.btnSuccess = btnSuccess
        self.blockquoteBg = blockquoteBg
        self.blockquoteFg = blockquoteFg
        self.borderSubtle = borderSubtle
        self.borderStrong = borderStrong
        self.thHoverBg = thHoverBg
        self.rowHoverBg = rowHoverBg
        self.caption = caption
        self.hrBorder = hrBorder
        self.markBg = markBg
        self.annotationBg = annotationBg
        self.annotationBorder = annotationBorder
        self.annotationHoverBg = annotationHoverBg
        self.calloutDefault = calloutDefault
        self.calloutTip = calloutTip
        self.calloutImportant = calloutImportant
        self.calloutWarning = calloutWarning
        self.calloutCaution = calloutCaution
        self.calloutAbstract = calloutAbstract
        self.calloutExample = calloutExample
        self.calloutQuote = calloutQuote
        self.calloutQuestion = calloutQuestion
        self.tocBg = tocBg
        self.anchor = anchor
        self.popoverBg = popoverBg
        self.popoverCodeBg = popoverCodeBg
        self.popoverShadow1 = popoverShadow1
        self.popoverShadow2 = popoverShadow2
        self.frontmatterBg = frontmatterBg
        self.lightboxBg = lightboxBg
    }

    /// Palette applied by default (base `:root`). Matches the pre-tokenization Mac preview values.
    public static let light = PreviewPalette(
        text: "#1D1D1F",
        headingSecondary: "rgba(29, 29, 31, 0.55)",
        background: "#FFFFFF",
        link: "#0071E3",
        wiki: "#34855A",
        wikiBorder: "rgba(52, 133, 90, 0.3)",
        wikiBroken: "#B35C3A",
        wikiBrokenBorder: "rgba(179, 92, 58, 0.4)",
        tag: "#3A6EA5",
        tagBg: "rgba(58, 110, 165, 0.08)",
        tagBgHover: "rgba(58, 110, 165, 0.15)",
        codeBg: "rgba(0, 0, 0, 0.04)",
        codeFg: "#1D1D1F",
        codeFilenameBg: "#EDEDF0",
        codeFilenameFg: "#86868B",
        preBg: "#F5F5F7",
        preFg: "#1D1D1F",
        btnBg: "rgba(0, 0, 0, 0.05)",
        btnBgHover: "rgba(0, 0, 0, 0.08)",
        btnBgActive: "rgba(0, 0, 0, 0.12)",
        btnFg: "#86868B",
        btnSuccess: "#34C759",
        blockquoteBg: "rgba(0, 0, 0, 0.03)",
        blockquoteFg: "#48484A",
        borderSubtle: "rgba(0, 0, 0, 0.06)",
        borderStrong: "rgba(0, 0, 0, 0.12)",
        thHoverBg: "rgba(0, 0, 0, 0.03)",
        rowHoverBg: "rgba(0, 0, 0, 0.02)",
        caption: "#86868B",
        hrBorder: "rgba(0, 0, 0, 0.1)",
        markBg: "rgba(255, 212, 0, 0.3)",
        annotationBg: "rgba(255, 212, 0, 0.24)",
        annotationBorder: "rgba(191, 142, 0, 0.45)",
        annotationHoverBg: "rgba(255, 212, 0, 0.36)",
        calloutDefault: "rgba(0, 122, 255, 0.1)",
        calloutTip: "rgba(52, 199, 89, 0.1)",
        calloutImportant: "rgba(175, 82, 222, 0.1)",
        calloutWarning: "rgba(255, 149, 0, 0.1)",
        calloutCaution: "rgba(255, 59, 48, 0.1)",
        calloutAbstract: "rgba(90, 200, 250, 0.1)",
        calloutExample: "rgba(88, 86, 214, 0.1)",
        calloutQuote: "rgba(142, 142, 147, 0.1)",
        calloutQuestion: "rgba(255, 204, 0, 0.1)",
        tocBg: "rgba(0, 0, 0, 0.025)",
        anchor: "#AEAEB2",
        popoverBg: "#FFFFFF",
        popoverCodeBg: "rgba(0, 0, 0, 0.04)",
        popoverShadow1: "rgba(0, 0, 0, 0.08)",
        popoverShadow2: "rgba(0, 0, 0, 0.06)",
        frontmatterBg: "rgba(0, 0, 0, 0.03)",
        lightboxBg: "rgba(0, 0, 0, 0.75)"
    )

    /// Palette applied inside `@media (prefers-color-scheme: dark)`.
    public static let dark = PreviewPalette(
        text: "#F5F5F7",
        headingSecondary: "rgba(245, 245, 247, 0.55)",
        background: "#323236",
        link: "#0A84FF",
        wiki: "#5ABF80",
        wikiBorder: "rgba(90, 191, 128, 0.3)",
        wikiBroken: "#D97A57",
        wikiBrokenBorder: "rgba(217, 122, 87, 0.4)",
        tag: "#7AB0D9",
        tagBg: "rgba(122, 176, 217, 0.12)",
        tagBgHover: "rgba(122, 176, 217, 0.2)",
        codeBg: "rgba(255, 255, 255, 0.06)",
        codeFg: "#F5F5F7",
        codeFilenameBg: "rgba(255, 255, 255, 0.07)",
        codeFilenameFg: "#AEAEB2",
        preBg: "rgba(255, 255, 255, 0.05)",
        preFg: "#F5F5F7",
        btnBg: "rgba(255, 255, 255, 0.07)",
        btnBgHover: "rgba(255, 255, 255, 0.1)",
        btnBgActive: "rgba(255, 255, 255, 0.14)",
        btnFg: "#AEAEB2",
        btnSuccess: "#30D158",
        blockquoteBg: "rgba(255, 255, 255, 0.04)",
        blockquoteFg: "#E5E5EA",
        borderSubtle: "rgba(255, 255, 255, 0.08)",
        borderStrong: "rgba(255, 255, 255, 0.15)",
        thHoverBg: "rgba(255, 255, 255, 0.05)",
        rowHoverBg: "rgba(255, 255, 255, 0.03)",
        caption: "#AEAEB2",
        hrBorder: "rgba(255, 255, 255, 0.1)",
        markBg: "rgba(255, 214, 0, 0.25)",
        annotationBg: "rgba(255, 214, 0, 0.2)",
        annotationBorder: "rgba(255, 214, 0, 0.45)",
        annotationHoverBg: "rgba(255, 214, 0, 0.3)",
        calloutDefault: "rgba(10, 132, 255, 0.14)",
        calloutTip: "rgba(48, 209, 88, 0.14)",
        calloutImportant: "rgba(191, 90, 242, 0.14)",
        calloutWarning: "rgba(255, 159, 10, 0.14)",
        calloutCaution: "rgba(255, 69, 58, 0.14)",
        calloutAbstract: "rgba(100, 210, 255, 0.14)",
        calloutExample: "rgba(94, 92, 230, 0.14)",
        calloutQuote: "rgba(152, 152, 157, 0.14)",
        calloutQuestion: "rgba(255, 214, 10, 0.14)",
        tocBg: "rgba(255, 255, 255, 0.035)",
        anchor: "rgba(255, 255, 255, 0.2)",
        popoverBg: "#2C2C2E",
        popoverCodeBg: "rgba(255, 255, 255, 0.08)",
        popoverShadow1: "rgba(0, 0, 0, 0.35)",
        popoverShadow2: "rgba(255, 255, 255, 0.08)",
        frontmatterBg: "rgba(255, 255, 255, 0.04)",
        lightboxBg: "rgba(0, 0, 0, 0.75)"
    )

    /// Palette applied inside `@media print` (and inlined into `:root` when `forExport: true`).
    /// Matches light, with two token differences preserved from the pre-tokenization `@media print` block:
    /// softer `.md-tag` background and a slightly heavier `mark` highlight.
    public static let print: PreviewPalette = {
        var p = PreviewPalette.light
        p.tagBg = "rgba(58, 110, 165, 0.06)"
        p.markBg = "rgba(255, 212, 0, 0.4)"
        p.annotationBg = "rgba(255, 212, 0, 0.18)"
        p.annotationHoverBg = "rgba(255, 212, 0, 0.18)"
        return p
    }()
}

public enum PreviewCSS {
    /// Generates the preview/export stylesheet. Colors are driven by CSS custom properties defined in a
    /// `:root` block built from `light`; `@media (prefers-color-scheme: dark)` and `@media print` each
    /// redeclare `:root` with their respective palettes. When `forExport: true`, the print palette is
    /// inlined into the base `:root` so contexts that don't fire `@media print` (web-view-driven PDF
    /// export flows) still get the print colors.
    public static func css(
        fontSize: CGFloat = 18,
        fontFamily: String = "sanFrancisco",
        forExport: Bool = false,
        bodyMaxWidth: String = "61em",
        light: PreviewPalette = .light,
        dark: PreviewPalette = .dark,
        print: PreviewPalette = .print
    ) -> String {
        let bodyFontFamily: String
        let headingFontFamily: String
        switch fontFamily {
        case "newYork":
            bodyFontFamily = "\"New York\", \"Iowan Old Style\", Georgia, serif"
            headingFontFamily = "\"New York\", \"Iowan Old Style\", Georgia, serif"
        case "sfMono":
            bodyFontFamily = "\"SF Mono\", SFMono-Regular, Menlo, monospace"
            headingFontFamily = "\"SF Mono\", SFMono-Regular, Menlo, monospace"
        default:
            bodyFontFamily = "system-ui, -apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"SF Pro Display\", \"Helvetica Neue\", sans-serif"
            headingFontFamily = "system-ui, -apple-system, BlinkMacSystemFont, \"SF Pro Display\", \"Helvetica Neue\", sans-serif"
        }

        let basePalette = forExport ? print : light
        let baseRoot = rootBlock(for: basePalette, selector: ":root")
        let darkRoot = rootBlock(for: dark, selector: ":root", indent: "    ")
        let printRoot = rootBlock(for: print, selector: ":root", indent: "    ")
        let darkBlock = "@media (prefers-color-scheme: dark) {\n\(darkRoot)\n}"
        let printBlock = "@media print {\n\(printRoot)\n}"

        let exportStructural = forExport ? """
        .code-copy-btn { display: none !important; }
        .table-copy-btn { display: none !important; }
        .sort-indicator { display: none !important; }
        thead { position: static !important; display: table-header-group; }
        tr:hover td { background-color: transparent !important; }
        th { cursor: default !important; }
        body {
            max-width: none !important;
            margin: 0 !important;
            padding: 0 !important;
        }
        details.callout > summary::before { content: "" !important; }
        .heading-anchor { display: none !important; }
        .lightbox-overlay { display: none !important; }
        .footnote-popover { display: none !important; }
        .wiki-link, .wiki-link-broken { border-bottom: none !important; }
        .callout { border: none !important; }
        .page-break {
            height: 0 !important;
            border: none !important;
            margin: 0 !important;
        }
        h1, h2, h3, h4, h5, h6 {
            page-break-after: avoid;
            break-after: avoid;
            page-break-inside: avoid;
            break-inside: avoid;
        }
        p, pre, blockquote, table, .frontmatter, .math-block, .mermaid, img, ul, ol {
            page-break-inside: avoid;
            break-inside: avoid;
        }
        tr {
            page-break-inside: avoid;
            break-inside: avoid;
        }
        img {
            display: block;
        }
        """ : ""

        return """
        \(baseRoot)

        \(darkBlock)

        \(printBlock)

        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: \(bodyFontFamily);
            font-size: \(Int(fontSize))px;
            line-height: 1.75;
            max-width: \(bodyMaxWidth);
            margin: 0 auto;
            padding-top: max(40px, env(safe-area-inset-top));
            padding-right: max(64px, env(safe-area-inset-right));
            padding-bottom: max(48px, env(safe-area-inset-bottom));
            padding-left: max(64px, env(safe-area-inset-left));
            color: var(--c-text);
            background-color: var(--c-bg);
            -webkit-font-smoothing: antialiased;
            -webkit-text-size-adjust: 100%;
        }

        h1, h2, h3, h4, h5, h6 {
            font-family: \(headingFontFamily);
            line-height: 1.25;
            margin-top: 2em;
            margin-bottom: 0.75em;
            letter-spacing: -0.015em;
            position: relative;
        }

        body > *:first-child {
            margin-top: 0;
        }

        /* Frontmatter metadata */
        .frontmatter {
            margin-bottom: 1.5em;
            padding: 1em 1.25em;
            background-color: var(--c-frontmatter-bg);
            border-radius: 10px;
            font-size: 0.85em;
        }

        .frontmatter-anchor {
            height: 0;
            margin: 0;
            padding: 0;
        }

        .frontmatter dl {
            margin: 0;
        }

        .frontmatter .frontmatter-row {
            display: flex;
            gap: 0.5em;
            padding: 0.15em 0;
        }

        .frontmatter dt {
            font-weight: 600;
            color: var(--c-caption);
            min-width: 6em;
        }

        .frontmatter dt::after {
            content: ":";
        }

        .frontmatter dd {
            margin: 0;
            color: var(--c-text);
            white-space: pre-wrap;
        }

        .frontmatter pre {
            margin: 0;
            padding: 0 !important;
            background: none !important;
            border: 0 !important;
            color: inherit !important;
            white-space: pre-wrap;
            font-size: 0.95em;
        }

        h1 { font-size: 2.25em; font-weight: 700; letter-spacing: -0.025em; }
        h2 { font-size: 1.625em; font-weight: 650; }
        h3 { font-size: 1.3125em; font-weight: 600; }
        h4 { font-size: 1.125em; font-weight: 600; }
        h5 { font-size: 1em; font-weight: 600; }
        h6 { font-size: 0.9375em; font-weight: 600; text-transform: uppercase; letter-spacing: 0.05em; color: var(--c-heading-secondary); }

        p {
            margin-bottom: 1.125em;
        }

        a {
            color: var(--c-link);
            text-decoration: none;
        }
        a:hover {
            text-decoration: underline;
        }
        .wiki-link {
            color: var(--c-wiki);
            text-decoration: none;
            border-bottom: 1px solid var(--c-wiki-border);
        }
        .wiki-link:hover {
            text-decoration: none;
            border-bottom-color: var(--c-wiki);
        }
        .wiki-link-broken {
            color: var(--c-wiki-broken);
            border-bottom: 1px dashed var(--c-wiki-broken-border);
        }
        .wiki-link-broken:hover {
            text-decoration: none;
            border-bottom-color: var(--c-wiki-broken);
        }
        .md-tag {
            color: var(--c-tag);
            text-decoration: none;
            background: var(--c-tag-bg);
            padding: 1px 5px;
            border-radius: 3px;
            font-size: 0.9em;
        }
        .md-tag:hover {
            background: var(--c-tag-bg-hover);
        }

        code {
            font-family: "SF Mono", SFMono-Regular, Menlo, monospace;
            font-size: 0.875em;
            background-color: var(--c-code-bg);
            color: var(--c-code-fg);
            padding: 0.125em 0.375em;
            border-radius: 5px;
        }

        .code-filename {
            font-family: "SF Mono", SFMono-Regular, Menlo, monospace;
            font-size: 0.8em;
            padding: 0.5em 1.25em;
            background: var(--c-code-filename-bg);
            border: none;
            border-radius: 10px 10px 0 0;
            color: var(--c-code-filename-fg);
        }

        pre {
            position: relative;
            background-color: var(--c-pre-bg);
            border: none;
            border-radius: 10px;
            padding: 1.125em 1.25em;
            margin-bottom: 1.25em;
            overflow-x: auto;
            color: var(--c-pre-fg);
        }

        .code-filename + pre {
            border-top-left-radius: 0;
            border-top-right-radius: 0;
            margin-top: 0;
        }

        .code-block-wrapper {
            position: relative;
            margin-bottom: 1.25em;
        }

        .code-block-wrapper > pre {
            margin-bottom: 0;
        }

        .code-block-wrapper:hover .code-copy-btn {
            opacity: 1;
        }

        .code-copy-btn {
            position: absolute;
            top: 6px;
            right: 6px;
            z-index: 1;
            width: 28px;
            height: 28px;
            padding: 0;
            margin: 0;
            border: none;
            border-radius: 6px;
            background: var(--c-btn-bg);
            color: var(--c-btn-fg);
            cursor: pointer;
            opacity: 0;
            transition: opacity 0.15s ease;
            display: flex;
            align-items: center;
            justify-content: center;
        }

        .code-copy-btn svg {
            display: block;
        }

        .code-copy-btn.copied {
            color: var(--c-btn-success);
        }

        .code-copy-btn:hover {
            background: var(--c-btn-bg-hover);
        }

        .code-copy-btn:active {
            background: var(--c-btn-bg-active);
        }

        .frontmatter .code-copy-btn {
            display: none;
        }

        pre code {
            background: none;
            color: inherit;
            padding: 0;
            font-size: 0.875em;
        }

        blockquote {
            border: none;
            background-color: var(--c-blockquote-bg);
            border-radius: 8px;
            padding: 0.75em 1.25em;
            margin-left: 0;
            margin-bottom: 1.25em;
            color: var(--c-blockquote-fg);
        }
        blockquote > *:last-child {
            margin-bottom: 0;
        }

        ul, ol {
            margin-bottom: 1em;
            padding-left: 1.625em;
        }

        li {
            margin-bottom: 0.3em;
        }

        /* Task lists */
        ul.contains-task-list {
            list-style: none;
            padding-left: 0;
        }

        li.task-list-item {
            display: flex;
            align-items: baseline;
            gap: 0.5em;
        }

        li.task-list-item input[type="checkbox"] {
            margin: 0;
        }

        /* Tables */
        .table-shell {
            position: relative;
            overflow: visible;
            margin-bottom: 1em;
            --table-copy-top: 6px;
        }

        .table-shell.has-copy-btn::after {
            content: "";
            position: absolute;
            top: calc(var(--table-copy-top) - 6px);
            right: -44px;
            width: 44px;
            height: 40px;
            pointer-events: auto;
        }

        .table-wrapper {
            overflow-x: auto;
        }

        table {
            border-collapse: collapse;
            width: 100%;
            font-variant-numeric: tabular-nums;
        }

        th, td {
            padding: 0.625em 0.875em;
            max-width: 20em;
            overflow-wrap: break-word;
        }

        thead {
            position: sticky;
            top: 0;
            z-index: 1;
        }

        th {
            font-weight: 600;
            background-color: transparent;
            border-bottom: 1px solid var(--c-border-strong);
            cursor: pointer;
            user-select: none;
            white-space: nowrap;
        }

        th:hover {
            background-color: var(--c-th-hover-bg);
        }

        td {
            border-bottom: 1px solid var(--c-border-subtle);
        }

        tr:nth-child(even) {
            background-color: transparent;
        }

        tr:hover td {
            background-color: var(--c-row-hover-bg);
        }

        .sort-indicator {
            font-size: 0.7em;
            margin-left: 0.3em;
            opacity: 0.3;
        }

        th.sort-asc .sort-indicator,
        th.sort-desc .sort-indicator {
            opacity: 1;
        }

        caption {
            caption-side: top;
            text-align: left;
            font-size: 0.9em;
            font-weight: 500;
            color: var(--c-caption);
            padding-bottom: 0.5em;
        }

        .table-copy-btn {
            position: absolute;
            right: -36px;
            width: 28px;
            height: 28px;
            padding: 0;
            margin: 0;
            border: none;
            border-radius: 6px;
            background: var(--c-btn-bg);
            color: var(--c-btn-fg);
            cursor: pointer;
            opacity: 0;
            pointer-events: none;
            transform: translateX(-4px);
            transition: opacity 0.15s ease, transform 0.15s ease;
            display: flex;
            align-items: center;
            justify-content: center;
            z-index: 2;
        }

        .table-copy-btn svg {
            display: block;
        }

        .table-copy-btn.copied {
            color: var(--c-btn-success);
        }

        .table-shell:hover .table-copy-btn,
        .table-copy-btn:hover,
        .table-copy-btn:focus-visible {
            opacity: 1;
            pointer-events: auto;
            transform: translateX(0);
        }

        .table-copy-btn:hover {
            background: var(--c-btn-bg-hover);
        }

        .table-copy-btn:active {
            background: var(--c-btn-bg-active);
        }

        /* Strikethrough */
        del {
            text-decoration: line-through;
            opacity: 0.6;
        }

        hr {
            border: none;
            border-top: 0.5px solid var(--c-hr-border);
            margin: 2.5em 0;
        }

        .page-break {
            display: block;
            height: 0;
            border-top: 1px dashed var(--c-border-strong);
            margin: 2em 0;
        }

        /* Highlight/Mark */
        mark {
            background-color: var(--c-mark-bg);
            color: inherit !important;
            padding: 0.1em 0.2em;
            border-radius: 3px;
        }

        .cd-annotation {
            background: var(--c-annotation-bg);
            border-bottom: 1px solid var(--c-annotation-border);
            border-radius: 3px;
            cursor: help;
            padding: 0.05em 0.15em;
        }

        .cd-annotation:hover {
            background: var(--c-annotation-hover-bg);
        }

        /* Superscript/Subscript */
        sup, sub {
            font-size: 0.75em;
            line-height: 0;
        }

        /* Callouts/Admonitions */
        .callout {
            border: none;
            border-radius: 10px;
            padding: 1em 1.25em;
            margin-bottom: 1.25em;
            background-color: var(--c-callout-default);
        }
        .callout-title {
            font-weight: 600;
            margin-bottom: 0.375em;
            display: flex;
            align-items: center;
            gap: 0.4em;
        }
        .callout-icon { flex-shrink: 0; }
        .callout-content > *:last-child { margin-bottom: 0; }
        .callout-content blockquote { border-left: none; padding-left: 0; color: inherit; }

        details.callout > summary { cursor: pointer; list-style: none; }
        details.callout > summary::-webkit-details-marker { display: none; }
        details.callout > summary::before { content: "▶"; font-size: 0.7em; margin-right: 0.3em; transition: transform 0.2s; display: inline-block; }
        details.callout[open] > summary::before { transform: rotate(90deg); }

        .callout-note, .callout-info { background-color: var(--c-callout-default); }
        .callout-tip { background-color: var(--c-callout-tip); }
        .callout-important { background-color: var(--c-callout-important); }
        .callout-warning { background-color: var(--c-callout-warning); }
        .callout-caution, .callout-danger { background-color: var(--c-callout-caution); }
        .callout-abstract { background-color: var(--c-callout-abstract); }
        .callout-todo { background-color: var(--c-callout-default); }
        .callout-example { background-color: var(--c-callout-example); }
        .callout-quote { background-color: var(--c-callout-quote); }
        .callout-bug, .callout-failure { background-color: var(--c-callout-caution); }
        .callout-success { background-color: var(--c-callout-tip); }
        .callout-question { background-color: var(--c-callout-question); }

        /* Table of Contents */
        .toc {
            background-color: var(--c-toc-bg);
            border: none;
            border-radius: 10px;
            padding: 1.25em 1.5em;
            margin-bottom: 1.5em;
        }
        .toc::before {
            content: "Table of Contents";
            display: block;
            font-weight: 600;
            font-size: 0.9em;
            margin-bottom: 0.5em;
            color: var(--c-caption);
        }
        .toc ul {
            margin-bottom: 0;
            padding-left: 1.2em;
            list-style: none;
        }
        .toc > ul { padding-left: 0; }
        .toc li { margin-bottom: 0.15em; }
        .toc a { font-size: 0.9em; }

        /* Heading anchor links */
        .heading-anchor {
            position: absolute;
            left: -1.2em;
            opacity: 0;
            text-decoration: none;
            color: var(--c-anchor);
            font-weight: 400;
            transition: opacity 0.15s ease;
        }
        h1:hover .heading-anchor, h2:hover .heading-anchor, h3:hover .heading-anchor,
        h4:hover .heading-anchor, h5:hover .heading-anchor, h6:hover .heading-anchor {
            opacity: 0.4;
        }
        .heading-anchor:hover { opacity: 1 !important; }

        /* Collapsible details animation */
        details::details-content {
            transition: block-size 0.3s ease, opacity 0.3s ease, content-visibility 0.3s ease allow-discrete;
            block-size: 0;
            opacity: 0;
            overflow: clip;
        }
        details[open]::details-content {
            block-size: auto;
            opacity: 1;
        }

        /* Image lightbox */
        .lightbox-overlay {
            position: fixed;
            inset: 0;
            background: var(--c-lightbox-bg);
            display: flex;
            align-items: center;
            justify-content: center;
            z-index: 9999;
            cursor: zoom-out;
            opacity: 0;
            transition: opacity 0.2s ease;
        }
        .lightbox-img {
            max-width: 90vw;
            max-height: 90vh;
            object-fit: contain;
            border-radius: 8px;
        }

        /* Footnote and annotation popovers */
        .footnote-popover,
        .annotation-popover {
            position: absolute;
            max-width: 400px;
            padding: 14px 18px;
            background: var(--c-popover-bg);
            border: none;
            border-radius: 10px;
            box-shadow: 0 4px 20px var(--c-popover-shadow-1), 0 0 0 0.5px var(--c-popover-shadow-2);
            color: var(--c-text);
            font-size: 0.9em;
            z-index: 100;
            line-height: 1.5;
        }
        .annotation-popover {
            cursor: default;
        }
        .annotation-popover-title {
            font-weight: 650;
            margin-bottom: 0.35em;
        }
        .annotation-popover-meta {
            color: var(--c-caption);
            font-size: 0.85em;
            margin-bottom: 0.6em;
        }
        .footnote-popover p { margin-bottom: 0.5em; }
        .footnote-popover p:last-child { margin-bottom: 0; }
        .footnote-popover code {
            background-color: var(--c-popover-code-bg);
            color: var(--c-text);
        }

        .math-block {
            text-align: center;
            margin: 1em 0;
            overflow-x: auto;
        }

        .math-inline {
            display: inline;
        }

        img {
            max-width: 100%;
            height: auto;
        }

        .img-placeholder {
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 8px;
            padding: 24px 16px;
            border-radius: 10px;
            background-color: var(--c-blockquote-bg);
            border: 1px dashed var(--c-border-strong);
            color: var(--c-anchor);
            font-size: 0.85em;
            margin-bottom: 1em;
            overflow: hidden;
        }

        .img-placeholder span {
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }

        .img-placeholder svg {
            flex-shrink: 0;
            opacity: 0.5;
        }

        /* Mermaid diagrams */
        .mermaid {
            text-align: center;
            margin-bottom: 1em;
            overflow-x: auto;
            color: var(--c-text);
        }

        .mermaid svg {
            max-width: 100%;
            height: auto;
        }

        @media print {
            mark {
                -webkit-print-color-adjust: exact;
                print-color-adjust: exact;
            }
            .callout {
                -webkit-print-color-adjust: exact;
                print-color-adjust: exact;
            }
            .code-copy-btn { display: none !important; }
            .table-copy-btn { display: none !important; }
            .sort-indicator { display: none !important; }
            thead { position: static !important; display: table-header-group; }
            tr:hover td { background-color: transparent !important; }
            th { cursor: default !important; }
            body {
                max-width: none;
                padding: 0;
                margin: 0;
            }
            .wiki-link, .wiki-link-broken { border-bottom: none !important; }
            details.callout > summary::before { content: "" !important; }
            .heading-anchor { display: none !important; }
            .lightbox-overlay { display: none !important; }
            .footnote-popover { display: none !important; }
            .page-break {
                page-break-after: always;
                break-after: page;
                height: 0;
                border: none;
            }
            h1, h2, h3, h4, h5, h6 {
                page-break-after: avoid;
                break-after: avoid;
                page-break-inside: avoid;
                break-inside: avoid;
            }
            p, pre, blockquote, table, .frontmatter, .math-block, .mermaid, img, ul, ol {
                page-break-inside: avoid;
                break-inside: avoid;
            }
            tr {
                page-break-inside: avoid;
                break-inside: avoid;
            }
            img {
                display: block;
            }
        }
        \(exportStructural)
        """
    }

    /// Renders a `:root { ... }` block (or any single-selector variant) with the palette's tokens.
    /// Exposed so tests can compare block-level output without re-parsing the whole stylesheet.
    public static func rootBlock(for palette: PreviewPalette, selector: String = ":root", indent: String = "") -> String {
        let pairs: [(String, String)] = [
            ("--c-text", palette.text),
            ("--c-heading-secondary", palette.headingSecondary),
            ("--c-bg", palette.background),
            ("--c-link", palette.link),
            ("--c-wiki", palette.wiki),
            ("--c-wiki-border", palette.wikiBorder),
            ("--c-wiki-broken", palette.wikiBroken),
            ("--c-wiki-broken-border", palette.wikiBrokenBorder),
            ("--c-tag", palette.tag),
            ("--c-tag-bg", palette.tagBg),
            ("--c-tag-bg-hover", palette.tagBgHover),
            ("--c-code-bg", palette.codeBg),
            ("--c-code-fg", palette.codeFg),
            ("--c-code-filename-bg", palette.codeFilenameBg),
            ("--c-code-filename-fg", palette.codeFilenameFg),
            ("--c-pre-bg", palette.preBg),
            ("--c-pre-fg", palette.preFg),
            ("--c-btn-bg", palette.btnBg),
            ("--c-btn-bg-hover", palette.btnBgHover),
            ("--c-btn-bg-active", palette.btnBgActive),
            ("--c-btn-fg", palette.btnFg),
            ("--c-btn-success", palette.btnSuccess),
            ("--c-blockquote-bg", palette.blockquoteBg),
            ("--c-blockquote-fg", palette.blockquoteFg),
            ("--c-border-subtle", palette.borderSubtle),
            ("--c-border-strong", palette.borderStrong),
            ("--c-th-hover-bg", palette.thHoverBg),
            ("--c-row-hover-bg", palette.rowHoverBg),
            ("--c-caption", palette.caption),
            ("--c-hr-border", palette.hrBorder),
            ("--c-mark-bg", palette.markBg),
            ("--c-annotation-bg", palette.annotationBg),
            ("--c-annotation-border", palette.annotationBorder),
            ("--c-annotation-hover-bg", palette.annotationHoverBg),
            ("--c-callout-default", palette.calloutDefault),
            ("--c-callout-tip", palette.calloutTip),
            ("--c-callout-important", palette.calloutImportant),
            ("--c-callout-warning", palette.calloutWarning),
            ("--c-callout-caution", palette.calloutCaution),
            ("--c-callout-abstract", palette.calloutAbstract),
            ("--c-callout-example", palette.calloutExample),
            ("--c-callout-quote", palette.calloutQuote),
            ("--c-callout-question", palette.calloutQuestion),
            ("--c-toc-bg", palette.tocBg),
            ("--c-anchor", palette.anchor),
            ("--c-popover-bg", palette.popoverBg),
            ("--c-popover-code-bg", palette.popoverCodeBg),
            ("--c-popover-shadow-1", palette.popoverShadow1),
            ("--c-popover-shadow-2", palette.popoverShadow2),
            ("--c-frontmatter-bg", palette.frontmatterBg),
            ("--c-lightbox-bg", palette.lightboxBg),
        ]
        let inner = pairs.map { "\(indent)    \($0.0): \($0.1);" }.joined(separator: "\n")
        return "\(indent)\(selector) {\n\(inner)\n\(indent)}"
    }
}
