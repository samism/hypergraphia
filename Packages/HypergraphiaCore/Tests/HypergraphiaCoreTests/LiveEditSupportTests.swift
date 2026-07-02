import Testing
import HypergraphiaCore

@Suite("LiveEditSupport sourcepos parsing")
struct LiveEditLineRangeTests {
    @Test func multiLineBlock() {
        #expect(LiveEditSupport.lineRange(fromSourcepos: "5:1-7:12") == 5...7)
    }

    @Test func singleLineBlock() {
        #expect(LiveEditSupport.lineRange(fromSourcepos: "12:1-12:45") == 12...12)
    }

    @Test func endColumnZeroExcludesEndLine() {
        // cmark emits end column 0 when a block ends at the start of endLine
        // (e.g. a list item followed by a trailing newline).
        #expect(LiveEditSupport.lineRange(fromSourcepos: "65:1-69:0") == 65...68)
    }

    @Test func invalidInputs() {
        #expect(LiveEditSupport.lineRange(fromSourcepos: "") == nil)
        #expect(LiveEditSupport.lineRange(fromSourcepos: "garbage") == nil)
        #expect(LiveEditSupport.lineRange(fromSourcepos: "5:1") == nil)
        #expect(LiveEditSupport.lineRange(fromSourcepos: "0:1-2:3") == nil)
        // Effective end (1) before start (3) is not a block.
        #expect(LiveEditSupport.lineRange(fromSourcepos: "3:1-1:0") == nil)
    }
}

@Suite("LiveEditSupport line slicing")
struct LiveEditSliceTests {
    let doc = "line1\nline2\nline3\nline4"

    @Test func middleLines() {
        #expect(LiveEditSupport.slice(doc, lines: 2...3) == "line2\nline3")
    }

    @Test func singleLine() {
        #expect(LiveEditSupport.slice(doc, lines: 1...1) == "line1")
    }

    @Test func wholeDocument() {
        #expect(LiveEditSupport.slice(doc, lines: 1...4) == doc)
    }

    @Test func outOfBounds() {
        #expect(LiveEditSupport.slice(doc, lines: 4...5) == nil)
    }
}

@Suite("LiveEditSupport line replacement")
struct LiveEditReplaceTests {
    let doc = "one\ntwo\nthree\nfour"

    @Test func replaceMiddleLine() {
        #expect(LiveEditSupport.replacingLines(in: doc, start: 2, end: 2, with: "TWO") == "one\nTWO\nthree\nfour")
    }

    @Test func replaceGrowsLineCount() {
        #expect(LiveEditSupport.replacingLines(in: doc, start: 2, end: 3, with: "a\nb\nc") == "one\na\nb\nc\nfour")
    }

    @Test func replaceShrinksLineCount() {
        #expect(LiveEditSupport.replacingLines(in: doc, start: 1, end: 3, with: "x") == "x\nfour")
    }

    @Test func replaceLastLine() {
        #expect(LiveEditSupport.replacingLines(in: doc, start: 4, end: 4, with: "FOUR") == "one\ntwo\nthree\nFOUR")
    }

    @Test func emptyReplacementDeletesLines() {
        #expect(LiveEditSupport.replacingLines(in: doc, start: 2, end: 3, with: "") == "one\nfour")
    }

    @Test func insertionBeforeLine() {
        // end == start - 1 denotes insertion without removing anything.
        #expect(LiveEditSupport.replacingLines(in: doc, start: 3, end: 2, with: "mid") == "one\ntwo\nmid\nthree\nfour")
    }

    @Test func insertionAtEnd() {
        #expect(LiveEditSupport.replacingLines(in: doc, start: 5, end: 4, with: "five") == "one\ntwo\nthree\nfour\nfive")
    }

    @Test func outOfBoundsReturnsNil() {
        #expect(LiveEditSupport.replacingLines(in: doc, start: 0, end: 1, with: "x") == nil)
        #expect(LiveEditSupport.replacingLines(in: doc, start: 2, end: 5, with: "x") == nil)
        #expect(LiveEditSupport.replacingLines(in: doc, start: 6, end: 5, with: "x") == nil)
    }
}

@Suite("LiveEditSupport compare-and-swap edits")
struct LiveEditApplyTests {
    let doc = "one\ntwo\nthree\nfour"

    @Test func appliesWhenOriginalMatches() {
        #expect(LiveEditSupport.applyingEdit(to: doc, start: 2, end: 3, original: "two\nthree", replacement: "X") == "one\nX\nfour")
    }

    @Test func dropsStaleCommit() {
        // Document changed underneath: lines 2-3 no longer hold the slice the
        // editor was opened on.
        #expect(LiveEditSupport.applyingEdit(to: doc, start: 2, end: 3, original: "stale\nslice", replacement: "X") == nil)
    }

    @Test func dropsOutOfBoundsCommit() {
        #expect(LiveEditSupport.applyingEdit(to: doc, start: 4, end: 6, original: "four", replacement: "X") == nil)
        #expect(LiveEditSupport.applyingEdit(to: doc, start: 3, end: 2, original: "", replacement: "X") == nil)
    }
}

@Suite("LiveEditSupport block deletion")
struct LiveEditDeleteTests {
    // Lines:            1      2  3      4  5
    let doc = "first\n\nmiddle\n\nlast"

    @Test func middleBlockSwallowsPrecedingBlank() {
        let d = LiveEditSupport.blockDeletion(in: doc, start: 3, end: 3, original: "middle")
        #expect(d?.start == 2 && d?.end == 3)
        #expect(d?.original == "\nmiddle")
        #expect(d?.previousLine == 1)
        let text = LiveEditSupport.applyingEdit(to: doc, start: d!.start, end: d!.end, original: d!.original, replacement: "")
        #expect(text == "first\n\nlast")
    }

    @Test func lastBlockSwallowsPrecedingBlank() {
        let d = LiveEditSupport.blockDeletion(in: doc, start: 5, end: 5, original: "last")
        #expect(d?.start == 4 && d?.end == 5)
        #expect(d?.previousLine == 3)
        let text = LiveEditSupport.applyingEdit(to: doc, start: d!.start, end: d!.end, original: d!.original, replacement: "")
        #expect(text == "first\n\nmiddle")
    }

    @Test func firstBlockSwallowsFollowingBlank() {
        let d = LiveEditSupport.blockDeletion(in: doc, start: 1, end: 1, original: "first")
        #expect(d?.start == 1 && d?.end == 2)
        #expect(d?.previousLine == 0, "no previous block before the first one")
        let text = LiveEditSupport.applyingEdit(to: doc, start: d!.start, end: d!.end, original: d!.original, replacement: "")
        #expect(text == "middle\n\nlast")
    }

    @Test func adjacentBlocksWithoutBlanksDeleteExactRange() {
        // Task-list items sit on consecutive lines with no separators.
        let tasks = "- [x] one\n- [ ] two\n- [ ] three"
        let d = LiveEditSupport.blockDeletion(in: tasks, start: 2, end: 2, original: "- [ ] two")
        #expect(d?.start == 2 && d?.end == 2)
        #expect(d?.previousLine == 1)
        let text = LiveEditSupport.applyingEdit(to: tasks, start: d!.start, end: d!.end, original: d!.original, replacement: "")
        #expect(text == "- [x] one\n- [ ] three")
    }

    @Test func multiLineBlockDeletes() {
        let text = "a\n\nline1\nline2\n\nz"
        let d = LiveEditSupport.blockDeletion(in: text, start: 3, end: 4, original: "line1\nline2")
        #expect(d?.start == 2 && d?.end == 4)
        let updated = LiveEditSupport.applyingEdit(to: text, start: d!.start, end: d!.end, original: d!.original, replacement: "")
        #expect(updated == "a\n\nz")
    }

    @Test func staleOriginalIsRejected() {
        #expect(LiveEditSupport.blockDeletion(in: doc, start: 3, end: 3, original: "not middle") == nil)
    }

    @Test func deletionNeverLeavesDoubleBlankLines() {
        let d = LiveEditSupport.blockDeletion(in: doc, start: 3, end: 3, original: "middle")
        let text = LiveEditSupport.applyingEdit(to: doc, start: d!.start, end: d!.end, original: d!.original, replacement: "")
        #expect(text?.contains("\n\n\n") == false)
    }
}

@Suite("LiveEditSupport range deletion")
struct LiveEditRangeDeleteTests {
    // Lines:            1      2  3      4  5      6  7
    let doc = "first\n\nsecond\n\nthird\n\nfourth"

    @Test func deletesEverythingAfterKeptBlock() {
        // Selection spanned blocks 1-3: keep `first` (ends line 1), delete
        // through the end of `third` (line 5), separators included.
        let plan = LiveEditSupport.rangeDeletion(in: doc, keepEnd: 1, deleteEnd: 5)
        #expect(plan?.start == 2 && plan?.end == 5)
        #expect(plan?.original == "\nsecond\n\nthird")
        let text = LiveEditSupport.applyingEdit(
            to: doc, start: plan!.start, end: plan!.end, original: plan!.original, replacement: ""
        )
        #expect(text == "first\n\nfourth")
    }

    @Test func selectAllKeepsFirstBlockOnly() {
        let plan = LiveEditSupport.rangeDeletion(in: doc, keepEnd: 1, deleteEnd: 7)
        #expect(plan?.start == 2 && plan?.end == 7)
        let text = LiveEditSupport.applyingEdit(
            to: doc, start: plan!.start, end: plan!.end, original: plan!.original, replacement: ""
        )
        #expect(text == "first")
    }

    @Test func midDocumentSpan() {
        // Keep `second` (ends line 3), delete through `third` (line 5); the
        // separator before `fourth` survives so blocks stay separated.
        let plan = LiveEditSupport.rangeDeletion(in: doc, keepEnd: 3, deleteEnd: 5)
        let text = LiveEditSupport.applyingEdit(
            to: doc, start: plan!.start, end: plan!.end, original: plan!.original, replacement: ""
        )
        #expect(text == "first\n\nsecond\n\nfourth")
        #expect(text?.contains("\n\n\n") == false)
    }

    @Test func adjacentBlocksWithoutSeparators() {
        let tasks = "- [x] one\n- [ ] two\n- [ ] three"
        let plan = LiveEditSupport.rangeDeletion(in: tasks, keepEnd: 1, deleteEnd: 3)
        let text = LiveEditSupport.applyingEdit(
            to: tasks, start: plan!.start, end: plan!.end, original: plan!.original, replacement: ""
        )
        #expect(text == "- [x] one")
    }

    @Test func invalidSpansReturnNil() {
        // deleteEnd before the first deletable line.
        #expect(LiveEditSupport.rangeDeletion(in: doc, keepEnd: 3, deleteEnd: 3) == nil)
        // Past the end of the document.
        #expect(LiveEditSupport.rangeDeletion(in: doc, keepEnd: 1, deleteEnd: 8) == nil)
        // keepEnd of 0 would mean "keep nothing" — start line must be >= 1.
        #expect(LiveEditSupport.rangeDeletion(in: doc, keepEnd: -1, deleteEnd: 3) == nil)
    }
}

@Suite("LiveEditSupport block appending")
struct LiveEditAppendTests {
    @Test func emptyDocument() {
        #expect(LiveEditSupport.appendingBlock("hello", to: "") == "hello")
    }

    @Test func noTrailingNewline() {
        #expect(LiveEditSupport.appendingBlock("new", to: "para") == "para\n\nnew")
    }

    @Test func singleTrailingNewline() {
        #expect(LiveEditSupport.appendingBlock("new", to: "para\n") == "para\n\nnew")
    }

    @Test func doubleTrailingNewline() {
        #expect(LiveEditSupport.appendingBlock("new", to: "para\n\n") == "para\n\nnew")
    }
}

@Suite("LiveEditSupport script")
struct LiveEditScriptTests {
    @Test func scriptExposesProtocol() {
        let script = LiveEditSupport.scriptHTML
        #expect(script.contains("messageHandlers.liveEdit"))
        #expect(script.contains("window.clearlyBeginEdit"))
        #expect(script.contains("window.clearlyBeginAppend"))
        #expect(script.contains("window.clearlySetLiveMode"))
        #expect(script.contains("window.clearlySetSource"))
        #expect(script.contains("requestEdit"))
        #expect(script.contains("commitEdit"))
        #expect(script.contains("appendBlock"))
        #expect(script.contains("deleteBlockRange"))
    }
}

@Suite("LiveEditSupport source script")
struct LiveEditSourceScriptTests {
    @Test func embedsSourceAsJSON() {
        let html = LiveEditSupport.sourceScriptHTML(for: "# Hi\n\nBody \"quoted\" text.")
        #expect(html.hasPrefix("<script>window.__clearlySource = "))
        #expect(html.hasSuffix(";</script>"))
        #expect(html.contains("\\n"))
        #expect(html.contains("\\\"quoted\\\""))
    }

    @Test func scriptCloseTagCannotBreakOut() {
        // JSON encoding escapes "/", so a literal </script> in the markdown
        // must not terminate the script element early.
        let html = LiveEditSupport.sourceScriptHTML(for: "evil </script><script>alert(1)")
        #expect(!html.dropFirst("<script>".count).dropLast("</script>".count).contains("</script>"))
    }

    @Test func emptySource() {
        let html = LiveEditSupport.sourceScriptHTML(for: "")
        #expect(html == "<script>window.__clearlySource = \"\";</script>")
    }
}
