import Testing
import ClearlyCore

@Suite("Hard line breaks")
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
