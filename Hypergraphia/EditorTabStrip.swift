import SwiftUI
import AppKit
import Combine
import HypergraphiaCore

/// Replaces the native window tab bar under the titlebar-less glass chrome.
/// The native bar spans the whole window — cutting across the floating
/// sidebar — so it stays hidden (`hideNativeTabBar`) and this strip renders
/// the same `NSWindowTabGroup` nested at the top of the editor column
/// instead. Tab grouping, switching, and closing all still go through the
/// native tab machinery.
@MainActor
final class EditorTabModel: ObservableObject {
    struct Tab: Identifiable, Equatable {
        let id: ObjectIdentifier
        let title: String
        let isSelected: Bool
        let window: NSWindow

        static func == (lhs: Tab, rhs: Tab) -> Bool {
            lhs.id == rhs.id && lhs.title == rhs.title && lhs.isSelected == rhs.isSelected
        }
    }

    @Published private(set) var tabs: [Tab] = []
    private(set) weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var titleCancellables: [AnyCancellable] = []

    /// Called from the window-resolving representable; may fire on every
    /// SwiftUI update, so everything in here must be idempotent and cheap.
    func adopt(_ window: NSWindow) {
        if self.window !== window {
            self.window = window
        }
        if observers.isEmpty {
            let names: [Notification.Name] = [
                NSWindow.didBecomeKeyNotification,
                NSWindow.didBecomeMainNotification,
                NSWindow.willCloseNotification
            ]
            for name in names {
                observers.append(NotificationCenter.default.addObserver(
                    forName: name, object: nil, queue: .main
                ) { [weak self] _ in
                    // willClose fires while the closing window is still in
                    // the tab group — recompute on the next runloop pass.
                    DispatchQueue.main.async {
                        self?.refresh()
                    }
                })
            }
        }
        refresh()
    }

    func refresh() {
        if #available(macOS 26.0, *) {
            hideNativeTabBar(in: window)
        }
        guard let window else {
            if !tabs.isEmpty {
                tabs = []
            }
            return
        }
        // The strip is always visible: a window outside any tab group (or
        // alone in one) still shows itself as a single tab.
        let group = window.tabGroup
        let windows = (group?.windows.count ?? 0) > 1 ? (group?.windows ?? []) : [window]
        let newTabs = windows.map { tab in
            Tab(
                id: ObjectIdentifier(tab),
                title: tab.title.isEmpty ? "Untitled" : tab.title,
                isSelected: (group?.selectedWindow ?? window) === tab,
                window: tab
            )
        }
        // Only publish real changes: adopt()/refresh() run inside SwiftUI
        // update passes, and an unconditional @Published write would spin an
        // endless update cycle.
        guard newTabs != tabs else { return }
        tabs = newTabs
        titleCancellables = windows.map { tab in
            tab.publisher(for: \.title).dropFirst().sink { [weak self] _ in
                self?.refresh()
            }
        }
    }

    func select(_ tab: Tab) {
        window?.tabGroup?.selectedWindow = tab.window
        tab.window.makeKeyAndOrderFront(nil)
        refresh()
    }

    func close(_ tab: Tab) {
        // The last tab doesn't take the window with it: a fresh untitled
        // tab replaces it in the same frame.
        if tabs.count == 1, tab.window === window {
            replaceOnlyTabWithUntitled(in: tab.window)
        } else {
            tab.window.performClose(nil)
        }
    }
}

struct EditorTabStrip: View {
    @ObservedObject var model: EditorTabModel
    /// Extra leading space so tabs clear the floating traffic lights and
    /// sidebar toggle when the sidebar is hidden and the strip starts at
    /// the window's left edge.
    var leadingInset: CGFloat = 0
    let onNewTab: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(model.tabs) { tab in
                TabItem(tab: tab) {
                    model.select(tab)
                } close: {
                    model.close(tab)
                }
            }

            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 22)
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help("New file in tab")
            .accessibilityLabel("New file in tab")
        }
        .padding(.leading, 8 + leadingInset)
        .padding(.trailing, 8)
        .padding(.vertical, 5)
        // The strip sits in the old titlebar band, so its empty areas act
        // as the window-drag handle.
        .background {
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
        }
    }
}

private struct TabItem: View {
    let tab: EditorTabModel.Tab
    let select: () -> Void
    let close: () -> Void
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Text(tab.title)
                .font(.system(size: 12, weight: tab.isSelected ? .medium : .regular))
                .foregroundStyle(tab.isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 24)

            HStack {
                if isHovered {
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 16)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Theme.hoverColor(inDark: colorScheme == .dark))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Close tab")
                    .accessibilityLabel("Close \(tab.title)")
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 5)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(tab.isSelected
                    ? Theme.hoverColor(inDark: colorScheme == .dark)
                    : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onTapGesture(perform: select)
        .pointerStyle(.link)
        .onHover { hovering in
            withAnimation(Theme.Motion.hover) {
                isHovered = hovering
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tab.title) tab")
        .accessibilityAddTraits(tab.isSelected ? .isSelected : [])
    }
}
