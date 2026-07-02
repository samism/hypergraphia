import SwiftUI
import AppKit
import HypergraphiaCore

/// Which content the left sidebar shows. Per-window, the file list is the
/// default, and outline stays one click away.
enum SidebarMode {
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

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
        .background(Theme.outlinePanelBackgroundSwiftUI)
    }

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                modeTab("FILES", systemImage: "doc.text", .folder)
                modeTab("OUTLINE", systemImage: "list.bullet.indent", .outline)
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.hoverColor(inDark: colorScheme == .dark).opacity(0.55))
            )

            Spacer()

            if mode == .folder && folderState.folderURL != nil {
                newFileButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 7)
    }

    private func modeTab(_ title: String, systemImage: String, _ tabMode: SidebarMode) -> some View {
        let isSelected = mode == tabMode

        return Button {
            mode = tabMode
        } label: {
            Label {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
            } icon: {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
            }
            .labelStyle(.titleAndIcon)
            .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected
                        ? Theme.backgroundColorSwiftUI.opacity(colorScheme == .dark ? 0.7 : 0.95)
                        : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var newFileButton: some View {
        Button {
            createMarkdownDocument(in: folderState)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.hoverColor(inDark: colorScheme == .dark).opacity(0.45))
                )
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help("New markdown file in this folder")
        .accessibilityLabel("New markdown file in this folder")
    }
}

/// Folder-mode sidebar content: the folder the window is oriented to and the
/// markdown files inside it.
private struct FolderListView: View {
    @ObservedObject var folderState: FolderState
    let currentFileURL: URL?

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
                        Text("Click + to create one")
                            .font(.system(size: 11))
                            .foregroundStyle(.quaternary)
                    }
                    .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(folderState.files) { file in
                                FileRow(
                                    file: file,
                                    isCurrent: file.url.standardizedFileURL == currentFileURL?.standardizedFileURL
                                ) {
                                    openMarkdownDocument(at: file.url, from: folderURL)
                                } onRename: {
                                    rename(file)
                                } onDelete: {
                                    delete(file)
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

    private func rename(_ file: FolderFile) {
        guard let requestedName = RenamePanel.chooseName(for: file) else { return }

        do {
            let newURL = try FolderState.renamedFileURL(for: file.url, displayName: requestedName)
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
    let onTap: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
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
            Button("Rename…") {
                onRename()
            }
            Divider()
            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
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

enum RenamePanel {
    @MainActor
    static func chooseName(for file: FolderFile) -> String? {
        let alert = NSAlert()
        alert.messageText = "Rename File"
        alert.informativeText = "Enter a new name for \(file.displayName)."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(string: file.displayName)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field

        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
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

    window.titleVisibility = .visible
    window.titlebarAppearsTransparent = false
    window.styleMask.remove(.fullSizeContentView)
    hideNativeTabAddButton(in: window)

    Task { @MainActor [weak window] in
        hideNativeTabAddButton(in: window)
    }
}

@MainActor
private func hideNativeTabAddButton(in window: NSWindow?) {
    guard let tabGroup = window?.tabGroup else { return }
    let selector = NSSelectorFromString("plusTab")
    guard tabGroup.responds(to: selector),
          let plus = tabGroup.perform(selector)?.takeUnretainedValue() as? NSView else { return }

    // ponytail: AppKit exposes tab groups but not a public switch for the
    // native tab-bar add button. Replace this if Hypergraphia gets custom tabs.
    plus.isHidden = true
    if let control = plus as? NSControl {
        control.isEnabled = false
    }
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
