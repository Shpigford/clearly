import Foundation

enum PreviewCSS {
    static func css(fontSize: CGFloat = 18, forExport: Bool = false) -> String {
    let exportOverrides = forExport ? """
    body {
        color: #222222 !important;
        background: white !important;
        max-width: none !important;
        margin: 0 !important;
        padding: 0 !important;
    }
    a { color: #3366AA !important; }
    code {
        background-color: #F0F0F0 !important;
        color: #CC3333 !important;
    }
    pre {
        background-color: #F5F5F5 !important;
        border-color: #E0E0E0 !important;
        color: #222222 !important;
    }
    pre code {
        background: none !important;
        color: #222222 !important;
    }
    blockquote {
        border-left-color: #CCCCCC !important;
        color: #666666 !important;
    }
    table th {
        background-color: #F5F5F5 !important;
        border-color: #DDDDDD !important;
    }
    table td {
        border-color: #EEEEEE !important;
    }
    table tr:nth-child(even) {
        background-color: #FAFAFA !important;
    }
    hr {
        border-color: #DDDDDD !important;
    }
    .img-placeholder {
        background-color: #F0F0F0 !important;
        border-color: #CCCCCC !important;
        color: #999999 !important;
    }
    .frontmatter {
        background-color: #F0F0F0 !important;
    }
    .frontmatter dt {
        color: #555555 !important;
    }
    .frontmatter dd {
        color: #333333 !important;
    }
    .page-break {
        height: 0 !important;
        border: none !important;
        margin: 0 !important;
    }
    """ : ""

    return """
    * {
        margin: 0;
        padding: 0;
        box-sizing: border-box;
    }

    body {
        font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
        font-size: \(Int(fontSize))px;
        line-height: 1.6;
        max-width: 61em;
        margin: 0 auto;
        padding: 10px 60px 40px;
        color: #222222;
        background-color: #FAFAFA;
        -webkit-font-smoothing: antialiased;
    }

    @media (prefers-color-scheme: dark) {
        body {
            color: #E0E0E0;
            background-color: #1A1A1A;
        }
        a { color: #6699CC; }
        code {
            background-color: #2A2A2A !important;
            color: #E07070 !important;
        }
        pre {
            background-color: #2A2A2A !important;
            border-color: #333333 !important;
            color: #E0E0E0 !important;
        }
        pre code {
            background: none !important;
            color: #E0E0E0 !important;
        }
        blockquote {
            border-left-color: #444444;
            color: #999999;
        }
        table th {
            background-color: #2A2A2A;
            border-color: #444444;
        }
        table td {
            border-color: #333333;
        }
        table tr:nth-child(even) {
            background-color: #222222;
        }
        hr {
            border-color: #333333;
        }
        .frontmatter {
            background-color: #222222 !important;
            border: 1px solid #333333 !important;
        }
        .frontmatter dt {
            color: #777777 !important;
        }
        .frontmatter dd {
            color: #999999 !important;
        }
    }

    h1, h2, h3, h4, h5, h6 {
        font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
        font-weight: 700;
        line-height: 1.3;
        margin-top: 1.5em;
        margin-bottom: 0.5em;
    }

    body > *:first-child {
        margin-top: 0;
    }

    /* Frontmatter metadata */
    .frontmatter {
        margin-bottom: 1.5em;
        padding: 0.75em 1em;
        background-color: #F0F0F0;
        border-radius: 6px;
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
        color: #555555;
        min-width: 6em;
    }

    .frontmatter dt::after {
        content: ":";
    }

    .frontmatter dd {
        margin: 0;
        color: #333333;
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

    h1 { font-size: 2em; }
    h2 { font-size: 1.5em; }
    h3 { font-size: 1.25em; }
    h4 { font-size: 1.1em; }

    p {
        margin-bottom: 1em;
    }

    a {
        color: #3366AA;
        text-decoration: none;
    }
    a:hover {
        text-decoration: underline;
    }

    code {
        font-family: "SF Mono", SFMono-Regular, Menlo, monospace;
        font-size: 0.85em;
        background-color: #F0F0F0;
        color: #CC3333;
        padding: 0.15em 0.35em;
        border-radius: 3px;
    }

    pre {
        background-color: #F5F5F5;
        border: 1px solid #E0E0E0;
        border-radius: 4px;
        padding: 1em;
        margin-bottom: 1em;
        overflow-x: auto;
    }

    pre code {
        background: none;
        color: inherit;
        padding: 0;
        font-size: 0.85em;
    }

    blockquote {
        border-left: 3px solid #CCCCCC;
        padding-left: 1em;
        margin-left: 0;
        margin-bottom: 1em;
        color: #666666;
        font-style: italic;
    }

    ul, ol {
        margin-bottom: 1em;
        padding-left: 1.5em;
    }

    li {
        margin-bottom: 0.25em;
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
    table {
        border-collapse: collapse;
        width: 100%;
        margin-bottom: 1em;
    }

    th, td {
        text-align: left;
        padding: 0.5em 0.75em;
    }

    th {
        font-weight: 600;
        background-color: #F5F5F5;
        border-bottom: 2px solid #DDDDDD;
    }

    td {
        border-bottom: 1px solid #EEEEEE;
    }

    tr:nth-child(even) {
        background-color: #FAFAFA;
    }

    /* Strikethrough */
    del {
        text-decoration: line-through;
        opacity: 0.6;
    }

    hr {
        border: none;
        border-top: 1px solid #DDDDDD;
        margin: 2em 0;
    }

    .page-break {
        display: block;
        height: 0;
        border-top: 2px dashed #CCCCCC;
        margin: 2em 0;
    }

    @media (prefers-color-scheme: dark) {
        .page-break {
            border-top-color: #444444;
        }
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
        border-radius: 6px;
        background-color: #F0F0F0;
        border: 1px dashed #CCCCCC;
        color: #999999;
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

    @media (prefers-color-scheme: dark) {
        .mermaid {
            color: #E0E0E0;
        }
    }

    @media (prefers-color-scheme: dark) {
        .img-placeholder {
            background-color: #2A2A2A;
            border-color: #444444;
            color: #777777;
        }
    }

    @media print {
        body {
            color: #222222 !important;
            background-color: #FFFFFF !important;
            max-width: none;
            padding: 0;
            margin: 0;
        }
        a { color: #3366AA !important; }
        code {
            background-color: #F0F0F0 !important;
            color: #CC3333 !important;
        }
        pre {
            background-color: #F5F5F5 !important;
            border-color: #E0E0E0 !important;
            color: #222222 !important;
        }
        pre code {
            background: none !important;
            color: #222222 !important;
        }
        blockquote {
            border-left-color: #CCCCCC !important;
            color: #666666 !important;
        }
        th {
            background-color: #F5F5F5 !important;
            border-color: #DDDDDD !important;
        }
        td {
            border-color: #EEEEEE !important;
        }
        tr:nth-child(even) {
            background-color: #FAFAFA !important;
        }
        hr {
            border-color: #DDDDDD !important;
        }
        .img-placeholder {
            background-color: #F0F0F0 !important;
            border-color: #CCCCCC !important;
            color: #999999 !important;
        }
        .frontmatter {
            background-color: #F0F0F0 !important;
        }
        .frontmatter dt {
            color: #555555 !important;
        }
        .frontmatter dd {
            color: #333333 !important;
        }
        .page-break {
            page-break-after: always;
            break-after: page;
            height: 0;
            border: none;
        }
    }
    \(exportOverrides)
    """
    }
}
