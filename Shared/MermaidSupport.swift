import Foundation

enum MermaidSupport {
    /// Base URL pointing to the bundle's resource directory,
    /// allowing WKWebView to load bundled JS files via relative <script src>.
    static var resourceBaseURL: URL? {
        Bundle.main.resourceURL
    }

    /// Mermaid <script> tag + initialization JS for preview HTML.
    /// Vendored mermaid.min.js v11 — see Shared/Resources/mermaid.min.js
    static let scriptHTML: String = """
    <script src="mermaid.min.js"></script>
    <script>
    (function() {
        var isDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
        mermaid.initialize({
            startOnLoad: false,
            theme: isDark ? 'dark' : 'neutral',
            securityLevel: 'strict'
        });
        document.querySelectorAll('pre code.language-mermaid').forEach(function(codeEl) {
            var pre = codeEl.parentElement;
            var container = document.createElement('div');
            container.className = 'mermaid';
            container.textContent = codeEl.textContent;
            var sp = pre.getAttribute('data-sourcepos');
            if (sp) container.setAttribute('data-sourcepos', sp);
            pre.replaceWith(container);
        });
        mermaid.run().then(function() {
            if (window._scheduleCacheRebuild) {
                window._scheduleCacheRebuild();
            }
        });
    })();
    </script>
    """
}

enum MathSupport {
    static func scriptHTML(for htmlBody: String) -> String {
        guard htmlBody.contains("math-inline") || htmlBody.contains("math-block") else {
            return ""
        }

        return """
        <link rel="stylesheet" href="katex.min.css">
        <script src="katex.min.js"></script>
        <script>
        if (window.katex) {
            document.querySelectorAll('.math-block').forEach(function(el) {
                katex.render(el.textContent, el, { displayMode: true, throwOnError: false });
            });
            document.querySelectorAll('.math-inline').forEach(function(el) {
                katex.render(el.textContent, el, { displayMode: false, throwOnError: false });
            });
        }
        </script>
        """
    }
}
