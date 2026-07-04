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

public enum FolderStateError: LocalizedError, Equatable {
    case emptyFileName
    case invalidFileName
    case fileAlreadyExists(String)

    public var errorDescription: String? {
        switch self {
        case .emptyFileName:
            return "File name cannot be empty."
        case .invalidFileName:
            return "File name cannot contain path separators."
        case .fileAlreadyExists(let name):
            return "A file named \"\(name)\" already exists."
        }
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

    /// Filename derived from a document's first line, for auto-naming
    /// untitled notes: the line's text up to the first period, with markdown
    /// block prefixes (heading #'s, blockquote >, list markers, checkboxes)
    /// and filesystem-hostile characters stripped. Nil when nothing usable
    /// remains.
    public static func derivedFileName(fromDocumentText text: String) -> String? {
        var line = String(text.prefix(while: { $0 != "\n" }))
        line = line.replacingOccurrences(
            of: #"^\s{0,3}(?:#{1,6}\s+|>\s*|(?:[-*+]|\d+[.)])\s+(?:\[[ xX]\]\s+)?)"#,
            with: "", options: .regularExpression
        )
        if let dot = line.firstIndex(of: ".") { line = String(line[..<dot]) }
        line = line.replacingOccurrences(of: "/", with: "-")
        line = line.replacingOccurrences(of: ":", with: "-")
        line = line.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return nil }
        if line.count > 64 {
            line = String(line.prefix(64)).trimmingCharacters(in: .whitespaces)
        }
        return line
    }

    /// Rename target for a sidebar file. The UI asks for the extensionless
    /// display name; if the user types a markdown extension anyway, preserve
    /// the original file's extension instead of doubling it.
    public static func renamedFileURL(for fileURL: URL, displayName rawName: String) throws -> URL {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FolderStateError.emptyFileName }
        guard !trimmed.contains("/") && !trimmed.contains(":") else { throw FolderStateError.invalidFileName }

        let typedExtension = (trimmed as NSString).pathExtension.lowercased()
        let baseName = markdownExtensions.contains(typedExtension)
            ? (trimmed as NSString).deletingPathExtension
            : trimmed
        guard !baseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FolderStateError.emptyFileName
        }

        let fileExtension = fileURL.pathExtension
        let fileName = fileExtension.isEmpty ? baseName : "\(baseName).\(fileExtension)"
        return fileURL.deletingLastPathComponent().appendingPathComponent(fileName)
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
