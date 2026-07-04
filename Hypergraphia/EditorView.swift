import SwiftUI
import HypergraphiaCore
import AppKit
import Combine
import os

struct EditorView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 16
    var fileURL: URL?
    var mode: ViewMode
    var positionSyncID: String
    var findState: FindState?
    var outlineState: OutlineState?
    var extraTopInset: CGFloat = 0
    var extraBottomInset: CGFloat = 0
    var jumpToLineState: JumpToLineState?
    var statusBarState: StatusBarState?
    var needsTrafficLightClearance: Bool = false
    var contentWidthEm: CGFloat? = nil
    @Environment(\.colorScheme) private var colorScheme

    private static func computeHorizontalInset(
        scrollViewWidth: CGFloat, contentWidthEm: CGFloat?,
        fontSize: CGFloat, needsTrafficLightClearance: Bool
    ) -> CGFloat {
        let minInset = Theme.editorInsetX + (needsTrafficLightClearance ? 20 : 0)
        guard let emValue = contentWidthEm else { return minInset }
        let maxWidthPoints = emValue * fontSize
        return max(minInset, (scrollViewWidth - maxWidthPoints) / 2.0)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSView {
        DiagnosticLog.log("makeNSView: creating EditorView (\(text.count) chars)")
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: extraBottomInset, right: 0)
        scrollView.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: -extraBottomInset, right: 0)

        let textView = HypergraphiaTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindPanel = false
        textView.usesFontPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        TextCheckingPreferences.apply(to: textView)

        // Font
        textView.font = Theme.editorFont
        textView.textColor = Theme.textColor
        textView.backgroundColor = Theme.backgroundColor

        // Paragraph style with line height — use min/max line height + baselineOffset
        // so text is vertically centered in each line (not top-aligned like lineSpacing)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = Theme.editorLineHeight
        paragraph.maximumLineHeight = Theme.editorLineHeight
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [
            .font: Theme.editorFont,
            .foregroundColor: Theme.textColor,
            .paragraphStyle: paragraph,
            .baselineOffset: Theme.editorBaselineOffset
        ]

        // Insets
        let horizontalInset = Self.computeHorizontalInset(
            scrollViewWidth: 0, contentWidthEm: contentWidthEm,
            fontSize: fontSize, needsTrafficLightClearance: needsTrafficLightClearance
        )
        textView.textContainerInset = NSSize(width: horizontalInset, height: Theme.editorInsetTop + extraTopInset)
        textView.textContainer?.lineFragmentPadding = 0

        // Layout
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.layoutManager?.allowsNonContiguousLayout = true

        // Insertion point color
        textView.insertionPointColor = Theme.textColor
        textView.documentURL = fileURL

        // Set initial text BEFORE attaching the text view delegate.
        // This avoids triggering textDidChange during makeNSView —
        // the first updateNSView call handles initial highlighting via the color-scheme check.
        // Note: we do NOT set textStorage.delegate — highlighting is driven explicitly
        // from textDidChange and updateNSView to avoid re-entrant layout manager access.
        let highlighter = MarkdownSyntaxHighlighter()
        context.coordinator.highlighter = highlighter
        textView.string = text
        context.coordinator.lastCommittedText = text
        textView.delegate = context.coordinator
        scrollView.documentView = textView

        context.coordinator.textView = textView
        ActiveEditor.shared.textView = textView
        context.coordinator.findState = findState
        context.coordinator.outlineState = outlineState
        if let findState {
            context.coordinator.observeFindState(findState)
        }
        // Wire up find bar presentation
        textView.onShowFind = { [weak findState] in
            guard let findState else { return }
            DispatchQueue.main.async {
                findState.present()
            }
        }

        context.coordinator.bindEditorIntegrations(findState: findState, outlineState: outlineState)

        // Observe scroll position for sync
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.flushEditorBuffer(_:)),
            name: .flushEditorBuffer,
            object: nil
        )

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleHighlightText(_:)),
            name: .highlightTextInEditor,
            object: nil
        )

        // Frame changes (window resize) — recompute horizontal insets
        textView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.textViewFrameDidChange(_:)),
            name: NSView.frameDidChangeNotification,
            object: textView
        )

        // Wire jump-to-line
        if let jumpState = jumpToLineState {
            let coord = context.coordinator
            jumpState.onJump = { [weak coord] line in
                coord?.jumpToLine(line)
            }
            jumpState.editorLineInfo = { [weak coord] in
                coord?.currentLineInfo() ?? (1, 1)
            }
        }

        let container = NSView()
        container.addSubview(scrollView)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.frame = NSRect(x: 0, y: 0, width: 0, height: 0)

        DiagnosticLog.log("makeNSView: EditorView ready")
        return container
    }

    static func dismantleNSView(_ container: NSView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        if let textView = coordinator.textView,
           ActiveEditor.shared.textView === textView {
            ActiveEditor.shared.textView = nil
        }
        DiagnosticLog.log("dismantleNSView: EditorView torn down")
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard let scrollView = container.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView,
              let textView = scrollView.documentView as? HypergraphiaTextView else { return }

        // Keep coordinator's parent fresh so the binding never goes stale
        context.coordinator.parent = self

        if mode == .edit {
            context.coordinator.bindEditorIntegrations(findState: findState, outlineState: outlineState)
        }

        // Update insets (content width, tab bar, traffic light clearance)
        context.coordinator.contentWidthEm = contentWidthEm
        context.coordinator.cachedFontSize = fontSize
        context.coordinator.cachedNeedsTrafficLightClearance = needsTrafficLightClearance
        let horizontalInset = Self.computeHorizontalInset(
            scrollViewWidth: scrollView.frame.width, contentWidthEm: contentWidthEm,
            fontSize: fontSize, needsTrafficLightClearance: needsTrafficLightClearance
        )
        let expectedInset = NSSize(width: horizontalInset, height: Theme.editorInsetTop + extraTopInset)
        if textView.textContainerInset != expectedInset {
            textView.textContainerInset = expectedInset
        }

        if abs(scrollView.contentInsets.bottom - extraBottomInset) > 0.5 {
            scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: extraBottomInset, right: 0)
            scrollView.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: -extraBottomInset, right: 0)
        }

        let didChangeDocument = context.coordinator.lastPositionSyncID != positionSyncID
        context.coordinator.lastPositionSyncID = positionSyncID

        // Restore scroll + focus when editing becomes visible or the document changes.
        if didChangeDocument {
            context.coordinator.cancelPendingBindingUpdate()
        }

        if mode == .edit && (context.coordinator.lastMode != .edit || didChangeDocument) {
            findState?.activeMode = .edit
            let fraction = ScrollBridge.fraction(for: positionSyncID)
            let docHeight = scrollView.documentView?.frame.height ?? 1
            let viewportHeight = scrollView.contentView.bounds.height
            let maxScroll = max(1, docHeight - viewportHeight)
            scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: fraction * maxScroll))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
            if findState?.isVisible == true {
                context.coordinator.performFind()
            }
        }
        // Leaving edit mode: give up the keyboard. The editor is hidden but
        // still alive in the ZStack — if it stays first responder, keystrokes
        // keep editing the document invisibly behind the rendered view.
        if mode != .edit && context.coordinator.lastMode == .edit {
            DispatchQueue.main.async {
                if let window = textView.window, window.firstResponder === textView {
                    window.makeFirstResponder(nil)
                }
            }
        }
        context.coordinator.lastMode = mode

        context.coordinator.updateCount += 1
        let count = context.coordinator.updateCount
        if count <= 5 || count % 100 == 0 {
            DiagnosticLog.log("updateNSView #\(count)")
        }

        // Always refresh colors (handles appearance changes via @Environment colorScheme)
        textView.backgroundColor = Theme.backgroundColor
        textView.insertionPointColor = Theme.textColor
        textView.documentURL = fileURL

        // Re-highlight and update typing attributes when appearance or font size changes
        let currentScheme = colorScheme
        let currentFontSize = fontSize
        let appearanceChanged = context.coordinator.lastColorScheme != currentScheme || context.coordinator.lastFontSize != currentFontSize
        if appearanceChanged {
            if count <= 5 {
                DiagnosticLog.log("updateNSView #\(count): appearance changed (scheme=\(currentScheme), fontSize=\(currentFontSize))")
            }
            context.coordinator.lastColorScheme = currentScheme
            context.coordinator.lastFontSize = currentFontSize
            textView.font = Theme.editorFont

            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = Theme.editorLineHeight
            paragraph.maximumLineHeight = Theme.editorLineHeight
            textView.typingAttributes = [
                .font: Theme.editorFont,
                .foregroundColor: Theme.textColor,
                .paragraphStyle: paragraph,
                .baselineOffset: Theme.editorBaselineOffset
            ]

            // Suppress scroll handler during highlighting to prevent layout manager deadlock
            context.coordinator.runFullHighlight(on: textView, caller: "appearance")
        }

        // Only update text if it changed externally (not from user typing).
        // When the user types, textDidChange marks the text view authoritative
        // until the next run loop. While updates are pending, any mismatch is
        // just SwiftUI catching up, not an external change.
        //
        // Marked-text composition (e.g. Option+U dead-key on a US keyboard;
        // CJK IMEs) also makes textView.string diverge from the binding —
        // setMarkedText inserts the composing character into textStorage but
        // does NOT fire textDidChange, so pendingBindingUpdates stays 0. The
        // hasMarkedText check below stops us from overwriting the composing
        // character with the stale binding value, which would silently abort
        // the dead-key sequence. The mismatch resolves naturally on the next
        // textDidChange — either when composition commits (Option+u then o →
        // "ö" gets inserted normally) or when the user dismisses it.
        if !context.coordinator.isUpdating
            && context.coordinator.pendingBindingUpdates == 0
            && !textView.hasMarkedText() {
            // Mismatch detection is on the per-keystroke path, so it has to
            // stay O(1) in the common no-change case. `text == lastCommitted`
            // hits Swift's same-storage fast path when SwiftUI hands back the
            // value the coordinator committed; the utf16/storage length gate
            // catches divergence without bridging the text view's backing
            // store (an O(n) NSMutableString copy) just to compare.
            let storageLength = textView.textStorage?.length ?? 0
            let textMismatch: Bool
            if text == context.coordinator.lastCommittedText && text.utf16.count == storageLength {
                textMismatch = false
            } else {
                textMismatch = text.utf16.count != storageLength || textView.string != text
            }
            if textMismatch {
                DiagnosticLog.log("updateNSView #\(count): external text change (\(text.utf16.count) utf16 units)")
                context.coordinator.isUpdating = true
                let selectedRanges = textView.selectedRanges
                textView.string = text
                textView.selectedRanges = selectedRanges
                context.coordinator.lastCommittedText = text
                context.coordinator.runFullHighlight(on: textView, caller: "externalText")
                // External text replacement (file load/revert) — old match ranges are stale.
                context.coordinator.clearFindHighlights()
                if let findState = context.coordinator.findState, findState.isVisible, findState.activeMode == .edit {
                    DispatchQueue.main.async { [weak findState] in
                        guard let findState, findState.activeMode == .edit else { return }
                        findState.matchCount = 0
                        findState.currentIndex = 0
                        findState.resultsAreStale = true
                    }
                }
                context.coordinator.isUpdating = false
            }
        } else if context.coordinator.isUpdating && count <= 5 {
            DiagnosticLog.log("updateNSView #\(count): skipped text check (isUpdating)")
        }

        if count <= 5 || count % 100 == 0 {
            DiagnosticLog.log("updateNSView #\(count) done")
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorView
        var isUpdating = false
        var isHighlightingInProgress = false
        var highlighter: MarkdownSyntaxHighlighter?
        var lastEditedRange: NSRange?
        var lastReplacementLength: Int = 0
        weak var textView: HypergraphiaTextView?
        var lastMode: ViewMode?
        var lastPositionSyncID: String?
        var findState: FindState?
        var outlineState: OutlineState?
        var lastColorScheme: ColorScheme?
        var lastFontSize: CGFloat?
        var contentWidthEm: CGFloat?
        var cachedFontSize: CGFloat = 12
        var cachedNeedsTrafficLightClearance: Bool = false
        var updateCount = 0
        private var lastScrollTime: TimeInterval = 0
        /// Tracks how many async binding updates are in-flight. While > 0,
        /// updateNSView must not replace the text view's content — the text
        /// view is authoritative and the binding will catch up.
        var pendingBindingUpdates = 0
        var pendingBindingUpdateToken: UUID?
        private var pendingFullHighlightWork: DispatchWorkItem?
        /// Snapshot of the last text this coordinator pushed into (or pulled
        /// from) the binding. Lets `updateNSView` skip the O(n) text-view
        /// bridge + compare on every SwiftUI pass where nothing changed.
        var lastCommittedText: String = ""
        /// Whether the previous selection had non-zero length — used to skip
        /// status-bar selection work entirely for plain caret movement.
        var hadSelection = false

        // Find state tracking
        var matchRanges: [NSRange] = []
        var lastMatches: [TextMatch] = []
        private var currentMatchIdx = 0 // 0-based internal index
        private var findCancellables = Set<AnyCancellable>()

        init(_ parent: EditorView) {
            self.parent = parent
        }

        func bindEditorIntegrations(findState: FindState?, outlineState: OutlineState?) {
            self.findState = findState
            self.outlineState = outlineState

            findState?.editorNavigateToNext = { [weak self] in
                self?.navigateToNextMatch()
            }
            findState?.editorNavigateToPrevious = { [weak self] in
                self?.navigateToPreviousMatch()
            }
            findState?.editorPerformReplace = { [weak self] in
                self?.performReplaceCurrent()
            }
            findState?.editorPerformReplaceAll = { [weak self] in
                self?.performReplaceAll()
            }

            outlineState?.scrollToRange = { [weak self] range in
                self?.scrollToHeading(range)
            }
        }

        func scrollToHeading(_ range: NSRange) {
            guard let textView else { return }
            textView.scrollRangeToVisible(range)
            textView.showFindIndicator(for: range)
        }

        /// Selections beyond this many UTF-16 units aren't bridged for
        /// mode-switch highlighting — the preview-side text search couldn't
        /// use a query that size anyway, and copying it per selection event
        /// makes shift-drags stutter on large documents.
        private static let maxBridgedSelectionLength = 10_000

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            // Store current selection for highlight-on-mode-switch.
            // `textStorage.mutableString` is the live backing store — using it
            // avoids the full-document snapshot that bridging `textView.string`
            // performs on every selection event.
            let range = textView.selectedRange()
            if range.length > 0, range.length <= Self.maxBridgedSelectionLength,
               let storage = textView.textStorage, range.upperBound <= storage.length {
                let text = storage.mutableString.substring(with: range)
                SelectionBridge.setSelection(text, for: parent.positionSyncID)
            } else {
                SelectionBridge.setSelection(nil, for: parent.positionSyncID)
            }

            // Status-bar selection counts only need refreshing when a real
            // selection exists or one was just dismissed; plain caret movement
            // (every keystroke fires this) skips the state churn entirely.
            let hasSelection = range.length > 0
            if hasSelection || hadSelection {
                parent.statusBarState?.updateSelection(range, in: lastCommittedText)
            }
            hadSelection = hasSelection
        }

        @objc func handleHighlightText(_ notification: Notification) {
            guard let searchText = notification.userInfo?["text"] as? String,
                  !searchText.isEmpty,
                  let textView else { return }
            let nsText = textView.string as NSString
            guard nsText.length > 0 else { return }

            // Determine visible character range to prioritize matches near current viewport
            var searchStart = 0
            if let layoutManager = textView.layoutManager, let container = textView.textContainer {
                let glyphRange = layoutManager.glyphRange(forBoundingRect: textView.visibleRect, in: container)
                let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
                searchStart = charRange.location
            }

            // Search forward from visible start, then wrap around
            var foundRange = nsText.range(of: searchText, options: [], range: NSRange(location: searchStart, length: nsText.length - searchStart))
            if foundRange.location == NSNotFound {
                foundRange = nsText.range(of: searchText, options: [], range: NSRange(location: 0, length: min(searchStart + searchText.count, nsText.length)))
            }
            guard foundRange.location != NSNotFound else { return }
            textView.scrollRangeToVisible(foundRange)
            textView.showFindIndicator(for: foundRange)
        }

        @objc func flushEditorBuffer(_ notification: Notification) {
            guard let textView else { return }
            pendingBindingUpdateToken = nil
            pendingBindingUpdates = 0
            commitTextViewContents(textView)
        }

        @objc func textViewFrameDidChange(_ notification: Notification) {
            // Recalculate horizontal inset on window resize to keep text centered
            guard let textView, let scrollView = textView.enclosingScrollView else { return }
            let horizontalInset = EditorView.computeHorizontalInset(
                scrollViewWidth: scrollView.frame.width,
                contentWidthEm: contentWidthEm,
                fontSize: cachedFontSize,
                needsTrafficLightClearance: cachedNeedsTrafficLightClearance
            )
            let currentVertical = textView.textContainerInset.height
            let newInset = NSSize(width: horizontalInset, height: currentVertical)
            if abs(textView.textContainerInset.width - newInset.width) > 0.5 {
                textView.textContainerInset = newInset
            }
        }

        func jumpToLine(_ line: Int) {
            guard let textView, let storage = textView.textStorage, line > 0 else { return }
            let nsText = storage.mutableString
            // Walk newline-by-newline to the target line's start; clamps to
            // the last line when the document has fewer lines.
            var location = 0
            var currentLine = 1
            while currentLine < line {
                let next = nsText.range(of: "\n", range: NSRange(location: location, length: nsText.length - location))
                if next.location == NSNotFound { break }
                location = next.location + 1
                currentLine += 1
            }
            let range = NSRange(location: location, length: 0)
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
            let lineEnd = nsText.range(of: "\n", range: NSRange(location: location, length: nsText.length - location))
            let end = lineEnd.location == NSNotFound ? nsText.length : lineEnd.location
            textView.showFindIndicator(for: NSRange(location: location, length: end - location))
        }

        func currentLineInfo() -> (current: Int, total: Int) {
            guard let textView, let storage = textView.textStorage else { return (1, 1) }
            let nsText = storage.mutableString
            let location = min(textView.selectedRange().location, nsText.length)
            func newlines(in range: NSRange) -> Int {
                var count = 0
                var cursor = range.location
                let end = NSMaxRange(range)
                while cursor < end {
                    let next = nsText.range(of: "\n", range: NSRange(location: cursor, length: end - cursor))
                    if next.location == NSNotFound { break }
                    count += 1
                    cursor = next.location + 1
                }
                return count
            }
            let lineNumber = newlines(in: NSRange(location: 0, length: location)) + 1
            let totalLines = lineNumber + newlines(in: NSRange(location: location, length: nsText.length - location))
            return (lineNumber, totalLines)
        }

        func cancelPendingBindingUpdate() {
            pendingBindingUpdates = 0
            pendingBindingUpdateToken = nil
        }

        /// Documents above this size get their full highlight deferred to
        /// the next runloop tick so the window (or the new content) appears
        /// immediately with plain styling instead of blocking behind the
        /// whole-document regex sweep.
        private static let deferredHighlightThreshold = 200_000
        private var deferredInitialHighlight: DispatchWorkItem?

        /// Run a full highlight pass — synchronously for ordinary documents,
        /// deferred one tick for large ones. Repeat calls coalesce.
        func runFullHighlight(on textView: NSTextView, caller: String) {
            guard let storage = textView.textStorage else { return }
            deferredInitialHighlight?.cancel()
            deferredInitialHighlight = nil
            guard storage.length > Self.deferredHighlightThreshold else {
                isHighlightingInProgress = true
                highlighter?.highlightAll(storage, caller: caller)
                isHighlightingInProgress = false
                return
            }
            let work = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let textView, let storage = textView.textStorage else { return }
                self.deferredInitialHighlight = nil
                self.isHighlightingInProgress = true
                self.highlighter?.highlightAll(storage, caller: "\(caller)-deferred")
                self.isHighlightingInProgress = false
                self.invalidateVisibleRegion(of: textView)
            }
            deferredInitialHighlight = work
            DispatchQueue.main.async(execute: work)
        }

        func observeFindState(_ state: FindState) {
            findCancellables.removeAll()

            state.$query
                .removeDuplicates()
                // Find-as-you-type runs a full-document scan plus a repaint
                // per query change; the debounce coalesces a burst of
                // keystrokes into one search without a perceptible delay.
                .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
                .sink { [weak self] newQuery in
                    guard let self,
                          let findState = self.findState,
                          findState.isVisible,
                          findState.activeMode == .edit else { return }
                    // `@Published` fires in willSet — `findState.query` still
                    // reads the OLD value here. Pass `newQuery` explicitly so
                    // performFind doesn't run a keystroke behind.
                    self.performFind(query: newQuery)
                }
                .store(in: &findCancellables)

            state.$isVisible
                .removeDuplicates()
                .sink { [weak self] visible in
                    guard let self else { return }
                    if visible {
                        guard self.findState?.activeMode == .edit else { return }
                        self.performFind()
                    } else {
                        self.clearFindHighlights()
                    }
                }
                .store(in: &findCancellables)

            // Re-run find whenever an option toggle changes. `@Published`
            // emits in `willSet`, so the property hasn't been updated yet on
            // this dispatch — bounce to the next runloop tick so `performFind`
            // reads the new value.
            Publishers.CombineLatest(state.$caseSensitive, state.$useRegex)
                .dropFirst()
                .sink { [weak self] _, _ in
                    DispatchQueue.main.async {
                        guard let self,
                              let findState = self.findState,
                              findState.isVisible,
                              findState.activeMode == .edit else { return }
                        self.performFind()
                    }
                }
                .store(in: &findCancellables)
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            lastEditedRange = affectedCharRange
            lastReplacementLength = replacementString?.utf16.count ?? 0
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }

            // Skip if we're the ones setting text programmatically (from updateNSView)
            if isUpdating {
                DiagnosticLog.log("textDidChange skipped (isUpdating)")
                return
            }

            // Block updateNSView from replacing text while binding update is pending.
            // Without this, SwiftUI can call updateNSView (e.g., from a layout pass
            // triggered by the text view growing) BEFORE the async binding update fires,
            // see a mismatch between the old binding and the new text, and overwrite
            // the text view with the stale binding value — causing the cursor to jump.
            pendingBindingUpdates = 1

            // Save scroll position before highlighting
            let scrollView = textView.enclosingScrollView
            let savedOrigin = scrollView?.contentView.bounds.origin

            // Highlight only the affected range for performance on long documents
            isHighlightingInProgress = true
            if let editedRange = lastEditedRange {
                highlighter?.highlightAround(textView.textStorage!, editedRange: editedRange, replacementLength: lastReplacementLength, caller: "textDidChange")
                lastEditedRange = nil
            } else {
                highlighter?.highlightAll(textView.textStorage!, caller: "textDidChange-fallback")
            }
            isHighlightingInProgress = false

            // If a block delimiter was edited, defer the full re-highlight so it
            // doesn't block typing. The paragraph was already highlighted above.
            if highlighter?.needsFullHighlight == true {
                highlighter?.needsFullHighlight = false
                pendingFullHighlightWork?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    guard let self, let textView = self.textView else { return }
                    let sv = textView.enclosingScrollView
                    let origin = sv?.contentView.bounds.origin
                    self.isHighlightingInProgress = true
                    self.highlighter?.highlightAll(textView.textStorage!, caller: "deferred-blockDelim")
                    self.isHighlightingInProgress = false
                    if let sv, let origin {
                        sv.contentView.scroll(to: origin)
                        sv.reflectScrolledClipView(sv.contentView)
                    }
                    self.invalidateVisibleRegion(of: textView)
                }
                pendingFullHighlightWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
            }

            // Restore scroll position that highlighting may have disturbed
            if let scrollView, let savedOrigin {
                scrollView.contentView.scroll(to: savedOrigin)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }

            // Attribute-only highlighting doesn't invalidate display, so mark
            // the viewport dirty after restoring scroll. Limit invalidation to
            // the visible rect so large documents don't repaint end-to-end.
            invalidateVisibleRegion(of: textView)

            // Clear on edit; user retypes the query to refresh (#264).
            if let findState, findState.isVisible, !matchRanges.isEmpty {
                clearFindHighlights()
                if findState.activeMode == .edit {
                    DispatchQueue.main.async { [weak findState] in
                        guard let findState, findState.activeMode == .edit else { return }
                        findState.matchCount = 0
                        findState.currentIndex = 0
                        findState.resultsAreStale = true
                    }
                }
            }

            // Update SwiftUI's document binding immediately so DocumentGroup
            // saves the latest keystroke even when Cmd+S follows typing.
            let token = UUID()
            pendingBindingUpdateToken = token
            commitTextViewContents(textView)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.pendingBindingUpdateToken == token else { return }
                self.pendingBindingUpdateToken = nil
                self.pendingBindingUpdates = 0
            }
        }

        private func commitTextViewContents(_ textView: NSTextView) {
            let snapshot = textView.string
            lastCommittedText = snapshot
            parent.text = snapshot
        }

        private var scrollSuppressCount = 0

        @objc func scrollViewDidScroll(_ notification: Notification) {
            // Suppress during highlighting to avoid scheduling unnecessary async blocks
            guard !isHighlightingInProgress else {
                scrollSuppressCount += 1
                if scrollSuppressCount == 1 || scrollSuppressCount % 100 == 0 {
                    DiagnosticLog.log("scrollViewDidScroll suppressed ×\(scrollSuppressCount)")
                }
                return
            }

            guard let clipView = notification.object as? NSClipView else { return }

            // Defer layout manager queries to the next run loop iteration.
            // boundsDidChangeNotification fires synchronously during layout passes;
            // querying the layout manager in that same call stack deadlocks the main thread.
            DispatchQueue.main.async { [weak self] in
                self?.computeScrollFraction(clipView)
            }
        }

        private func computeScrollFraction(_ clipView: NSClipView) {
            guard let scrollView = clipView.enclosingScrollView else { return }
            let now = CACurrentMediaTime()
            guard now - lastScrollTime >= 0.016 else { return }
            lastScrollTime = now

            let docHeight = scrollView.documentView?.frame.height ?? 1
            let viewportHeight = clipView.bounds.height
            let maxScroll = max(1, docHeight - viewportHeight)
            let fraction = min(max(clipView.bounds.origin.y / maxScroll, 0), 1)
            ScrollBridge.setFraction(fraction, for: parent.positionSyncID)

        }

        private func invalidateVisibleRegion(of textView: NSTextView) {
            let visibleRect = textView.enclosingScrollView?.contentView.documentVisibleRect ?? textView.visibleRect
            textView.setNeedsDisplay(visibleRect, avoidAdditionalLayout: true)
        }

        // MARK: - Find

        func performFind(query overrideQuery: String? = nil) {
            guard let textView else { return }
            let didRecompute = recomputeMatches(query: overrideQuery)
            guard didRecompute else { return }
            applyFindHighlights()
            if let first = matchRanges.first {
                textView.scrollRangeToVisible(first)
            }
        }

        /// Recomputes matches against the current text view and updates state,
        /// but does NOT paint highlights or scroll. Returns false if the query
        /// was empty / errored (in which case state was already reset).
        @discardableResult
        private func recomputeMatches(query overrideQuery: String? = nil) -> Bool {
            guard let textView, let findState else { return false }
            let query = overrideQuery ?? findState.query
            clearFindHighlights()

            guard !query.isEmpty else {
                matchRanges = []
                lastMatches = []
                currentMatchIdx = 0
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          let findState = self.findState,
                          findState.activeMode == .edit else { return }
                    findState.matchCount = 0
                    findState.currentIndex = 0
                    findState.resultsAreStale = false
                    findState.regexError = nil
                    findState.lastReplaceCount = nil
                }
                return false
            }

            let options = TextMatchOptions(
                caseSensitive: findState.caseSensitive,
                useRegex: findState.useRegex
            )

            let matches: [TextMatch]
            do {
                matches = try TextMatcher.matches(of: query, in: textView.string, options: options)
            } catch let TextMatcherError.invalidRegex(message) {
                matchRanges = []
                lastMatches = []
                currentMatchIdx = 0
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          let findState = self.findState,
                          findState.activeMode == .edit else { return }
                    findState.matchCount = 0
                    findState.currentIndex = 0
                    findState.resultsAreStale = false
                    findState.regexError = message
                    findState.lastReplaceCount = nil
                }
                return false
            } catch {
                matches = []
            }

            matchRanges = matches.map(\.range)
            lastMatches = matches
            currentMatchIdx = 0

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let findState = self.findState,
                      findState.activeMode == .edit else { return }
                findState.matchCount = matches.count
                findState.currentIndex = matches.isEmpty ? 0 : 1
                findState.resultsAreStale = false
                findState.regexError = nil
                findState.lastReplaceCount = nil
            }
            return true
        }

        func navigateToNextMatch() {
            // After clear-on-edit, matchRanges is empty but the user's query is
            // still in the find bar — treat ⌘G / Find Next as a re-run trigger.
            if matchRanges.isEmpty, let findState, !findState.query.isEmpty {
                performFind()
                return
            }
            guard !matchRanges.isEmpty else { return }
            let previous = currentMatchIdx
            currentMatchIdx = (currentMatchIdx + 1) % matchRanges.count
            moveCurrentHighlight(from: previous)
            textView?.scrollRangeToVisible(matchRanges[currentMatchIdx])
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let findState = self.findState,
                      findState.activeMode == .edit else { return }
                findState.currentIndex = self.currentMatchIdx + 1
            }
        }

        func navigateToPreviousMatch() {
            if matchRanges.isEmpty, let findState, !findState.query.isEmpty {
                performFind()
                return
            }
            guard !matchRanges.isEmpty else { return }
            let previous = currentMatchIdx
            currentMatchIdx = (currentMatchIdx - 1 + matchRanges.count) % matchRanges.count
            moveCurrentHighlight(from: previous)
            textView?.scrollRangeToVisible(matchRanges[currentMatchIdx])
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let findState = self.findState,
                      findState.activeMode == .edit else { return }
                findState.currentIndex = self.currentMatchIdx + 1
            }
        }

        // Find highlights live on the layout manager via temporary attributes,
        // not on text storage. This is Apple's recommended pattern for
        // transient UI highlighting and means find painting never overwrites
        // `==highlight==` markdown backgrounds (which DO live on storage).

        /// Painting every match of a short query in a large document (tens of
        /// thousands of temporary attributes) takes visible time. Paint a
        /// window of matches centered on the current one instead; navigation
        /// repaints only when it leaves the window. The match COUNT shown in
        /// the find bar always reflects every match.
        private static let maxPaintedMatches = 2000
        private var paintedMatchWindow: Range<Int> = 0..<0

        private static func paintWindow(around index: Int, count: Int) -> Range<Int> {
            guard count > maxPaintedMatches else { return 0..<count }
            let half = maxPaintedMatches / 2
            let start = max(0, min(index - half, count - maxPaintedMatches))
            return start..<(start + maxPaintedMatches)
        }

        private func applyFindHighlights() {
            guard let textView, let layoutManager = textView.layoutManager else { return }
            let storage = textView.textStorage!
            let fullRange = NSRange(location: 0, length: storage.length)
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
            let window = Self.paintWindow(around: currentMatchIdx, count: matchRanges.count)
            paintedMatchWindow = window
            for i in window {
                let range = matchRanges[i]
                guard range.upperBound <= storage.length else { continue }
                let color = (i == currentMatchIdx) ? Theme.findCurrentHighlightColor : Theme.findHighlightColor
                layoutManager.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: range)
            }
        }

        /// Navigation fast path: recolor just the two affected matches
        /// instead of clearing and repainting the whole set. Falls back to a
        /// full repaint when the new current match is outside the painted
        /// window (recentering it there).
        private func moveCurrentHighlight(from previous: Int) {
            guard let textView, let layoutManager = textView.layoutManager,
                  previous != currentMatchIdx,
                  paintedMatchWindow.contains(currentMatchIdx),
                  matchRanges.indices.contains(currentMatchIdx) else {
                applyFindHighlights()
                return
            }
            let storage = textView.textStorage!
            if paintedMatchWindow.contains(previous),
               matchRanges.indices.contains(previous),
               matchRanges[previous].upperBound <= storage.length {
                layoutManager.addTemporaryAttribute(
                    .backgroundColor, value: Theme.findHighlightColor,
                    forCharacterRange: matchRanges[previous]
                )
            }
            if matchRanges[currentMatchIdx].upperBound <= storage.length {
                layoutManager.addTemporaryAttribute(
                    .backgroundColor, value: Theme.findCurrentHighlightColor,
                    forCharacterRange: matchRanges[currentMatchIdx]
                )
            }
        }

        func clearFindHighlights() {
            guard let textView, let layoutManager = textView.layoutManager else { return }
            let storage = textView.textStorage!
            let fullRange = NSRange(location: 0, length: storage.length)
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
            matchRanges = []
            lastMatches = []
            currentMatchIdx = 0
            paintedMatchWindow = 0..<0
        }

        // MARK: - Replace

        func performReplaceCurrent() {
            guard let textView, let findState,
                  !lastMatches.isEmpty,
                  currentMatchIdx < lastMatches.count else { return }
            let match = lastMatches[currentMatchIdx]
            let storage = textView.textStorage!
            guard match.range.upperBound <= storage.length else { return }
            let replacement = ReplaceEngine.substitution(for: match,
                                                         in: textView.string,
                                                         template: findState.replacementText,
                                                         isRegex: findState.useRegex)
            guard textView.shouldChangeText(in: match.range, replacementString: replacement) else { return }
            let resumeLocation = match.range.location + (replacement as NSString).length
            textView.replaceCharacters(in: match.range, with: replacement)
            textView.didChangeText()
            findState.lastReplaceCount = nil
            // Silent rescan — advanceToMatchAtOrAfter handles the single
            // applyFindHighlights + scroll, so we don't double-paint.
            recomputeMatches()
            advanceToMatchAtOrAfter(location: resumeLocation)
        }

        /// After a single-match replace, jump to the first remaining match at or
        /// after `location`. Skips any new match the replacement string may have
        /// introduced inside its own range, so consecutive Replace presses walk
        /// forward instead of cycling on the same spot.
        private func advanceToMatchAtOrAfter(location: Int) {
            guard !lastMatches.isEmpty else {
                DispatchQueue.main.async { [weak self] in
                    guard let self, let findState = self.findState, findState.activeMode == .edit else { return }
                    findState.currentIndex = 0
                }
                return
            }
            let nextIdx = lastMatches.firstIndex(where: { $0.range.location >= location }) ?? 0
            currentMatchIdx = nextIdx
            applyFindHighlights()
            textView?.scrollRangeToVisible(matchRanges[currentMatchIdx])
            let publishedIdx = currentMatchIdx + 1
            DispatchQueue.main.async { [weak self] in
                guard let self, let findState = self.findState, findState.activeMode == .edit else { return }
                findState.currentIndex = publishedIdx
            }
        }

        func performReplaceAll() {
            guard let textView, let findState, !lastMatches.isEmpty else { return }
            let oldText = textView.string
            let nsOldText = oldText as NSString
            let newText = ReplaceEngine.applyAll(matches: lastMatches,
                                                 in: oldText,
                                                 template: findState.replacementText,
                                                 isRegex: findState.useRegex)
            let fullRange = NSRange(location: 0, length: nsOldText.length)
            guard textView.shouldChangeText(in: fullRange, replacementString: newText) else { return }
            let replaceCount = lastMatches.count
            textView.replaceCharacters(in: fullRange, with: newText)
            textView.didChangeText()
            DispatchQueue.main.async { [weak findState] in
                findState?.lastReplaceCount = replaceCount
            }
            // Clear the "Replaced N occurrences" label after a beat so it
            // doesn't linger across an unrelated session. If a later action
            // already changed `lastReplaceCount`, leave that one alone.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak findState] in
                if findState?.lastReplaceCount == replaceCount {
                    findState?.lastReplaceCount = nil
                }
            }
        }
    }
}
