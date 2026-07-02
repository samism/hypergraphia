import Foundation
import Testing
@testable import HypergraphiaCore

struct FolderStateTests {

    private func makeTempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func touch(_ name: String, in folder: URL) throws {
        try Data().write(to: folder.appendingPathComponent(name))
    }

    @Test func listsOnlyMarkdownFiles() throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        try touch("notes.md", in: folder)
        try touch("readme.markdown", in: folder)
        try touch("component.mdx", in: folder)
        try touch("image.png", in: folder)
        try touch("script.sh", in: folder)
        try touch("plain.txt", in: folder)

        let names = FolderState.markdownFiles(in: folder).map(\.displayName)
        #expect(names.sorted() == ["component", "notes", "readme"])
    }

    @Test func displayNameStripsExtension() {
        let file = FolderFile(url: URL(fileURLWithPath: "/tmp/My Notes.md"))
        #expect(file.displayName == "My Notes")
    }

    @Test func extensionMatchIsCaseInsensitive() throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        try touch("SHOUTING.MD", in: folder)

        #expect(FolderState.markdownFiles(in: folder).map(\.displayName) == ["SHOUTING"])
    }

    @Test func skipsHiddenFilesAndDirectories() throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        try touch(".hidden.md", in: folder)
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("folder-named-like-a-file.md"),
            withIntermediateDirectories: true
        )
        // Markdown inside a subdirectory stays out of the (top-level) list.
        try touch("folder-named-like-a-file.md/nested.md", in: folder)

        #expect(FolderState.markdownFiles(in: folder).isEmpty)
    }

    @Test func sortsLikeFinder() throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        try touch("note 10.md", in: folder)
        try touch("note 2.md", in: folder)
        try touch("Alpha.md", in: folder)

        let names = FolderState.markdownFiles(in: folder).map(\.displayName)
        #expect(names == ["Alpha", "note 2", "note 10"])
    }

    @Test func newFileURLAvoidsCollisions() throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(FolderState.newFileURL(in: folder).lastPathComponent == "Untitled.md")

        try touch("untitled.md", in: folder)
        #expect(FolderState.newFileURL(in: folder).lastPathComponent == "Untitled 2.md")

        try touch("Untitled 2.md", in: folder)
        #expect(FolderState.newFileURL(in: folder).lastPathComponent == "Untitled 3.md")
    }

    @Test func createUntitledFileWritesAndRefreshes() throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let state = FolderState()
        state.open(folder: folder)
        #expect(state.files.isEmpty)

        let created = try state.createUntitledFile()
        #expect(created.lastPathComponent == "Untitled.md")
        #expect(FileManager.default.fileExists(atPath: created.path))
        #expect(state.files.map(\.displayName) == ["Untitled"])
    }

    @Test func closeFolderClearsState() throws {
        let folder = try makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        try touch("a.md", in: folder)
        let state = FolderState()
        state.open(folder: folder)
        #expect(!state.files.isEmpty)

        state.closeFolder()
        #expect(state.folderURL == nil)
        #expect(state.files.isEmpty)
    }
}
