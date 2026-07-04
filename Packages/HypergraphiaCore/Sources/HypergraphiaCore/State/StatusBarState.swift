import Foundation

public final class StatusBarState: ObservableObject {
    @Published public private(set) var counts: MarkdownStats.Counts = .empty

    /// Above this many UTF-16 units, stats computation (a ~20-pass regex
    /// strip plus localized word enumeration) is too expensive to run
    /// synchronously per keystroke on the main thread. Larger inputs are
    /// debounced onto a background queue; smaller ones stay synchronous so
    /// the count never visibly lags on ordinary notes.
    static let asyncThreshold = 20_000

    /// Debounce for background stats. Word counts are ambient UI — a quarter
    /// second of staleness during continuous typing is imperceptible.
    private static let debounceInterval: TimeInterval = 0.25

    private static let statsQueue = DispatchQueue(
        label: "com.sabotage.clearly.stats", qos: .userInitiated
    )

    private var lastText: String = ""
    private var lastSelection: NSRange = NSRange(location: 0, length: 0)
    private var cachedTotals: MarkdownStats.Counts = .empty
    private var hasCachedTotals = false

    /// Cancels superseded background computations. Only touched on the
    /// caller's (main) thread; results hop back to main and check it there.
    private var generation = 0
    private var pendingWork: DispatchWorkItem?

    public init() {}

    /// Replace the cached document text and recompute. Selection length is
    /// preserved if it still fits inside the new text; otherwise it collapses.
    public func updateText(_ text: String) {
        lastText = text
        hasCachedTotals = false
        let nsLength = (text as NSString).length
        if lastSelection.location + lastSelection.length > nsLength {
            lastSelection = NSRange(location: 0, length: 0)
        }
        recomputeAll()
    }

    /// Replace just the selection range. Caller passes the current text so
    /// the cache stays consistent (selection events fire faster than the
    /// debounced text-binding write).
    public func updateSelection(_ range: NSRange, in text: String) {
        lastText = text
        lastSelection = range
        if hasCachedTotals {
            recomputeSelectionOnly()
        } else {
            recomputeAll()
        }
    }

    /// Clear selection without changing the cached text — used when the
    /// document switches or the editor is dismissed.
    public func resetSelection() {
        lastSelection = NSRange(location: 0, length: 0)
        if hasCachedTotals {
            recomputeSelectionOnly()
        } else {
            recomputeAll()
        }
    }

    private func recomputeAll() {
        pendingWork?.cancel()
        pendingWork = nil
        generation += 1

        let text = lastText
        let selection = lastSelection
        guard text.utf16.count > Self.asyncThreshold else {
            applyTotals(MarkdownStats.compute(text: text, selectedRange: selection))
            return
        }

        let expected = generation
        let work = DispatchWorkItem { [weak self] in
            let computed = MarkdownStats.compute(text: text, selectedRange: selection)
            DispatchQueue.main.async {
                guard let self, self.generation == expected else { return }
                self.applyTotals(computed)
            }
        }
        pendingWork = work
        Self.statsQueue.asyncAfter(deadline: .now() + Self.debounceInterval, execute: work)
    }

    private func applyTotals(_ computed: MarkdownStats.Counts) {
        counts = computed
        cachedTotals = MarkdownStats.Counts(
            totalWords: computed.totalWords,
            totalChars: computed.totalChars,
            totalReadingSeconds: computed.totalReadingSeconds,
            selectionWords: 0,
            selectionChars: 0,
            hasSelection: false
        )
        hasCachedTotals = true
    }

    private func recomputeSelectionOnly() {
        pendingWork?.cancel()
        pendingWork = nil
        generation += 1

        guard lastSelection.length > Self.asyncThreshold else {
            applySelection(selectionCounts(in: lastText, selection: lastSelection))
            return
        }

        // Huge selections (Select All on a large document, shift-drags) get
        // the same debounce treatment as full-text recomputes.
        let expected = generation
        let text = lastText
        let selection = lastSelection
        let work = DispatchWorkItem { [weak self] in
            let computed = Self.selectionCounts(in: text, selection: selection)
            DispatchQueue.main.async {
                guard let self, self.generation == expected else { return }
                self.applySelection(computed)
            }
        }
        pendingWork = work
        Self.statsQueue.asyncAfter(deadline: .now() + Self.debounceInterval, execute: work)
    }

    private func applySelection(_ selection: (words: Int, chars: Int, hasSelection: Bool)) {
        counts = MarkdownStats.Counts(
            totalWords: cachedTotals.totalWords,
            totalChars: cachedTotals.totalChars,
            totalReadingSeconds: cachedTotals.totalReadingSeconds,
            selectionWords: selection.words,
            selectionChars: selection.chars,
            hasSelection: selection.hasSelection
        )
    }

    private func selectionCounts(in text: String, selection: NSRange) -> (words: Int, chars: Int, hasSelection: Bool) {
        Self.selectionCounts(in: text, selection: selection)
    }

    private static func selectionCounts(in text: String, selection: NSRange) -> (words: Int, chars: Int, hasSelection: Bool) {
        let nsText = text as NSString
        guard selection.length > 0,
              selection.location >= 0,
              selection.location + selection.length <= nsText.length else {
            return (0, 0, false)
        }

        let selectedText = nsText.substring(with: selection)
        let selected = MarkdownStats.compute(text: selectedText, selectedRange: NSRange())
        return (selected.totalWords, selected.totalChars, true)
    }
}
