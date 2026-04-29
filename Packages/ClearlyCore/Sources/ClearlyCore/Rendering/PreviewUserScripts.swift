import Foundation
import WebKit

/// Shared user scripts injected into both Mac and iOS preview WKWebViews.
/// These run at `atDocumentEnd` after each `loadHTMLString`, walking the
/// rendered DOM to install the code-block chrome (copy + fold buttons),
/// stamp heading-scoped fold keys, and wire postMessage handlers.
public enum PreviewUserScripts {

    /// Single combined script: wraps each `<pre>` in `.code-block-wrapper`,
    /// stamps `data-fold-key`, injects fold chevron + copy button, and
    /// registers click handlers that talk to native handlers
    /// `copyToClipboard` and `foldToggle`.
    public static func codeBlockChromeScript() -> WKUserScript {
        let copyIcon = #"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"18\" height=\"18\" viewBox=\"0 0 18 18\"><g fill=\"none\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\" stroke=\"currentColor\"><path d=\"M12.25 5.75H13.75C14.8546 5.75 15.75 6.6454 15.75 7.75V13.75C15.75 14.8546 14.8546 15.75 13.75 15.75H7.75C6.6454 15.75 5.75 14.8546 5.75 13.75V12.25\"></path><path d=\"M10.25 2.25H4.25C3.14543 2.25 2.25 3.14543 2.25 4.25V10.25C2.25 11.3546 3.14543 12.25 4.25 12.25H10.25C11.3546 12.25 12.25 11.3546 12.25 10.25V4.25C12.25 3.14543 11.3546 2.25 10.25 2.25Z\"></path></g></svg>"#
        let checkIcon = #"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"12\" height=\"12\" viewBox=\"0 0 12 12\"><g fill=\"none\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\" stroke=\"currentColor\"><path d=\"m1.76,7.004l2.25,3L10.24,1.746\"></path></g></svg>"#
        let chevronIcon = #"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"14\" height=\"14\" viewBox=\"0 0 14 14\"><path fill=\"none\" stroke=\"currentColor\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.75\" d=\"M3.5 5l3.5 3.5L10.5 5\"></path></svg>"#

        let source = """
        (function() {
            var copyIcon = '\(copyIcon)';
            var checkIcon = '\(checkIcon)';
            var chevronIcon = '\(chevronIcon)';

            // --- Fold-key derivation: walk DOM in order, track heading stack. ---
            var headingStack = []; // [{level, title}]
            var counterStack = []; // counters[i] = blocks under headingStack[i]
            var rootCounter = 0;

            function popToLevel(level) {
                while (headingStack.length > 0 &&
                       headingStack[headingStack.length - 1].level >= level) {
                    headingStack.pop();
                    counterStack.pop();
                }
            }

            function nextIndexUnderHeading() {
                if (counterStack.length === 0) {
                    var idx = rootCounter;
                    rootCounter += 1;
                    return idx;
                }
                var idx = counterStack[counterStack.length - 1];
                counterStack[counterStack.length - 1] = idx + 1;
                return idx;
            }

            function currentHeadingPath() {
                return headingStack.map(function(h) { return h.title; });
            }

            function buildFoldKey() {
                var key = {
                    headingPath: currentHeadingPath(),
                    indexUnderHeading: nextIndexUnderHeading()
                };
                // Match Swift JSONEncoder.OutputFormatting.sortedKeys: keys
                // in alphabetical order. Hand-build the JSON to guarantee it.
                return JSON.stringify({
                    headingPath: key.headingPath,
                    indexUnderHeading: key.indexUnderHeading
                });
            }

            // Single in-order traversal of body's direct descendants.
            // Headings under nested elements (e.g. inside callouts) are not
            // stack-pushed; this matches the Swift outline parser's behavior
            // of only treating top-level headings as scope-defining.
            // Persisted fold keys are only stamped on top-level blocks, but
            // every rendered <pre> still gets copy/fold chrome below.
            var topLevelFoldKeys = new WeakMap();

            for (let el = document.body.firstElementChild; el; el = el.nextElementSibling) {
                let tag = el.tagName;
                if (/^H[1-6]$/.test(tag)) {
                    let level = parseInt(tag.charAt(1), 10);
                    popToLevel(level);
                    headingStack.push({ level: level, title: (el.textContent || '').trim() });
                    counterStack.push(0);
                    continue;
                }
                // We only care about <pre> blocks that aren't inside a frontmatter wrapper.
                let pre = null;
                if (tag === 'PRE') {
                    pre = el;
                } else if (el.classList && el.classList.contains('code-filename')) {
                    // The next sibling should be a <pre>; we'll process it on its own iteration.
                    continue;
                }
                if (!pre) continue;
                if (pre.closest && pre.closest('.frontmatter')) continue;
                if (pre.closest && pre.closest('.code-block-wrapper')) continue;
                topLevelFoldKeys.set(pre, buildFoldKey());
            }

            document.querySelectorAll('pre').forEach(function(pre) {
                if (pre.closest && pre.closest('.frontmatter')) return;
                if (pre.closest && pre.closest('.code-block-wrapper')) return;

                // Wrap <pre> (possibly with preceding .code-filename) in .code-block-wrapper.
                let wrapper = document.createElement('div');
                wrapper.className = 'code-block-wrapper';
                let prev = pre.previousElementSibling;
                let hasFilename = prev && prev.classList && prev.classList.contains('code-filename');
                if (hasFilename) {
                    pre.parentNode.insertBefore(wrapper, prev);
                    wrapper.appendChild(prev);
                } else {
                    pre.parentNode.insertBefore(wrapper, pre);
                }
                wrapper.appendChild(pre);

                // Stamp fold key.
                let foldKey = topLevelFoldKeys.get(pre) || '';
                if (foldKey) wrapper.setAttribute('data-fold-key', foldKey);

                // Detect language from <code class="language-xxx"> if present.
                let codeEl = pre.querySelector('code');
                let lang = '';
                if (codeEl && codeEl.classList) {
                    for (let c = 0; c < codeEl.classList.length; c++) {
                        let cls = codeEl.classList[c];
                        if (cls.indexOf('language-') === 0) {
                            lang = cls.substring(9);
                            break;
                        }
                    }
                }

                // Fold button.
                let foldBtn = document.createElement('button');
                foldBtn.className = 'code-fold-btn';
                foldBtn.type = 'button';
                foldBtn.setAttribute('aria-label', 'Fold code block');
                foldBtn.setAttribute('aria-expanded', 'true');
                foldBtn.innerHTML = chevronIcon;
                if (hasFilename) {
                    foldBtn.style.top = (prev.offsetHeight + 6) + 'px';
                }
                foldBtn.addEventListener('click', function(e) {
                    e.preventDefault();
                    e.stopPropagation();
                    toggleFold(wrapper, foldBtn, /*notifyNative=*/true);
                });
                foldBtn.addEventListener('keydown', function(e) {
                    if (e.key === ' ' || e.key === 'Enter') {
                        e.preventDefault();
                        toggleFold(wrapper, foldBtn, /*notifyNative=*/true);
                    }
                });
                wrapper.appendChild(foldBtn);

                // Copy button (existing behavior).
                let copyBtn = document.createElement('button');
                copyBtn.className = 'code-copy-btn';
                copyBtn.type = 'button';
                copyBtn.setAttribute('aria-label', 'Copy code');
                copyBtn.innerHTML = copyIcon;
                if (hasFilename) {
                    copyBtn.style.top = (prev.offsetHeight + 6) + 'px';
                }
                copyBtn.addEventListener('click', function(e) {
                    e.preventDefault();
                    e.stopPropagation();
                    let lines = codeEl ? codeEl.querySelectorAll('.code-line') : null;
                    let text;
                    if (lines && lines.length > 0) {
                        text = Array.from(lines).map(function(l) { return l.textContent; }).join('\\n');
                    } else {
                        text = codeEl ? codeEl.textContent : pre.textContent;
                    }
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.copyToClipboard) {
                        window.webkit.messageHandlers.copyToClipboard.postMessage(text);
                    }
                    copyBtn.classList.add('copied');
                    copyBtn.innerHTML = checkIcon;
                    setTimeout(function() {
                        copyBtn.classList.remove('copied');
                        copyBtn.innerHTML = copyIcon;
                    }, 1500);
                });
                wrapper.appendChild(copyBtn);

                // Build the fold summary (lang + first non-blank line + count).
                let summary = document.createElement('div');
                summary.className = 'code-fold-summary';
                summary.setAttribute('role', 'button');
                summary.setAttribute('tabindex', '0');
                summary.setAttribute('aria-label', 'Unfold code block');
                let langEl = document.createElement('span');
                langEl.className = 'code-fold-lang';
                langEl.textContent = lang || 'code';
                let firstLineEl = document.createElement('span');
                firstLineEl.className = 'code-fold-firstline';
                let metaEl = document.createElement('span');
                metaEl.className = 'code-fold-meta';

                let summaryComputed = computeSummaryParts(pre, codeEl);
                firstLineEl.textContent = summaryComputed.firstLine;
                metaEl.textContent = summaryComputed.totalLines > 1
                    ? '+' + (summaryComputed.totalLines - 1) + ' more line' + (summaryComputed.totalLines - 1 === 1 ? '' : 's')
                    : '';

                summary.appendChild(langEl);
                summary.appendChild(firstLineEl);
                if (metaEl.textContent) summary.appendChild(metaEl);
                summary.addEventListener('click', function(e) {
                    e.preventDefault();
                    toggleFold(wrapper, foldBtn, /*notifyNative=*/true);
                });
                wrapper.appendChild(summary);
            });

            function computeSummaryParts(pre, codeEl) {
                var lines = codeEl ? codeEl.querySelectorAll('.code-line') : null;
                var first = '';
                var total = 0;
                if (lines && lines.length > 0) {
                    total = lines.length;
                    for (var i = 0; i < lines.length; i++) {
                        var t = (lines[i].textContent || '').trim();
                        if (t.length) { first = t; break; }
                    }
                    if (!first && lines.length) first = (lines[0].textContent || '');
                } else {
                    var raw = (codeEl ? codeEl.textContent : pre.textContent) || '';
                    var parts = raw.split('\\n');
                    total = parts.length;
                    for (var j = 0; j < parts.length; j++) {
                        if (parts[j].trim().length) { first = parts[j].trim(); break; }
                    }
                    if (!first && parts.length) first = parts[0];
                }
                if (first.length > 80) first = first.substring(0, 77) + '…';
                return { firstLine: first, totalLines: total };
            }

            function toggleFold(wrapper, btn, notifyNative) {
                var folded = !wrapper.classList.contains('is-folded');
                applyFold(wrapper, btn, folded);
                if (notifyNative) {
                    var key = wrapper.getAttribute('data-fold-key') || '';
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.foldToggle) {
                        window.webkit.messageHandlers.foldToggle.postMessage({ key: key, folded: folded });
                    }
                }
            }

            function applyFold(wrapper, btn, folded) {
                if (folded) {
                    wrapper.classList.add('is-folded');
                    if (btn) {
                        btn.setAttribute('aria-expanded', 'false');
                        btn.setAttribute('aria-label', 'Unfold code block');
                    }
                } else {
                    wrapper.classList.remove('is-folded');
                    if (btn) {
                        btn.setAttribute('aria-expanded', 'true');
                        btn.setAttribute('aria-label', 'Fold code block');
                    }
                }
            }

            // Expose an API for native code to apply persisted fold state
            // after didFinish.
            window.clearlyApplyFolds = function(foldedKeys) {
                if (!foldedKeys || foldedKeys.length === 0) return;
                var lookup = {};
                for (var i = 0; i < foldedKeys.length; i++) {
                    lookup[foldedKeys[i]] = true;
                }
                var wrappers = document.querySelectorAll('.code-block-wrapper[data-fold-key]');
                for (var w = 0; w < wrappers.length; w++) {
                    var wrapper = wrappers[w];
                    var key = wrapper.getAttribute('data-fold-key');
                    if (key && lookup[key]) {
                        var btn = wrapper.querySelector('.code-fold-btn');
                        applyFold(wrapper, btn, true);
                    }
                }
            };
        })();
        """
        return WKUserScript(
            source: source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
    }
}
