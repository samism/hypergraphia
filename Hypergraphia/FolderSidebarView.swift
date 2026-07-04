import SwiftUI
import AppKit
import HypergraphiaCore

/// Which content the left sidebar shows. Backed by `@AppStorage` so every
/// window (tab) reflects the same mode — switching tabs must not appear to
/// flip the sidebar. String-raw for AppStorage compatibility.
enum SidebarMode: String {
    case outline
    case folder
}

/// Left sidebar container: FILES / OUTLINE mode toggle in the header, then
/// either the document outline or the folder file list.
struct SidebarView: View {
    @Binding var mode: SidebarMode
    @ObservedObject var outlineState: OutlineState
    @ObservedObject var folderState: FolderState
    var isEditorVisible: Bool
    let fileURL: URL?
    /// Height of the panel's top strip under the titlebar-less glass chrome.
    /// The traffic lights and the window-level sidebar/mode buttons overlay
    /// this area; the file list / outline starts right below it.
    var chromeTopPadding: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Traffic-light strip. Empty in the view tree — the lights and
            // the overlay buttons float above it — but it doubles as a
            // window-drag handle now that the titlebar is gone.
            Color.clear
                .frame(height: chromeTopPadding)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())

            Rectangle()
                .fill(Theme.separatorColor(inDark: colorScheme == .dark))
                .frame(height: 1)
                .padding(.horizontal, 12)

            switch mode {
            case .outline:
                OutlineView(outlineState: outlineState, isEditorVisible: isEditorVisible)
            case .folder:
                FolderListView(folderState: folderState, currentFileURL: fileURL)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(panelBackground)
    }

    /// On macOS 26+ the container supplies a Liquid Glass surface, so the
    /// panel itself must stay transparent for the glass to show through.
    @ViewBuilder
    private var panelBackground: some View {
        if #available(macOS 26.0, *) {
            Color.clear
        } else {
            Theme.outlinePanelBackgroundSwiftUI
        }
    }
}

/// Folder-mode sidebar content: the folder the window is oriented to and the
/// markdown files inside it.
private struct FolderListView: View {
    @ObservedObject var folderState: FolderState
    let currentFileURL: URL?
    /// File currently being renamed inline; its row shows a text field.
    @State private var renamingFileURL: URL?

    var body: some View {
        if let folderURL = folderState.folderURL {
            VStack(alignment: .leading, spacing: 0) {
                folderRow(folderURL)
                if folderState.files.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Text("No markdown files")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(folderState.files) { file in
                                FileRow(
                                    file: file,
                                    isCurrent: file.url.standardizedFileURL == currentFileURL?.standardizedFileURL,
                                    isRenaming: renamingFileURL == file.url
                                ) {
                                    openMarkdownDocument(at: file.url, from: folderURL)
                                } onRename: {
                                    renamingFileURL = file.url
                                } onDelete: {
                                    delete(file)
                                } onRenameCommit: { newName in
                                    // Guarded: the focus-loss and click-away
                                    // paths can both fire for one dismissal.
                                    guard renamingFileURL == file.url else { return }
                                    renamingFileURL = nil
                                    performRename(file, to: newName)
                                } onRenameCancel: {
                                    renamingFileURL = nil
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 8)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Spacer()
            VStack(spacing: 10) {
                Text("No folder open")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                Button("Open Folder…") {
                    if let url = FolderPanel.choose() {
                        folderState.open(folder: url)
                    }
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity)
            Spacer()
        }
    }

    /// Minimal "this window is oriented to this folder" marker. Clicking it
    /// re-opens the chooser to switch folders.
    private func folderRow(_ folderURL: URL) -> some View {
        Button {
            if let url = FolderPanel.choose() {
                folderState.open(folder: url)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(folderURL.lastPathComponent)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help("Change folder")
        .accessibilityLabel("Folder \(folderURL.lastPathComponent). Change folder")
    }

    private func delete(_ file: FolderFile) {
        let document = openDocument(for: file.url)
        let nextWindow = isCurrent(file) ? windowToSelectAfterDeleting(document: document) : nil

        do {
            try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
            folderState.refresh()
            close(document, selecting: nextWindow)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func performRename(_ file: FolderFile, to requestedName: String) {
        let trimmed = requestedName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != file.displayName else { return }

        do {
            let newURL = try FolderState.renamedFileURL(for: file.url, displayName: trimmed)
            guard newURL.standardizedFileURL != file.url.standardizedFileURL else { return }
            guard !FileManager.default.fileExists(atPath: newURL.path) else {
                throw FolderStateError.fileAlreadyExists(newURL.lastPathComponent)
            }

            if let document = openDocument(for: file.url) {
                document.move(to: newURL) { error in
                    if let error {
                        NSAlert(error: error).runModal()
                        return
                    }
                    setDocumentTitle(document, for: newURL)
                    folderState.refresh()
                }
            } else {
                try FileManager.default.moveItem(at: file.url, to: newURL)
                folderState.refresh()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func openDocument(for url: URL) -> NSDocument? {
        let target = url.standardizedFileURL
        return NSDocumentController.shared.documents.first { document in
            document.fileURL?.standardizedFileURL == target
        }
    }

    private func isCurrent(_ file: FolderFile) -> Bool {
        file.url.standardizedFileURL == currentFileURL?.standardizedFileURL
    }

    private func windowToSelectAfterDeleting(document: NSDocument?) -> NSWindow? {
        guard let window = document?.windowControllers.compactMap(\.window).first else { return nil }
        let tabs = window.tabbedWindows ?? [window]
        guard let index = tabs.firstIndex(where: { $0 === window }) else { return nil }

        if index + 1 < tabs.count {
            return tabs[index + 1]
        }
        if index > 0 {
            return tabs[index - 1]
        }
        return nil
    }

    private func close(_ document: NSDocument?, selecting window: NSWindow?) {
        window?.makeKeyAndOrderFront(nil)
        document?.close()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct FileRow: View {
    let file: FolderFile
    let isCurrent: Bool
    let isRenaming: Bool
    let onTap: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let onRenameCommit: (String) -> Void
    let onRenameCancel: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var draftName: String = ""
    @FocusState private var renameFieldFocused: Bool

    var body: some View {
        if isRenaming {
            renameField
        } else {
            row
        }
    }

    private var row: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                Text(file.displayName)
                    .font(.system(size: 12, weight: isCurrent ? .medium : .regular))
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isCurrent
                    ? Theme.hoverColor(inDark: colorScheme == .dark)
                    : Color.clear)
                .padding(.horizontal, 4)
        )
        .contextMenu {
            Button("Rename") {
                onRename()
            }
            Divider()
            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    /// In-place editor replacing the row while renaming: Return commits,
    /// Escape cancels, clicking away commits (Finder-style). Clicks on
    /// non-focusable areas don't move focus off a text field, so a monitor
    /// sharing the field's frame catches those and commits explicitly.
    private var renameField: some View {
        TextField("", text: $draftName)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .focused($renameFieldFocused)
            .onSubmit {
                onRenameCommit(draftName)
            }
            .onExitCommand {
                onRenameCancel()
            }
            .onChange(of: renameFieldFocused) { _, focused in
                if !focused && isRenaming {
                    onRenameCommit(draftName)
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.hoverColor(inDark: colorScheme == .dark))
                    .padding(.horizontal, 4)
            )
            .background(
                ClickOutsideMonitor {
                    onRenameCommit(draftName)
                }
            )
            .onAppear {
                draftName = file.displayName
                DispatchQueue.main.async {
                    renameFieldFocused = true
                }
            }
            .accessibilityLabel("Rename \(file.displayName)")
    }
}

/// Invisible view matching its host's frame that watches for mouse-downs
/// landing outside it (in the same window) and reports them — used to end
/// inline rename when the user clicks anywhere else.
private struct ClickOutsideMonitor: NSViewRepresentable {
    let onClickOutside: () -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onClickOutside = onClickOutside
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.onClickOutside = onClickOutside
    }

    final class MonitorView: NSView {
        var onClickOutside: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(
                    matching: [.leftMouseDown, .rightMouseDown]
                ) { [weak self] event in
                    if let self, let window = self.window, event.window === window {
                        let point = self.convert(event.locationInWindow, from: nil)
                        if !self.bounds.contains(point) {
                            self.onClickOutside?()
                        }
                    }
                    return event
                }
            } else if window == nil, let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}

// MARK: - Folder chooser + open-with-folder-context helpers

enum FolderPanel {
    @MainActor
    static func choose() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Folder"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

@MainActor
func createMarkdownDocument(in folderState: FolderState, promptForFolder: Bool = false, tabbingInto sourceWindow: NSWindow? = nil) {
    if folderState.folderURL == nil {
        guard promptForFolder, let folder = FolderPanel.choose() else { return }
        folderState.open(folder: folder)
    }

    do {
        let url = try folderState.createUntitledFile()
        openMarkdownDocument(at: url, from: folderState.folderURL, tabbingInto: sourceWindow)
    } catch {
        NSAlert(error: error).runModal()
    }
}

func displayTitle(for url: URL?) -> String {
    guard let url else { return "Untitled" }
    return url.deletingPathExtension().lastPathComponent
}

@MainActor
func setDocumentTitle(_ document: NSDocument?, for url: URL?) {
    let title = displayTitle(for: url)
    document?.displayName = title
    document?.windowControllers.compactMap(\.window).forEach { window in
        window.title = title
        configureDocumentWindowChrome(window)
    }
}

@MainActor
func configureDocumentWindowChrome(_ window: NSWindow?) {
    guard let window else { return }

    if #available(macOS 26.0, *) {
        // Liquid-glass chrome: no title bar; the traffic lights sit inside
        // the floating sidebar, Finder-style. The window title is still set
        // (tabs, Mission Control, and the Window menu need it) — it's just
        // not drawn.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        TrafficLightMover.shared.manage(window)
        hideNativeTabBar(in: window)
    } else {
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.styleMask.remove(.fullSizeContentView)
    }
    configureNativeTabAddButton(in: window)

    Task { @MainActor [weak window] in
        configureNativeTabAddButton(in: window)
        if #available(macOS 26.0, *) {
            hideNativeTabBar(in: window)
        }
    }
}

/// The native tab bar spans the whole window and cuts across the floating
/// glass sidebar, so under the titlebar-less chrome it stays hidden;
/// `EditorTabStrip` renders the same tab group nested in the editor column.
///
/// `toggleTabBar` cannot do this: AppKit refuses to hide the bar while the
/// group has more than one tab (the same reason View ▸ Hide Tab Bar grays
/// out). So, in the spirit of the existing `plusTab` retargeting hack, the
/// bar's titlebar accessory view is hidden directly — the tab group itself
/// stays fully functional. Re-enforced from chrome configuration and
/// `EditorTabModel.refresh()` since AppKit re-adds the accessory when tabs
/// change.
@MainActor
func hideNativeTabBar(in window: NSWindow?) {
    guard let window else { return }
    hideTabBarChrome(in: window)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak window] in
        guard let window else { return }
        hideTabBarChrome(in: window)
    }
}

@MainActor
private func hideTabBarChrome(in window: NSWindow) {
    // Preferred: the accessory controller — hiding it reclaims the titlebar
    // space in layout.
    for accessory in window.titlebarAccessoryViewControllers
    where containsTabBar(accessory.view) {
        if !accessory.isHidden {
            accessory.isHidden = true
        }
    }
    // Fallback: hide any tab-bar view hosted directly in the theme frame.
    if let frameView = window.contentView?.superview {
        hideTabBarViews(in: frameView)
    }
}

@MainActor
private func containsTabBar(_ view: NSView) -> Bool {
    if String(describing: type(of: view)).contains("TabBar") {
        return true
    }
    return view.subviews.contains { containsTabBar($0) }
}

@MainActor
private func hideTabBarViews(in view: NSView) {
    for subview in view.subviews {
        if String(describing: type(of: subview)).contains("TabBar") {
            if !subview.isHidden {
                subview.isHidden = true
            }
        } else {
            hideTabBarViews(in: subview)
        }
    }
}

/// Nudges the standard window buttons down-right so they sit inside the
/// floating glass sidebar (the way Finder positions them) instead of hugging
/// the window corner. AppKit rebuilds the titlebar asynchronously after the
/// style-mask change and resets the button frames, so the offset is
/// re-applied on delayed ticks and on resize / key-state / fullscreen
/// notifications. Base origins are cached per window so repeated
/// applications don't accumulate.
@MainActor
final class TrafficLightMover {
    static let shared = TrafficLightMover()
    static let offset = CGPoint(x: 12, y: 10)

    private let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
    private var baseOrigins: [ObjectIdentifier: [NSWindow.ButtonType: CGPoint]] = [:]
    private var managed = Set<ObjectIdentifier>()

    func manage(_ window: NSWindow) {
        apply(to: window)
        for delay in [0.05, 0.3, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak window] in
                guard let window else { return }
                self?.apply(to: window)
            }
        }
        let key = ObjectIdentifier(window)
        guard !managed.contains(key) else { return }
        managed.insert(key)

        let names: [Notification.Name] = [
            NSWindow.didResizeNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didExitFullScreenNotification
        ]
        for name in names {
            NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main
            ) { [weak self, weak window] _ in
                guard let window else { return }
                MainActor.assumeIsolated {
                    self?.apply(to: window)
                }
            }
        }
    }

    private func apply(to window: NSWindow) {
        // No represented URL under the titlebar-less chrome: the document
        // proxy icon and the hover title-menu chevron would float orphaned
        // over the sidebar's top strip. NSDocument re-sets it on every title
        // sync, so this heals on the same cadence as the button offsets.
        if window.representedURL != nil {
            window.representedURL = nil
        }
        if let proxy = window.standardWindowButton(.documentIconButton), !proxy.isHidden {
            proxy.isHidden = true
        }
        let key = ObjectIdentifier(window)
        for type in buttonTypes {
            guard let button = window.standardWindowButton(type) else { continue }
            let base: CGPoint
            if let cached = baseOrigins[key]?[type] {
                base = cached
            } else {
                base = button.frame.origin
                baseOrigins[key, default: [:]][type] = base
            }
            let flipped = button.superview?.isFlipped ?? false
            let target = NSPoint(
                x: base.x + Self.offset.x,
                y: flipped ? base.y + Self.offset.y : base.y - Self.offset.y
            )
            if button.frame.origin != target {
                button.setFrameOrigin(target)
            }
        }
    }
}

@MainActor
private func configureNativeTabAddButton(in window: NSWindow?) {
    guard let tabGroup = window?.tabGroup else { return }
    let selector = NSSelectorFromString("plusTab")
    guard tabGroup.responds(to: selector),
          let view = tabGroup.perform(selector)?.takeUnretainedValue() as? NSView,
          let control = view as? NSControl ?? view.subviews.compactMap({ $0 as? NSControl }).first else { return }

    // ponytail: AppKit exposes the tab button view but not a public way to
    // retarget it. Replace this when Hypergraphia owns a custom tab bar.
    control.target = NativeTabAddButtonTarget.shared
    control.action = #selector(NativeTabAddButtonTarget.createFileFromTabBar(_:))
    control.isEnabled = true
    control.isHidden = false
}

/// Closing a document window's only tab must not take the window (or the
/// app) with it: a fresh untitled tab joins the same tab group first, then
/// the old tab closes — the window shell never moves, only the content
/// resets to the click-to-start-writing state. Quitting and closing the
/// window itself (red button) are untouched.
@MainActor
func replaceOnlyTabWithUntitled(in sourceWindow: NSWindow) {
    guard let document = try? NSDocumentController.shared.openUntitledDocumentAndDisplay(true) else { return }
    adoptReplacementTab(document: document, into: sourceWindow, attemptsLeft: 20)
}

/// SwiftUI attaches a `DocumentGroup` document's window controllers a beat
/// after `openUntitledDocumentAndDisplay` returns; poll briefly until the
/// window exists, then tab it in and close the tab it replaces.
@MainActor
private func adoptReplacementTab(document: NSDocument, into sourceWindow: NSWindow, attemptsLeft: Int) {
    guard let targetWindow = document.windowControllers.compactMap(\.window).first else {
        guard attemptsLeft > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            adoptReplacementTab(document: document, into: sourceWindow, attemptsLeft: attemptsLeft - 1)
        }
        return
    }
    sourceWindow.tabbingMode = .preferred
    targetWindow.tabbingMode = .preferred
    if sourceWindow.tabbedWindows?.contains(where: { $0 === targetWindow }) != true {
        sourceWindow.addTabbedWindow(targetWindow, ordered: .above)
    }
    configureDocumentWindowChrome(sourceWindow)
    configureDocumentWindowChrome(targetWindow)
    targetWindow.makeKeyAndOrderFront(nil)
    // The replacement is in the group, so this close only takes the tab —
    // an emptied auto-created file still gets trashed by its own
    // willClose handling.
    sourceWindow.performClose(nil)
}

/// Opens a markdown file as a document window. When it came from a folder
/// sidebar, stages that folder so the opened document's `ContentView` adopts
/// it (folder mode, same folder) on appear.
@MainActor
func openMarkdownDocument(at url: URL, from folder: URL?, tabbingInto sourceWindow: NSWindow? = nil) {
    let sourceWindow = sourceWindow ?? NSApp.keyWindow
    if let folder {
        FolderHandoff.stage(folder: folder, forOpening: url)
    }
    NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, error in
        if let error {
            NSAlert(error: error).runModal()
            return
        }
        setDocumentTitle(document, for: url)
        guard let sourceWindow,
              sourceWindow.isVisible,
              let targetWindow = document?.windowControllers.compactMap(\.window).first,
              targetWindow !== sourceWindow else { return }

        sourceWindow.tabbingMode = .preferred
        targetWindow.tabbingMode = .preferred
        if sourceWindow.tabbedWindows?.contains(where: { $0 === targetWindow }) != true {
            sourceWindow.addTabbedWindow(targetWindow, ordered: .above)
        }
        configureDocumentWindowChrome(sourceWindow)
        configureDocumentWindowChrome(targetWindow)
        targetWindow.makeKeyAndOrderFront(nil)
    }
}

/// Hands folder context from the window that initiated an open to the opened
/// document view. Keyed by standardized file URL, claimed once, and
/// time-limited: when the document was already open (no new ContentView
/// appears), the stale entry must not make that file adopt the folder at
/// some unrelated later open.
@MainActor
enum FolderHandoff {
    private static var pending: [URL: (folder: URL, staged: Date)] = [:]
    private static let maxAge: TimeInterval = 10

    static func stage(folder: URL, forOpening fileURL: URL) {
        pending = pending.filter { Date().timeIntervalSince($0.value.staged) < maxAge }
        pending[fileURL.standardizedFileURL] = (folder, Date())
    }

    static func claim(for fileURL: URL?) -> URL? {
        guard let key = fileURL?.standardizedFileURL,
              let entry = pending.removeValue(forKey: key),
              Date().timeIntervalSince(entry.staged) < maxAge else { return nil }
        return entry.folder
    }
}
