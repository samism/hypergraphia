import AppKit
import HypergraphiaCore

/// Notification channels paired between `EditorView` and `PreviewView`
/// for cross-pane jumps (click a heading / find-result in one pane and
/// scroll the other to the same line).
extension Notification.Name {
    static let scrollPreviewToLine = Notification.Name("HypergraphiaScrollPreviewToLine")
    static let flushEditorBuffer = Notification.Name("HypergraphiaFlushEditorBuffer")
    static let highlightTextInEditor = Notification.Name("HypergraphiaHighlightTextInEditor")
    static let highlightTextInPreview = Notification.Name("HypergraphiaHighlightTextInPreview")
}

/// Holds a weak reference to the currently focused `HypergraphiaTextView`.
/// Menu commands (formatting, etc.) target whichever editor most
/// recently became key. Without `WorkspaceManager` to track multi-doc
/// activation, this is the simplest stand-in that works under
/// `DocumentGroup`'s one-window-per-document model.
@MainActor
final class ActiveEditor {
    static let shared = ActiveEditor()
    weak var textView: HypergraphiaTextView?
    private init() {}
}
