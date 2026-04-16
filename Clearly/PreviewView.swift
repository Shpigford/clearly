import SwiftUI
import WebKit
import Combine

/// WKWebView subclass that allows window dragging from the top region.
/// WKWebView normally consumes all mouse events, blocking `isMovableByWindowBackground`.
/// This intercepts mouseDown in the top strip and calls `performDrag` instead.
private final class DraggableWKWebView: WKWebView {
    static let dragHeight: CGFloat = 28

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        // WKWebView is flipped (y=0 at top)
        if local.y <= Self.dragHeight {
            window?.performDrag(with: event)
            return
        }
        super.mouseDown(with: event)
    }
}

struct PreviewView: NSViewRepresentable {
    let markdown: String
    var fontSize: CGFloat = 18
    var fontFamily: String = "sanFrancisco"
    var mode: ViewMode
    var positionSyncID: String
    var fileURL: URL?
    var findState: FindState?
    var outlineState: OutlineState?
    var onTaskToggle: ((Int, Bool) -> Void)?
    var onClickToSource: ((Int) -> Void)?
    var onWikiLinkClicked: ((String, String?) -> Void)?
    var onTagClicked: ((String) -> Void)?
    var wikiFileNames: Set<String>?
    var contentWidthEm: CGFloat? = nil
    var extraTopInset: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    private var bodyMaxWidthCSS: String {
        guard let contentWidthEm else { return "none" }
        // Body padding is part of the box width, so add it back to match editor text width.
        return "calc(\(Int(contentWidthEm))em + 128px)"
    }

    private var contentKey: String {
        "\(markdown)__\(fontSize)__\(fontFamily)__\(colorScheme == .dark ? "dark" : "light")__\(LocalImageSupport.fileURLKeyFragment(fileURL))__\(wikiFilesKey)__\(contentWidthEm.map { "\($0)" } ?? "off")"
    }

    private var wikiFilesKey: String {
        (wikiFileNames ?? []).sorted().joined(separator: "\n")
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(LocalImageSchemeHandler(), forURLScheme: LocalImageSupport.scheme)
        config.userContentController.add(context.coordinator, name: "linkClicked")
        config.userContentController.add(context.coordinator, name: "scrollSync")
        config.userContentController.add(context.coordinator, name: "copyToClipboard")
        config.userContentController.add(context.coordinator, name: "taskToggle")
        config.userContentController.add(context.coordinator, name: "clickToSource")
        config.userContentController.add(context.coordinator, name: "selectionCapture")
        config.userContentController.addUserScript(Self.copyButtonUserScript())
        let webView = DraggableWKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.underPageBackgroundColor = Theme.backgroundColor
        webView.alphaValue = 0 // hidden until content loads
        context.coordinator.fileURL = fileURL
        context.coordinator.positionSyncID = positionSyncID
        context.coordinator.findState = findState
        context.coordinator.outlineState = outlineState
        context.coordinator.onTaskToggle = onTaskToggle
        context.coordinator.onClickToSource = onClickToSource
        context.coordinator.onWikiLinkClicked = onWikiLinkClicked
        context.coordinator.onTagClicked = onTagClicked
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
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleScrollToLine(_:)),
            name: .scrollPreviewToLine,
            object: nil
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleHighlightText(_:)),
            name: .highlightTextInPreview,
            object: nil
        )

        loadHTML(in: webView, context: context)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.isHidden = mode != .preview
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

        // Skip expensive content rendering when preview is hidden.
        // When content changes while hidden, lastContentKey stays stale,
        // so the normal key comparison below will trigger a reload once visible.
        guard mode == .preview else { return }

        if context.coordinator.lastContentKey != contentKey {
            if context.coordinator.skipNextReload {
                // Task toggle already updated the DOM; just sync the content key
                context.coordinator.skipNextReload = false
                context.coordinator.lastContentKey = contentKey
            } else {
                loadHTML(in: webView, context: context)
            }
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "linkClicked")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "scrollSync")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "copyToClipboard")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "taskToggle")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "clickToSource")
    }

    private func loadHTML(in webView: WKWebView, context: Context) {
        context.coordinator.lastContentKey = contentKey
        context.coordinator.isLoadingContent = true
        let rawBody = MarkdownRenderer.renderHTML(markdown, appLinkURLs: true)
        let htmlBody = LocalImageSupport.resolveImageSources(in: rawBody, relativeTo: fileURL)
        let wikiFilesJSON: String = {
            guard let names = wikiFileNames, !names.isEmpty else { return "[]" }
            guard let data = try? JSONSerialization.data(withJSONObject: Array(names)),
                  var json = String(data: data, encoding: .utf8) else { return "[]" }
            // Prevent </script> injection in HTML context
            json = json.replacingOccurrences(of: "</", with: "<\\/")
            return json
        }()
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
        // Capture text selection for highlight-on-mode-switch.
        var _lastSelText = '';
        document.addEventListener('selectionchange', function() {
            var sel = window.getSelection();
            var text = sel ? sel.toString() : '';
            if (text !== _lastSelText) {
                _lastSelText = text;
                window.webkit.messageHandlers.selectionCapture.postMessage({ text: text });
            }
        });
        """
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(PreviewCSS.css(fontSize: fontSize, fontFamily: fontFamily, bodyMaxWidth: bodyMaxWidthCSS))
        mark.clearly-find { background-color: rgba(255, 230, 0, 0.4); border-radius: 2px; padding: 0 1px; }
        mark.clearly-mode-highlight { background: rgba(255, 210, 50, 0.5); border-radius: 3px; padding: 0 1px; transition: background 1.5s ease; }
        mark.clearly-mode-highlight.fade { background: transparent; }
        mark.clearly-find.current { background-color: rgba(255, 165, 0, 0.6); }
        @media (prefers-color-scheme: dark) {
            mark.clearly-find { background-color: rgba(180, 150, 0, 0.4); }
            mark.clearly-find.current { background-color: rgba(200, 150, 0, 0.6); }
        }
        </style>
        </head>
        <body\(extraTopInset > 0 ? " style=\"padding-top: \(Int(extraTopInset))px\"" : "")>\(htmlBody)</body>
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
        // Heading anchor links
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
            var link = document.createElement('a');
            link.className = 'heading-anchor';
            link.href = '#' + h.id;
            link.textContent = '#';
            link.addEventListener('click', function(e) { e.stopPropagation(); });
            h.prepend(link);
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
        // Click-to-source: double-click to jump to editor
        document.addEventListener('dblclick', function(e) {
            var el = e.target;
            while (el && el !== document.body) {
                var sp = el.getAttribute('data-sourcepos');
                if (sp) {
                    var m = /^(\\d+):/.exec(sp);
                    if (m && window.webkit && window.webkit.messageHandlers.clickToSource) {
                        window.webkit.messageHandlers.clickToSource.postMessage(parseInt(m[1], 10));
                    }
                    return;
                }
                el = el.parentElement;
            }
        });
        // Image lightbox
        document.querySelectorAll('img').forEach(function(img) {
            img.style.cursor = 'zoom-in';
            img.addEventListener('click', function(e) {
                e.preventDefault();
                var overlay = document.createElement('div');
                overlay.className = 'lightbox-overlay';
                var clone = img.cloneNode();
                clone.className = 'lightbox-img';
                clone.style.cursor = 'default';
                overlay.appendChild(clone);
                overlay.addEventListener('click', function() {
                    overlay.style.opacity = '0';
                    setTimeout(function() { overlay.remove(); }, 200);
                });
                document.body.appendChild(overlay);
                requestAnimationFrame(function() { overlay.style.opacity = '1'; });
            });
        });
        // Footnote popovers
        document.querySelectorAll('.footnote-ref a, sup.footnote-ref a').forEach(function(a) {
            var popover = null;
            a.addEventListener('mouseenter', function(e) {
                var href = a.getAttribute('href');
                if (!href || !href.startsWith('#')) return;
                var target = document.querySelector(href);
                if (!target) return;
                popover = document.createElement('div');
                popover.className = 'footnote-popover';
                var content = target.cloneNode(true);
                var backref = content.querySelector('.footnote-backref');
                if (backref) backref.remove();
                popover.innerHTML = content.innerHTML;
                document.body.appendChild(popover);
                var rect = a.getBoundingClientRect();
                popover.style.top = (rect.bottom + window.scrollY + 6) + 'px';
                popover.style.left = Math.max(8, Math.min(rect.left, window.innerWidth - 420)) + 'px';
            });
            a.addEventListener('mouseleave', function() {
                if (popover) { popover.remove(); popover = null; }
            });
        });
        // Wiki-link broken detection
        (function() {
            var knownFiles = new Set(\(wikiFilesJSON));
            document.querySelectorAll('a.wiki-link').forEach(function(a) {
                var href = a.getAttribute('href') || '';
                if (!href.startsWith('clearly://wiki/')) return;
                var target = decodeURIComponent(href.replace('clearly://wiki/', '').split('#')[0]);
                if (knownFiles.size > 0 && !knownFiles.has(target.toLowerCase())) {
                    a.classList.add('wiki-link-broken');
                }
            });
        })();
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
        var lastMode: ViewMode?
        var scrollFraction: Double = 0
        var didInitialLoad = false
        var fileURL: URL?
        var positionSyncID = ""
        var findState: FindState?
        var outlineState: OutlineState?
        var onTaskToggle: ((Int, Bool) -> Void)?
        var onClickToSource: ((Int) -> Void)?
        var onWikiLinkClicked: ((String, String?) -> Void)?
        var onTagClicked: ((String) -> Void)?
        var skipNextReload = false
        var isLoadingContent = false
        var pendingScrollLine: Int?
        var pendingHighlightText: String?
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

        @objc func handleScrollToLine(_ notification: Notification) {
            guard let line = notification.userInfo?["line"] as? Int, line > 0 else { return }
            pendingScrollLine = line
            guard !isLoadingContent else { return }
            scrollToPendingLine()
        }

        @objc func handleHighlightText(_ notification: Notification) {
            guard let searchText = notification.userInfo?["text"] as? String,
                  !searchText.isEmpty else { return }
            pendingHighlightText = searchText
            guard !isLoadingContent, let webView else { return }
            applyPendingHighlight()
        }

        private func applyPendingHighlight() {
            guard let searchText = pendingHighlightText, let webView else { return }
            pendingHighlightText = nil
            let escaped = searchText
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
            let js = """
            (function() {
                // Remove any previous mode-highlight marks
                document.querySelectorAll('mark.clearly-mode-highlight').forEach(function(m) {
                    var p = m.parentNode;
                    p.replaceChild(document.createTextNode(m.textContent), m);
                    p.normalize();
                });
                var query = '\(escaped)';
                // Walk text nodes to find the match nearest the current viewport
                var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
                var candidates = [];
                var node;
                while (node = walker.nextNode()) {
                    var idx = node.textContent.indexOf(query);
                    if (idx >= 0) {
                        candidates.push({ node: node, offset: idx });
                    }
                }
                if (candidates.length === 0) return;
                // Pick the candidate closest to the viewport center
                var viewCenter = window.scrollY + window.innerHeight / 2;
                var best = candidates[0];
                var bestDist = Infinity;
                for (var i = 0; i < candidates.length; i++) {
                    var range = document.createRange();
                    range.setStart(candidates[i].node, candidates[i].offset);
                    range.setEnd(candidates[i].node, candidates[i].offset + query.length);
                    var rect = range.getBoundingClientRect();
                    var dist = Math.abs(rect.top + window.scrollY - viewCenter);
                    if (dist < bestDist) {
                        bestDist = dist;
                        best = candidates[i];
                    }
                }
                // Wrap the match in a highlight mark
                var range = document.createRange();
                range.setStart(best.node, best.offset);
                range.setEnd(best.node, best.offset + query.length);
                var mark = document.createElement('mark');
                mark.className = 'clearly-mode-highlight';
                range.surroundContents(mark);
                mark.scrollIntoView({ behavior: 'smooth', block: 'center' });
                // Fade out after a brief pause
                setTimeout(function() {
                    mark.classList.add('fade');
                    setTimeout(function() {
                        var p = mark.parentNode;
                        if (p) {
                            p.replaceChild(document.createTextNode(mark.textContent), mark);
                            p.normalize();
                        }
                    }, 1600);
                }, 100);
            })();
            """
            webView.evaluateJavaScript(js)
        }

        private func scrollToPendingLine() {
            guard let line = pendingScrollLine else { return }
            let js = """
            (function() {
                var targetLine = \(line);
                var candidates = Array.from(document.querySelectorAll('[data-sourcepos]'));
                var best = null;
                for (var i = 0; i < candidates.length; i++) {
                    var sp = candidates[i].getAttribute('data-sourcepos');
                    if (!sp) continue;
                    var match = /^(\\d+):/.exec(sp);
                    if (!match) continue;
                    var startLine = parseInt(match[1], 10);
                    if (startLine === targetLine) {
                        best = candidates[i];
                        break;
                    }
                    if (startLine < targetLine) {
                        best = candidates[i];
                    } else if (best === null) {
                        best = candidates[i];
                        break;
                    } else {
                        break;
                    }
                }
                if (best) {
                    best.scrollIntoView({behavior:'smooth', block:'start'});
                }
            })();
            """
            webView?.evaluateJavaScript(js)
            pendingScrollLine = nil
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
            isLoadingContent = false
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
            scrollToPendingLine()
            applyPendingHighlight()
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
            if href.hasPrefix("clearly://wiki/") {
                let remainder = String(href.dropFirst("clearly://wiki/".count))
                let parts = remainder.components(separatedBy: "#")
                let target = parts[0].removingPercentEncoding ?? parts[0]
                let heading = parts.count > 1 ? (parts[1].removingPercentEncoding ?? parts[1]) : nil
                DispatchQueue.main.async { [weak self] in
                    self?.onWikiLinkClicked?(target, heading)
                }
                return
            }
            if href.hasPrefix("clearly://tag/") {
                let tagName = String(href.dropFirst("clearly://tag/".count))
                    .removingPercentEncoding ?? String(href.dropFirst("clearly://tag/".count))
                DispatchQueue.main.async { [weak self] in
                    self?.onTagClicked?(tagName)
                }
                return
            }
            guard let targetURL = resolvedLinkURL(for: href) else { return }
            NSWorkspace.shared.open(targetURL)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "copyToClipboard", let text = message.body as? String {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                return
            }

            if message.name == "linkClicked", let href = message.body as? String {
                handleLinkClick(href)
                return
            }

            if message.name == "taskToggle", let body = message.body as? [String: Any],
               let sourcepos = body["sourcepos"] as? String,
               let checked = body["checked"] as? Bool {
                // Parse line number from sourcepos "startLine:startCol-endLine:endCol"
                if let dashIdx = sourcepos.firstIndex(of: ":"),
                   let line = Int(sourcepos[sourcepos.startIndex..<dashIdx]) {
                    // The checkbox is already toggled in the DOM — skip the next
                    // HTML reload so the page doesn't flash.
                    skipNextReload = true
                    DispatchQueue.main.async { [weak self] in
                        self?.onTaskToggle?(line, checked)
                    }
                }
                return
            }

            if message.name == "clickToSource", let line = message.body as? Int {
                DispatchQueue.main.async { [weak self] in
                    self?.onClickToSource?(line)
                }
                return
            }

            if message.name == "selectionCapture",
               let body = message.body as? [String: Any],
               let text = body["text"] as? String {
                SelectionBridge.setSelection(text, for: self.positionSyncID)
                return
            }

            guard message.name == "scrollSync",
                  let body = message.body as? [String: Any],
                  let fraction = (body["fraction"] as? NSNumber)?.doubleValue else { return }

            scrollFraction = fraction
            ScrollBridge.setFraction(fraction, for: self.positionSyncID)
        }
    }

    private static func copyButtonUserScript() -> WKUserScript {
        let copyIcon = #"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"18\" height=\"18\" viewBox=\"0 0 18 18\"><g fill=\"none\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\" stroke=\"currentColor\"><path d=\"M12.25 5.75H13.75C14.8546 5.75 15.75 6.6454 15.75 7.75V13.75C15.75 14.8546 14.8546 15.75 13.75 15.75H7.75C6.6454 15.75 5.75 14.8546 5.75 13.75V12.25\"></path><path d=\"M10.25 2.25H4.25C3.14543 2.25 2.25 3.14543 2.25 4.25V10.25C2.25 11.3546 3.14543 12.25 4.25 12.25H10.25C11.3546 12.25 12.25 11.3546 12.25 10.25V4.25C12.25 3.14543 11.3546 2.25 10.25 2.25Z\"></path></g></svg>"#
        let checkIcon = #"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"12\" height=\"12\" viewBox=\"0 0 12 12\"><g fill=\"none\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\" stroke=\"currentColor\"><path d=\"m1.76,7.004l2.25,3L10.24,1.746\"></path></g></svg>"#
        let source = """
        (function() {
            var copyIcon = '\(copyIcon)';
            var checkIcon = '\(checkIcon)';
            document.querySelectorAll('pre').forEach(function(pre) {
                if (pre.closest('.frontmatter') || pre.closest('.code-block-wrapper')) return;
                var wrapper = document.createElement('div');
                wrapper.className = 'code-block-wrapper';
                var prev = pre.previousElementSibling;
                var hasFilename = prev && prev.classList.contains('code-filename');
                if (hasFilename) {
                    pre.parentNode.insertBefore(wrapper, prev);
                    wrapper.appendChild(prev);
                } else {
                    pre.parentNode.insertBefore(wrapper, pre);
                }
                wrapper.appendChild(pre);
                var btn = document.createElement('button');
                btn.className = 'code-copy-btn';
                if (hasFilename) {
                    btn.style.top = (prev.offsetHeight + 6) + 'px';
                }
                btn.type = 'button';
                btn.setAttribute('aria-label', 'Copy code');
                btn.innerHTML = copyIcon;
                btn.addEventListener('click', function(e) {
                    e.preventDefault();
                    e.stopPropagation();
                    var code = pre.querySelector('code');
                    var lines = code ? code.querySelectorAll('.code-line') : null;
                    var text;
                    if (lines && lines.length > 0) {
                        text = Array.from(lines).map(function(l) { return l.textContent; }).join('\\n');
                    } else {
                        text = code ? code.textContent : pre.textContent;
                    }
                    window.webkit.messageHandlers.copyToClipboard.postMessage(text);
                    btn.classList.add('copied');
                    btn.innerHTML = checkIcon;
                    setTimeout(function() {
                        btn.classList.remove('copied');
                        btn.innerHTML = copyIcon;
                    }, 1500);
                });
                wrapper.appendChild(btn);
            });
        })();
        """
        return WKUserScript(
            source: source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
    }
}
