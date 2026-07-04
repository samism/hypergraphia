import Foundation

public struct HeadingItem: Identifiable, Hashable {
    public let id = UUID()
    public let level: Int       // 1-6
    public let title: String    // Inline markdown stripped
    public let range: NSRange   // Location in document text
    public let previewAnchor: PreviewSourceAnchor

    public init(level: Int, title: String, range: NSRange, previewAnchor: PreviewSourceAnchor) {
        self.level = level
        self.title = title
        self.range = range
        self.previewAnchor = previewAnchor
    }

    /// Content-based equality (the `id` UUID is deliberately excluded): two
    /// parses of unchanged text must produce equal items so `OutlineState`
    /// can skip publishing — otherwise the sidebar re-diffs every row on
    /// every debounced parse while the user types.
    public static func == (lhs: HeadingItem, rhs: HeadingItem) -> Bool {
        lhs.level == rhs.level
            && lhs.title == rhs.title
            && lhs.range == rhs.range
            && lhs.previewAnchor == rhs.previewAnchor
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(level)
        hasher.combine(title)
        hasher.combine(range.location)
        hasher.combine(range.length)
    }
}

public final class OutlineState: ObservableObject {
    @Published public var isVisible: Bool {
        didSet { UserDefaults.standard.set(isVisible, forKey: "outlineVisible") }
    }
    @Published public var headings: [HeadingItem] = []

    /// Set by EditorView coordinator, called when user clicks a heading (editor scroll)
    public var scrollToRange: ((NSRange) -> Void)?
    /// Set by PreviewView coordinator, called when user clicks a heading (preview scroll)
    public var scrollToHeading: ((HeadingItem) -> Void)?

    private static let atxHeadingRegex = try! NSRegularExpression(
        pattern: "^(#{1,6})\\s+(.+)$",
        options: .anchorsMatchLines
    )
    private static let setextHeadingRegex = try! NSRegularExpression(
        pattern: "^(.+)\\n([=-]+)[ \\t]*$",
        options: .anchorsMatchLines
    )
    private static let codeBlockRegex = try! NSRegularExpression(
        pattern: "^((?:`{3,}|~{3,}))[^\n]*\\n([\\s\\S]*?)^\\1[ \\t]*$",
        options: [.anchorsMatchLines]
    )
    private static let frontmatterRegex = try! NSRegularExpression(
        pattern: "\\A---[ \\t]*\\n([\\s\\S]*?)\\n---[ \\t]*(?:\\n|\\z)",
        options: []
    )

    private var parseWork: DispatchWorkItem?

    public init() {
        self.isVisible = UserDefaults.standard.bool(forKey: "outlineVisible")
    }

    public func toggle() {
        isVisible.toggle()
    }

    public func parseHeadings(from text: String) {
        parseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.performParse(from: text)
        }
        parseWork = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func performParse(from text: String) {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        // Find ranges to skip (code blocks, frontmatter)
        var skipRanges: [NSRange] = []

        Self.frontmatterRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let range = match?.range { skipRanges.append(range) }
        }
        Self.codeBlockRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let range = match?.range { skipRanges.append(range) }
        }

        // Find headings, skipping those inside code blocks/frontmatter
        struct RawHeading {
            let level: Int
            let title: String
            let range: NSRange
        }
        var raw: [RawHeading] = []

        Self.atxHeadingRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            let matchRange = match.range

            // Skip if inside a code block or frontmatter
            for skip in skipRanges {
                if skip.location <= matchRange.location &&
                    NSMaxRange(skip) >= NSMaxRange(matchRange) {
                    return
                }
            }

            let hashRange = match.range(at: 1)
            let titleRange = match.range(at: 2)
            let rawTitle = nsText.substring(with: titleRange)
            raw.append(RawHeading(
                level: hashRange.length,
                title: Self.stripInlineMarkdown(rawTitle),
                range: matchRange
            ))
        }

        Self.setextHeadingRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            let matchRange = match.range

            for skip in skipRanges {
                if skip.location <= matchRange.location &&
                    NSMaxRange(skip) >= NSMaxRange(matchRange) {
                    return
                }
            }

            let titleRange = match.range(at: 1)
            let markerRange = match.range(at: 2)
            let rawTitle = nsText.substring(with: titleRange)
            let marker = nsText.substring(with: markerRange)
            raw.append(RawHeading(
                level: marker.first == "=" ? 1 : 2,
                title: Self.stripInlineMarkdown(rawTitle),
                range: matchRange
            ))
        }

        raw.sort { $0.range.location < $1.range.location }

        // Resolve every anchor offset's line/column in one forward walk over
        // the text instead of re-walking from the start for each heading.
        var offsets: [Int] = []
        offsets.reserveCapacity(raw.count * 2)
        for heading in raw {
            offsets.append(heading.range.location)
            offsets.append(max(heading.range.location, NSMaxRange(heading.range) - 1))
        }
        let positions = Self.lineAndColumnTable(for: offsets, in: nsText)

        let items = raw.map { heading -> HeadingItem in
            let startOffset = heading.range.location
            let endOffset = max(heading.range.location, NSMaxRange(heading.range) - 1)
            let start = positions[startOffset] ?? (line: 1, column: 1)
            let end = positions[endOffset] ?? start
            return HeadingItem(
                level: heading.level,
                title: heading.title,
                range: heading.range,
                previewAnchor: PreviewSourceAnchor(
                    startLine: start.line,
                    startColumn: start.column,
                    endLine: end.line,
                    endColumn: end.column,
                    progress: 0
                )
            )
        }

        DispatchQueue.main.async {
            // Skip the publish when nothing changed — typing in body text
            // re-parses every 0.4s, and an unconditional assignment would
            // re-render the whole outline sidebar each time.
            if self.headings != items {
                self.headings = items
            }
        }
    }

    /// Inline-markdown stripping patterns for heading titles, compiled once.
    /// (These previously recompiled per heading — six compiles each.)
    private static let inlineStripPatterns: [(NSRegularExpression, String)] = {
        let raw: [(String, String)] = [
            // Images ![alt](url) → alt — must come before links
            ("!\\[([^\\]]*)\\]\\([^)]+\\)", "$1"),
            // Links [text](url) → text
            ("\\[([^\\]]+)\\]\\([^)]+\\)", "$1"),
            // Bold **text** or __text__
            ("(\\*\\*|__)(.+?)\\1", "$2"),
            // Italic *text* or _text_ (simplified)
            ("(?<![\\w*])[*_](.+?)[*_](?![\\w*])", "$1"),
            // Strikethrough ~~text~~
            ("~~(.+?)~~", "$1"),
            // Inline code `text`
            ("`([^`]+)`", "$1"),
        ]
        return raw.compactMap { pattern, template in
            (try? NSRegularExpression(pattern: pattern)).map { ($0, template) }
        }
    }()

    /// Strip bold, italic, code, strikethrough, and link markdown from heading text
    private static func stripInlineMarkdown(_ text: String) -> String {
        var result = text
        for (regex, template) in inlineStripPatterns {
            let range = NSRange(location: 0, length: (result as NSString).length)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: template)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Line/column positions for a set of offsets, resolved in a single
    /// forward pass. `offsets` may be unsorted and contain duplicates.
    private static func lineAndColumnTable(
        for offsets: [Int],
        in text: NSString
    ) -> [Int: (line: Int, column: Int)] {
        guard !offsets.isEmpty else { return [:] }
        let sortedOffsets = offsets.map { min(max(0, $0), text.length) }.sorted()
        var table: [Int: (line: Int, column: Int)] = [:]
        table.reserveCapacity(sortedOffsets.count)

        var line = 1
        var lineStart = 0
        var lineEnd = 0 // start of the next line after `lineStart`

        for offset in sortedOffsets {
            if table[offset] != nil { continue }
            // Advance line-by-line until `offset` falls inside the current line.
            while lineStart < offset {
                if lineEnd <= lineStart {
                    lineEnd = NSMaxRange(text.lineRange(for: NSRange(location: lineStart, length: 0)))
                }
                if lineEnd > offset || lineEnd == lineStart { break }
                line += 1
                lineStart = lineEnd
                lineEnd = lineStart
            }
            table[offset] = (line, max(1, offset - lineStart + 1))
        }
        return table
    }
}
