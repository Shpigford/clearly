import SwiftUI
import WebKit

struct PreviewView: NSViewRepresentable {
    let markdown: String
    var fontSize: CGFloat = 18
    var scrollSync: ScrollSync?
    var fileURL: URL?
    @Environment(\.colorScheme) private var colorScheme

    private var contentKey: String {
        "\(markdown)__\(fontSize)__\(colorScheme == .dark ? "dark" : "light")__\(LocalImageSupport.fileURLKeyFragment(fileURL))"
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(LocalImageSchemeHandler(), forURLScheme: LocalImageSupport.scheme)
        config.userContentController.add(context.coordinator, name: "linkClicked")
        if scrollSync != nil {
            config.userContentController.add(context.coordinator, name: "scrollSync")
        }
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.underPageBackgroundColor = Theme.backgroundColor
        webView.alphaValue = 0 // hidden until content loads
        context.coordinator.scrollSync = scrollSync
        context.coordinator.fileURL = fileURL
        scrollSync?.previewWebView = webView
        loadHTML(in: webView, context: context)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.underPageBackgroundColor = Theme.backgroundColor
        context.coordinator.scrollSync = scrollSync
        context.coordinator.fileURL = fileURL
        scrollSync?.previewWebView = webView

        if context.coordinator.lastContentKey != contentKey {
            loadHTML(in: webView, context: context)
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "linkClicked")
        if coordinator.scrollSync != nil {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "scrollSync")
        }
    }

    private func loadHTML(in webView: WKWebView, context: Context) {
        context.coordinator.lastContentKey = contentKey
        let rawBody = MarkdownRenderer.renderHTML(markdown)
        let htmlBody = LocalImageSupport.resolveImageSources(in: rawBody, relativeTo: fileURL)
        let scrollJS = scrollSync != nil ? """
        // Keep block positions fresh when the preview reflows.
        window._spCache = [];
        window._cacheRebuildPending = false;
        window._parseSourcePos = function(sp) {
            var match = /^(\\d+):(\\d+)-(\\d+):(\\d+)$/.exec(sp || '');
            if (!match) return null;
            return {
                startLine: parseInt(match[1], 10),
                startColumn: parseInt(match[2], 10),
                endLine: parseInt(match[3], 10),
                endColumn: parseInt(match[4], 10)
            };
        };
        window._rebuildSpCache = function() {
            window._spCache = [];
            document.querySelectorAll('[data-sourcepos]').forEach(function(el) {
                var pos = window._parseSourcePos(el.getAttribute('data-sourcepos'));
                if (!pos) return;
                var rect = el.getBoundingClientRect();
                window._spCache.push({
                    startLine: pos.startLine,
                    startColumn: pos.startColumn,
                    endLine: pos.endLine,
                    endColumn: pos.endColumn,
                    top: rect.top + window.scrollY,
                    bottom: rect.bottom + window.scrollY
                });
            });
        };
        window._scheduleCacheRebuild = function() {
            if (window._cacheRebuildPending) return;
            window._cacheRebuildPending = true;
            requestAnimationFrame(function() {
                window._cacheRebuildPending = false;
                window._rebuildSpCache();
            });
        };
        window._rebuildSpCache();

        if (window.ResizeObserver) {
            window._resizeObserver = new ResizeObserver(function() {
                window._scheduleCacheRebuild();
            });
            window._resizeObserver.observe(document.body);
        }

        // Smooth scroll loop — decouples async evaluateJavaScript from actual scrolling
        window._targetScrollY = window.scrollY;
        window._syncFromEditor = false;
        (function syncLoop() {
            if (window._syncFromEditor) {
                var diff = window._targetScrollY - window.scrollY;
                if (Math.abs(diff) > 0.5) {
                    window.scrollTo(0, window.scrollY + diff * 0.45);
                } else {
                    window._syncFromEditor = false;
                }
            }
            requestAnimationFrame(syncLoop);
        })();

        // Preview scroll listener for preview→editor sync
        var _scrollTicking = false;
        window.addEventListener('scroll', function() {
            if (window._syncFromEditor) return;
            if (_scrollTicking) return;
            _scrollTicking = true;
            requestAnimationFrame(function() {
                var c = window._spCache;
                var sy = window.scrollY + window.innerHeight / 2;
                if (!c || !c.length) {
                    window.webkit.messageHandlers.scrollSync.postMessage({
                        startLine: 1,
                        startColumn: 1,
                        endLine: 1,
                        endColumn: 1,
                        progress: 0
                    });
                    _scrollTicking = false;
                    return;
                }
                var anchor = {
                    startLine: 1,
                    startColumn: 1,
                    endLine: 1,
                    endColumn: 1,
                    progress: 0
                };
                for (var i = 0; i < c.length; i++) {
                    if (c[i].top > sy) break;
                    anchor = c[i];
                }
                var height = Math.max(1, anchor.bottom - anchor.top);
                var progress = Math.max(0, Math.min(1, (sy - anchor.top) / height));
                window.webkit.messageHandlers.scrollSync.postMessage({
                    startLine: anchor.startLine,
                    startColumn: anchor.startColumn,
                    endLine: anchor.endLine,
                    endColumn: anchor.endColumn,
                    progress: progress
                });
                _scrollTicking = false;
            });
        });
        """ : ""
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(PreviewCSS.css(fontSize: fontSize))</style>
        </head>
        <body>\(htmlBody)</body>
        <script>
        document.querySelectorAll('img').forEach(function(img) {
            if (!img.complete) {
                img.addEventListener('load', function() {
                    window._scheduleCacheRebuild && window._scheduleCacheRebuild();
                }, { once: true });
            }
            img.addEventListener('error', function() {
                var el = document.createElement('div');
                el.className = 'img-placeholder';
                var label = img.alt || '';
                el.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="2" ry="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/></svg>' + (label ? '<span>' + label + '</span>' : '');
                if (img.width) el.style.width = img.width + 'px';
                img.replaceWith(el);
                window._scheduleCacheRebuild && window._scheduleCacheRebuild();
            });
        });
        // Intercept link clicks and forward to native
        document.addEventListener('click', function(e) {
            var a = e.target.closest('a[href]');
            if (!a) return;
            var href = a.getAttribute('href');
            if (!href) return;
            // Allow pure anchor links for in-page scrolling
            if (href.startsWith('#')) return;
            e.preventDefault();
            window.webkit.messageHandlers.linkClicked.postMessage(href);
        });
        \(scrollJS)
        </script>
        \(MathSupport.scriptHTML(for: htmlBody))
        \(MermaidSupport.scriptHTML)
        </html>
        """
        webView.loadHTMLString(html, baseURL: MermaidSupport.resourceBaseURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var scrollSync: ScrollSync?
        var lastContentKey: String?
        var didInitialLoad = false
        var fileURL: URL?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if !didInitialLoad {
                webView.alphaValue = 1
                didInitialLoad = true
            }
            scrollSync?.syncPreview()
        }

        private func resolvedLinkURL(for href: String) -> URL? {
            if let url = URL(string: href),
               url.scheme != nil {
                return url
            }

            if href.hasPrefix("/") {
                return URL(fileURLWithPath: href)
            }

            guard let fileURL else { return nil }
            return URL(string: href, relativeTo: fileURL)?.absoluteURL
        }

        private func handleLinkClick(_ href: String) {
            guard let targetURL = resolvedLinkURL(for: href) else { return }
            NSWorkspace.shared.open(targetURL)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "linkClicked", let href = message.body as? String {
                handleLinkClick(href)
                return
            }

            guard message.name == "scrollSync",
                  let body = message.body as? [String: Any],
                  let startLine = (body["startLine"] as? NSNumber)?.intValue,
                  let startColumn = (body["startColumn"] as? NSNumber)?.intValue,
                  let endLine = (body["endLine"] as? NSNumber)?.intValue,
                  let endColumn = (body["endColumn"] as? NSNumber)?.intValue,
                  let progress = (body["progress"] as? NSNumber)?.doubleValue else { return }

            scrollSync?.previewDidScroll(anchor: PreviewSourceAnchor(
                startLine: startLine,
                startColumn: startColumn,
                endLine: endLine,
                endColumn: endColumn,
                progress: progress
            ))
        }
    }
}
