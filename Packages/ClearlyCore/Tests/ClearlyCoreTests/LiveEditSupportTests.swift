import Testing
import ClearlyCore

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
        #expect(script.contains("requestEdit"))
        #expect(script.contains("commitEdit"))
        #expect(script.contains("appendBlock"))
    }
}
