import SwiftUI
import AppKit
import HypergraphiaCore

/// Which content the left sidebar shows. Per-window: a window opened from a
/// folder starts in `.folder`; everything else starts in `.outline`.
enum SidebarMode {
    case outline
    case folder
}

/// Left sidebar container: OUTLINE / FILES mode toggle in the header, then
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
        HStack(spacing: 12) {
            modeTab("OUTLINE", .outline)
            modeTab("FILES", .folder)
            Spacer()
            if mode == .folder && folderState.folderURL != nil {
                newFileButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private func modeTab(_ title: String, _ tabMode: SidebarMode) -> some View {
        Button {
            mode = tabMode
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(mode == tabMode ? AnyShapeStyle(.secondary) : AnyShapeStyle(.quaternary))
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .accessibilityAddTraits(mode == tabMode ? .isSelected : [])
    }

    private var newFileButton: some View {
        Button {
            createFile()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help("New markdown file in this folder")
        .accessibilityLabel("New markdown file in this folder")
    }

    private func createFile() {
        do {
            let url = try folderState.createUntitledFile()
            openMarkdownDocument(at: url, from: folderState.folderURL)
        } catch {
            NSAlert(error: error).runModal()
        }
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
                                }
                            }
                        }
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
}

private struct FileRow: View {
    let file: FolderFile
    let isCurrent: Bool
    let onTap: () -> Void
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            Text(file.displayName)
                .font(.system(size: 12, weight: isCurrent ? .medium : .regular))
                .foregroundStyle(isCurrent ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
                .padding(.trailing, 8)
                .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isCurrent || isHovered
                    ? Theme.hoverColor(inDark: colorScheme == .dark)
                    : Color.clear)
                .padding(.horizontal, 4)
        )
        .onHover { hovering in
            withAnimation(Theme.Motion.hover) {
                isHovered = hovering
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

/// Opens a markdown file as a document window. When it came from a folder
/// sidebar, stages that folder so the new window's `ContentView` adopts it
/// (folder mode, same folder) on appear.
@MainActor
func openMarkdownDocument(at url: URL, from folder: URL?) {
    if let folder {
        FolderHandoff.stage(folder: folder, forOpening: url)
    }
    NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
}

/// Hands folder context from the window that initiated an open to the new
/// document window. Keyed by standardized file URL, claimed once, and
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
