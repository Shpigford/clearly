import Foundation

public enum PreviewCSS {
    public static func css(fontSize: CGFloat = 18, fontFamily: String = "sanFrancisco", forExport: Bool = false, bodyMaxWidth: String = "61em") -> String {
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
    let exportOverrides = forExport ? """
    .wiki-link { color: #34855A !important; border-bottom: none !important; }
    .wiki-link-broken { color: #B35C3A !important; border-bottom: none !important; }
    .md-tag { color: #3A6EA5 !important; background: rgba(58, 110, 165, 0.06) !important; }
    .code-copy-btn { display: none !important; }
    .table-copy-btn { display: none !important; }
    .sort-indicator { display: none !important; }
    thead { position: static !important; }
    thead { display: table-header-group; }
    tr:hover td { background-color: transparent !important; }
    th { cursor: default !important; }
    body {
        color: #1D1D1F !important;
        background: white !important;
        max-width: none !important;
        margin: 0 !important;
        padding: 0 !important;
    }
    a { color: #0071E3 !important; }
    code {
        background-color: #F5F5F7 !important;
        color: #1D1D1F !important;
    }
    pre {
        background-color: #F5F5F7 !important;
        color: #1D1D1F !important;
    }
    pre code {
        background: none !important;
        color: #1D1D1F !important;
    }
    blockquote {
        border: none !important;
        color: #48484A !important;
    }
    table th {
        background-color: transparent !important;
        border-color: rgba(0, 0, 0, 0.12) !important;
    }
    table td {
        border-color: rgba(0, 0, 0, 0.06) !important;
    }
    table tr:nth-child(even) {
        background-color: transparent !important;
    }
    hr {
        border-color: rgba(0, 0, 0, 0.12) !important;
    }
    .img-placeholder {
        background-color: #F5F5F7 !important;
        border-color: rgba(0, 0, 0, 0.12) !important;
        color: #AEAEB2 !important;
    }
    .frontmatter {
        background-color: #F5F5F7 !important;
    }
    .frontmatter dt {
        color: #86868B !important;
    }
    .frontmatter dd {
        color: #1D1D1F !important;
    }
    mark {
        background-color: rgba(255, 212, 0, 0.4) !important;
    }
    .callout {
        border: none !important;
        background-color: rgba(0, 0, 0, 0.03) !important;
    }
    details.callout > summary::before { content: "" !important; }
    .toc { background-color: #F5F5F7 !important; }
    .heading-anchor { display: none !important; }
    .lightbox-overlay { display: none !important; }
    .footnote-popover { display: none !important; }
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
        padding: 40px 64px 48px;
        color: #1D1D1F;
        background-color: #FFFFFF;
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
        background-color: rgba(0, 0, 0, 0.03);
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
        color: #86868B;
        min-width: 6em;
    }

    .frontmatter dt::after {
        content: ":";
    }

    .frontmatter dd {
        margin: 0;
        color: #1D1D1F;
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
    h6 { font-size: 0.9375em; font-weight: 600; text-transform: uppercase; letter-spacing: 0.05em; color: rgba(29, 29, 31, 0.55); }

    p {
        margin-bottom: 1.125em;
    }

    a {
        color: #0071E3;
        text-decoration: none;
    }
    a:hover {
        text-decoration: underline;
    }
    .wiki-link {
        color: #34855A;
        text-decoration: none;
        border-bottom: 1px solid rgba(52, 133, 90, 0.3);
    }
    .wiki-link:hover {
        text-decoration: none;
        border-bottom-color: #34855A;
    }
    .wiki-link-broken {
        color: #B35C3A;
        border-bottom: 1px dashed rgba(179, 92, 58, 0.4);
    }
    .wiki-link-broken:hover {
        text-decoration: none;
        border-bottom-color: #B35C3A;
    }
    .md-tag {
        color: #3A6EA5;
        text-decoration: none;
        background: rgba(58, 110, 165, 0.08);
        padding: 1px 5px;
        border-radius: 3px;
        font-size: 0.9em;
    }
    .md-tag:hover {
        background: rgba(58, 110, 165, 0.15);
    }

    code {
        font-family: "SF Mono", SFMono-Regular, Menlo, monospace;
        font-size: 0.875em;
        background-color: rgba(0, 0, 0, 0.04);
        color: #1D1D1F;
        padding: 0.125em 0.375em;
        border-radius: 5px;
    }

    .code-filename {
        font-family: "SF Mono", SFMono-Regular, Menlo, monospace;
        font-size: 0.8em;
        padding: 0.5em 1.25em;
        background: #EDEDF0;
        border: none;
        border-radius: 10px 10px 0 0;
        color: #86868B;
    }

    pre {
        position: relative;
        background-color: #F5F5F7;
        border: none;
        border-radius: 10px;
        padding: 1.125em 1.25em;
        margin-bottom: 1.25em;
        overflow-x: auto;
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
        background: rgba(0, 0, 0, 0.05);
        color: #86868B;
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
        color: #34C759;
    }

    .code-copy-btn:hover {
        background: rgba(0, 0, 0, 0.08);
    }

    .code-copy-btn:active {
        background: rgba(0, 0, 0, 0.12);
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
        background-color: rgba(0, 0, 0, 0.03);
        border-radius: 8px;
        padding: 0.75em 1.25em;
        margin-left: 0;
        margin-bottom: 1.25em;
        color: #48484A;
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
        border-bottom: 1px solid rgba(0, 0, 0, 0.12);
        cursor: pointer;
        user-select: none;
        white-space: nowrap;
    }

    th:hover {
        background-color: rgba(0, 0, 0, 0.03);
    }

    td {
        border-bottom: 1px solid rgba(0, 0, 0, 0.06);
    }

    tr:nth-child(even) {
        background-color: transparent;
    }

    tr:hover td {
        background-color: rgba(0, 0, 0, 0.02);
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
        color: #86868B;
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
        background: rgba(0, 0, 0, 0.05);
        color: #86868B;
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
        color: #34C759;
    }

    .table-shell:hover .table-copy-btn,
    .table-copy-btn:hover,
    .table-copy-btn:focus-visible {
        opacity: 1;
        pointer-events: auto;
        transform: translateX(0);
    }

    .table-copy-btn:hover {
        background: rgba(0, 0, 0, 0.08);
    }

    .table-copy-btn:active {
        background: rgba(0, 0, 0, 0.12);
    }

    /* Strikethrough */
    del {
        text-decoration: line-through;
        opacity: 0.6;
    }

    hr {
        border: none;
        border-top: 0.5px solid rgba(0, 0, 0, 0.1);
        margin: 2.5em 0;
    }

    .page-break {
        display: block;
        height: 0;
        border-top: 1px dashed rgba(0, 0, 0, 0.12);
        margin: 2em 0;
    }

    /* Highlight/Mark */
    mark {
        background-color: rgba(255, 212, 0, 0.3);
        color: inherit !important;
        padding: 0.1em 0.2em;
        border-radius: 3px;
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
        background-color: rgba(0, 122, 255, 0.1);
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

    .callout-note, .callout-info { background-color: rgba(0, 122, 255, 0.1); }
    .callout-tip { background-color: rgba(52, 199, 89, 0.1); }
    .callout-important { background-color: rgba(175, 82, 222, 0.1); }
    .callout-warning { background-color: rgba(255, 149, 0, 0.1); }
    .callout-caution, .callout-danger { background-color: rgba(255, 59, 48, 0.1); }
    .callout-abstract { background-color: rgba(90, 200, 250, 0.1); }
    .callout-todo { background-color: rgba(0, 122, 255, 0.1); }
    .callout-example { background-color: rgba(88, 86, 214, 0.1); }
    .callout-quote { background-color: rgba(142, 142, 147, 0.1); }
    .callout-bug, .callout-failure { background-color: rgba(255, 59, 48, 0.1); }
    .callout-success { background-color: rgba(52, 199, 89, 0.1); }
    .callout-question { background-color: rgba(255, 204, 0, 0.1); }

    /* Table of Contents */
    .toc {
        background-color: rgba(0, 0, 0, 0.025);
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
        color: #86868B;
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
        color: #AEAEB2;
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
        background: rgba(0, 0, 0, 0.75);
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

    /* Footnote popovers */
    .footnote-popover {
        position: absolute;
        max-width: 400px;
        padding: 14px 18px;
        background: #FFFFFF;
        border: none;
        border-radius: 10px;
        box-shadow: 0 4px 20px rgba(0, 0, 0, 0.08), 0 0 0 0.5px rgba(0, 0, 0, 0.06);
        font-size: 0.9em;
        z-index: 100;
        line-height: 1.5;
    }
    .footnote-popover p { margin-bottom: 0.5em; }
    .footnote-popover p:last-child { margin-bottom: 0; }

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
        background-color: rgba(0, 0, 0, 0.03);
        border: 1px dashed rgba(0, 0, 0, 0.12);
        color: #AEAEB2;
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
    }

    .mermaid svg {
        max-width: 100%;
        height: auto;
    }

    /* ========== Dark Mode ========== */
    @media (prefers-color-scheme: dark) {
        body {
            color: #F5F5F7;
            background-color: #323236;
        }
        a { color: #0A84FF; }
        .wiki-link { color: #5ABF80; border-bottom-color: rgba(90, 191, 128, 0.3); }
        .wiki-link:hover { border-bottom-color: #5ABF80; }
        .wiki-link-broken { color: #D97A57; border-bottom-color: rgba(217, 122, 87, 0.4); }
        .wiki-link-broken:hover { border-bottom-color: #D97A57; }
        .md-tag { color: #7AB0D9; background: rgba(122, 176, 217, 0.12); }
        .md-tag:hover { background: rgba(122, 176, 217, 0.2); }
        h6 { color: rgba(245, 245, 247, 0.55); }
        code {
            background-color: rgba(255, 255, 255, 0.06);
            color: #F5F5F7;
        }
        .code-filename {
            background: rgba(255, 255, 255, 0.07);
            color: #AEAEB2;
        }
        pre {
            background-color: rgba(255, 255, 255, 0.05);
            color: #F5F5F7;
        }
        pre code {
            background: none;
            color: #F5F5F7;
        }
        .code-copy-btn {
            background: rgba(255, 255, 255, 0.07);
            color: #AEAEB2;
        }
        .code-copy-btn:hover {
            background: rgba(255, 255, 255, 0.1);
        }
        .code-copy-btn:active {
            background: rgba(255, 255, 255, 0.14);
        }
        .code-copy-btn.copied {
            color: #30D158;
        }
        blockquote {
            color: #E5E5EA;
            background-color: rgba(255, 255, 255, 0.04);
        }
        table th {
            background-color: transparent;
            border-color: rgba(255, 255, 255, 0.15);
        }
        table th:hover {
            background-color: rgba(255, 255, 255, 0.05);
        }
        table td {
            border-color: rgba(255, 255, 255, 0.08);
        }
        table tr:nth-child(even) {
            background-color: transparent;
        }
        tr:hover td {
            background-color: rgba(255, 255, 255, 0.03);
        }
        caption {
            color: #AEAEB2;
        }
        .table-copy-btn {
            background: rgba(255, 255, 255, 0.07);
            color: #AEAEB2;
        }
        .table-copy-btn:hover {
            background: rgba(255, 255, 255, 0.1);
        }
        .table-copy-btn:active {
            background: rgba(255, 255, 255, 0.14);
        }
        .table-copy-btn.copied {
            color: #30D158;
        }
        hr {
            border-color: rgba(255, 255, 255, 0.1);
        }
        .page-break {
            border-top-color: rgba(255, 255, 255, 0.12);
        }
        mark {
            background-color: rgba(255, 214, 0, 0.25);
        }
        .callout {
            background-color: rgba(10, 132, 255, 0.14);
        }
        .callout-tip { background-color: rgba(48, 209, 88, 0.14); }
        .callout-important { background-color: rgba(191, 90, 242, 0.14); }
        .callout-warning { background-color: rgba(255, 159, 10, 0.14); }
        .callout-caution, .callout-danger { background-color: rgba(255, 69, 58, 0.14); }
        .callout-abstract { background-color: rgba(100, 210, 255, 0.14); }
        .callout-example { background-color: rgba(94, 92, 230, 0.14); }
        .callout-quote { background-color: rgba(152, 152, 157, 0.14); }
        .callout-bug, .callout-failure { background-color: rgba(255, 69, 58, 0.14); }
        .callout-success { background-color: rgba(48, 209, 88, 0.14); }
        .callout-question { background-color: rgba(255, 214, 10, 0.14); }
        .toc {
            background-color: rgba(255, 255, 255, 0.035);
        }
        .toc::before { color: #AEAEB2; }
        .heading-anchor { color: rgba(255, 255, 255, 0.2); }
        .frontmatter {
            background-color: rgba(255, 255, 255, 0.04);
        }
        .frontmatter dt {
            color: #AEAEB2;
        }
        .frontmatter dd {
            color: #F5F5F7;
        }
        .footnote-popover {
            background: #2C2C2E;
            color: #F5F5F7;
            box-shadow: 0 4px 24px rgba(0, 0, 0, 0.35), 0 0 0 0.5px rgba(255, 255, 255, 0.08);
        }
        .footnote-popover code {
            background-color: rgba(255, 255, 255, 0.08);
            color: #F5F5F7;
        }
        .mermaid {
            color: #F5F5F7;
        }
        .img-placeholder {
            background-color: rgba(255, 255, 255, 0.04);
            border-color: rgba(255, 255, 255, 0.12);
            color: #8E8E93;
        }
    }

    @media print {
        .wiki-link { color: #34855A !important; border-bottom: none !important; }
        .wiki-link-broken { color: #B35C3A !important; border-bottom: none !important; }
        .md-tag { color: #3A6EA5 !important; background: rgba(58, 110, 165, 0.06) !important; }
        .code-filename {
            background: #EDEDF0 !important;
            color: #86868B !important;
        }
        .code-copy-btn { display: none !important; }
        .table-copy-btn { display: none !important; }
        .sort-indicator { display: none !important; }
        thead { position: static !important; }
        thead { display: table-header-group; }
        tr:hover td { background-color: transparent !important; }
        th { cursor: default !important; }
        body {
            color: #1D1D1F !important;
            background-color: #FFFFFF !important;
            max-width: none;
            padding: 0;
            margin: 0;
        }
        a { color: #0071E3 !important; }
        code {
            background-color: #F5F5F7 !important;
            color: #1D1D1F !important;
        }
        pre {
            background-color: #F5F5F7 !important;
            color: #1D1D1F !important;
        }
        pre code {
            background: none !important;
            color: #1D1D1F !important;
        }
        blockquote {
            border-left-color: rgba(0, 0, 0, 0.15) !important;
            color: #48484A !important;
        }
        th {
            background-color: transparent !important;
            border-color: rgba(0, 0, 0, 0.12) !important;
        }
        td {
            border-color: rgba(0, 0, 0, 0.06) !important;
        }
        tr:nth-child(even) {
            background-color: transparent !important;
        }
        hr {
            border-color: rgba(0, 0, 0, 0.12) !important;
        }
        .img-placeholder {
            background-color: #F5F5F7 !important;
            border-color: rgba(0, 0, 0, 0.12) !important;
            color: #AEAEB2 !important;
        }
        .frontmatter {
            background-color: #F5F5F7 !important;
        }
        .frontmatter dt {
            color: #86868B !important;
        }
        .frontmatter dd {
            color: #1D1D1F !important;
        }
        mark {
            background-color: rgba(255, 212, 0, 0.4) !important;
            -webkit-print-color-adjust: exact;
            print-color-adjust: exact;
        }
        .callout {
            border: none !important;
            -webkit-print-color-adjust: exact;
            print-color-adjust: exact;
        }
        details.callout > summary::before { content: "" !important; }
        .toc { background-color: #F5F5F7 !important; }
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
    \(exportOverrides)
    """
    }
}
