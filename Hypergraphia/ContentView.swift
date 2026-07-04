import SwiftUI
import AppKit
import HypergraphiaCore

/// Per-document scene root: hosts the editor / preview, find bar, jump-to-line
/// bar, outline panel, and the floating bottom toolbar (mode picker / counts /
/// copy / outline). One instance per `DocumentGroup` window.
struct ContentView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?

    @State private var viewMode: ViewMode
    /// Shared across all windows/tabs (and relaunches): tab switches must
    /// not appear to flip the sidebar between files and outline.
    @AppStorage("sidebarMode") private var sidebarMode: SidebarMode = .folder
    @StateObject private var outlineState = OutlineState()
    @StateObject private var folderState = FolderState()
    @StateObject private var findState = FindState()
    @StateObject private var jumpToLineState = JumpToLineState()
    @StateObject private var statusBarState = StatusBarState()
    @StateObject private var tabModel = EditorTabModel()

    @AppStorage("editorFontSize") private var fontSize: Double = 12
    @AppStorage("previewFontFamily") private var previewFontFamily: String = "sanFrancisco"
    @AppStorage("contentWidth") private var contentWidth: String = "off"
    @AppStorage("alwaysShowBottomToolbar") private var alwaysShowBottomToolbar: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHoveringBottom: Bool = false

    /// A live-mode block editor is open: the tab strip hides (hover the top
    /// band to peek at it). Debounced off so commit→reload→reopen chains
    /// don't flash the strip between two editors.
    @State private var isBlockEditing: Bool = false
    @State private var isHoveringTabBand: Bool = false
    /// Hovering the band while editing pins the strip visible for the rest
    /// of that editing session (a new editor or a scroll re-hides it).
    @State private var editHideCleared: Bool = false
    @State private var editingClearWork: DispatchWorkItem?
    /// A save-as binding an untitled window to an auto-created file is in
    /// flight; guards against double-creation while it completes.
    @State private var autoCreatePending: Bool = false
    /// A first-line auto-rename move is in flight; guards against firing a
    /// second move off the next text change before it completes.
    @State private var autoRenamePending: Bool = false
    /// Coalesces edit-mode keystrokes into one rename per pause.
    @State private var renameDebounceWork: DispatchWorkItem?
    /// The filename currently tracks the first content line, so edits to
    /// it keep renaming the file. Armed when a text change departs from a
    /// first line the name matched; re-judged after every move.
    @State private var fileNameSynced: Bool = false

    /// Stable per-window key for ScrollBridge / SelectionBridge. Re-keyed on
    /// document URL change so two windows on different files don't collide.
    @State private var positionSyncID: String = UUID().uuidString

    init(document: Binding<MarkdownDocument>, fileURL: URL?) {
        self._document = document
        self.fileURL = fileURL
        // Never land a blank document in Preview — there'd be nothing to see
        // and no obvious way to edit. (Live is fine: it shows a click-to-
        // start-writing affordance.)
        let raw = UserDefaults.standard.string(forKey: "defaultViewMode") ?? "live"
        let preferred = ViewMode(rawValue: raw) ?? .live
        let isBlank = document.wrappedValue.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self._viewMode = State(initialValue: (preferred == .preview && isBlank) ? .edit : preferred)
    }

    private var shouldShowBottomToolbar: Bool {
        alwaysShowBottomToolbar || isHoveringBottom
    }

    private var contentWidthEm: CGFloat? {
        switch contentWidth {
        case "narrow": return 50
        case "medium": return 65
        case "wide": return 80
        default: return nil
        }
    }

    var body: some View {
        GeometryReader { proxy in
            mainLayout(topInset: proxy.safeAreaInsets.top)
        }
        .frame(minWidth: 600, minHeight: 360)
        .background(WindowTitleSetter(fileURL: fileURL, newFile: { window in
            newFile(tabbingInto: window)
        }, onWindow: { window in
            tabModel.adopt(window)
        }))
        .focusedSceneValue(\.findState, findState)
        .focusedSceneValue(\.outlineState, outlineState)
        .focusedSceneValue(\.viewMode, $viewMode)
        .focusedSceneValue(\.exportPDFAction) { exportPDF() }
        .focusedSceneValue(\.printDocumentAction) { printDocument() }
        .focusedSceneValue(\.openFolderAction) { openFolder() }
        .focusedSceneValue(\.newFileAction) { newFile() }
        .onAppear {
            outlineState.parseHeadings(from: document.text)
            statusBarState.updateText(document.text)
            refreshFileNameSync()
            // Window opened from another window's folder sidebar: orient this
            // window to the same folder.
            if let folder = FolderHandoff.claim(for: fileURL) {
                folderState.open(folder: folder)
                sidebarMode = .folder
                outlineState.isVisible = true
            } else {
                orientSidebarToDocumentFolder()
            }
        }
        .onChange(of: document.text) { oldText, newText in
            outlineState.parseHeadings(from: newText)
            statusBarState.updateText(newText)
            // Untitled window gained content (edit-mode keystrokes land
            // here): give it a real file in the open folder right away.
            if !newText.isEmpty {
                autoCreateFileIfNeeded()
                // The name matched the first line as it was before this
                // change — keep it matching. (Never disarmed here: an
                // emptied-then-retyped first line stays synced.)
                if fileNameTracksFirstLine(in: oldText) {
                    fileNameSynced = true
                }
                scheduleFirstLineRename()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { note in
            // Leaving an emptied file behind deletes it, Apple Notes-style.
            guard let window = note.object as? NSWindow, window === tabModel.window else { return }
            autoDeleteIfEmpty(unbindDocument: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            guard let window = note.object as? NSWindow, window === tabModel.window else { return }
            autoDeleteIfEmpty(unbindDocument: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            // Sidebar visibility persists globally ("outlineVisible"), but
            // each tab is its own window whose OutlineState snapshotted the
            // default at init. Without reconciling on key changes, switching
            // tabs flips between stale snapshots and the sidebar appears to
            // toggle on its own.
            let stored = UserDefaults.standard.bool(forKey: "outlineVisible")
            if outlineState.isVisible != stored {
                outlineState.isVisible = stored
            }
        }
        .onChange(of: fileURL) { _, _ in
            // Re-key bridges when the document is saved/renamed so a new
            // file's scroll position doesn't inherit the old fraction.
            positionSyncID = UUID().uuidString
            orientSidebarToDocumentFolder()
            refreshFileNameSync()
        }
        .watchExternalChanges(fileURL: fileURL, text: $document.text) { url in
            // Sync SwiftUI's underlying NSDocument's fileModificationDate to
            // the new on-disk mtime — without this, the next autosave detects
            // a conflict and shows "could not be autosaved" dialog. We
            // deliberately do NOT try to suppress the title's "Edited"
            // decoration: SwiftUI tracks its own FileDocument-vs-disk diff
            // for that, and the indicator is a useful "doc changed under you"
            // signal anyway.
            let target = url.standardizedFileURL
            guard let doc = NSDocumentController.shared.documents.first(where: { $0.fileURL?.standardizedFileURL == target }) else { return }
            if let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date {
                doc.fileModificationDate = mtime
            }
        }
    }

    /// Window content. `topInset` is the height of the (transparent) titlebar
    /// region — the traffic-light strip, plus the native tab bar when tabs are
    /// showing. The sidebar extends up under it; the editor column stays
    /// below it.
    @ViewBuilder
    private func mainLayout(topInset rawTopInset: CGFloat) -> some View {
        // When our own tab strip is handling tabs, the hidden native tab bar
        // may still reserve titlebar height in the safe area — cap the inset
        // at the plain traffic-light strip so the content reclaims that space.
        let topInset = tabModel.tabs.isEmpty ? rawTopInset : min(rawTopInset, 28)
        HStack(spacing: 0) {
            if outlineState.isVisible {
                sidebar(topInset: topInset)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            VStack(spacing: 0) {
                if findState.isVisible || jumpToLineState.isVisible {
                    // Clear of the tab strip's overlay region at the top.
                    VStack(spacing: 0) {
                        if findState.isVisible {
                            FindBarView(findState: findState)
                            Divider()
                        }
                        if jumpToLineState.isVisible {
                            JumpToLineBar(state: jumpToLineState)
                            Divider()
                        }
                    }
                    .padding(.top, contentTopInset)
                }

                mainPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .bottom) {
                        bottomToolbarOverlay
                    }
            }
            // The traffic-light band only needs reserving when it actually
            // floats over the editor column: sidebar hidden and no tab strip.
            // With the sidebar open the lights sit over the panel, so the
            // editor content rises to the window top.
            .padding(.top, (tabsShowing || outlineState.isVisible) ? 0 : topInset)
            .overlay(alignment: .top) {
                if #available(macOS 26.0, *), tabsShowing {
                    // Hover zone summoning the hidden tab strip. Hit-test
                    // transparent, so it never steals clicks from the tabs
                    // (or from content underneath).
                    BottomHoverTracker { hovering in
                        withAnimation(tabStripAnimation) {
                            isHoveringTabBand = hovering
                            // Reaching for the strip un-latches the editing
                            // hide, so it stays put after the mouse moves on.
                            if hovering {
                                editHideCleared = true
                            }
                        }
                    }
                    .frame(height: 48)
                }
            }
            .overlay(alignment: .top) {
                if #available(macOS 26.0, *), tabsShowing, stripRevealed {
                    // The tab strip floats over the content (which carries a
                    // constant matching top inset), so peeking in and out
                    // never reflows the document. Tabs are free-floating
                    // glass capsules in the traffic-light band, Safari-
                    // style — no opaque band, so mid-scroll text passes
                    // beneath them; with the sidebar hidden the leading
                    // inset clears the floating lights and toggle.
                    EditorTabStrip(
                        model: tabModel,
                        leadingInset: outlineState.isVisible ? 0 : 122
                    )
                    .padding(.top, 7)
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        // Match the editor background so the gutters around the floating
        // glass sidebar read as one continuous surface, not window chrome.
        .background(Theme.backgroundColorSwiftUI)
        .ignoresSafeArea(.container, edges: .top)
        .overlay(alignment: .top) {
            if #available(macOS 26.0, *), topInset > 0, !tabsShowing, !outlineState.isVisible {
                // The titlebar is hidden; this strip keeps the top of the
                // window draggable when no tab strip occupies it and the
                // sidebar (whose top strip has its own drag handle) is
                // hidden. Content-blocking matters: when the editor rises to
                // the window top, this overlay must not sit over it. Overlay
                // content gets the container safe area re-applied, so it
                // must ignore it again to reach the true window top.
                Color.clear
                    .frame(height: topInset)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .gesture(WindowDragGesture())
                    .ignoresSafeArea(.container, edges: .top)
            }
        }
        .overlay(alignment: .topLeading) {
            if #available(macOS 26.0, *) {
                // Right-justified against the sidebar panel's trailing edge
                // (12pt inset) so it doesn't crowd the traffic lights; with
                // the sidebar hidden it returns beside the lights, clear of
                // the tab strip's leading inset.
                sidebarToggle
                    .padding(.leading, outlineState.isVisible ? 208 : 90)
                    .padding(.top, 11)
                    .ignoresSafeArea(.container, edges: .top)
            }
        }
        .overlay(alignment: .topTrailing) {
            if #available(macOS 26.0, *), tabsShowing {
                // Always visible and always in the same place — pinned at
                // the trailing edge whether tabs are showing, hidden for
                // editing, or absent entirely.
                newTabButton
                    .padding(.top, 12)
                    .padding(.trailing, 22)
                    .ignoresSafeArea(.container, edges: .top)
            }
        }
        // Fast slide for the sidebar; the editor column, tab-strip inset,
        // and button row glide along with it. Scoped to visibility so no
        // other layout change picks up the animation.
        .animation(
            reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.9),
            value: outlineState.isVisible
        )
    }

    /// Whether the custom editor tab strip is occupying the top band.
    private var tabsShowing: Bool {
        if #available(macOS 26.0, *) {
            return !tabModel.tabs.isEmpty
        }
        return false
    }

    /// Whether the tab strip is currently shown (its band collapses to zero
    /// height otherwise, extending the content to the window's top border).
    private var stripRevealed: Bool {
        !isBlockEditing || editHideCleared || isHoveringTabBand
    }

    /// Hide/reveal animation for the tab strip band and everything that
    /// reflows with it.
    private var tabStripAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.9)
    }

    /// Constant top inset baked into the content under the glass chrome:
    /// the tab strip overlays this region, so peeking in/out never moves
    /// the document, while mid-scroll text still reaches the window's top
    /// border (insets only pad the document's start). Availability-based
    /// rather than tab-count-based so the preview's HTML template (which
    /// bakes it in at load) never goes stale.
    private var contentTopInset: CGFloat {
        if #available(macOS 26.0, *) {
            // 48pt strip band + 8pt breathing room below its divider,
            // matching the sidebar's gap between its rule and folder row.
            return 56
        }
        return 0
    }

    /// Claude-desktop-style toggle that lives next to the traffic lights —
    /// inside the glass sidebar when it's open, floating over the editor
    /// strip when it's closed.
    @available(macOS 26.0, *)
    @available(macOS 26.0, *)
    private var newTabButton: some View {
        Button {
            newFile(tabbingInto: tabModel.window)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        // Explicit cursor control: SwiftUI's pointer styles lose to the
        // WKWebView underneath, which re-asserts its own cursor on every
        // tracked mouse move and flickers the pointer.
        .onHover { hovering in
            (hovering ? NSCursor.pointingHand : NSCursor.arrow).set()
        }
        .help("New file in tab")
        .accessibilityLabel("New file in tab")
    }

    @ViewBuilder
    private var sidebarToggle: some View {
        let button = Button {
            outlineState.isVisible.toggle()
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help(outlineState.isVisible ? "Hide sidebar" : "Show sidebar")
        .accessibilityLabel(outlineState.isVisible ? "Hide sidebar" : "Show sidebar")

        if #available(macOS 26.0, *) {
            button.glassEffect(.regular.interactive(), in: .circle)
        } else {
            button
        }
    }

    private var bottomToolbarOverlay: some View {
        ZStack(alignment: .bottom) {
            BottomHoverTracker { hovering in
                withAnimation(.easeInOut(duration: 0.18)) {
                    isHoveringBottom = hovering
                }
            }
            .frame(height: 96)

            if shouldShowBottomToolbar {
                // The glass toolbar reveals the content beneath itself; a
                // fade-to-background scrim would give it nothing but a flat
                // fill to refract, so it's legacy-only.
                if #unavailable(macOS 26.0) {
                    LinearGradient(
                        stops: [
                            .init(color: Theme.backgroundColorSwiftUI.opacity(0), location: 0),
                            .init(color: Theme.backgroundColorSwiftUI.opacity(0.7), location: 0.55),
                            .init(color: Theme.backgroundColorSwiftUI, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 96)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }

                BottomToolbar(statusBarState: statusBarState)
                .padding(.horizontal, 12)
                // Floats clear of the window's bottom edge: the page's
                // horizontal scroller lives in the bottom ~16pt, and a
                // toolbar sitting on top of it makes the scroller
                // unreachable.
                .padding(.bottom, 24)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    /// Left sidebar. On macOS 26+ it floats as an inset Liquid Glass panel —
    /// same rounded-glass chrome Finder and Xcode use for their sidebars —
    /// with a faint blue cast, hosting the traffic lights in its top strip.
    /// Earlier systems keep the flat full-height panel.
    @ViewBuilder
    private func sidebar(topInset: CGFloat) -> some View {
        if #available(macOS 26.0, *) {
            SidebarView(
                mode: $sidebarMode,
                outlineState: outlineState,
                folderState: folderState,
                isEditorVisible: viewMode == .edit,
                fileURL: fileURL,
                // Top strip tall enough for the traffic lights + overlay
                // buttons; its separator sits at 48pt from the window top,
                // level with the tab strip's divider.
                chromeTopPadding: max(40, topInset + 12)
            )
            .frame(width: 240)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .glassEffect(
                // systemBlue resolves dynamically for light/dark; the low
                // opacity keeps it a hue the glass picks up, not a fill.
                .regular.tint(Color(nsColor: .systemBlue).opacity(colorScheme == .dark ? 0.15 : 0.1)),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .padding(.leading, 8)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
        } else {
            SidebarView(
                mode: $sidebarMode,
                outlineState: outlineState,
                folderState: folderState,
                isEditorVisible: viewMode == .edit,
                fileURL: fileURL
            )
            .frame(width: 240)
        }
    }

    @ViewBuilder
    private var mainPane: some View {
        ZStack {
            EditorView(
                text: $document.text,
                fontSize: CGFloat(fontSize),
                fileURL: fileURL,
                mode: viewMode,
                positionSyncID: positionSyncID,
                findState: findState,
                outlineState: outlineState,
                extraTopInset: contentTopInset,
                extraBottomInset: BottomToolbar.pillHeight + 40,
                jumpToLineState: jumpToLineState,
                statusBarState: statusBarState,
                contentWidthEm: contentWidthEm
            )
            .opacity(viewMode == .edit ? 1 : 0)
            .allowsHitTesting(viewMode == .edit)

            PreviewView(
                markdown: document.text,
                fontSize: CGFloat(fontSize) + 4,
                fontFamily: previewFontFamily,
                mode: viewMode,
                positionSyncID: positionSyncID,
                fileURL: fileURL,
                findState: findState,
                outlineState: outlineState,
                onTaskToggle: { line, checked in
                    toggleTask(line: line, checked: checked)
                },
                onLiveEdit: { start, end, original, text in
                    applyLiveEdit(start: start, end: end, original: original, text: text)
                },
                onLiveInsert: { afterLine, text in
                    if let updated = LiveEditSupport.insertingBlock(text, after: afterLine, in: document.text) {
                        document.text = updated
                    }
                },
                onLiveEditingChanged: { editing in
                    setBlockEditing(editing)
                },
                onLiveTyping: {
                    autoCreateFileIfNeeded()
                },
                onLiveAppend: { text in
                    document.text = LiveEditSupport.appendingBlock(text, to: document.text)
                },
                contentWidthEm: contentWidthEm,
                extraTopInset: contentTopInset
            )
            .opacity(showsRenderedPane ? 1 : 0)
            .allowsHitTesting(showsRenderedPane)
        }
    }

    private var showsRenderedPane: Bool {
        viewMode == .preview || viewMode == .live
    }

    /// Replace source lines `start...end` (1-based, from the rendered page's
    /// data-sourcepos) with the block text the user typed in live mode.
    /// Compare-and-swap: the commit is dropped when those lines no longer
    /// contain `original` (e.g. the file changed on disk mid-edit).
    private func applyLiveEdit(start: Int, end: Int, original: String, text: String) {
        guard let updated = LiveEditSupport.applyingEdit(to: document.text, start: start, end: end, original: original, replacement: text) else { return }
        guard updated != document.text else { return }
        document.text = updated
    }

    /// Debounced editing-state sink: "off" waits a beat so commit → reload →
    /// reopen chains (Enter on a heading, arrow-key travel) don't flash the
    /// tab strip between two editors.
    private func setBlockEditing(_ editing: Bool) {
        editingClearWork?.cancel()
        editingClearWork = nil
        if editing {
            withAnimation(tabStripAnimation) {
                isBlockEditing = true
                // Each new editing session hides the strip afresh.
                editHideCleared = false
            }
        } else {
            let work = DispatchWorkItem {
                withAnimation(tabStripAnimation) {
                    isBlockEditing = false
                    editHideCleared = false
                }
            }
            editingClearWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
        }
    }

    /// Toggle the `[ ]` / `[x]` on the source line that produced this rendered
    /// task. Called from the preview-side click handler.
    private func toggleTask(line: Int, checked: Bool) {
        let lines = document.text.components(separatedBy: "\n")
        guard line > 0, line <= lines.count else { return }
        let original = lines[line - 1]
        let updated: String
        if checked {
            updated = original.replacingOccurrences(of: "[ ]", with: "[x]", options: [], range: original.range(of: "[ ]"))
        } else {
            updated = original.replacingOccurrences(of: "[x]", with: "[ ]", options: .caseInsensitive, range: original.range(of: "[x]", options: .caseInsensitive))
        }
        guard updated != original else { return }
        var newLines = lines
        newLines[line - 1] = updated
        document.text = newLines.joined(separator: "\n")
    }

    /// File ▸ Open Folder…: orient this window's sidebar to a chosen folder.
    private func openFolder() {
        guard let url = FolderPanel.choose() else { return }
        folderState.open(folder: url)
        sidebarMode = .folder
        outlineState.isVisible = true
    }

    private func newFile(tabbingInto window: NSWindow? = nil) {
        createMarkdownDocument(in: folderState, promptForFolder: true, tabbingInto: window)
    }

    /// This window's underlying NSDocument.
    private func windowDocument() -> NSDocument? {
        guard let window = tabModel.window else { return nil }
        return NSDocumentController.shared.documents.first { document in
            document.windowControllers.contains { $0.window === window }
        }
    }

    /// First character typed into an untitled window: create a markdown
    /// file for it in the open folder (falling back to the default notes
    /// folder) and bind the document to it — the file appears in the
    /// sidebar immediately via the folder watcher.
    private func autoCreateFileIfNeeded() {
        // SwiftUI's fileURL lags the NSDocument in both directions — a render
        // pass behind a save-as (which can mint a second file) and behind an
        // auto-delete's unbind (which would block re-creating). The
        // NSDocument is authoritative for whether this window is untitled.
        guard !autoCreatePending,
              let doc = windowDocument(),
              doc.fileURL == nil else { return }
        if folderState.folderURL == nil, let fallback = DefaultNotesFolder.url {
            folderState.open(folder: fallback)
        }
        guard folderState.folderURL != nil else { return }
        autoCreatePending = true
        do {
            let url = try folderState.createUntitledFile()
            doc.save(to: url, ofType: doc.fileType ?? "net.daringfireball.markdown", for: .saveAsOperation) { error in
                autoCreatePending = false
                if error == nil {
                    setDocumentTitle(doc, for: url)
                    folderState.refresh()
                }
            }
        } catch {
            autoCreatePending = false
        }
    }

    /// Whether the filename tracks the first line of the given text —
    /// auto-generated ("Untitled", "Untitled 2", …) or equal to the name
    /// that text's first line derives (modulo a collision counter). Only
    /// tracking files keep renaming as the first block changes; a
    /// deliberately named file (a repo README, a manually renamed note) is
    /// never clobbered. Judged against the text the name came FROM — by
    /// the time a rename runs, the first line has already moved on.
    private func fileNameTracksFirstLine(in text: String) -> Bool {
        guard let url = windowDocument()?.fileURL ?? fileURL else {
            // Untitled window: auto-create will mint a tracking name.
            return true
        }
        let base = strippingCounterSuffix(url.deletingPathExtension().lastPathComponent)
        if isAutoGeneratedFileName(base) { return true }
        return base == (FolderState.derivedFileName(fromDocumentText: text) ?? "")
    }

    /// Re-judge sync against the current name and text: after any move
    /// (auto-rename, sidebar rename, save-as) the name either matches the
    /// first line — sync continues — or it was set deliberately and the
    /// file stops renaming itself.
    private func refreshFileNameSync() {
        fileNameSynced = fileNameTracksFirstLine(in: document.text)
    }

    /// Debounced so edit-mode keystrokes on the first line coalesce into
    /// one rename instead of moving the file per character. (Live-mode
    /// commits arrive whole, so the delay is imperceptible there.)
    private func scheduleFirstLineRename() {
        renameDebounceWork?.cancel()
        let work = DispatchWorkItem { autoRenameToFirstLine() }
        renameDebounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    /// Keeps the filename in sync with the first content line, Apple
    /// Notes-style: the line up to its first period, markdown prefixes
    /// stripped, with collision counters when a sibling owns the name.
    private func autoRenameToFirstLine() {
        guard fileNameSynced,
              !autoRenamePending, !autoCreatePending,
              let doc = windowDocument(),
              let url = doc.fileURL,
              let title = FolderState.derivedFileName(fromDocumentText: document.text)
        else { return }
        // Already in sync (a collision counter still counts as synced —
        // re-deriving must not walk "Title 2" to "Title 3").
        let currentBase = url.deletingPathExtension().lastPathComponent
        guard strippingCounterSuffix(currentBase) != title else { return }
        var candidate = title
        var counter = 2
        var target = try? FolderState.renamedFileURL(for: url, displayName: candidate)
        while let t = target,
              t.standardizedFileURL != url.standardizedFileURL,
              FileManager.default.fileExists(atPath: t.path) {
            guard counter <= 50 else { return }
            candidate = "\(title) \(counter)"
            counter += 1
            target = try? FolderState.renamedFileURL(for: url, displayName: candidate)
        }
        guard let newURL = target,
              newURL.standardizedFileURL != url.standardizedFileURL else { return }
        autoRenamePending = true
        doc.move(to: newURL) { error in
            autoRenamePending = false
            if error == nil {
                setDocumentTitle(doc, for: newURL)
                folderState.refresh()
            }
        }
    }

    /// "Title 2" → "Title": collision counters are bookkeeping, not part of
    /// the name the first line derives.
    private func strippingCounterSuffix(_ name: String) -> String {
        name.replacingOccurrences(of: #" \d+$"#, with: "", options: .regularExpression)
    }

    /// "Untitled", "Untitled 2", … — names minted by `createUntitledFile`.
    private func isAutoGeneratedFileName(_ name: String) -> Bool {
        name.range(of: #"^Untitled( \d+)?$"#, options: .regularExpression) != nil
    }

    /// A file whose content was completely deleted disappears when the user
    /// moves on (window resigns key or closes): trash it and drop it from
    /// the sidebar. With `unbindDocument`, the window itself survives — the
    /// document reverts to untitled and marked-clean, exactly the state it
    /// had before the first keystroke auto-created the file, so typing again
    /// simply creates a fresh one. (Closing the document here instead would
    /// take down the last window, and the app with it.)
    private func autoDeleteIfEmpty(unbindDocument: Bool) {
        guard !autoCreatePending,
              document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let doc = windowDocument()
        guard let url = doc?.fileURL ?? fileURL else { return }
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        folderState.refresh()
        if unbindDocument, let doc {
            doc.fileURL = nil
            doc.updateChangeCount(.changeCleared)
            setDocumentTitle(doc, for: nil)
            // The document turning untitled makes AppKit/SwiftUI rebuild the
            // titlebar (unsaved-document proxy) a beat after the synchronous
            // configure inside setDocumentTitle, resurfacing the native bar.
            // Re-hide it once the dust settles — same delayed re-apply trick
            // as TrafficLightMover.
            let window = tabModel.window
            for delay in [0.05, 0.3, 1.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    configureDocumentWindowChrome(window)
                }
            }
        }
    }

    private func orientSidebarToDocumentFolder() {
        if let folder = fileURL?.deletingLastPathComponent() {
            folderState.open(folder: folder)
        } else if let fallback = DefaultNotesFolder.url {
            // Untitled windows orient to the default notes folder.
            folderState.open(folder: fallback)
        }
    }

    private func exportPDF() {
        PDFExporter().exportPDF(
            markdown: document.text,
            fontSize: CGFloat(fontSize),
            fontFamily: previewFontFamily,
            fileURL: fileURL
        )
    }

    private func printDocument() {
        PDFExporter().printHTML(
            markdown: document.text,
            fontSize: CGFloat(fontSize),
            fontFamily: previewFontFamily,
            fileURL: fileURL
        )
    }
}

private struct WindowTitleSetter: NSViewRepresentable {
    let fileURL: URL?
    let newFile: (NSWindow?) -> Void
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            let title = displayTitle(for: fileURL)
            if let window = nsView?.window {
                window.title = title
                configureDocumentWindowChrome(window)
                window.hypergraphiaNewFileAction = { [weak window] in
                    newFile(window)
                }
                onWindow(window)
            }

            guard let target = fileURL?.standardizedFileURL else { return }
            let document = NSDocumentController.shared.documents.first { document in
                document.fileURL?.standardizedFileURL == target
            }
            setDocumentTitle(document, for: fileURL)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        nsView.window?.hypergraphiaNewFileAction = nil
    }
}
