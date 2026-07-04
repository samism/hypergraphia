import XCTest
@testable import HypergraphiaCore

/// Regression coverage for the highlighter's two passes. These pin the
/// user-visible attribute results (fonts, colors, protected ranges) so the
/// incremental substring-based pass can't drift from the full pass.
final class MarkdownSyntaxHighlighterTests: XCTestCase {

    private func storage(_ text: String) -> NSTextStorage {
        NSTextStorage(string: text)
    }

    private func range(of needle: String, in storage: NSTextStorage) -> NSRange {
        (storage.string as NSString).range(of: needle)
    }

    // MARK: - Full pass

    func testHighlightAllStylesInlineConstructs() {
        let text = "# Title\n\nSome **bold** and *italic* and `code` here.\n"
        let s = storage(text)
        let highlighter = MarkdownSyntaxHighlighter()
        highlighter.highlightAll(s)

        let boldRange = range(of: "bold", in: s)
        let boldFont = s.attribute(.font, at: boldRange.location, effectiveRange: nil) as? PlatformFont
        XCTAssertEqual(boldFont, Theme.editorBoldFont)
        let boldColor = s.attribute(.foregroundColor, at: boldRange.location, effectiveRange: nil) as? PlatformColor
        XCTAssertEqual(boldColor, Theme.boldColor)

        let italicRange = range(of: "italic", in: s)
        let italicFont = s.attribute(.font, at: italicRange.location, effectiveRange: nil) as? PlatformFont
        XCTAssertEqual(italicFont, Theme.editorItalicFont)

        let codeRange = range(of: "code", in: s)
        let codeFont = s.attribute(.font, at: codeRange.location, effectiveRange: nil) as? PlatformFont
        XCTAssertEqual(codeFont, Theme.editorCodeFont)

        let headingRange = range(of: "Title", in: s)
        let headingFont = s.attribute(.font, at: headingRange.location, effectiveRange: nil) as? PlatformFont
        XCTAssertEqual(headingFont, Theme.editorHeadingFont)
        // The "# " marker reads as syntax
        let markerColor = s.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? PlatformColor
        XCTAssertEqual(markerColor, Theme.syntaxColor)
    }

    func testHighlightAllProtectsCodeBlocksFromInlineStyling() {
        let text = "Before\n\n```\nnot **bold** here\n```\n\nAfter **bold**\n"
        let s = storage(text)
        let highlighter = MarkdownSyntaxHighlighter()
        highlighter.highlightAll(s)

        // Inside the fence: code font, no bold styling.
        let inner = range(of: "not **bold** here", in: s)
        let innerFont = s.attribute(.font, at: inner.location + 6, effectiveRange: nil) as? PlatformFont
        XCTAssertEqual(innerFont, Theme.editorCodeFont)
        XCTAssertTrue(highlighter.isInsideProtectedRange(at: inner.location))

        // Outside the fence: bold styling applies.
        let after = range(of: "After **bold**", in: s)
        let boldStart = after.location + "After **".utf16.count
        let outerFont = s.attribute(.font, at: boldStart, effectiveRange: nil) as? PlatformFont
        XCTAssertEqual(outerFont, Theme.editorBoldFont)
        XCTAssertFalse(highlighter.isInsideProtectedRange(at: after.location))
    }

    func testHighlightAllDetectsFrontmatterAndMathBlocks() {
        let text = "---\ntitle: Test\n---\n\n$$\nx^2\n$$\n\nBody\n"
        let s = storage(text)
        let highlighter = MarkdownSyntaxHighlighter()
        highlighter.highlightAll(s)

        XCTAssertTrue(highlighter.isInsideProtectedRange(at: range(of: "title", in: s).location))
        XCTAssertTrue(highlighter.isInsideProtectedRange(at: range(of: "x^2", in: s).location))
        XCTAssertFalse(highlighter.isInsideProtectedRange(at: range(of: "Body", in: s).location))
    }

    // MARK: - Incremental pass

    func testHighlightAroundMatchesFullPassForInlineEdit() {
        // Start from a fully highlighted document, append characters the way
        // typing does, and verify the incremental pass produces the same
        // attributes as a from-scratch full pass on identical content.
        let initial = "# Title\n\nplain paragraph\n\nlast line\n"
        let s = storage(initial)
        let highlighter = MarkdownSyntaxHighlighter()
        highlighter.highlightAll(s)

        let insertion = "now **bold** "
        let insertAt = (initial as NSString).range(of: "paragraph").location
        s.replaceCharacters(in: NSRange(location: insertAt, length: 0), with: insertion)
        highlighter.highlightAround(
            s,
            editedRange: NSRange(location: insertAt, length: 0),
            replacementLength: (insertion as NSString).length
        )

        let reference = storage(s.string)
        MarkdownSyntaxHighlighter().highlightAll(reference)

        let paragraphRange = (s.string as NSString).paragraphRange(
            for: NSRange(location: insertAt, length: 0)
        )
        for offset in paragraphRange.location..<NSMaxRange(paragraphRange) {
            let got = s.attributes(at: offset, effectiveRange: nil)
            let want = reference.attributes(at: offset, effectiveRange: nil)
            XCTAssertEqual(
                got[.font] as? PlatformFont, want[.font] as? PlatformFont,
                "font mismatch at \(offset)"
            )
            XCTAssertEqual(
                got[.foregroundColor] as? PlatformColor, want[.foregroundColor] as? PlatformColor,
                "color mismatch at \(offset)"
            )
        }
    }

    func testHighlightAroundShiftsProtectedRangesOnEditAbove() {
        let text = "intro\n\n```\ncode body\n```\n"
        let s = storage(text)
        let highlighter = MarkdownSyntaxHighlighter()
        highlighter.highlightAll(s)

        let codeBodyBefore = range(of: "code body", in: s)
        XCTAssertTrue(highlighter.isInsideProtectedRange(at: codeBodyBefore.location))

        // Insert plain text into the intro line — protected range must shift.
        let insertion = "longer "
        s.replaceCharacters(in: NSRange(location: 0, length: 0), with: insertion)
        highlighter.highlightAround(
            s,
            editedRange: NSRange(location: 0, length: 0),
            replacementLength: (insertion as NSString).length
        )

        let codeBodyAfter = range(of: "code body", in: s)
        XCTAssertEqual(codeBodyAfter.location, codeBodyBefore.location + (insertion as NSString).length)
        XCTAssertTrue(highlighter.isInsideProtectedRange(at: codeBodyAfter.location))
        XCTAssertFalse(highlighter.isInsideProtectedRange(at: 0))
    }

    func testHighlightAroundInsideCodeBlockKeepsCodeStyling() {
        let text = "intro\n\n```\ncode body\n```\n"
        let s = storage(text)
        let highlighter = MarkdownSyntaxHighlighter()
        highlighter.highlightAll(s)

        // Type inside the code block; the paragraph is fully inside the
        // protected range and must keep code font, not pick up bold.
        let insertAt = range(of: "body", in: s).location
        let insertion = "**x** "
        s.replaceCharacters(in: NSRange(location: insertAt, length: 0), with: insertion)
        highlighter.highlightAround(
            s,
            editedRange: NSRange(location: insertAt, length: 0),
            replacementLength: (insertion as NSString).length
        )

        let styledFont = s.attribute(.font, at: insertAt + 2, effectiveRange: nil) as? PlatformFont
        XCTAssertEqual(styledFont, Theme.editorCodeFont)
    }

    func testHighlightAroundFlagsBlockDelimiterEdits() {
        let text = "intro\n\nplain\n"
        let s = storage(text)
        let highlighter = MarkdownSyntaxHighlighter()
        highlighter.highlightAll(s)
        XCTAssertFalse(highlighter.needsFullHighlight)

        // Turn the "plain" line into a code fence — must request a full pass.
        let plain = range(of: "plain", in: s)
        s.replaceCharacters(in: plain, with: "```")
        highlighter.highlightAround(
            s,
            editedRange: plain,
            replacementLength: 3
        )
        XCTAssertTrue(highlighter.needsFullHighlight)
    }

    func testHighlightAroundWithStaleRangeFallsBackSafely() {
        let text = "short\n"
        let s = storage(text)
        let highlighter = MarkdownSyntaxHighlighter()
        // Range far past the end must not crash (iOS marked-text path).
        highlighter.highlightAround(
            s,
            editedRange: NSRange(location: 500, length: 4),
            replacementLength: 4
        )
        let font = s.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont
        XCTAssertEqual(font, Theme.editorFont)
    }
}
