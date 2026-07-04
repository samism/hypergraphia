import SwiftUI
import AppKit
import HypergraphiaCore

/// Floating word/character count shown over the document content. Mode
/// switching lives in the View menu; the sidebar toggle sits in the top
/// chrome.
struct BottomToolbar: View {
    @ObservedObject var statusBarState: StatusBarState

    /// Reserved height for the bottom controls. `ContentView` passes this to
    /// `EditorView.extraBottomInset` and the preview CSS floor so content
    /// scrolls clear of the overlay.
    static let pillHeight: CGFloat = 40

    var body: some View {
        if #available(macOS 26.0, *) {
            glassBody
        } else {
            legacyBody
        }
    }

    @available(macOS 26.0, *)
    private var glassBody: some View {
        GlassEffectContainer(spacing: 0) {
            countText
                .padding(.horizontal, 14)
                .frame(height: 28)
                .glassEffect(.regular, in: .capsule)
                .accessibilityLabel(countAccessibilityLabel)
                .accessibilityAddTraits(.isStaticText)
                .frame(maxWidth: .infinity)
                .frame(height: Self.pillHeight)
        }
    }

    private var legacyBody: some View {
        countText
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(NSColor.unemphasizedSelectedContentBackgroundColor))
            )
            .accessibilityLabel(countAccessibilityLabel)
            .accessibilityAddTraits(.isStaticText)
            .frame(maxWidth: .infinity)
            .frame(height: Self.pillHeight)
    }

    private var countAccessibilityLabel: String {
        "\(statusBarState.counts.totalWords) words, \(statusBarState.counts.totalChars) characters"
    }

    private var countText: some View {
        let counts = statusBarState.counts
        let words = counts.hasSelection ? counts.selectionWords : counts.totalWords
        let chars = counts.hasSelection ? counts.selectionChars : counts.totalChars
        return Text("\(words.formatted()) words \u{00B7} \(chars.formatted()) characters")
            .font(.system(size: 11))
            .tracking(0.3)
            .foregroundStyle(.tertiary)
            .monospacedDigit()
            .lineLimit(1)
    }
}

// MARK: - Mouse tracker (hover detection without blocking clicks)

/// NSView with an NSTrackingArea that fires `onHover` callbacks but returns
/// nil from `hitTest` so clicks pass through to whatever is underneath.
struct BottomHoverTracker: NSViewRepresentable {
    let onHover: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = TrackingView()
        view.onHover = onHover
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? TrackingView)?.onHover = onHover
    }

    private final class TrackingView: NSView {
        var onHover: ((Bool) -> Void)?
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            onHover?(true)
        }

        override func mouseExited(with event: NSEvent) {
            onHover?(false)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}

// MARK: - Right-side icon button style

private struct BottomToolbarIconStyle: ButtonStyle {
    let isActive: Bool
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 28, height: 28)
            .foregroundStyle(isActive ? Theme.accentForegroundColorSwiftUI : Color.secondary)
            .background {
                let opacity: Double = {
                    if configuration.isPressed { return 0.16 }
                    if isActive { return 0.14 }
                    if isHovering { return 0.08 }
                    return 0
                }()
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? Theme.accentColorSwiftUI.opacity(opacity) : Color.primary.opacity(opacity))
            }
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
    }
}
