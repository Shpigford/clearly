import Foundation

public enum SyntaxHighlightSupport {
    public static func scriptHTML(for htmlBody: String) -> String {
        guard htmlBody.contains("class=\"language-") else { return "" }
        guard let cssURL = Bundle.main.url(forResource: "highlight-theme.css", withExtension: nil)?.absoluteString,
              let jsURL = Bundle.main.url(forResource: "highlight.min.js", withExtension: nil)?.absoluteString else {
            return ""
        }

        return """
        <link rel="stylesheet" href="\(cssURL)">
        <script src="\(jsURL)"></script>
        <script>
        (function() {
            if (!window.hljs) return;
            hljs.configure({ ignoreUnescapedHTML: true });
            document.querySelectorAll('pre code[class*="language-"]').forEach(function(el) {
                // Skip mermaid blocks (handled by MermaidSupport)
                if (el.classList.contains('language-mermaid')) return;
                var isDiff = el.classList.contains('language-diff');
                hljs.highlightElement(el);
                // Wrap lines for line numbers and diff highlighting
                var lines = el.innerHTML.split('\\n');
                // Remove trailing empty line
                if (lines.length > 0 && lines[lines.length - 1].trim() === '') {
                    lines.pop();
                }
                var wrapped = lines.map(function(line) {
                    var cls = 'code-line';
                    if (isDiff) {
                        var stripped = line.replace(/<[^>]*>/g, '');
                        if (stripped.charAt(0) === '+') cls += ' diff-add';
                        else if (stripped.charAt(0) === '-') cls += ' diff-del';
                        else if (stripped.startsWith('@@')) cls += ' diff-hunk';
                    }
                    return '<span class="' + cls + '">' + line + '</span>';
                }).join('');
                el.innerHTML = wrapped;
                // Add numbered class for line numbers (skip diff blocks)
                if (!isDiff) {
                    el.classList.add('code-numbered');
                }
            });
        })();
        </script>
        """
    }
}
