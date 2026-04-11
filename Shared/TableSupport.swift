import Foundation

enum TableSupport {
    static func scriptHTML(for htmlBody: String) -> String {
        guard htmlBody.contains("<table") else { return "" }

        let copyIcon = #"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"18\" height=\"18\" viewBox=\"0 0 18 18\"><g fill=\"none\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\" stroke=\"currentColor\"><path d=\"M12.25 5.75H13.75C14.8546 5.75 15.75 6.6454 15.75 7.75V13.75C15.75 14.8546 14.8546 15.75 13.75 15.75H7.75C6.6454 15.75 5.75 14.8546 5.75 13.75V12.25\"></path><path d=\"M10.25 2.25H4.25C3.14543 2.25 2.25 3.14543 2.25 4.25V10.25C2.25 11.3546 3.14543 12.25 4.25 12.25H10.25C11.3546 12.25 12.25 11.3546 12.25 10.25V4.25C12.25 3.14543 11.3546 2.25 10.25 2.25Z\"></path></g></svg>"#
        let checkIcon = #"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"12\" height=\"12\" viewBox=\"0 0 12 12\"><g fill=\"none\" stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"1.5\" stroke=\"currentColor\"><path d=\"m1.76,7.004l2.25,3L10.24,1.746\"></path></g></svg>"#

        return """
        <script>
        (function() {
            var copyIcon = '\(copyIcon)';
            var checkIcon = '\(checkIcon)';

            function positionCopyButton(table, button) {
                if (!button) return;
                var caption = table.querySelector('caption');
                var top = (caption ? caption.getBoundingClientRect().height : 0) + 6;
                button.style.top = top + 'px';
                button.parentElement.style.setProperty('--table-copy-top', top + 'px');
            }

            // Wrap each table in a shell + scrollable container
            document.querySelectorAll('table').forEach(function(table) {
                var shell = document.createElement('div');
                shell.className = 'table-shell';
                var wrapper = document.createElement('div');
                wrapper.className = 'table-wrapper';
                table.parentNode.insertBefore(shell, table);
                shell.appendChild(wrapper);
                wrapper.appendChild(table);
            });

            // Add copy-as-TSV button (only when copyToClipboard handler is available)
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.copyToClipboard) {
                document.querySelectorAll('.table-shell').forEach(function(shell) {
                    var table = shell.querySelector('table');
                    var btn = document.createElement('button');
                    btn.className = 'table-copy-btn';
                    btn.type = 'button';
                    btn.setAttribute('aria-label', 'Copy table as TSV');
                    btn.innerHTML = copyIcon;
                    btn.addEventListener('click', function(e) {
                        e.preventDefault();
                        e.stopPropagation();
                        var tsv = [];
                        table.querySelectorAll('tr').forEach(function(row) {
                            var cells = [];
                            row.querySelectorAll('th, td').forEach(function(cell) {
                                cells.push(cell.textContent.trim());
                            });
                            tsv.push(cells.join('\\t'));
                        });
                        window.webkit.messageHandlers.copyToClipboard.postMessage(tsv.join('\\n'));
                        btn.classList.add('copied');
                        btn.innerHTML = checkIcon;
                        setTimeout(function() {
                            btn.classList.remove('copied');
                            btn.innerHTML = copyIcon;
                        }, 1500);
                    });
                    shell.classList.add('has-copy-btn');
                    shell.appendChild(btn);
                    positionCopyButton(table, btn);
                    window.addEventListener('resize', function() {
                        positionCopyButton(table, btn);
                    });
                });
            }

            // Sortable columns — iterate per-table so colIndex is correct
            document.querySelectorAll('table').forEach(function(table) {
                var thead = table.querySelector('thead');
                if (!thead) return;
                var originalRows = null;

                thead.querySelectorAll('th').forEach(function(th, colIndex) {
                    var span = document.createElement('span');
                    span.className = 'sort-indicator';
                    th.appendChild(span);
                    th.dataset.sortState = '0'; // 0=none, 1=asc, 2=desc

                    th.addEventListener('click', function() {
                        var tbody = table.querySelector('tbody') || table;
                        var rows = Array.from(tbody.querySelectorAll('tr'));
                        var sortState = parseInt(th.dataset.sortState || '0', 10);

                        // Store original order on first sort
                        if (!originalRows) {
                            originalRows = rows.slice();
                        }

                        // Clear other column states in this table
                        thead.querySelectorAll('th').forEach(function(otherTh, i) {
                            if (i !== colIndex) {
                                otherTh.classList.remove('sort-asc', 'sort-desc');
                                otherTh.dataset.sortState = '0';
                                var ind = otherTh.querySelector('.sort-indicator');
                                if (ind) ind.textContent = '';
                            }
                        });

                        sortState = (sortState + 1) % 3;
                        th.dataset.sortState = String(sortState);

                        if (sortState === 0) {
                            th.classList.remove('sort-asc', 'sort-desc');
                            span.textContent = '';
                            if (originalRows) originalRows.forEach(function(row) { tbody.appendChild(row); });
                        } else {
                            var asc = sortState === 1;
                            th.classList.toggle('sort-asc', asc);
                            th.classList.toggle('sort-desc', !asc);
                            span.textContent = asc ? ' \\u25B2' : ' \\u25BC';

                            rows.sort(function(a, b) {
                                var aText = (a.children[colIndex] || {}).textContent || '';
                                var bText = (b.children[colIndex] || {}).textContent || '';
                                var result = aText.localeCompare(bText, undefined, { numeric: true, sensitivity: 'base' });
                                return asc ? result : -result;
                            });
                            rows.forEach(function(row) { tbody.appendChild(row); });
                        }
                    });
                });
            });
        })();
        </script>
        """
    }
}
