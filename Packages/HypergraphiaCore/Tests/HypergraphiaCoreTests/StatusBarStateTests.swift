import XCTest
import Combine
@testable import HypergraphiaCore

final class StatusBarStateTests: XCTestCase {
    func testSelectionChangesKeepDocumentTotals() {
        let state = StatusBarState()
        let text = "**Hello** world from Hypergraphia"

        state.updateText(text)
        state.updateSelection((text as NSString).range(of: "world from"), in: text)

        XCTAssertEqual(state.counts.totalWords, 4)
        XCTAssertEqual(state.counts.totalChars, "Hello world from Hypergraphia".count)
        XCTAssertEqual(state.counts.selectionWords, 2)
        XCTAssertEqual(state.counts.selectionChars, "world from".count)

        state.resetSelection()
        XCTAssertEqual(state.counts.totalWords, 4)
        XCTAssertFalse(state.counts.hasSelection)
    }

    func testTextChangeAfterTextChangeRefreshesTotals() {
        let state = StatusBarState()

        state.updateText("one two")
        XCTAssertEqual(state.counts.totalWords, 2)

        state.updateText("one two three")
        XCTAssertEqual(state.counts.totalWords, 3)
    }

    func testLargeTextComputesAsynchronouslyOffMain() {
        let state = StatusBarState()
        // Build a text safely past the async threshold: N repetitions of a
        // five-word sentence.
        let sentence = "alpha beta gamma delta epsilon\n"
        let repetitions = StatusBarState.asyncThreshold / sentence.utf16.count + 10
        let text = String(repeating: sentence, count: repetitions)

        state.updateText(text)
        // Large input must NOT be computed synchronously on the calling thread.
        XCTAssertEqual(state.counts.totalWords, 0)

        let expectation = expectation(description: "async totals published")
        let cancellable = state.$counts.dropFirst().sink { counts in
            if counts.totalWords == repetitions * 5 {
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 5)
        _ = cancellable
        XCTAssertEqual(state.counts.totalWords, repetitions * 5)
    }

    func testRapidLargeUpdatesPublishOnlyTheLatest() {
        let state = StatusBarState()
        let sentence = "one two three four five\n"
        let repetitions = StatusBarState.asyncThreshold / sentence.utf16.count + 10
        let base = String(repeating: sentence, count: repetitions)

        // Two updates in quick succession: the debounce must drop the first.
        state.updateText(base)
        state.updateText(base + "extra word here\n")

        let expectation = expectation(description: "latest totals published")
        let expected = repetitions * 5 + 3
        let cancellable = state.$counts.dropFirst().sink { counts in
            if counts.totalWords == expected {
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 5)
        _ = cancellable
        XCTAssertEqual(state.counts.totalWords, expected)
    }
}
