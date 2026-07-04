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

    /// Inserts `block` as its own markdown block after 1-based line
    /// `afterLine` (0 inserts before the first line), adding the blank
    /// separator lines cmark needs: always one above, and one below when the
    /// following line isn't already blank. Returns nil when `afterLine` is
    /// out of bounds.
    public static func insertingBlock(_ block: String, after afterLine: Int, in text: String) -> String? {
        let lines = text.components(separatedBy: "\n")
        guard afterLine >= 0, afterLine <= lines.count else { return nil }
        var insertion = block.components(separatedBy: "\n")
        if afterLine > 0 {
            insertion = [""] + insertion
        }
        if afterLine < lines.count,
           !lines[afterLine].trimmingCharacters(in: .whitespaces).isEmpty {
            insertion.append("")
        }
        return replacingLines(
            in: text, start: afterLine + 1, end: afterLine,
            with: insertion.joined(separator: "\n")
        )
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
    ///   Optional `insertAfter` asks the native side to reopen a new-block
    ///   insert editor below that line after the reload.
    /// - `{type: "appendBlock", text}` — append a new block to the document.
    ///   Optional `reopenAppend` reopens the append editor after the reload.
    /// - `{type: "insertBlock", afterLine, text}` — insert a new block after
    ///   a source line. Optional `reopenInsert` chains another insert editor.
    /// - `{type: "editingState", active}` — a block editor opened or closed
    ///   (native chrome reacts, e.g. hiding the tab strip).
    /// - `{type: "contentTyped"}` — first keystroke in an editor (native side
    ///   auto-creates a file for untitled documents).
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

        function markBlocks() {
            document.querySelectorAll('[data-sourcepos]').forEach(function(el) {
                if (el.parentElement && el.parentElement.closest('[data-sourcepos]')) return;
                // List items are line-scoped: each item is its own block,
                // not the surrounding list — checkboxes, bullets, and
                // numbered items alike.
                if (el.tagName === 'UL' || el.tagName === 'OL') {
                    el.querySelectorAll('li').forEach(function(li) {
                        if (li.hasAttribute('data-sourcepos')) li.classList.add('live-block');
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

        function parseSourcepos(sp) {
            var m = /^(\\d+):\\d+-(\\d+):(\\d+)$/.exec(sp || '');
            if (!m) return null;
            return { start: parseInt(m[1], 10),
                     end: parseInt(m[2], 10) - (m[3] === '0' ? 1 : 0) };
        }

        // A list item's OWN lines: cmark's sourcepos spans the whole item
        // including nested sublists, but items are per-line blocks — the
        // range stops where the first nested sublist starts.
        function itemOwnRange(li) {
            var r = parseSourcepos(li.getAttribute('data-sourcepos'));
            if (!r) return null;
            li.querySelectorAll(':scope > ul[data-sourcepos], :scope > ol[data-sourcepos]').forEach(function(sub) {
                var s = parseSourcepos(sub.getAttribute('data-sourcepos'));
                if (s && s.start - 1 < r.end) r.end = s.start - 1;
            });
            if (r.end < r.start) r.end = r.start;
            return r;
        }

        function rangeFor(el) {
            return el.tagName === 'LI'
                ? itemOwnRange(el)
                : parseSourcepos(el.getAttribute('data-sourcepos'));
        }

        // Sourcepos string describing the block's editable lines — for list
        // items a synthesized own-line span, otherwise the cmark attribute.
        function sourceposFor(el) {
            if (el.tagName === 'LI') {
                var r = itemOwnRange(el);
                if (r) return r.start + ':1-' + r.end + ':1';
            }
            return el.getAttribute('data-sourcepos');
        }

        // Rendered blocks by source position (the active editor's block is
        // swapped out of the DOM, so it never appears here).
        function blockRanges() {
            var ranges = [];
            document.querySelectorAll('.live-block').forEach(function(el) {
                var r = rangeFor(el);
                if (!r) return;
                ranges.push({ el: el, start: r.start, end: r.end });
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
            if (!a || a.committed || a.isAppend || a.isInsert || mouseHeld) return;
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
            if (!docSource || a.isAppend || a.isInsert || a.committed) return false;
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
            // Mixed content: drop heading scale, mono styling, and the
            // in-place list-item editor's inline prefix outdent.
            a.wrap.className = 'live-editor';
            a.wrap.style.marginLeft = '';
            a.wrap.style.width = '';
            a.ta.classList.remove('live-mono');
            a.ta.style.height = '';
            autogrow(a.ta);
            a.ta.setSelectionRange(selS, selE, selD);
            return true;
        }

        // Tells the native side whether a block editor is open (it hides the
        // tab strip while one is). Reopen flows deliberately skip the "off"
        // notification so the strip doesn't flash between two editors.
        function notifyEditing() {
            post({ type: 'editingState', active: !!active });
        }

        function closeActive(commit) {
            if (!active || active.committed) return;
            var a = active;
            var value = a.ta.value;
            var changed = (a.isAppend || a.isInsert) ? value.trim().length > 0 : value !== a.original;
            if (commit && changed) {
                a.committed = true;
                a.ta.readOnly = true;
                if (a.isAppend) {
                    post({ type: 'appendBlock', text: value });
                } else if (a.isInsert) {
                    post({ type: 'insertBlock', afterLine: a.insertAfterLine, text: value });
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
                notifyEditing();
                return;
            }
            // Cancel / unchanged: restore the rendered block in place.
            // Absorbed neighbors go back first, newest-first per side, so
            // each recorded next-sibling anchor is attached when needed.
            for (var i = a.below.length - 1; i >= 0; i--) reinsert(a.below[i].recs);
            for (var j = a.above.length - 1; j >= 0; j--) reinsert(a.above[j].recs);
            a.below = [];
            a.above = [];
            if (a.isAppend || a.isInsert) {
                a.wrap.remove();
            } else if (a.liHost) {
                // Put the item's own-line content back in front of any
                // nested sublists.
                a.wrap.remove();
                for (var k = a.liKept.length - 1; k >= 0; k--) {
                    a.liHost.insertBefore(a.liKept[k], a.liHost.firstChild);
                }
                a.liHost.classList.remove('live-editing');
            } else if (a.originalEl) {
                a.wrap.replaceWith(a.originalEl);
            }
            if (a.header) a.header.style.display = '';
            active = null;
            notifyEditing();
        }

        // Enter in a text block ends the block at the caret: text after the
        // caret moves into a new block below and the caret follows it to
        // the start; with nothing after the caret, the block commits and a
        // fresh empty one opens below, Apple Notes-style.
        function splitActive(a) {
            var ta = a.ta;
            var head = ta.value.slice(0, ta.selectionStart);
            var tail = ta.value.slice(ta.selectionEnd);
            if (tail.trim() === '') {
                finishAndInsertAfter(a);
                return;
            }
            var value = head + '\\n\\n' + tail;
            a.committed = true;
            a.ta.readOnly = true;
            active = null;
            if (a.isAppend) {
                post({ type: 'appendBlock', text: value, reopenAppend: true });
                return;
            }
            if (a.isInsert) {
                post({ type: 'insertBlock', afterLine: a.insertAfterLine, text: value,
                       reopenInsert: true });
                return;
            }
            // The head keeps the block's lines; the tail becomes the block
            // after the separator — reopen there, caret at its start.
            post({ type: 'commitEdit', start: a.start, end: a.end,
                   text: value, original: a.original,
                   reopenLine: a.start + head.split('\\n').length + 1,
                   reopenCaretStart: true });
        }

        // Committing a finished block and opening a fresh empty editor right
        // below it, Apple Notes-style.
        function finishAndInsertAfter(a) {
            var value = a.ta.value;
            if (value.trim() === '') return;
            if (a.isAppend) {
                a.committed = true;
                a.ta.readOnly = true;
                active = null;
                post({ type: 'appendBlock', text: value, reopenAppend: true });
                return;
            }
            if (a.isInsert) {
                a.committed = true;
                a.ta.readOnly = true;
                active = null;
                post({ type: 'insertBlock', afterLine: a.insertAfterLine, text: value,
                       reopenInsert: true });
                return;
            }
            if (value !== a.original) {
                // Commit; after the reload the native side reopens an insert
                // editor below the block's new extent.
                a.committed = true;
                a.ta.readOnly = true;
                active = null;
                post({ type: 'commitEdit', start: a.start, end: a.end, text: value, original: a.original,
                       insertAfter: a.start + value.split('\\n').length - 1 });
                return;
            }
            // Unchanged: restore the rendered block and insert in place —
            // no reload needed.
            var line = a.end;
            closeActive(true);
            beginInsertAfter(line);
        }

        // Opens an empty editor as a NEW block positioned after the block
        // ending at `line` (its commit inserts rather than replaces).
        function beginInsertAfter(line) {
            if (!live) return;
            closeActive(true);
            var target = null;
            blockRanges().forEach(function(r) {
                if (r.end <= line && (!target || r.end > target.end)) target = r;
            });
            var built = buildEditor('', false);
            if (target) {
                var unit = unitFor(target.el);
                unit.parentNode.insertBefore(built.wrap, unit.nextSibling);
            } else {
                document.body.appendChild(built.wrap);
            }
            active = { wrap: built.wrap, ta: built.ta, original: '', originalEl: null,
                       header: null, start: 0, end: 0, isAppend: false,
                       isInsert: true, insertAfterLine: target ? target.end : 0,
                       committed: false, above: [], below: [],
                       baseWrapClass: null, baseTaClass: null, baseHeight: null };
            attachEvents(active);
            autogrow(built.ta);
            built.ta.focus();
            built.wrap.scrollIntoView({ block: 'nearest' });
            notifyEditing();
        }

        window.clearlyBeginInsertAfterLine = function(line) {
            beginInsertAfter(line);
        };

        // Keep the editor's presentation in step with its markdown while
        // typing: adding/removing leading #'s rescales between heading
        // levels immediately, and deleting the last # drops the block to
        // body-text scale — no need to leave the editor first.
        function syncHeadingScale(a) {
            if (a.ta.classList.contains('live-mono')) return;
            var m = a.ta.value.split('\\n', 1)[0].match(/^\\s{0,3}(#{1,6})\\s/);
            var next = m ? 'live-h' + m[1].length : null;
            var changed = false;
            for (var i = 1; i <= 6; i++) {
                var cls = 'live-h' + i;
                if (cls !== next && a.wrap.classList.contains(cls)) {
                    a.wrap.classList.remove(cls);
                    changed = true;
                }
            }
            if (next && !a.wrap.classList.contains(next)) {
                a.wrap.classList.add(next);
                changed = true;
            }
            if (changed) {
                a.ta.style.height = '';
                autogrow(a.ta);
            }
        }

        function attachEvents(a) {
            a.ta.addEventListener('input', function() {
                syncHeadingScale(a);
                autogrow(a.ta);
                // First keystroke in any editor — native side auto-creates
                // a file for untitled documents.
                if (!a.typedNotified) {
                    a.typedNotified = true;
                    post({ type: 'contentTyped' });
                }
            });
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
                // Plain vertical arrows on the editor's first/last source
                // line travel to the neighboring block; horizontal arrows
                // travel from the very start/end. The caret always lands at
                // the END of the entered block, so repeated Up/Down walks
                // blocks without the caret bouncing between line ends.
                if (!e.shiftKey && !e.metaKey && !e.altKey && !e.ctrlKey && !e.isComposing
                    && ta.selectionStart === ta.selectionEnd) {
                    var onLastLine = ta.value.indexOf('\\n', ta.selectionEnd) === -1;
                    var onFirstLine = ta.selectionStart === 0
                        || ta.value.lastIndexOf('\\n', ta.selectionStart - 1) === -1;
                    if ((e.key === 'ArrowDown' && onLastLine)
                        || (e.key === 'ArrowRight' && ta.selectionEnd === ta.value.length)) {
                        if (travel(a, false)) { e.preventDefault(); e.stopPropagation(); return; }
                    } else if ((e.key === 'ArrowUp' && onFirstLine)
                               || (e.key === 'ArrowLeft' && ta.selectionStart === 0)) {
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
                // Enter never inserts a newline into a text block: it ends
                // the block at the caret and continues in a new one below —
                // every line is its own block. Code, tables, math, and
                // frontmatter (mono editors) keep literal newlines, as do
                // editors that absorbed neighbors (multi-block selections);
                // Shift+Enter stays an in-block line break everywhere.
                if (e.key === 'Enter' && !e.shiftKey && !e.metaKey && !e.ctrlKey && !e.altKey
                    && !e.isComposing && !a.above.length && !a.below.length && active === a
                    && !ta.classList.contains('live-mono')) {
                    e.preventDefault();
                    e.stopPropagation();
                    splitActive(a);
                    return;
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
                    // …unless it's the document's only block: with nowhere
                    // for the caret to land, the empty editor stays focused
                    // and keeps taking input. (An in-place list-item editor
                    // leaves its own <li> in the DOM — don't count it.)
                    var remaining = blockRanges().filter(function(r) {
                        return r.el !== a.liHost;
                    });
                    if (!remaining.length) return;
                    if (a.isAppend) {
                        a.committed = true;
                        a.wrap.remove();
                        active = null;
                        editBlockAtOrAbove(Number.MAX_SAFE_INTEGER);
                    } else if (a.isInsert) {
                        // Backspace on an emptied insert editor abandons it
                        // and lands the caret in the block above.
                        a.committed = true;
                        a.wrap.remove();
                        active = null;
                        editBlockAtOrAbove(a.insertAfterLine);
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
            if (el.tagName === 'LI') {
                // Where the item's rendered TEXT begins, relative to the
                // li's content origin. Normal bullets hang their marker in
                // the list gutter, so text starts at the origin itself; task
                // items are flex rows whose text starts after the styled
                // checkbox and gap. Measured before the content detaches.
                var textOffset = 0;
                var cb = el.querySelector(':scope > input[type="checkbox"]');
                if (cb) {
                    textOffset = (cb.getBoundingClientRect().right - el.getBoundingClientRect().left)
                        + (parseFloat(getComputedStyle(el).columnGap) || 0);
                }
                // List items edit in place, one line at a time: only the
                // item's own-line content swaps for the editor; nested
                // sublists stay rendered inside the item.
                var kept = [];
                Array.prototype.slice.call(el.childNodes).forEach(function(n) {
                    if (n.nodeType === 1 && (n.tagName === 'UL' || n.tagName === 'OL')) return;
                    kept.push(n);
                    el.removeChild(n);
                });
                el.classList.add('live-editing');
                el.insertBefore(built.wrap, el.firstChild);
                // In-place editing must not disturb the item's vertical
                // rhythm — the editor is a line within the li, not a
                // swapped-in block with its own margins.
                built.wrap.style.marginTop = '0';
                built.wrap.style.marginBottom = '0';
                // Hang the markdown prefix (indent, marker, checkbox) out
                // into the marker gutter so the item's TEXT stays exactly
                // where it rendered.
                var prefixMatch = source.match(/^\\s*(?:[-*+]|\\d+[.)])\\s+(?:\\[[ xX]\\]\\s+)?/);
                if (prefixMatch) {
                    var probe = document.createElement('span');
                    probe.textContent = prefixMatch[0];
                    var taStyle = getComputedStyle(built.ta);
                    probe.style.cssText = 'position:absolute;visibility:hidden;white-space:pre;';
                    probe.style.font = taStyle.font;
                    probe.style.letterSpacing = taStyle.letterSpacing;
                    document.body.appendChild(probe);
                    var prefixWidth = probe.getBoundingClientRect().width;
                    probe.remove();
                    var shift = prefixWidth - textOffset;
                    built.wrap.style.marginLeft = (-shift) + 'px';
                    built.wrap.style.width = 'calc(100% + ' + shift + 'px)';
                }
                active = { wrap: built.wrap, ta: built.ta, original: source, originalEl: null,
                           liHost: el, liKept: kept,
                           header: null, start: start, end: end, isAppend: false, committed: false,
                           above: [], below: [], baseWrapClass: null, baseTaClass: null, baseHeight: null };
                attachEvents(active);
                autogrow(built.ta);
                active.baseHeight = built.ta.style.height;
            } else {
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
            }
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
            notifyEditing();
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
            notifyEditing();
        };

        // Opens the editor for the deepest editable block that starts at or
        // nearest above the given source line (used after deleting a block to
        // land the caret in its predecessor).
        function editBlockAtOrAbove(line, clear, caretStart) {
            var best = null;
            var bestLine = -1;
            document.querySelectorAll('.live-block').forEach(function(el) {
                var r = rangeFor(el);
                if (!r) return;
                if (r.start <= line && r.start > bestLine) {
                    best = el;
                    bestLine = r.start;
                }
            });
            if (!best) return;
            clearNext = !!clear;
            caretStartNext = !!caretStart;
            pending = { el: best };
            post({ type: 'requestEdit', sourcepos: sourceposFor(best) });
        }

        window.clearlyEditBlockAtLine = function(line, clear, caretStart) {
            if (live) editBlockAtOrAbove(line, clear, caretStart);
        };

        // Arrow-key travel: a plain arrow at the editor's very start or end
        // moves the caret into the neighboring block — the current block
        // leaves edit mode (committing as usual) and the neighbor enters it.
        function travel(a, up) {
            if (a.isInsert) return false;
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
                caretStartNext = false;
                pending = { el: target.el };
                post({ type: 'requestEdit', sourcepos: sourceposFor(target.el) });
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
                   reopenLine: newLine });
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

        // Cmd+A routed from native (the Edit menu's key equivalent consumes
        // it before the DOM ever sees a keydown). First press selects the
        // block; pressing with everything already selected widens the editor
        // to the whole document and selects all of it.
        window.clearlySelectAllInEditor = function() {
            if (!active || active.committed) return false;
            var a = active, ta = a.ta;
            if (ta.value.length > 0
                && ta.selectionStart === 0 && ta.selectionEnd === ta.value.length) {
                expandActive(a, true, true);
                expandActive(a, false, true);
            }
            ta.focus();
            ta.setSelectionRange(0, ta.value.length);
            return true;
        };

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
            if (e.target.closest('input, button, summary, th, .code-copy-btn, .code-fold-btn, .table-copy-btn, .mermaid-zoom-icon, .live-img-zoom, .lightbox-overlay, .footnote-popover, .live-editor')) {
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
            if (block) {
                // List items edit individually — the innermost item under
                // the click; everything else edits at the outermost block.
                // A whole list is never an edit target: clicks landing on
                // the container itself (gaps between items, gutters) go to
                // the item nearest the click.
                if (block.tagName === 'UL' || block.tagName === 'OL') {
                    var nearest = null, best = Infinity;
                    block.querySelectorAll('li[data-sourcepos]').forEach(function(li) {
                        var r = li.getBoundingClientRect();
                        var d = e.clientY < r.top ? r.top - e.clientY
                              : e.clientY > r.bottom ? e.clientY - r.bottom : 0;
                        // Ties prefer the descendant: a parent item's box
                        // spans its sublist's rows.
                        if (d < best || (d === best && nearest && nearest.contains(li))) {
                            best = d; nearest = li;
                        }
                    });
                    block = nearest;
                } else {
                    var item = block.closest('li[data-sourcepos]');
                    if (item) {
                        block = item;
                    } else {
                        while (block && block.parentElement && block.parentElement.closest('[data-sourcepos]')) {
                            block = block.parentElement.closest('[data-sourcepos]');
                        }
                    }
                }
            }
            if (block) {
                e.preventDefault();
                e.stopPropagation();
                clearNext = false;
                caretStartNext = false;
                pending = { el: block };
                post({ type: 'requestEdit', sourcepos: sourceposFor(block) });
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
