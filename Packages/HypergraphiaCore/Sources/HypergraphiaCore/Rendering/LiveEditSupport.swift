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

    /// Plans the deletion behind a multi-block selection: everything after
    /// the block being kept (`keepEnd` = its last line) through the end of
    /// the last selected block, separators included. Returns nil when the
    /// span is out of bounds.
    public static func rangeDeletion(
        in text: String, keepEnd: Int, deleteEnd: Int
    ) -> (start: Int, end: Int, original: String)? {
        let count = text.components(separatedBy: "\n").count
        let start = keepEnd + 1
        guard start >= 1, deleteEnd >= start, deleteEnd <= count,
              let original = slice(text, lines: start...deleteEnd) else { return nil }
        return (start, deleteEnd, original)
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

    /// A script tag exposing the full markdown source to the page, enabling
    /// synchronous selection expansion across block boundaries (no native
    /// round trip, so default caret behavior is preserved). JSON encoding
    /// escapes `/`, so `</script>` in the markdown cannot break out.
    public static func sourceScriptHTML(for markdown: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: markdown, options: .fragmentsAllowed),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return "<script>window.__clearlySource = \(json);</script>"
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
        var clearNext = false; // empty the next opened editor (selection delete)
        var caretStartNext = false; // place the next opened editor's caret at 0
        var mouseHeld = false; // suppress shrink while a drag is in progress
        // Full markdown source (sourceScriptHTML), powering selection
        // expansion across block boundaries.
        var docSource = (typeof window.__clearlySource === 'string') ? window.__clearlySource : null;

        window.clearlySetSource = function(s) {
            docSource = (typeof s === 'string') ? s : null;
        };

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

        // The whole visual unit a block belongs to — wrapper chrome (copy/
        // fold buttons, table shells, mermaid zoom icons) moves with it.
        function unitFor(el) {
            return el.closest('.code-block-wrapper, .table-shell, .mermaid-wrapper') || el;
        }

        // Rendered blocks by source position (the active editor's block is
        // swapped out of the DOM, so it never appears here).
        function blockRanges() {
            var ranges = [];
            document.querySelectorAll('.live-block').forEach(function(el) {
                var m = /^(\\d+):\\d+-(\\d+):(\\d+)$/.exec(el.getAttribute('data-sourcepos') || '');
                if (!m) return;
                ranges.push({ el: el,
                              start: parseInt(m[1], 10),
                              end: parseInt(m[2], 10) - (m[3] === '0' ? 1 : 0) });
            });
            return ranges;
        }

        // Detach the rendered blocks in [fromLine, toLine], returning records
        // that can reattach them exactly where they were.
        function removeRenderedBlocks(fromLine, toLine) {
            var recs = [];
            blockRanges().forEach(function(r) {
                if (r.start < fromLine || r.end > toLine) return;
                var unit = unitFor(r.el);
                if (unit.previousElementSibling && unit.previousElementSibling.classList.contains('code-filename')) {
                    var h = unit.previousElementSibling;
                    recs.push({ el: h, parent: h.parentNode, next: h.nextSibling });
                    h.remove();
                }
                recs.push({ el: unit, parent: unit.parentNode, next: unit.nextSibling });
                unit.remove();
            });
            return recs;
        }

        // Reattach detached units in reverse removal order, so each recorded
        // next-sibling anchor is back in the document before it's needed.
        function reinsert(recs) {
            for (var i = recs.length - 1; i >= 0; i--) {
                var s = recs[i];
                var anchor = (s.next && s.next.parentNode === s.parent) ? s.next : null;
                s.parent.insertBefore(s.el, anchor);
            }
        }

        // Release absorbed neighbors the selection has retreated from: a
        // block that is no longer selected leaves edit mode and returns to
        // rendered form. Only safe while the editor content is untouched —
        // once the user types, absorption is final until commit or cancel.
        function maybeShrink(a) {
            if (!a || a.committed || a.isAppend || mouseHeld) return;
            if (a.ta.value !== a.original) return;
            if (!a.below.length && !a.above.length) return;
            var ta = a.ta;
            var changed = false;
            while (a.below.length) {
                var seg = a.below[a.below.length - 1];
                var boundary = ta.value.length - seg.len;
                if (ta.selectionEnd > boundary) break;
                var s = ta.selectionStart, e = ta.selectionEnd, d = ta.selectionDirection;
                a.below.pop();
                ta.value = ta.value.slice(0, boundary);
                a.original = a.original.slice(0, a.original.length - seg.len);
                a.end = seg.prevEnd;
                reinsert(seg.recs);
                ta.setSelectionRange(s, e, d);
                changed = true;
            }
            while (a.above.length) {
                var top = a.above[a.above.length - 1];
                if (ta.selectionStart < top.len) break;
                var s2 = ta.selectionStart - top.len, e2 = ta.selectionEnd - top.len;
                var d2 = ta.selectionDirection;
                a.above.pop();
                ta.value = ta.value.slice(top.len);
                a.original = a.original.slice(top.len);
                a.start = top.prevStart;
                reinsert(top.recs);
                ta.setSelectionRange(s2, e2, d2);
                changed = true;
            }
            if (!changed) return;
            // Fully retracted: the editor is a single block again, so give it
            // back its block-specific styling and snapped height.
            if (!a.below.length && !a.above.length && a.baseWrapClass != null) {
                a.wrap.className = a.baseWrapClass;
                a.ta.className = a.baseTaClass;
            }
            ta.style.height = '';
            autogrow(ta);
            if (!a.below.length && !a.above.length && a.baseHeight) {
                ta.style.height = a.baseHeight;
            }
        }

        // Grow the active editor to include the neighboring block (or the
        // document edge), keeping the selection anchored. Runs synchronously
        // so the browser's default caret movement continues into the newly
        // included text.
        function expandActive(a, up, toDocEdge) {
            if (!docSource || a.isAppend || a.committed) return false;
            var lines = docSource.split('\\n');
            var newStart = a.start, newEnd = a.end;
            if (up) {
                if (toDocEdge) {
                    newStart = 1;
                } else {
                    var prev = null;
                    blockRanges().forEach(function(r) {
                        if (r.end < a.start && (!prev || r.start > prev.start)) prev = r;
                    });
                    if (!prev) return false;
                    newStart = prev.start;
                }
                if (newStart >= a.start) return false;
            } else {
                if (toDocEdge) {
                    newEnd = lines.length;
                } else {
                    var next = null;
                    blockRanges().forEach(function(r) {
                        if (r.start > a.end && (!next || r.end < next.end)) next = r;
                    });
                    if (!next) return false;
                    newEnd = next.end;
                }
                if (newEnd <= a.end) return false;
            }
            var selS = a.ta.selectionStart, selE = a.ta.selectionEnd;
            var selD = a.ta.selectionDirection;
            if (a.baseWrapClass == null) {
                a.baseWrapClass = a.wrap.className;
                a.baseTaClass = a.ta.className;
            }
            if (up) {
                var head = lines.slice(newStart - 1, a.start - 1).join('\\n');
                a.ta.value = head + '\\n' + a.ta.value;
                a.original = head + '\\n' + a.original;
                a.above.push({ len: head.length + 1, prevStart: a.start,
                               recs: removeRenderedBlocks(newStart, a.start - 1) });
                a.start = newStart;
                var shift = head.length + 1;
                selS += shift; selE += shift;
            } else {
                var tail = lines.slice(a.end, newEnd).join('\\n');
                a.ta.value = a.ta.value + '\\n' + tail;
                a.original = a.original + '\\n' + tail;
                a.below.push({ len: tail.length + 1, prevEnd: a.end,
                               recs: removeRenderedBlocks(a.end + 1, newEnd) });
                a.end = newEnd;
            }
            // Mixed content: drop heading scale and mono styling.
            a.wrap.className = 'live-editor';
            a.ta.classList.remove('live-mono');
            a.ta.style.height = '';
            autogrow(a.ta);
            a.ta.setSelectionRange(selS, selE, selD);
            return true;
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
                } else if (value.trim() === '') {
                    // Committing an emptied block deletes it cleanly
                    // (separator blank lines get swallowed too).
                    post({ type: 'deleteBlock', start: a.start, end: a.end, original: a.original, reopen: false });
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
            // Absorbed neighbors go back first, newest-first per side, so
            // each recorded next-sibling anchor is attached when needed.
            for (var i = a.below.length - 1; i >= 0; i--) reinsert(a.below[i].recs);
            for (var j = a.above.length - 1; j >= 0; j--) reinsert(a.above[j].recs);
            a.below = [];
            a.above = [];
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
                // A key press means any mouse drag is over (a lost mouseup
                // outside the window must not disable shrink forever).
                mouseHeld = false;
                // Selection running past the block boundary grows the editor
                // into the neighboring blocks, Apple Notes-style. Expansion is
                // synchronous, so the default caret movement then continues
                // into the newly included text — no preventDefault. Option is
                // allowed on the plain-arrow branches: the default action then
                // extends by paragraph (option+up/down) or word (option+
                // left/right) into the absorbed text.
                var ta = a.ta;
                // A plain arrow with the caret at the very start or end
                // travels to the neighboring block. (WebKit already moves the
                // caret to the boundary when an arrow can't move further, so
                // from anywhere in the block two presses walk out of it.)
                if (!e.shiftKey && !e.metaKey && !e.altKey && !e.ctrlKey && !e.isComposing
                    && ta.selectionStart === ta.selectionEnd) {
                    if ((e.key === 'ArrowDown' || e.key === 'ArrowRight')
                        && ta.selectionEnd === ta.value.length) {
                        if (travel(a, false)) { e.preventDefault(); e.stopPropagation(); return; }
                    } else if ((e.key === 'ArrowUp' || e.key === 'ArrowLeft')
                               && ta.selectionStart === 0) {
                        if (travel(a, true)) { e.preventDefault(); e.stopPropagation(); return; }
                    }
                }
                if (e.shiftKey && e.metaKey && !e.altKey && e.key === 'ArrowDown') {
                    expandActive(a, false, true);
                } else if (e.shiftKey && e.metaKey && !e.altKey && e.key === 'ArrowUp') {
                    expandActive(a, true, true);
                } else if (e.shiftKey && !e.metaKey
                           && (e.key === 'ArrowDown' || e.key === 'ArrowRight')
                           && ta.selectionEnd === ta.value.length
                           && ta.selectionDirection !== 'backward') {
                    expandActive(a, false, false);
                } else if (e.shiftKey && !e.metaKey
                           && (e.key === 'ArrowUp' || e.key === 'ArrowLeft')
                           && ta.selectionStart === 0
                           && (ta.selectionStart === ta.selectionEnd || ta.selectionDirection === 'backward')) {
                    expandActive(a, true, false);
                } else if (e.metaKey && !e.shiftKey && !e.altKey && (e.key === 'a' || e.key === 'A')
                           && ta.value.length > 0
                           && ta.selectionStart === 0 && ta.selectionEnd === ta.value.length) {
                    // Everything in the block is already selected: the second
                    // Cmd-A widens to the whole document.
                    expandActive(a, true, true);
                    expandActive(a, false, true);
                }
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
                        post({ type: 'deleteBlock', start: a.start, end: a.end, original: a.original, reopen: true });
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
            a.ta.addEventListener('mousedown', function() { mouseHeld = true; });
            // Shrink triggers: newer WebKit fires selectionchange at the
            // control itself; the keyup covers engines that don't.
            a.ta.addEventListener('selectionchange', function() {
                if (active === a) maybeShrink(a);
            });
            a.ta.addEventListener('keyup', function(e) {
                if (active === a && e.key && e.key.indexOf('Arrow') === 0) maybeShrink(a);
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
            var unit = unitFor(el);
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
                       header: header, start: start, end: end, isAppend: false, committed: false,
                       above: [], below: [], baseWrapClass: null, baseTaClass: null, baseHeight: null };
            attachEvents(active);
            autogrow(built.ta);
            // scrollHeight rounds up fractional line heights; snap to the
            // replaced block's exact height so the page below doesn't shift.
            if (Math.abs(built.ta.getBoundingClientRect().height - unitHeight) <= 3) {
                built.ta.style.height = unitHeight + 'px';
            }
            active.baseHeight = built.ta.style.height;
            built.ta.focus();
            var len = built.ta.value.length;
            built.ta.setSelectionRange(len, len);
            if (caretStartNext) {
                // Arrow-key travel into this block from above lands at the
                // beginning, like a continuous document.
                caretStartNext = false;
                built.ta.setSelectionRange(0, 0);
            }
            if (clearNext) {
                // Selection delete: this block survives, but cleared. The
                // original stays intact so the commit/delete paths verify
                // against the real source.
                clearNext = false;
                built.ta.value = '';
                autogrow(built.ta);
            }
        };

        window.clearlyBeginAppend = function() {
            if (!live) return;
            closeActive(true);
            var built = buildEditor('', false);
            document.body.appendChild(built.wrap);
            active = { wrap: built.wrap, ta: built.ta, original: '', originalEl: null,
                       start: 0, end: 0, isAppend: true, committed: false,
                       above: [], below: [], baseWrapClass: null, baseTaClass: null, baseHeight: null };
            attachEvents(active);
            autogrow(built.ta);
            built.ta.focus();
            built.wrap.scrollIntoView({ block: 'nearest' });
        };

        // Opens the editor for the deepest editable block that starts at or
        // nearest above the given source line (used after deleting a block to
        // land the caret in its predecessor).
        function editBlockAtOrAbove(line, clear, caretStart) {
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
            clearNext = !!clear;
            caretStartNext = !!caretStart;
            pending = { el: best };
            post({ type: 'requestEdit', sourcepos: best.getAttribute('data-sourcepos') });
        }

        window.clearlyEditBlockAtLine = function(line, clear, caretStart) {
            if (live) editBlockAtOrAbove(line, clear, caretStart);
        };

        // Arrow-key travel: a plain arrow at the editor's very start or end
        // moves the caret into the neighboring block — the current block
        // leaves edit mode (committing as usual) and the neighbor enters it.
        function travel(a, up) {
            var target = null;
            blockRanges().forEach(function(r) {
                if (up) {
                    if (r.end < a.start && (!target || r.start > target.start)) target = r;
                } else {
                    if (r.start > a.end && (!target || r.end < target.end)) target = r;
                }
            });
            var value = a.ta.value;
            var changed = a.isAppend ? value.trim().length > 0 : value !== a.original;
            if (a.isAppend) {
                // Only the unchanged empty append editor travels (up, to the
                // last block); otherwise leave the caret where it is.
                if (up && !changed) {
                    a.committed = true;
                    a.wrap.remove();
                    active = null;
                    editBlockAtOrAbove(Number.MAX_SAFE_INTEGER, false, false);
                    return true;
                }
                return false;
            }
            if (!target) return false;
            if (!changed) {
                // Nothing to commit: restore this block in place and open the
                // neighbor directly, no reload needed.
                closeActive(true);
                clearNext = false;
                caretStartNext = !up;
                pending = { el: target.el };
                post({ type: 'requestEdit', sourcepos: target.el.getAttribute('data-sourcepos') });
                return true;
            }
            a.committed = true;
            a.ta.readOnly = true;
            active = null;
            if (value.trim() === '') {
                // Leaving an emptied block deletes it; land in the neighbor.
                post({ type: 'deleteBlock', start: a.start, end: a.end, original: a.original,
                       reopen: up ? 'prev' : 'next' });
                return true;
            }
            // Commit, then reopen the neighbor after the reload. Downward the
            // neighbor's line shifts by however many lines this commit added
            // or removed; upward it is untouched.
            var newLine = up
                ? target.start
                : target.start + (value.split('\\n').length - (a.end - a.start + 1));
            post({ type: 'commitEdit', start: a.start, end: a.end, text: value, original: a.original,
                   reopenLine: newLine, reopenCaretStart: !up });
            return true;
        }

        // Backspace/Delete over a selection: every touched block is deleted
        // except the first, which reopens cleared — the multi-block analogue
        // of select-all + delete in a conventional editor.
        document.addEventListener('keydown', function(e) {
            if (!live || active) return;
            if (e.key !== 'Backspace' && e.key !== 'Delete') return;
            if (e.target.closest && e.target.closest('.live-editor, input, textarea')) return;
            var sel = window.getSelection();
            if (!sel || sel.isCollapsed || sel.rangeCount === 0) return;
            var range = sel.getRangeAt(0);
            // Pick the span by source lines, not DOM order: the footnote
            // section renders at the end of the DOM but its sourcepos points
            // mid-document.
            var first = null, last = null, firstLine = Infinity, lastLine = -1;
            document.querySelectorAll('.live-block').forEach(function(el) {
                if (!range.intersectsNode(el)) return;
                var m = /^(\\d+):\\d+-(\\d+):(\\d+)$/.exec(el.getAttribute('data-sourcepos') || '');
                if (!m) return;
                var start = parseInt(m[1], 10);
                var end = parseInt(m[2], 10) - (m[3] === '0' ? 1 : 0);
                if (start < firstLine) { firstLine = start; first = el; }
                if (end > lastLine) { lastLine = end; last = el; }
            });
            if (!first) return;
            e.preventDefault();
            e.stopPropagation();
            sel.removeAllRanges();
            if (first === last) {
                clearNext = true;
                pending = { el: first };
                post({ type: 'requestEdit', sourcepos: first.getAttribute('data-sourcepos') });
            } else {
                post({ type: 'deleteBlockRange',
                       first: first.getAttribute('data-sourcepos'),
                       last: last.getAttribute('data-sourcepos') });
            }
        });

        // Older WebKit fires selectionchange at the document rather than the
        // text control; maybeShrink is idempotent so double delivery is fine.
        document.addEventListener('selectionchange', function() {
            if (active) maybeShrink(active);
        });
        // Releasing a drag re-enables shrink and applies any pending retreat.
        document.addEventListener('mouseup', function() {
            if (!mouseHeld) return;
            mouseHeld = false;
            if (active) maybeShrink(active);
        });

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

        // Chrome clicks don't always unfocus the page either (SwiftUI
        // buttons don't steal first responder), so the native side watches
        // for clicks outside the web view and closes the editor explicitly.
        window.clearlyCloseActiveEditor = function() { closeActive(true); };

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

            // Interactive elements keep their normal behavior. The click is
            // still outside the active editor, so an untouched editor closes
            // quietly; an edited one stays — committing here could shift
            // source lines under the control's own message (e.g. a checkbox
            // toggle posting a line number read from the pre-commit DOM).
            if (e.target.closest('input, button, summary, th, .code-copy-btn, .code-fold-btn, .table-copy-btn, .heading-anchor, .mermaid-zoom-icon, .live-img-zoom, .lightbox-overlay, .footnote-popover, .live-editor')) {
                if (active && !active.committed
                    && (active.isAppend ? active.ta.value.trim() === '' : active.ta.value === active.original)) {
                    closeActive(false);
                }
                return;
            }
            // Clicking a link follows it instead of editing its block (the
            // bubble-phase link handler forwards external URLs to native;
            // in-page anchors scroll by default), and leaves edit mode.
            if (e.target.closest('a[href]')) {
                closeActive(true);
                return;
            }

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
                clearNext = false;
                caretStartNext = false;
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
                return;
            }
            // Anything else — margins, gaps between blocks, dead space —
            // takes the active block out of focus and edit mode, committing
            // changes. (WebKit doesn't blur a textarea for clicks on
            // non-focusable space, so this must be explicit.)
            closeActive(true);
        }, true);
    })();
    </script>
    """
}
