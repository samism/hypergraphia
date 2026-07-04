import Testing
@testable import HypergraphiaCore

/// Pins the code-region protect/restore machinery and the fast-path guards
/// added to the post-processing pipeline.
@Suite("Render pipeline protection")
struct MarkdownRenderPipelineTests {

    @Test func manyCodeSpansSurviveWithHighlightMarks() {
        // More than ten spans exercises multi-digit placeholder tokens.
        var markdown = ""
        for i in 0..<12 {
            markdown += "Span `code_\(i)` and ==mark \(i)== here.\n\n"
        }
        let html = MarkdownRenderer.renderHTML(markdown)
        for i in 0..<12 {
            #expect(html.contains("<code>code_\(i)</code>"))
            #expect(html.contains("<mark>mark \(i)</mark>"))
        }
        #expect(!html.contains("__CLEARLY_PROTECTED_CODE_"))
    }

    @Test func highlightSyntaxInsideCodeIsNotTransformed() {
        let markdown = "Outside ==yes==\n\n```\ninside ==no==\n```\n"
        let html = MarkdownRenderer.renderHTML(markdown)
        #expect(html.contains("<mark>yes</mark>"))
        #expect(html.contains("inside ==no=="))
        #expect(!html.contains("<mark>no</mark>"))
    }

    @Test func superSubInsideCodeIsNotTransformed() {
        let markdown = "H~2~O and x^2^\n\n`a~b~c` and `d^e^f`\n"
        let html = MarkdownRenderer.renderHTML(markdown)
        #expect(html.contains("H<sub>2</sub>O"))
        #expect(html.contains("x<sup>2</sup>"))
        #expect(html.contains("a~b~c"))
        #expect(html.contains("d^e^f"))
    }

    @Test func codeFilenameTitlesAreExtracted() {
        let markdown = """
        Intro line

        ```swift title="Sources/App.swift"
        let x = 1
        ```
        """
        let html = MarkdownRenderer.renderHTML(markdown)
        #expect(html.contains("<div class=\"code-filename\">Sources/App.swift</div>"))
        #expect(!html.contains("title=\"Sources/App.swift\""))
    }

    @Test func plainDocumentRendersWithoutMathArtifacts() {
        // A document with no $ must not grow math spans; one with escaped
        // dollars keeps them literal.
        let plain = MarkdownRenderer.renderHTML("Just a paragraph with words.\n")
        #expect(!plain.contains("math-inline"))

        let escaped = MarkdownRenderer.renderHTML("Costs \\$5 and \\$10 today.\n")
        #expect(escaped.contains("$5"))
        #expect(!escaped.contains("math-inline"))
    }
}
