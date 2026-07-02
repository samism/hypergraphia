import Testing
import HypergraphiaCore

// .serialized: cmark-gfm's C entry points are not safe to call concurrently
// (extension registration races) — Swift Testing runs tests in parallel by
// default, unlike the XCTest renderer suites.
@Suite("Hard line breaks", .serialized)
struct MarkdownLineBreakTests {
    @Test func typedNewlineRendersAsLineBreak() {
        // CMARK_OPT_HARDBREAKS: a lone newline must survive the render
        // visibly — live mode round-trips typed newlines through the source.
        let html = MarkdownRenderer.renderHTML("line one\nline two")
        #expect(html.contains("<br"))
        #expect(html.contains("line one"))
        #expect(html.contains("line two"))
    }

    @Test func blankLineStillSplitsParagraphs() {
        let html = MarkdownRenderer.renderHTML("para one\n\npara two")
        let paragraphs = html.components(separatedBy: "<p").count - 1
        #expect(paragraphs == 2)
    }

    @Test func codeBlocksAreUnaffected() {
        let html = MarkdownRenderer.renderHTML("```\nline one\nline two\n```")
        #expect(!html.contains("<br"))
    }
}
