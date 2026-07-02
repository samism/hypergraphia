import SwiftUI
import HypergraphiaCore

@main
struct HypergraphiaApp_iOS: App {
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            DocumentDetailBody(document: file.$document, fileURL: file.fileURL)
        }
    }
}
