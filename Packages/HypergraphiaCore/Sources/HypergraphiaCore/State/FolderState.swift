import Foundation

/// A markdown file shown in the folder sidebar.
public struct FolderFile: Identifiable, Hashable {
    public let url: URL
    public var id: URL { url }
    /// Name shown in the sidebar — extension stripped.
    public var displayName: String { url.deletingPathExtension().lastPathComponent }

    public init(url: URL) {
        self.url = url
    }
}

/// Per-window state for the sidebar's folder mode: the folder the window is
/// oriented to and the markdown files inside it (top level only — no
/// recursion). Watches the directory with a kqueue `DispatchSource` so files
/// added, removed, or renamed out-of-process show up without a manual
/// refresh.
public final class FolderState: ObservableObject {
    @Published public private(set) var folderURL: URL?
    @Published public private(set) var files: [FolderFile] = []

    /// Mirrors `public.filename-extension` for `net.daringfireball.markdown`
    /// in the app Info.plists — anything the app can open as a document.
    public static let markdownExtensions: Set<String> = [
        "md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdx"
    ]

    private var watcher: DispatchSourceFileSystemObject?
    private var refreshWork: DispatchWorkItem?

    public init() {}

    deinit { stopWatching() }

    public func open(folder url: URL) {
        folderURL = url
        files = Self.markdownFiles(in: url)
        watch(url)
    }

    public func closeFolder() {
        stopWatching()
        folderURL = nil
        files = []
    }

    /// Re-list the folder immediately.
    public func refresh() {
        guard let folderURL else { return }
        files = Self.markdownFiles(in: folderURL)
    }

    /// Top-level markdown files in `folder`, sorted like Finder.
    public static func markdownFiles(in folder: URL) -> [FolderFile] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { url in
                guard Self.markdownExtensions.contains(url.pathExtension.lowercased()) else { return false }
                return (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            }
            .map(FolderFile.init)
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    /// First non-colliding "Untitled.md" / "Untitled N.md" URL in `folder`.
    /// Case-insensitive so it stays safe on the default APFS variant.
    public static func newFileURL(in folder: URL, baseName: String = "Untitled") -> URL {
        let existing = Set(
            ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
                .map { $0.lowercased() }
        )
        var name = "\(baseName).md"
        var counter = 2
        while existing.contains(name.lowercased()) {
            name = "\(baseName) \(counter).md"
            counter += 1
        }
        return folder.appendingPathComponent(name)
    }

    /// Create an empty untitled markdown file in the open folder and return
    /// its URL.
    @discardableResult
    public func createUntitledFile() throws -> URL {
        guard let folderURL else { throw CocoaError(.fileNoSuchFile) }
        let url = Self.newFileURL(in: folderURL)
        try Data().write(to: url, options: .withoutOverwriting)
        refresh()
        return url
    }

    // MARK: - Directory watching

    private func watch(_ url: URL) {
        stopWatching()
        let fd = Darwin.open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.scheduleRefresh() }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    private func stopWatching() {
        watcher?.cancel()
        watcher = nil
        refreshWork?.cancel()
        refreshWork = nil
    }

    /// Coalesce a burst of directory events into one re-list.
    private func scheduleRefresh() {
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }
}
