import AppKit

/// The user's default notes folder. Persisted as a security-scoped bookmark
/// (the sandbox forgets plain paths across launches) plus a display path for
/// the Settings UI. Chosen on first launch — the app insists — and
/// changeable later in Settings ▸ General.
@MainActor
enum DefaultNotesFolder {
    private static let bookmarkKey = "defaultNotesFolderBookmark"
    /// Display-only mirror of the chosen path (Settings binds to it).
    static let pathKey = "defaultNotesFolderPath"

    private static var accessedURL: URL?

    static var isSet: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    /// Resolves the bookmark and starts security-scoped access (held for the
    /// app's lifetime; the folder backs every window's file list).
    static var url: URL? {
        if let accessedURL {
            return accessedURL
        }
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        if stale, let refreshed = try? resolved.bookmarkData(
            options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil
        ) {
            UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
        }
        _ = resolved.startAccessingSecurityScopedResource()
        accessedURL = resolved
        return resolved
    }

    static func set(_ url: URL) {
        if let accessedURL {
            accessedURL.stopAccessingSecurityScopedResource()
            self.accessedURL = nil
        }
        if let data = try? url.bookmarkData(
            options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil
        ) {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }
        UserDefaults.standard.set(url.path, forKey: pathKey)
    }

    /// First-launch flow: keeps presenting the chooser until a folder is
    /// picked, then stores it as the default.
    static func promptUntilChosen() {
        guard !isSet else { return }
        NSApp.activate(ignoringOtherApps: true)
        while !isSet {
            if let url = choose(message: "Choose your default notes folder. New windows open here, and you can change it later in Settings.") {
                set(url)
            }
        }
    }

    /// One-shot chooser (Settings ▸ Change…). Returns nil on cancel.
    static func choose(message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = message
        panel.prompt = "Use as Notes Folder"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
