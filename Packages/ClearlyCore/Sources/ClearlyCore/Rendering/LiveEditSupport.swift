import Foundation

/// Live mode: the rendered preview becomes block-editable. Clicking a block
/// swaps it for an inline editor showing that block's markdown source; leaving
/// the block commits the edited lines back into the document, which re-renders.
///
/// Round-tripping is line-based: cmark's `data-sourcepos` (absolute against the
/// full document — `MarkdownRenderer` corrects for stripped frontmatter) names
/// the exact source lines a block came from, so editing replaces those lines
/// verbatim. The markdown source stays the single source of truth; no HTML →
/// markdown conversion ever happens.
public enum LiveEditSupport {

    // MARK: - Sourcepos line math (pure, testable)

    /// Parses `"startLine:startCol-endLine:endCol"` into an inclusive 1-based
    /// line range. cmark uses `endCol == 0` to mean "the block ended at the
    /// start of endLine", i.e. endLine itself is not part of the block.
    public static func lineRange(fromSourcepos sourcepos: String) -> ClosedRange<Int>? {
        let parts = sourcepos.split(separator: "-")
        guard parts.count == 2 else { return nil }
        let start = parts[0].split(separator: ":")
        let end = parts[1].split(separator: ":")
        guard start.count == 2, end.count == 2,
              let startLine = Int(start[0]),
              let endLine = Int(end[0]),
              let endColumn = Int(end[1]) else { return nil }
        let effectiveEnd = endColumn == 0 ? endLine - 1 : endLine
        guard startLine >= 1, effectiveEnd >= startLine else { return nil }
        return startLine...effectiveEnd
    }

    /// Returns the given 1-based inclusive line range of `text`, or nil when
    /// the range falls outside the document.
    public static func slice(_ text: String, lines: ClosedRange<Int>) -> String? {
        let all = text.components(separatedBy: "\n")
        guard lines.lowerBound >= 1, lines.upperBound <= all.count else { return nil }
        return all[(lines.lowerBound - 1)...(lines.upperBound - 1)].joined(separator: "\n")
    }

    /// Replaces 1-based inclusive lines `start...end` of `text` with
    /// `replacement` (which may span any number of lines, including zero
    /// when empty). `end == start - 1` denotes insertion before line `start`.
    /// Returns nil when the range falls outside the document.
    public static func replacingLines(in text: String, start: Int, end: Int, with replacement: String) -> String? {
        let all = text.components(separatedBy: "\n")
        guard start >= 1, end >= start - 1, end <= all.count, start <= all.count + 1 else { return nil }
        let head = all.prefix(start - 1)
        let tail = all.suffix(from: min(end, all.count))
        let middle = replacement.isEmpty ? [] : replacement.components(separatedBy: "\n")
        return (Array(head) + middle + Array(tail)).joined(separator: "\n")
    }

    /// Compare-and-swap edit: replaces lines `start...end` only when they
    /// still contain `original` — the source the editor was opened on. Returns
    /// nil (drop the commit) when the document changed underneath, so a stale
    /// commit can never splice the wrong lines.
    public static func applyingEdit(to text: String, start: Int, end: Int, original: String, replacement: String) -> String? {
        guard start >= 1, end >= start else { return nil }
        guard slice(text, lines: start...end) == original else { return nil }
        return replacingLines(in: text, start: start, end: end, with: replacement)
    }

    /// Plans the removal of a whole block (Backspace on an emptied editor).
    /// Expands the range to swallow one adjacent blank separator line —
    /// preferring the preceding one — so deletions don't accumulate blank
    /// lines, and reports where the previous block ends in the resulting
    /// document (0 when the deleted block was first). Returns nil when the
    /// target lines no longer hold `original`.
    public static func blockDeletion(
        in text: String, start: Int, end: Int, original: String
    ) -> (start: Int, end: Int, original: String, previousLine: Int)? {
        let lines = text.components(separatedBy: "\n")
        guard start >= 1, start <= end, end <= lines.count else { return nil }
        guard slice(text, lines: start...end) == original else { return nil }
        var s = start
        var e = end
        if s > 1, lines[s - 2].trimmingCharacters(in: .whitespaces).isEmpty {
            s -= 1
        } else if e < lines.count, lines[e].trimmingCharacters(in: .whitespaces).isEmpty {
            e += 1
        }
        guard let expandedOriginal = slice(text, lines: s...e) else { return nil }
        return (s, e, expandedOriginal, s - 1)
    }

    /// Appends `block` to `text` as a new markdown block, inserting the blank
    /// line cmark needs to keep it separate from the previous block.
    public static func appendingBlock(_ block: String, to text: String) -> String {
        let trimmedBlock = block
        guard !text.isEmpty else { return trimmedBlock }
        if text.hasSuffix("\n\n") {
            return text + trimmedBlock
        }
        if text.hasSuffix("\n") {
            return text + "\n" + trimmedBlock
        }
        return text + "\n\n" + trimmedBlock
    }

    // MARK: - Injected script

    /// Message protocol posted to the `liveEdit` handler:
    /// - `{type: "requestEdit", sourcepos}` — user clicked a block; native side
    ///   replies with `window.clearlyBeginEdit(start, end, sourceJSON)`.
    /// - `{type: "requestAppend"}` — user clicked below the last block; native
    ///   side replies with `window.clearlyBeginAppend()`.
    /// - `{type: "commitEdit", start, end, text}` — replace source lines.
    /// - `{type: "appendBlock", text}` — append a new block to the document.
    ///
    /// Native side toggles the mode with `window.clearlySetLiveMode(bool)`.
    public static let scriptHTML = """
    <script>
    (function() {
        var live = false;
        var pending = null;   // element awaiting a clearlyBeginEdit reply
        var active = null;    // {editor, textarea, original, start, end, isAppend, committed}

        function isTaskItem(el) {
            return el && el.tagName === 'LI'
                && el.hasAttribute('data-sourcepos')
                && el.querySelector(':scope > input[type="checkbox"]') !== null;
        }

        function markBlocks() {
            document.querySelectorAll('[data-sourcepos]').forEach(function(el) {
                if (el.parentElement && el.parentElement.closest('[data-sourcepos]')) return;
                // Checklist items are line-scoped: each item is its own
                // block, not the surrounding list.
                if (el.tagName === 'UL' && el.querySelector(':scope > li > input[type="checkbox"]')) {
                    el.querySelectorAll('li').forEach(function(li) {
                        if (isTaskItem(li)) li.classList.add('live-block');
                    });
                    return;
                }
                el.classList.add('live-block');
            });
        }
        markBlocks();

        function lastBlockBottom() {
            var blocks = document.querySelectorAll('.live-block');
            if (!blocks.length) return -Infinity;
            return blocks[blocks.length - 1].getBoundingClientRect().bottom;
        }

        function post(msg) {
            if (window.webkit && window.webkit.messageHandlers.liveEdit) {
                window.webkit.messageHandlers.liveEdit.postMessage(msg);
            }
        }

        function autogrow(ta) {
            ta.style.height = 'auto';
            ta.style.height = ta.scrollHeight + 'px';
        }

        function buildEditor(source, mono) {
            var wrap = document.createElement('div');
            wrap.className = 'live-editor';
            var ta = document.createElement('textarea');
            if (mono) ta.className = 'live-mono';
            // Default rows="2" floors scrollHeight at two lines, making
            // single-line blocks grow a phantom line when they open.
            ta.rows = 1;
            ta.value = source;
            ta.spellcheck = false;
            ta.setAttribute('autocorrect', 'off');
            ta.setAttribute('autocapitalize', 'off');
            wrap.appendChild(ta);
            return { wrap: wrap, ta: ta };
        }

        function closeActive(commit) {
            if (!active || active.committed) return;
            var a = active;
            var value = a.ta.value;
            var changed = a.isAppend ? value.trim().length > 0 : value !== a.original;
            if (commit && changed) {
                a.committed = true;
                a.ta.readOnly = true;
                if (a.isAppend) {
                    post({ type: 'appendBlock', text: value });
                } else {
                    // `original` lets the native side verify the target lines
                    // still hold what this editor was opened on before splicing.
                    post({ type: 'commitEdit', start: a.start, end: a.end, text: value, original: a.original });
                }
                // The reload triggered by the source change replaces the DOM.
                active = null;
                return;
            }
            // Cancel / unchanged: restore the rendered block in place.
            if (a.isAppend) {
                a.wrap.remove();
            } else if (a.originalEl) {
                a.wrap.replaceWith(a.originalEl);
            }
            if (a.header) a.header.style.display = '';
            active = null;
        }

        function attachEvents(a) {
            a.ta.addEventListener('input', function() { autogrow(a.ta); });
            a.ta.addEventListener('keydown', function(e) {
                if (e.key === 'Escape') {
                    e.preventDefault();
                    e.stopPropagation();
                    if (active === a) closeActive(false);
                } else if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) {
                    e.preventDefault();
                    a.ta.blur();
                } else if (e.key === 'Backspace' && a.ta.value === '' && active === a) {
                    // Backspace on an emptied block deletes it and moves the
                    // caret into the previous block.
                    e.preventDefault();
                    e.stopPropagation();
                    if (a.isAppend) {
                        a.committed = true;
                        a.wrap.remove();
                        active = null;
                        editBlockAtOrAbove(Number.MAX_SAFE_INTEGER);
                    } else {
                        a.committed = true;
                        a.ta.readOnly = true;
                        active = null;
                        post({ type: 'deleteBlock', start: a.start, end: a.end, original: a.original });
                        // The reload triggered by the deletion replaces the
                        // DOM; the native side reopens the previous block.
                    }
                }
            });
            a.ta.addEventListener('blur', function() {
                // Let a click that caused the blur land first — and only act
                // if this editor is still the active one; a committed editor
                // blurring (when the next one takes focus) must not close it.
                setTimeout(function() { if (active === a) closeActive(true); }, 0);
            });
        }

        window.clearlyBeginEdit = function(start, end, source) {
            if (!pending || !live) { pending = null; return; }
            var el = pending.el;
            pending = null;
            closeActive(true);
            var mono = /^(PRE|TABLE)$/.test(el.tagName)
                || el.classList.contains('frontmatter')
                || el.classList.contains('math-block')
                || el.closest('.table-shell, .code-block-wrapper, .mermaid-wrapper') !== null;
            var built = buildEditor(source, mono);
            // Headings edit at their rendered scale.
            if (/^H[1-6]$/.test(el.tagName)) {
                built.wrap.classList.add('live-' + el.tagName.toLowerCase());
            }
            // Swap out the whole visual unit — wrapper chrome (copy/fold
            // buttons, table shells, mermaid zoom icons) must not float
            // around the bare editor.
            var unit = el.closest('.code-block-wrapper, .table-shell, .mermaid-wrapper') || el;
            // The code filename header is a sibling outside the wrapper.
            var header = null;
            if (unit.previousElementSibling && unit.previousElementSibling.classList.contains('code-filename')) {
                header = unit.previousElementSibling;
                header.style.display = 'none';
            }
            // Keep the replaced block's vertical rhythm so nothing jumps.
            var cs = getComputedStyle(unit);
            var unitHeight = unit.getBoundingClientRect().height;
            built.wrap.style.marginTop = cs.marginTop;
            built.wrap.style.marginBottom = cs.marginBottom;
            unit.replaceWith(built.wrap);
            active = { wrap: built.wrap, ta: built.ta, original: source, originalEl: unit,
                       header: header, start: start, end: end, isAppend: false, committed: false };
            attachEvents(active);
            autogrow(built.ta);
            // scrollHeight rounds up fractional line heights; snap to the
            // replaced block's exact height so the page below doesn't shift.
            if (Math.abs(built.ta.getBoundingClientRect().height - unitHeight) <= 3) {
                built.ta.style.height = unitHeight + 'px';
            }
            built.ta.focus();
            var len = built.ta.value.length;
            built.ta.setSelectionRange(len, len);
        };

        window.clearlyBeginAppend = function() {
            if (!live) return;
            closeActive(true);
            var built = buildEditor('', false);
            document.body.appendChild(built.wrap);
            active = { wrap: built.wrap, ta: built.ta, original: '', originalEl: null,
                       start: 0, end: 0, isAppend: true, committed: false };
            attachEvents(active);
            autogrow(built.ta);
            built.ta.focus();
            built.wrap.scrollIntoView({ block: 'nearest' });
        };

        // Opens the editor for the deepest editable block that starts at or
        // nearest above the given source line (used after deleting a block to
        // land the caret in its predecessor).
        function editBlockAtOrAbove(line) {
            var best = null;
            var bestLine = -1;
            document.querySelectorAll('.live-block').forEach(function(el) {
                var m = /^(\\d+):/.exec(el.getAttribute('data-sourcepos') || '');
                if (!m) return;
                var startLine = parseInt(m[1], 10);
                if (startLine <= line && startLine > bestLine) {
                    best = el;
                    bestLine = startLine;
                }
            });
            if (!best) return;
            pending = { el: best };
            post({ type: 'requestEdit', sourcepos: best.getAttribute('data-sourcepos') });
        }

        window.clearlyEditBlockAtLine = function(line) {
            if (live) editBlockAtOrAbove(line);
        };

        window.clearlySetLiveMode = function(on) {
            live = !!on;
            document.body.classList.toggle('live-mode', live);
            // Leaving live mode behaves like leaving the block: commit, don't
            // discard — switching to the editor must not lose typed changes.
            if (!live) {
                closeActive(true);
                hideImgZoom();
            }
        };

        // In live mode a plain click on an image edits its block, so the
        // lightbox gets its own affordance: a hover button on the image.
        var imgZoom = null;
        function hideImgZoom() {
            if (imgZoom) { imgZoom.style.display = 'none'; imgZoom._img = null; }
        }
        function showImgZoom(img) {
            if (!imgZoom) {
                imgZoom = document.createElement('button');
                imgZoom.className = 'live-img-zoom';
                imgZoom.title = 'View full size';
                imgZoom.innerHTML = '<svg width="14" height="14" viewBox="0 0 22 22" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="10" cy="10" r="7"/><line x1="15.5" y1="15.5" x2="20" y2="20"/><line x1="10" y1="7" x2="10" y2="13"/><line x1="7" y1="10" x2="13" y2="10"/></svg>';
                imgZoom.addEventListener('click', function(e) {
                    e.preventDefault();
                    e.stopPropagation();
                    var target = imgZoom._img;
                    hideImgZoom();
                    if (!target) return;
                    var overlay = document.createElement('div');
                    overlay.className = 'lightbox-overlay';
                    var clone = target.cloneNode();
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
                document.body.appendChild(imgZoom);
            }
            var rect = img.getBoundingClientRect();
            imgZoom.style.display = 'flex';
            imgZoom.style.left = (window.scrollX + rect.right - 36) + 'px';
            imgZoom.style.top = (window.scrollY + rect.top + 8) + 'px';
            imgZoom._img = img;
        }
        document.addEventListener('mouseover', function(e) {
            if (!live) { hideImgZoom(); return; }
            if (e.target.tagName === 'IMG' && e.target.closest('.live-block')) {
                showImgZoom(e.target);
            } else if (imgZoom && e.target !== imgZoom && !imgZoom.contains(e.target)) {
                hideImgZoom();
            }
        });

        // Clicking app chrome outside the web view (sidebar, toolbar) unfocuses
        // the page without firing the textarea's own blur — commit then too.
        window.addEventListener('blur', function() { closeActive(true); });

        // Text cursor over the empty space below the content, where a click
        // appends a new block.
        document.addEventListener('mousemove', function(e) {
            if (!live) return;
            var below = (e.target === document.body || e.target === document.documentElement)
                && e.clientY > lastBlockBottom();
            document.body.classList.toggle('live-append-zone', below);
        });

        document.addEventListener('click', function(e) {
            if (!live) return;
            if (active && active.wrap.contains(e.target)) return;
            // A drag-select ends in a click; don't destroy the selection by
            // opening an editor.
            var sel = window.getSelection();
            if (sel && !sel.isCollapsed) return;

            // Interactive elements keep their normal behavior.
            if (e.target.closest('input, button, summary, th, .code-copy-btn, .code-fold-btn, .table-copy-btn, .heading-anchor, .mermaid-zoom-icon, .live-img-zoom, .lightbox-overlay, .footnote-popover, .live-editor')) {
                return;
            }
            // Cmd-click follows links; plain click edits the block.
            if (e.target.closest('a[href]') && (e.metaKey || e.ctrlKey)) return;

            var block = e.target.closest('[data-sourcepos]');
            // Checklist items edit individually; everything else edits at
            // the outermost block.
            if (!isTaskItem(block)) {
                while (block && block.parentElement && block.parentElement.closest('[data-sourcepos]')) {
                    block = block.parentElement.closest('[data-sourcepos]');
                }
            }
            if (block) {
                e.preventDefault();
                e.stopPropagation();
                pending = { el: block };
                post({ type: 'requestEdit', sourcepos: block.getAttribute('data-sourcepos') });
                return;
            }
            // Click on empty space below the content appends a new block.
            if ((e.target === document.body || e.target === document.documentElement)
                && e.clientY > lastBlockBottom()) {
                e.preventDefault();
                e.stopPropagation();
                post({ type: 'requestAppend' });
            }
        }, true);
    })();
    </script>
    """
}
