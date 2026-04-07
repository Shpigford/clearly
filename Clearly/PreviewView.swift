import SwiftUI
import WebKit
import Combine

struct PreviewView: NSViewRepresentable {
    let markdown: String
    var fontSize: CGFloat = 18
    var mode: ViewMode
    var positionSyncID: String
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
        config.userContentController.add(context.coordinator, name: "scrollSync")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.underPageBackgroundColor = Theme.backgroundColor
        webView.alphaValue = 0 // hidden until content loads
        context.coordinator.fileURL = fileURL
        context.coordinator.positionSyncID = positionSyncID
        context.coordinator.findState = findState
        context.coordinator.outlineState = outlineState
        let coordinator = context.coordinator
        findState?.previewNavigateToNext = { [weak coordinator] in
            coordinator?.navigateToNextMatch()
        }
        findState?.previewNavigateToPrevious = { [weak coordinator] in
            coordinator?.navigateToPreviousMatch()
        }
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
        context.coordinator.fileURL = fileURL
        context.coordinator.positionSyncID = positionSyncID

        // Detect mode change: restore scroll position when becoming visible
        if mode == .preview && context.coordinator.lastMode != .preview {
            findState?.activeMode = .preview
            let fraction = ScrollBridge.fraction(for: positionSyncID)
            context.coordinator.scrollFraction = fraction
            let js = "var ms=Math.max(1,document.body.scrollHeight-window.innerHeight);window.scrollTo(0,\(fraction)*ms);"
            webView.evaluateJavaScript(js)
            if findState?.isVisible == true {
                context.coordinator.performFind(query: findState?.query ?? "")
            }
        }
        context.coordinator.lastMode = mode

        if context.coordinator.lastContentKey != contentKey {
            loadHTML(in: webView, context: context)
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "linkClicked")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "scrollSync")
    }

    private func loadHTML(in webView: WKWebView, context: Context) {
        context.coordinator.lastContentKey = contentKey
        let rawBody = MarkdownRenderer.renderHTML(markdown)
        let htmlBody = LocalImageSupport.resolveImageSources(in: rawBody, relativeTo: fileURL)
        let scrollJS = """
        // Track scroll fraction for position sync between editor and preview.
        var _scrollTicking = false;
        window.addEventListener('scroll', function() {
            if (_scrollTicking) return;
            _scrollTicking = true;
            requestAnimationFrame(function() {
                var maxScroll = Math.max(1, document.body.scrollHeight - window.innerHeight);
                var fraction = window.scrollY / maxScroll;
                window.webkit.messageHandlers.scrollSync.postMessage({ fraction: fraction });
                _scrollTicking = false;
            });
        });
        """
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
        var lastContentKey: String?
        var lastMode: ViewMode?
        var scrollFraction: Double = 0
        var didInitialLoad = false
        var fileURL: URL?
        var positionSyncID = ""
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
                    guard let self,
                          let findState = self.findState,
                          findState.isVisible,
                          findState.activeMode == .preview else { return }
                    self.performFind(query: query)
                }
                .store(in: &findCancellables)

            state.$isVisible
                .removeDuplicates()
                .sink { [weak self] visible in
                    guard let self else { return }
                    if visible {
                        guard self.findState?.activeMode == .preview else { return }
                        self.performFind(query: self.findState?.query ?? "")
                    } else {
                        self.clearFindHighlights()
                    }
                }
                .store(in: &findCancellables)
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

        func performFind(query: String) {
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
                    guard self.findState?.activeMode == .preview else { return }
                    self.findState?.matchCount = count
                    self.findState?.currentIndex = count > 0 ? 1 : 0
                }
            }
        }

        func navigateToNextMatch() {
            guard matchCount > 0 else { return }
            currentMatchIdx = (currentMatchIdx + 1) % matchCount
            navigateToMatch(currentMatchIdx)
        }

        func navigateToPreviousMatch() {
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
                guard self?.findState?.activeMode == .preview else { return }
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
                guard self?.findState?.activeMode == .preview || self?.findState?.isVisible == false else { return }
                self?.findState?.matchCount = 0
                self?.findState?.currentIndex = 0
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if !didInitialLoad {
                didInitialLoad = true
            }
            webView.alphaValue = 1
            // Restore scroll position after HTML reload
            if scrollFraction > 0.01 {
                let js = "var ms=Math.max(1,document.body.scrollHeight-window.innerHeight);window.scrollTo(0,\(scrollFraction)*ms);"
                webView.evaluateJavaScript(js)
            }
            // Re-apply find highlights after page reload
            if let query = findState?.query,
               findState?.isVisible == true,
               findState?.activeMode == .preview,
               !query.isEmpty {
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
                  let fraction = (body["fraction"] as? NSNumber)?.doubleValue else { return }

            scrollFraction = fraction
            ScrollBridge.setFraction(fraction, for: self.positionSyncID)
        }
    }
}
