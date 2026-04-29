import Foundation

public enum MermaidLightboxSupport {
    /// Returns the svg-pan-zoom <script> tag plus inline lightbox JS for
    /// preview HTML. Returns "" when the rendered HTML contains no mermaid
    /// code blocks (saves the ~29 KB svg-pan-zoom payload on diagram-free docs).
    public static func scriptHTML(for htmlBody: String) -> String {
        guard htmlBody.contains("language-mermaid") else { return "" }
        guard let panZoomURL = Bundle.main.url(
            forResource: "svg-pan-zoom.min.js", withExtension: nil
        )?.absoluteString else {
            return ""
        }
        return """
        <script src="\(panZoomURL)"></script>
        <script>
        \(lightboxJS)
        </script>
        """
    }

    private static let lightboxJS: String = #"""
    (function() {
      if (window.__mermaidLightboxInstalled) return;
      window.__mermaidLightboxInstalled = true;

      var DRAG_THRESHOLD = 4;
      var FIT_CLAMP_MAX = 2.0;
      var panZoomInstance = null;
      var activeOverlay = null;
      var savedScrollY = 0;
      var dragState = null;

      // Capture-phase router runs before the page-level bubble-phase listener
      // so we can intercept SVG <a xlink:href> clicks (which closest('a[href]')
      // can miss) and so we can route .mermaid-wrapper background clicks to
      // the lightbox before any other handler eats them.
      document.addEventListener('click', onDocumentClick, true);
      document.addEventListener('keydown', onDocumentKeydown);

      // Mermaid runs asynchronously; the script that initializes it dispatches
      // a 'mermaid-ready' event when mermaid.run() resolves. Listen for it,
      // and immediately decorate if we missed the event.
      if (window.__mermaidReady) {
        decorateMermaidDiagrams();
      } else {
        window.addEventListener('mermaid-ready', decorateMermaidDiagrams);
      }

      function decorateMermaidDiagrams() {
        var diagrams = document.querySelectorAll('.mermaid');
        for (var i = 0; i < diagrams.length; i++) {
          wrapDiagram(diagrams[i]);
        }
      }

      function wrapDiagram(mermaidEl) {
        if (mermaidEl.parentElement &&
            mermaidEl.parentElement.classList.contains('mermaid-wrapper')) {
          return;
        }
        var wrapper = document.createElement('div');
        wrapper.className = 'mermaid-wrapper';
        mermaidEl.parentNode.insertBefore(wrapper, mermaidEl);
        wrapper.appendChild(mermaidEl);

        var icon = document.createElement('div');
        icon.className = 'mermaid-zoom-icon';
        icon.innerHTML =
          '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" ' +
          'viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
          'stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' +
          '<circle cx="11" cy="11" r="7"/>' +
          '<line x1="21" y1="21" x2="16.65" y2="16.65"/>' +
          '<line x1="11" y1="8" x2="11" y2="14"/>' +
          '<line x1="8" y1="11" x2="14" y2="11"/></svg>';
        wrapper.appendChild(icon);
      }

      function onDocumentClick(e) {
        var target = e.target;
        if (!target || !target.closest) return;

        var anchor = target.closest('a');
        if (anchor) {
          // SVG anchors live inside .mermaid; mermaid v11 emits HTML <a href>
          // for click directives in some versions and SVG <a xlink:href> in
          // others. Capture both and forward to native via the existing
          // linkClicked handler so the URL opens in the user's default browser.
          var insideMermaid = !!target.closest('.mermaid');
          if (insideMermaid) {
            var href = anchor.getAttribute('href') ||
                       anchor.getAttribute('xlink:href');
            if (href && href.indexOf('#') !== 0) {
              var linkHandler = window.webkit && window.webkit.messageHandlers &&
                                window.webkit.messageHandlers.linkClicked;
              if (linkHandler) {
                e.preventDefault();
                e.stopPropagation();
                linkHandler.postMessage(href);
              }
            }
            return;
          }
          // Anchors outside mermaid fall through to the existing page-level
          // click listener for normal link handling.
          return;
        }

        // Non-anchor click inside a mermaid wrapper → open the lightbox,
        // unless the click came at the end of a drag-pan inside the lightbox
        // itself (handled separately by the overlay click listener).
        var wrapper = target.closest('.mermaid-wrapper');
        if (!wrapper) return;
        if (activeOverlay) return; // suppress while lightbox open
        e.preventDefault();
        var mermaidEl = wrapper.querySelector('.mermaid');
        if (mermaidEl) openLightbox(mermaidEl);
      }

      function onDocumentKeydown(e) {
        if (!activeOverlay || !panZoomInstance) return;
        if (e.key === 'Escape') {
          e.preventDefault();
          closeLightbox();
        } else if (e.key === '+' || e.key === '=') {
          e.preventDefault();
          panZoomInstance.zoomIn();
          updateZoomReadout();
        } else if (e.key === '-' || e.key === '_') {
          e.preventDefault();
          panZoomInstance.zoomOut();
          updateZoomReadout();
        } else if (e.key === '0') {
          e.preventDefault();
          fitAndCenter();
        }
      }

      function openLightbox(mermaidEl) {
        var svgOriginal = mermaidEl.querySelector('svg');
        if (!svgOriginal) return;

        savedScrollY = window.scrollY || 0;

        var overlay = document.createElement('div');
        overlay.className = 'mermaid-lightbox';
        overlay.tabIndex = -1;

        var stage = document.createElement('div');
        stage.className = 'mermaid-lightbox-stage';

        // svg-pan-zoom mutates its target element. Always work on a clone so
        // the inline diagram (used for re-renders) is left intact.
        var svgClone = svgOriginal.cloneNode(true);
        svgClone.removeAttribute('width');
        svgClone.removeAttribute('height');
        svgClone.style.width = '100%';
        svgClone.style.height = '100%';
        svgClone.style.maxWidth = 'none';
        stage.appendChild(svgClone);

        var controls = buildControls();
        var closeBtn = buildCloseButton();

        overlay.appendChild(stage);
        overlay.appendChild(controls);
        overlay.appendChild(closeBtn);
        document.body.appendChild(overlay);
        document.body.style.overflow = 'hidden';

        activeOverlay = overlay;

        try {
          panZoomInstance = svgPanZoom(svgClone, {
            panEnabled: true,
            zoomEnabled: true,
            controlIconsEnabled: false,
            fit: true,
            center: true,
            minZoom: 0.2,
            maxZoom: 12,
            zoomScaleSensitivity: 0.3,
            dblClickZoomEnabled: false,
            preventMouseEventsDefault: false,
            beforePan: function() { return true; },
            onZoom: updateZoomReadout
          });
          // Clamp the fit zoom so a tiny diagram doesn't blow up to 600%.
          if (panZoomInstance.getZoom() > FIT_CLAMP_MAX) {
            var rect = svgClone.getBoundingClientRect();
            panZoomInstance.zoomAtPoint(FIT_CLAMP_MAX, {
              x: rect.width / 2, y: rect.height / 2
            });
          }
          updateZoomReadout();
          attachOverlayHandlers(overlay, stage, svgClone);
        } catch (err) {
          // Empty / zero-bbox SVGs can throw inside svg-pan-zoom. Render the
          // diagram centered with no zoom controls; user can still close.
          panZoomInstance = null;
          controls.style.display = 'none';
          attachOverlayHandlers(overlay, stage, svgClone);
        }

        // ESC needs focus on the overlay, not on whatever was focused before.
        requestAnimationFrame(function() {
          overlay.classList.add('mermaid-lightbox--open');
          overlay.focus();
        });
      }

      function buildControls() {
        var bar = document.createElement('div');
        bar.className = 'mermaid-lightbox-controls';

        var minus = document.createElement('button');
        minus.type = 'button';
        minus.textContent = '−';
        minus.setAttribute('aria-label', 'Zoom out');
        minus.addEventListener('click', function(e) {
          e.stopPropagation();
          if (panZoomInstance) { panZoomInstance.zoomOut(); updateZoomReadout(); }
        });

        var readout = document.createElement('div');
        readout.className = 'zoom-readout';
        readout.textContent = '100%';

        var plus = document.createElement('button');
        plus.type = 'button';
        plus.textContent = '+';
        plus.setAttribute('aria-label', 'Zoom in');
        plus.addEventListener('click', function(e) {
          e.stopPropagation();
          if (panZoomInstance) { panZoomInstance.zoomIn(); updateZoomReadout(); }
        });

        var fit = document.createElement('button');
        fit.type = 'button';
        fit.textContent = 'Fit';
        fit.setAttribute('aria-label', 'Fit to screen');
        fit.addEventListener('click', function(e) {
          e.stopPropagation();
          fitAndCenter();
        });

        bar.appendChild(minus);
        bar.appendChild(readout);
        bar.appendChild(plus);
        bar.appendChild(fit);
        return bar;
      }

      function buildCloseButton() {
        var btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'mermaid-lightbox-close';
        btn.setAttribute('aria-label', 'Close');
        btn.innerHTML =
          '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" ' +
          'viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
          'stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">' +
          '<line x1="18" y1="6" x2="6" y2="18"/>' +
          '<line x1="6" y1="6" x2="18" y2="18"/></svg>';
        btn.addEventListener('click', function(e) {
          e.stopPropagation();
          closeLightbox();
        });
        return btn;
      }

      function attachOverlayHandlers(overlay, stage, svg) {
        // Track drag distance at document level so a pan that ends with the
        // mouse over the backdrop doesn't synthesize a close-click.
        function onMouseDown(e) {
          if (e.button !== 0) return;
          dragState = {
            startX: e.clientX, startY: e.clientY, dragged: false
          };
        }
        function onMouseMove(e) {
          if (!dragState) return;
          if (Math.abs(e.clientX - dragState.startX) > DRAG_THRESHOLD ||
              Math.abs(e.clientY - dragState.startY) > DRAG_THRESHOLD) {
            dragState.dragged = true;
          }
        }
        document.addEventListener('mousedown', onMouseDown, true);
        document.addEventListener('mousemove', onMouseMove, true);
        overlay._mermaidLightboxCleanup = function() {
          document.removeEventListener('mousedown', onMouseDown, true);
          document.removeEventListener('mousemove', onMouseMove, true);
        };

        overlay.addEventListener('click', function(e) {
          // Anchor inside SVG: capture-phase router already handled it.
          if (e.target.closest('a')) return;
          // Buttons handled their own click via stopPropagation.
          // Drag-mouseup on backdrop should not close.
          if (dragState && dragState.dragged) {
            dragState = null;
            return;
          }
          dragState = null;
          // Close when click is on the backdrop or stage (not the SVG itself).
          if (e.target === overlay ||
              e.target.classList.contains('mermaid-lightbox-stage')) {
            closeLightbox();
          }
        });

        // Double-click inside the SVG toggles fit ↔ 200%.
        svg.addEventListener('dblclick', function(e) {
          e.preventDefault();
          if (!panZoomInstance) return;
          var z = panZoomInstance.getZoom();
          if (z > 1.05) {
            fitAndCenter();
          } else {
            var rect = svg.getBoundingClientRect();
            panZoomInstance.zoomAtPoint(2.0, {
              x: e.clientX - rect.left, y: e.clientY - rect.top
            });
            updateZoomReadout();
          }
        });

        // Suppress page right-click context menu inside the lightbox so it
        // doesn't show "Inspect Element / Reload" defaults during normal use.
        overlay.addEventListener('contextmenu', function(e) {
          e.preventDefault();
        });
      }

      function fitAndCenter() {
        if (!panZoomInstance) return;
        panZoomInstance.resize();
        panZoomInstance.fit();
        panZoomInstance.center();
        if (panZoomInstance.getZoom() > FIT_CLAMP_MAX) {
          panZoomInstance.zoom(FIT_CLAMP_MAX);
        }
        updateZoomReadout();
      }

      function updateZoomReadout() {
        if (!activeOverlay) return;
        var readout = activeOverlay.querySelector('.zoom-readout');
        if (!readout) return;
        var z = panZoomInstance ? panZoomInstance.getZoom() : 1;
        readout.textContent = Math.round(z * 100) + '%';
      }

      function closeLightbox() {
        if (!activeOverlay) return;
        var overlay = activeOverlay;
        activeOverlay = null;

        if (overlay._mermaidLightboxCleanup) {
          overlay._mermaidLightboxCleanup();
          overlay._mermaidLightboxCleanup = null;
        }

        if (panZoomInstance) {
          try { panZoomInstance.destroy(); } catch (e) { /* ignore */ }
          panZoomInstance = null;
        }
        dragState = null;

        overlay.classList.remove('mermaid-lightbox--open');
        document.body.style.overflow = '';
        // Restore scroll position (defensive — overflow:hidden can reset it
        // on some WebKit versions).
        if (savedScrollY) window.scrollTo(0, savedScrollY);

        setTimeout(function() {
          if (overlay.parentNode) overlay.parentNode.removeChild(overlay);
        }, 220);
      }
    })();
    """#
}
