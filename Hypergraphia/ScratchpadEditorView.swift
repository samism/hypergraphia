import SwiftUI
import AppKit
import HypergraphiaCore

final class ScratchpadTextView: PersistentTextCheckingTextView {
    var onSave: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        if event.charactersIgnoringModifiers == "s" {
            onSave?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

struct ScratchpadEditorView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 16
    var onSave: (() -> Void)?
    var onTextChange: ((String) -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        let textView = ScratchpadTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindPanel = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        TextCheckingPreferences.apply(to: textView)

        textView.font = Theme.editorFont
        textView.textColor = Theme.textColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false

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

        textView.textContainerInset = NSSize(width: 20, height: 8)
        textView.textContainer?.lineFragmentPadding = 0

        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.layoutManager?.allowsNonContiguousLayout = true

        textView.insertionPointColor = Theme.textColor

        let highlighter = MarkdownSyntaxHighlighter()
        context.coordinator.highlighter = highlighter
        textView.string = text
        context.coordinator.lastCommittedText = text
        textView.delegate = context.coordinator

        let coordinator = context.coordinator
        textView.onSave = { [weak coordinator] in
            coordinator?.onSave?()
        }
        coordinator.onSave = onSave

        scrollView.documentView = textView
        coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        context.coordinator.parent = self
        context.coordinator.onSave = onSave

        textView.insertionPointColor = Theme.textColor

        let currentScheme = colorScheme
        let currentFontSize = fontSize
        let appearanceChanged = context.coordinator.lastColorScheme != currentScheme || context.coordinator.lastFontSize != currentFontSize
        if appearanceChanged {
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

            context.coordinator.isHighlighting = true
            context.coordinator.highlighter?.highlightAll(textView.textStorage!, caller: "scratchpad-appearance")
            context.coordinator.isHighlighting = false
        }

        // Same guards as the main editor: while a binding commit is in
        // flight the text view is authoritative (without this, a SwiftUI
        // pass triggered between textDidChange and the binding settling —
        // e.g. by the store's @Observable mutation in onTextChange — would
        // overwrite the view with the stale binding and eat the keystroke).
        // hasMarkedText protects in-flight IME composition, and the
        // length-first comparison keeps the no-change path O(1).
        if !context.coordinator.isUpdating
            && context.coordinator.pendingBindingUpdates == 0
            && !textView.hasMarkedText() {
            let storageLength = textView.textStorage?.length ?? 0
            let textMismatch: Bool
            if text == context.coordinator.lastCommittedText && text.utf16.count == storageLength {
                textMismatch = false
            } else {
                textMismatch = text.utf16.count != storageLength || textView.string != text
            }
            if textMismatch {
                context.coordinator.isUpdating = true
                let selectedRanges = textView.selectedRanges
                textView.string = text
                textView.selectedRanges = selectedRanges
                context.coordinator.lastCommittedText = text
                context.coordinator.isHighlighting = true
                context.coordinator.highlighter?.highlightAll(textView.textStorage!, caller: "scratchpad-externalText")
                context.coordinator.isHighlighting = false
                context.coordinator.isUpdating = false
            }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScratchpadEditorView
        var isUpdating = false
        var isHighlighting = false
        var highlighter: MarkdownSyntaxHighlighter?
        weak var textView: NSTextView?
        var lastColorScheme: ColorScheme?
        var lastFontSize: CGFloat?
        var onSave: (() -> Void)?
        var lastEditedRange: NSRange?
        var lastReplacementLength: Int = 0
        /// See EditorView.Coordinator: blocks updateNSView from replacing
        /// the text view while the binding write from textDidChange hasn't
        /// settled through SwiftUI yet.
        var pendingBindingUpdates = 0
        var pendingBindingUpdateToken: UUID?
        var lastCommittedText: String = ""

        init(_ parent: ScratchpadEditorView) {
            self.parent = parent
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            lastEditedRange = affectedCharRange
            lastReplacementLength = replacementString?.utf16.count ?? 0
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if isUpdating { return }

            // Text view is authoritative until the binding write settles.
            pendingBindingUpdates = 1

            isHighlighting = true
            if let editedRange = lastEditedRange {
                highlighter?.highlightAround(textView.textStorage!, editedRange: editedRange, replacementLength: lastReplacementLength, caller: "scratchpad-textDidChange")
                lastEditedRange = nil
            } else {
                highlighter?.highlightAll(textView.textStorage!, caller: "scratchpad-textDidChange-fallback")
            }
            isHighlighting = false

            // Commit synchronously (matching the main editor) so nothing can
            // observe a window where the view and binding disagree, then
            // release the guard on the next runloop tick once SwiftUI has
            // caught up.
            let newText = textView.string
            lastCommittedText = newText
            parent.onTextChange?(newText)
            parent.text = newText

            let token = UUID()
            pendingBindingUpdateToken = token
            DispatchQueue.main.async { [weak self] in
                guard let self, self.pendingBindingUpdateToken == token else { return }
                self.pendingBindingUpdateToken = nil
                self.pendingBindingUpdates = 0
            }
        }
    }
}
