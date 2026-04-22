import SwiftUI
import WebKit
import ClearlyCore

struct PreviewView_iOS: UIViewRepresentable {
    let markdown: String
    let fileURL: URL?
    let fontSize: CGFloat
    let fontFamily: String
    let hideFrontmatter: Bool
    /// When false, the WebView stays mounted but markdown→HTML rendering is
    /// skipped entirely. Avoids running the cmark + post-processing pipeline
    /// on every keystroke when the user is in edit mode and the preview is
    /// hidden. The HTML refreshes the moment `isVisible` flips back to true.
    let isVisible: Bool
    var onWikiLinkClicked: ((String) -> Void)?
    var onTaskToggle: ((Int, Bool) -> Void)?

    init(
        markdown: String,
        fileURL: URL?,
        fontSize: CGFloat = 18,
        fontFamily: String = "sanFrancisco",
        hideFrontmatter: Bool = false,
        isVisible: Bool = true,
        onWikiLinkClicked: ((String) -> Void)? = nil,
        onTaskToggle: ((Int, Bool) -> Void)? = nil
    ) {
        self.markdown = markdown
        self.fileURL = fileURL
        self.fontSize = fontSize
        self.fontFamily = fontFamily
        self.hideFrontmatter = hideFrontmatter
        self.isVisible = isVisible
        self.onWikiLinkClicked = onWikiLinkClicked
        self.onTaskToggle = onTaskToggle
    }

    private var contentKey: String {
        "\(fontSize)|\(fontFamily)|\(hideFrontmatter)|\(markdown.hashValue)"
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(LocalImageSchemeHandler(), forURLScheme: LocalImageSupport.scheme)
        config.userContentController.add(context.coordinator, name: "linkClicked")
        config.userContentController.add(context.coordinator, name: "taskToggle")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = true
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.scrollView.alwaysBounceVertical = true

        context.coordinator.fileURL = fileURL
        context.coordinator.onWikiLinkClicked = onWikiLinkClicked
        context.coordinator.onTaskToggle = onTaskToggle

        if isVisible {
            loadHTML(in: webView, context: context)
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.fileURL = fileURL
        context.coordinator.onWikiLinkClicked = onWikiLinkClicked
        context.coordinator.onTaskToggle = onTaskToggle

        // Skip the markdown→HTML pipeline when the preview is hidden. The
        // moment `isVisible` flips back to true, the next `updateUIView`
        // sees a stale `lastContentKey` and renders fresh content.
        guard isVisible else { return }

        if context.coordinator.lastContentKey != contentKey {
            if context.coordinator.skipNextReload {
                context.coordinator.skipNextReload = false
                context.coordinator.lastContentKey = contentKey
            } else {
                loadHTML(in: webView, context: context)
            }
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "linkClicked")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "taskToggle")
    }

    private func loadHTML(in webView: WKWebView, context: Context) {
        context.coordinator.lastContentKey = contentKey
        let rawBody = MarkdownRenderer.renderHTML(markdown, appLinkURLs: true, includeFrontmatter: !hideFrontmatter)
        let htmlBody = LocalImageSupport.resolveImageSources(in: rawBody, relativeTo: fileURL)

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(PreviewCSS.css(fontSize: fontSize, fontFamily: fontFamily, bodyMaxWidth: "100%"))
        body {
            padding-top: max(16px, env(safe-area-inset-top));
            padding-right: max(20px, env(safe-area-inset-right));
            padding-bottom: max(32px, env(safe-area-inset-bottom));
            padding-left: max(20px, env(safe-area-inset-left));
        }
        </style>
        </head>
        <body>\(htmlBody)</body>
        <script>
        // Image load-error fallback
        document.querySelectorAll('img').forEach(function(img) {
            img.addEventListener('error', function() {
                var el = document.createElement('div');
                el.className = 'img-placeholder';
                var label = img.alt || '';
                el.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="2" ry="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/></svg>' + (label ? '<span>' + label + '</span>' : '');
                img.replaceWith(el);
            });
        });
        // Intercept link clicks and forward to native
        document.addEventListener('click', function(e) {
            var a = e.target.closest('a[href]');
            if (!a) return;
            var href = a.getAttribute('href');
            if (!href) return;
            if (href.startsWith('#')) return;
            e.preventDefault();
            window.webkit.messageHandlers.linkClicked.postMessage(href);
        });
        // Heading anchor ids (no click handlers; purely for #fragment scrolling)
        var usedHeadingIDs = new Set();
        function uniqueHeadingID(base, normalize) {
            var normalized = base || 'section';
            if (normalize) {
                normalized = normalized.toLowerCase().replace(/[^\\w]+/g, '-').replace(/^-|-$/g, '') || 'section';
            }
            var candidate = normalized;
            var suffix = 1;
            while (usedHeadingIDs.has(candidate)) {
                candidate = normalized + '-' + suffix;
                suffix += 1;
            }
            usedHeadingIDs.add(candidate);
            return candidate;
        }
        document.querySelectorAll('h1,h2,h3,h4,h5,h6').forEach(function(h) {
            h.id = uniqueHeadingID(h.id || h.textContent.trim(), !h.id);
        });
        // Task list checkbox toggle
        document.querySelectorAll('input[type="checkbox"]').forEach(function(cb) {
            var li = cb.closest('li');
            if (!li) return;
            cb.removeAttribute('disabled');
            cb.disabled = false;
            cb.style.cursor = 'pointer';
            cb.addEventListener('click', function(e) {
                e.stopPropagation();
                var sp = li.getAttribute('data-sourcepos');
                if (!sp) {
                    var parent = li.closest('[data-sourcepos]');
                    if (parent) sp = parent.getAttribute('data-sourcepos');
                }
                if (sp && window.webkit && window.webkit.messageHandlers.taskToggle) {
                    window.webkit.messageHandlers.taskToggle.postMessage({
                        sourcepos: sp,
                        checked: cb.checked
                    });
                }
            });
        });
        // Image tap-to-zoom (lightweight lightbox)
        document.querySelectorAll('img').forEach(function(img) {
            img.addEventListener('click', function(e) {
                e.preventDefault();
                var overlay = document.createElement('div');
                overlay.className = 'lightbox-overlay';
                var clone = img.cloneNode();
                clone.className = 'lightbox-img';
                overlay.appendChild(clone);
                overlay.addEventListener('click', function() {
                    overlay.style.opacity = '0';
                    setTimeout(function() { overlay.remove(); }, 200);
                });
                document.body.appendChild(overlay);
                requestAnimationFrame(function() { overlay.style.opacity = '1'; });
            });
        });
        </script>
        \(MathSupport.scriptHTML(for: htmlBody))
        \(TableSupport.scriptHTML(for: htmlBody))
        \(MermaidSupport.scriptHTML)
        \(SyntaxHighlightSupport.scriptHTML(for: htmlBody))
        </html>
        """
        webView.loadHTMLString(html, baseURL: fileURL?.deletingLastPathComponent() ?? MermaidSupport.resourceBaseURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastContentKey: String?
        var skipNextReload: Bool = false
        var fileURL: URL?
        var onWikiLinkClicked: ((String) -> Void)?
        var onTaskToggle: ((Int, Bool) -> Void)?

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "linkClicked", let href = message.body as? String {
                handleLinkClick(href)
                return
            }

            if message.name == "taskToggle",
               let body = message.body as? [String: Any],
               let sourcepos = body["sourcepos"] as? String,
               let checked = body["checked"] as? Bool {
                if let dashIdx = sourcepos.firstIndex(of: ":"),
                   let line = Int(sourcepos[sourcepos.startIndex..<dashIdx]) {
                    skipNextReload = true
                    DispatchQueue.main.async { [weak self] in
                        self?.onTaskToggle?(line, checked)
                    }
                }
                return
            }
        }

        private func resolvedLinkURL(for href: String) -> URL? {
            if let url = URL(string: href), url.scheme != nil {
                return url
            }
            if href.hasPrefix("/") {
                return URL(fileURLWithPath: href)
            }
            guard let fileURL else { return nil }
            return URL(string: href, relativeTo: fileURL)?.absoluteURL
        }

        private func handleLinkClick(_ href: String) {
            if href.hasPrefix("clearly://wiki/") {
                let remainder = String(href.dropFirst("clearly://wiki/".count))
                let nameOnly = remainder.components(separatedBy: "#").first ?? remainder
                let target = nameOnly.removingPercentEncoding ?? nameOnly
                DispatchQueue.main.async { [weak self] in
                    self?.onWikiLinkClicked?(target)
                }
                return
            }
            // Other `clearly://` schemes (tags, etc.) are handled in later phases.
            if href.hasPrefix("clearly://") { return }
            guard let url = resolvedLinkURL(for: href) else { return }
            DispatchQueue.main.async {
                UIApplication.shared.open(url)
            }
        }
    }
}
