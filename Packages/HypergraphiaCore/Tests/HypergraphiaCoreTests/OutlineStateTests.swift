import XCTest
import Combine
@testable import HypergraphiaCore

final class OutlineStateTests: XCTestCase {

    /// Runs the debounced background parse and waits for headings to publish.
    private func parse(_ text: String, timeout: TimeInterval = 3) -> [HeadingItem] {
        let state = OutlineState()
        let expectation = expectation(description: "headings published")
        let cancellable = state.$headings.dropFirst().sink { _ in
            expectation.fulfill()
        }
        state.parseHeadings(from: text)
        wait(for: [expectation], timeout: timeout)
        _ = cancellable
        return state.headings
    }

    func testParsesAtxAndSetextHeadingsInDocumentOrder() {
        let text = """
        # First

        Body text

        Second
        ======

        ## Third
        """
        let headings = parse(text)
        XCTAssertEqual(headings.map(\.title), ["First", "Second", "Third"])
        XCTAssertEqual(headings.map(\.level), [1, 1, 2])
    }

    func testSkipsHeadingsInsideCodeBlocksAndFrontmatter() {
        let text = """
        ---
        title: Not a heading
        ---

        # Real

        ```
        # Fenced comment
        ```
        """
        let headings = parse(text)
        XCTAssertEqual(headings.map(\.title), ["Real"])
    }

    func testPreviewAnchorsCarryCorrectLineNumbers() {
        let text = "# One\n\ntext\n\n## Two\nmore\n### Three\n"
        let headings = parse(text)
        XCTAssertEqual(headings.count, 3)
        XCTAssertEqual(headings[0].previewAnchor.startLine, 1)
        XCTAssertEqual(headings[1].previewAnchor.startLine, 5)
        XCTAssertEqual(headings[2].previewAnchor.startLine, 7)
        XCTAssertEqual(headings.map(\.previewAnchor.startColumn), [1, 1, 1])
        // Single-line headings end on their own line.
        XCTAssertEqual(headings[0].previewAnchor.endLine, 1)
        XCTAssertEqual(headings[2].previewAnchor.endLine, 7)
    }

    func testStripsInlineMarkdownFromTitles() {
        let text = "# **Bold** and [linked](https://x.com) and `code` and ![img](pic.png)\n"
        let headings = parse(text)
        XCTAssertEqual(headings.first?.title, "Bold and linked and code and img")
    }
}
