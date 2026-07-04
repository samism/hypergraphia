import Cocoa
import HypergraphiaCore
import QuickLookUI
import WebKit

class PreviewViewController: NSViewController, QLPreviewingController {
    private var webView: WKWebView!

    override func loadView() {
        webView = WKWebView()
        self.view = webView
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)

            // Spacebar previews have a latency budget: render huge documents
            // truncated (cut at a line boundary) with a notice instead of
            // making quicklookd chew through megabytes of markdown.
            let (renderData, truncated) = TextFileDecoder.truncatedAtLineBoundary(
                data, limit: Limits.maxQuickLookRenderSize
            )

            // Never-fail decode — UTF-16 exports and legacy-encoded notes
            // preview correctly instead of erroring out of QuickLook (the
            // old strict-UTF-8 read threw for anything else).
            let markdownText = TextFileDecoder.decode(renderData)
            var htmlBody = MarkdownRenderer.renderHTML(markdownText)
            if truncated {
                htmlBody += """
                <div style="margin-top:2em;padding:12px 16px;border-radius:8px;\
                background:rgba(128,128,128,0.12);font-style:italic;">\
                Preview truncated — open in Hypergraphia to view the full document.</div>
                """
            }

            let html = """
            <!DOCTYPE html>
            <html>
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>\(PreviewCSS.css())</style>
            <style>
            @media (max-width: 400px) {
                body { font-size: 14px; padding: 10px 20px 20px; }
            }
            </style>
            </head>
            <body>\(htmlBody)</body>
            \(MathSupport.scriptHTML(for: htmlBody))
            \(TableSupport.scriptHTML(for: htmlBody))
            \(MermaidSupport.scriptHTML)
            \(SyntaxHighlightSupport.scriptHTML(for: htmlBody))
            </html>
            """

            webView.loadHTMLString(html, baseURL: MermaidSupport.resourceBaseURL)
            handler(nil)
        } catch {
            handler(error)
        }
    }

}
