import SwiftUI
import WebKit
import Combine

struct PreviewView: NSViewRepresentable {
    let markdown: String
    var fontSize: CGFloat = 18
    var scrollSync: ScrollSync?
    var fileURL: URL?
    var findState: FindState?
    var outlineState: OutlineState?
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
        context.coordinator.findState = findState
        context.coordinator.outlineState = outlineState
        scrollSync?.previewWebView = webView
        if let findState {
            context.coordinator.observeFindState(findState, webView: webView)
        }
        outlineState?.scrollToPreviewAnchor = { [weak coordinator = context.coordinator] anchor in
            coordinator?.scrollToHeading(anchor: anchor)
        }

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
        <style>\(PreviewCSS.css(fontSize: fontSize))
        mark.clearly-find { background-color: rgba(255, 230, 0, 0.4); border-radius: 2px; padding: 0 1px; }
        mark.clearly-find.current { background-color: rgba(255, 165, 0, 0.6); }
        @media (prefers-color-scheme: dark) {
            mark.clearly-find { background-color: rgba(180, 150, 0, 0.4); }
            mark.clearly-find.current { background-color: rgba(200, 150, 0, 0.6); }
        }
        </style>
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
        webView.loadHTMLString(html, baseURL: fileURL?.deletingLastPathComponent() ?? MermaidSupport.resourceBaseURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var scrollSync: ScrollSync?
        var lastContentKey: String?
        var didInitialLoad = false
        var fileURL: URL?
        var findState: FindState?
        var outlineState: OutlineState?
        weak var webView: WKWebView?
        private var findCancellables = Set<AnyCancellable>()
        private var matchCount = 0
        private var currentMatchIdx = 0

        func observeFindState(_ state: FindState, webView: WKWebView) {
            self.webView = webView
            findCancellables.removeAll()

            state.$query
                .removeDuplicates()
                .sink { [weak self] query in
                    guard let self, self.findState?.isVisible == true else { return }
                    self.performFind(query: query)
                }
                .store(in: &findCancellables)

            state.$isVisible
                .removeDuplicates()
                .sink { [weak self] visible in
                    guard let self else { return }
                    if visible {
                        self.setNavigationClosures()
                        self.performFind(query: self.findState?.query ?? "")
                    } else {
                        self.clearFindHighlights()
                    }
                }
                .store(in: &findCancellables)
        }

        private func setNavigationClosures() {
            findState?.navigateToNext = { [weak self] in
                self?.navigateToNextMatch()
            }
            findState?.navigateToPrevious = { [weak self] in
                self?.navigateToPreviousMatch()
            }
        }

        func scrollToHeading(anchor: PreviewSourceAnchor) {
            let js = """
            (function() {
                var headings = document.querySelectorAll('h1,h2,h3,h4,h5,h6');
                for (var i = 0; i < headings.length; i++) {
                    var sp = headings[i].getAttribute('data-sourcepos');
                    if (!sp) continue;
                    var match = /^(\\d+):(\\d+)-(\\d+):(\\d+)$/.exec(sp);
                    if (!match) continue;
                    if (
                        parseInt(match[1], 10) === \(anchor.startLine) &&
                        parseInt(match[2], 10) === \(anchor.startColumn)
                    ) {
                        headings[i].scrollIntoView({behavior:'smooth', block:'start'});
                        return;
                    }
                }
            })();
            """
            webView?.evaluateJavaScript(js)
        }

        private func performFind(query: String) {
            guard let webView, didInitialLoad else { return }
            guard !query.isEmpty else {
                clearFindHighlights()
                return
            }

            let escaped = query
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")

            let js = """
            (function() {
                document.querySelectorAll('mark.clearly-find').forEach(function(m) {
                    var p = m.parentNode;
                    p.replaceChild(document.createTextNode(m.textContent), m);
                    p.normalize();
                });
                var query = '\(escaped)';
                var count = 0;
                var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
                var nodes = [];
                while (walker.nextNode()) {
                    if (walker.currentNode.parentElement.closest('script,style')) continue;
                    nodes.push(walker.currentNode);
                }
                nodes.forEach(function(node) {
                    var text = node.textContent;
                    var lower = text.toLowerCase();
                    var lq = query.toLowerCase();
                    if (lower.indexOf(lq) === -1) return;
                    var frag = document.createDocumentFragment();
                    var last = 0, idx;
                    while ((idx = lower.indexOf(lq, last)) !== -1) {
                        if (idx > last) frag.appendChild(document.createTextNode(text.substring(last, idx)));
                        var mark = document.createElement('mark');
                        mark.className = 'clearly-find';
                        mark.dataset.idx = count;
                        mark.textContent = text.substring(idx, idx + query.length);
                        frag.appendChild(mark);
                        count++;
                        last = idx + query.length;
                    }
                    if (last < text.length) frag.appendChild(document.createTextNode(text.substring(last)));
                    node.parentNode.replaceChild(frag, node);
                });
                var first = document.querySelector('mark.clearly-find');
                if (first) { first.classList.add('current'); first.scrollIntoView({block:'center'}); }
                return count;
            })();
            """

            webView.evaluateJavaScript(js) { [weak self] result, _ in
                guard let self else { return }
                let count = (result as? Int) ?? 0
                self.matchCount = count
                self.currentMatchIdx = 0
                DispatchQueue.main.async {
                    self.findState?.matchCount = count
                    self.findState?.currentIndex = count > 0 ? 1 : 0
                }
            }
        }

        private func navigateToNextMatch() {
            guard matchCount > 0 else { return }
            currentMatchIdx = (currentMatchIdx + 1) % matchCount
            navigateToMatch(currentMatchIdx)
        }

        private func navigateToPreviousMatch() {
            guard matchCount > 0 else { return }
            currentMatchIdx = (currentMatchIdx - 1 + matchCount) % matchCount
            navigateToMatch(currentMatchIdx)
        }

        private func navigateToMatch(_ index: Int) {
            let js = """
            (function() {
                var marks = document.querySelectorAll('mark.clearly-find');
                marks.forEach(function(m) { m.classList.remove('current'); });
                if (marks[\(index)]) {
                    marks[\(index)].classList.add('current');
                    marks[\(index)].scrollIntoView({block:'center'});
                }
            })();
            """
            webView?.evaluateJavaScript(js)
            DispatchQueue.main.async { [weak self] in
                self?.findState?.currentIndex = index + 1
            }
        }

        private func clearFindHighlights() {
            let js = """
            (function() {
                document.querySelectorAll('mark.clearly-find').forEach(function(m) {
                    var p = m.parentNode;
                    p.replaceChild(document.createTextNode(m.textContent), m);
                    p.normalize();
                });
            })();
            """
            webView?.evaluateJavaScript(js)
            matchCount = 0
            currentMatchIdx = 0
            DispatchQueue.main.async { [weak self] in
                self?.findState?.matchCount = 0
                self?.findState?.currentIndex = 0
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if !didInitialLoad {
                webView.alphaValue = 1
                didInitialLoad = true
            }
            scrollSync?.syncPreview()
            // Re-apply find highlights after page reload
            if let query = findState?.query, findState?.isVisible == true, !query.isEmpty {
                performFind(query: query)
            }
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
