import Foundation

public enum MermaidSupport {
    /// Base URL pointing to the bundle's resource directory,
    /// allowing WKWebView to load bundled JS files via relative <script src>.
    public static var resourceBaseURL: URL? {
        Bundle.main.resourceURL
    }

    /// Mermaid <script> tag + initialization JS for preview HTML.
    /// Vendored mermaid.min.js v11 — see Shared/Resources/mermaid.min.js
    public static var scriptHTML: String {
        guard let mermaidURL = resourceURL(named: "mermaid.min.js") else {
            return ""
        }

        return """
        <script src="\(mermaidURL)"></script>
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

    private static func resourceURL(named name: String) -> String? {
        Bundle.main.url(forResource: name, withExtension: nil)?.absoluteString
    }
}

public enum MathSupport {
    public static func scriptHTML(for htmlBody: String) -> String {
        guard htmlBody.contains("math-inline") || htmlBody.contains("math-block") else {
            return ""
        }

        guard let cssURL = Bundle.main.url(forResource: "katex.min.css", withExtension: nil)?.absoluteString,
              let jsURL = Bundle.main.url(forResource: "katex.min.js", withExtension: nil)?.absoluteString else {
            return ""
        }

        return """
        <link rel="stylesheet" href="\(cssURL)">
        <script src="\(jsURL)"></script>
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
