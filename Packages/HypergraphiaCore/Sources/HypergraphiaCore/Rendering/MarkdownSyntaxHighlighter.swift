import Foundation
import os
import QuartzCore

private typealias Attr = PlatformTextAttributes

public final class MarkdownSyntaxHighlighter: NSObject {

    public override init() {
        super.init()
    }

    private var isHighlighting = false
    private var cachedProtectedRanges: [ProtectedRange] = []

    /// Set by `highlightAround` when a block delimiter is detected.
    /// The caller should schedule a deferred `highlightAll` instead of running it synchronously.
    public var needsFullHighlight = false

    /// Incremental passes below this duration are routine and not worth a
    /// log line per keystroke; only slow outliers get recorded.
    private static let slowPassLogThresholdMs: Double = 8

    // MARK: - Regex Patterns

    private static let frontmatterKeyRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "^([\\w][\\w\\s.-]*)(:)",
        options: .anchorsMatchLines
    )

    private static let frontmatterBlockRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "\\A---[ \\t]*\\n([\\s\\S]*?)\\n---[ \\t]*(?:\\n|\\z)"
    )

    private static let fencedCodeBlockRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "^(`{3,})(.*?)\\n([\\s\\S]*?)^\\1\\s*$",
        options: .anchorsMatchLines
    )

    private static let displayMathBlockRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "^\\$\\$\\n([\\s\\S]*?)^\\$\\$\\s*$",
        options: .anchorsMatchLines
    )

    /// Block-level patterns that produce protected ranges. Order matters:
    /// frontmatter styling must land before code/math styling can overpaint it.
    private static let blockPatterns: [(NSRegularExpression, HighlightStyle)] = {
        var result: [(NSRegularExpression, HighlightStyle)] = []
        if let regex = frontmatterBlockRegex { result.append((regex, .frontmatter)) }
        if let regex = fencedCodeBlockRegex { result.append((regex, .codeBlock)) }
        if let regex = displayMathBlockRegex { result.append((regex, .mathBlock)) }
        return result
    }()

    /// Inline / line-level patterns, applied after block patterns so their
    /// matches can be suppressed inside protected block ranges.
    private static let inlinePatterns: [(NSRegularExpression, HighlightStyle)] = {
        var result: [(NSRegularExpression, HighlightStyle)] = []

        func add(_ pattern: String, _ style: HighlightStyle, options: NSRegularExpression.Options = []) {
            if let regex = try? NSRegularExpression(pattern: pattern, options: options) {
                result.append((regex, style))
            }
        }

        // Inline math: $...$
        add(MathSupport.inlineMathPattern, .mathInline)

        // Headings: # Heading
        add("^(#{1,6}\\s+)(.+)$", .heading, options: .anchorsMatchLines)

        // Bold italic: ***text*** or ___text___
        add("(\\*\\*\\*|___)([^\n]+?)(\\1)", .boldItalic)

        // Bold: **text** or __text__ (not part of ***triple***)
        add("(?<![*_])(\\*\\*(?!\\*)|__(?!_))([^\n]+?)(\\1)(?![*_])", .bold)

        // Italic: *text* or _text_ (not inside words for _)
        add("(?<![\\w*])(\\*(?!\\*)|_(?!_))(?!\\s)([^\n]+?)(?<!\\s)\\1(?![\\w*])", .italic)

        // Strikethrough: ~~text~~
        add("(~~)([^\n]+?)(~~)", .strikethrough)

        // Inline code: `code`
        add("(`+)([^\n]+?)(\\1)", .inlineCode)

        // Images: ![alt](src) — must come before links
        add("(!\\[)([^\\]\n]*)(\\]\\([^\n]+?\\))", .link)

        // Links: [text](url)
        add("(\\[)([^\n]+?)(\\]\\([^\n]+?\\))", .link)

        // Reference links: [text][ref]
        add("(\\[)([^\\]\n]+)(\\])(\\[)([^\\]\n]*)(\\])", .link)

        // Blockquotes: > text
        add("^(>+\\s?)(.*)$", .blockquote, options: .anchorsMatchLines)

        // Unordered list markers: - or * or +
        add("^(\\s*[-*+]\\s)", .listMarker, options: .anchorsMatchLines)

        // Ordered list markers: 1.
        add("^(\\s*\\d+\\.\\s)", .listMarker, options: .anchorsMatchLines)

        // Task list: - [ ] or - [x]
        add("^(\\s*[-*+]\\s\\[[ xX]\\]\\s)", .listMarker, options: .anchorsMatchLines)

        // Horizontal rule
        add("^([-*_]{3,})\\s*$", .syntax, options: .anchorsMatchLines)

        // Highlight/Mark: ==text==
        add("(==)([^=\n]+?)(==)", .highlight)

        // Footnote markers: [^ref]
        add("(\\[\\^)([^\\]\n]+)(\\])", .footnote)

        // Table rows: lines with pipes
        add("^(\\|.+\\|)\\s*$", .syntax, options: .anchorsMatchLines)

        // Setext headings: text followed by === or --- on next line
        add("^(.+)\\n(={3,}|-{3,})\\s*$", .heading, options: .anchorsMatchLines)

        // HTML tags
        add("(</?[a-zA-Z][a-zA-Z0-9]*(?:\\s+[^>]*)?>)", .htmlTag)

        return result
    }()

    // MARK: - Highlight Styles

    private enum HighlightStyle {
        case heading
        case bold
        case boldItalic
        case italic
        case strikethrough
        case inlineCode
        case codeBlock
        case link
        case blockquote
        case listMarker
        case syntax
        case mathBlock
        case mathInline
        case frontmatter
        case highlight
        case footnote
        case htmlTag
    }

    private enum ProtectedBlockKind {
        case code
        case math
        case frontmatter
    }

    private struct ProtectedRange {
        var range: NSRange
        let kind: ProtectedBlockKind
    }

    /// Fonts and metrics resolved once per highlight pass, so per-match style
    /// application never touches `Theme`'s cache lock or UserDefaults.
    private struct Styles {
        let body: PlatformFont
        let bold: PlatformFont
        let italic: PlatformFont
        let boldItalic: PlatformFont
        let heading: PlatformFont
        let code: PlatformFont
        let lineHeight: CGFloat
        let baselineOffset: CGFloat

        static func current() -> Styles {
            Styles(
                body: Theme.editorFont,
                bold: Theme.editorBoldFont,
                italic: Theme.editorItalicFont,
                boldItalic: Theme.editorBoldItalicFont,
                heading: Theme.editorHeadingFont,
                code: Theme.editorCodeFont,
                lineHeight: Theme.editorLineHeight,
                baselineOffset: Theme.editorBaselineOffset
            )
        }
    }

    // MARK: - Protected-range intersection

    /// Non-overlapping, sorted union of the protected ranges, for fast
    /// intersection tests during inline-pattern application.
    private static func mergedRanges(_ ranges: [ProtectedRange]) -> [NSRange] {
        guard !ranges.isEmpty else { return [] }
        let sorted = ranges.map(\.range).sorted { $0.location < $1.location }
        var merged: [NSRange] = [sorted[0]]
        for range in sorted.dropFirst() {
            let last = merged[merged.count - 1]
            if range.location <= NSMaxRange(last) {
                let end = max(NSMaxRange(last), NSMaxRange(range))
                merged[merged.count - 1] = NSRange(location: last.location, length: end - last.location)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    private static func intersects(_ range: NSRange, merged: [NSRange]) -> Bool {
        guard range.length > 0, !merged.isEmpty else { return false }
        // Binary search: first merged range starting at or after `range`.
        var lo = 0, hi = merged.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if merged[mid].location < range.location { lo = mid + 1 } else { hi = mid }
        }
        if lo < merged.count, merged[lo].location < NSMaxRange(range) { return true }
        if lo > 0, NSMaxRange(merged[lo - 1]) > range.location { return true }
        return false
    }

    // MARK: - Full Highlighting

    public func highlightAll(_ textStorage: PlatformTextStorage, caller: String = "") {
        guard !isHighlighting else { return }
        guard textStorage.length <= Limits.maxHighlightAllLength else {
            DiagnosticLog.log("MarkdownSyntaxHighlighter: skipping highlightAll over \(textStorage.length) chars")
            return
        }
        isHighlighting = true
        defer { isHighlighting = false }
        let startTime = CACurrentMediaTime()
        let styles = Styles.current()

        textStorage.beginEditing()
        let fullRange = NSRange(location: 0, length: textStorage.length)
        // Whole-document regexes need a stable Swift String; this is the one
        // full bridge copy a full pass pays (incremental passes never do).
        let text = textStorage.string
        let nsText = text as NSString

        // Reset to default style
        let paragraph = PlatformParagraphStyle()
        paragraph.minimumLineHeight = styles.lineHeight
        paragraph.maximumLineHeight = styles.lineHeight

        textStorage.addAttributes([
            Attr.font: styles.body,
            Attr.foregroundColor: Theme.textColor,
            Attr.paragraphStyle: paragraph,
            Attr.baselineOffset: styles.baselineOffset
        ], range: fullRange)

        // Pass 1: block-level constructs (frontmatter, fenced code, display
        // math). These collect the protected ranges inline patterns must skip.
        var protectedRanges: [ProtectedRange] = []
        for (regex, style) in Self.blockPatterns {
            regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                guard let match else { return }
                switch style {
                case .codeBlock:
                    protectedRanges.append(ProtectedRange(range: match.range, kind: .code))
                    textStorage.addAttributes([
                        Attr.font: styles.code,
                        Attr.foregroundColor: Theme.codeColor
                    ], range: match.range)
                    if match.numberOfRanges >= 2 {
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: match.range(at: 1))
                    }

                case .mathBlock:
                    protectedRanges.append(ProtectedRange(range: match.range, kind: .math))
                    textStorage.addAttribute(Attr.foregroundColor, value: Theme.mathColor, range: match.range)
                    // Fade the opening $$ delimiter
                    let openRange = NSRange(location: match.range.location, length: 2)
                    if openRange.upperBound <= textStorage.length {
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: openRange)
                    }
                    // Fade the closing $$ delimiter
                    let closeStart = match.range.location + match.range.length - 2
                    let closeRange = NSRange(location: closeStart, length: 2)
                    if closeRange.upperBound <= textStorage.length && closeStart >= match.range.location {
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: closeRange)
                    }

                case .frontmatter:
                    let matchedText = nsText.substring(with: match.range)
                    guard FrontmatterSupport.extract(from: matchedText) != nil else { return }
                    protectedRanges.append(ProtectedRange(range: match.range, kind: .frontmatter))
                    self.applyFrontmatterStyling(match: match, nsText: nsText, to: textStorage)

                default:
                    break
                }
            }
        }

        cachedProtectedRanges = protectedRanges
        let merged = Self.mergedRanges(protectedRanges)

        // Pass 2: inline patterns, skipping matches inside protected blocks.
        for (regex, style) in Self.inlinePatterns {
            regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                guard let match else { return }
                if Self.intersects(match.range, merged: merged) { return }
                self.applyInlineStyle(style, match: match, offset: 0, to: textStorage, styles: styles)
            }
        }

        textStorage.endEditing()

        let elapsed = (CACurrentMediaTime() - startTime) * 1000
        let tag = caller.isEmpty ? "" : "(\(caller))"
        DiagnosticLog.log("highlightAll\(tag): \(textStorage.length) chars in \(Int(elapsed))ms")
    }

    /// Frontmatter block styling: base color, faded delimiters, YAML keys.
    /// Shared by the full pass; the incremental pass never re-styles a whole
    /// frontmatter block (that path goes through the deferred full pass).
    private func applyFrontmatterStyling(match: NSTextCheckingResult, nsText: NSString, to textStorage: PlatformTextStorage) {
        // Base color for the whole block
        textStorage.addAttribute(Attr.foregroundColor, value: Theme.frontmatterColor, range: match.range)
        // Color the opening --- delimiter line
        let openLineEnd = nsText.range(of: "\n", range: match.range)
        if openLineEnd.location != NSNotFound {
            let openRange = NSRange(location: match.range.location, length: openLineEnd.location - match.range.location)
            textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: openRange)
        }
        // Color the closing --- delimiter (last line of match)
        let matchStr = nsText.substring(with: match.range) as NSString
        let lastNewline = matchStr.range(of: "\n", options: .backwards)
        if lastNewline.location != NSNotFound {
            let closeStart = match.range.location + lastNewline.location + 1
            let closeLen = match.range.location + match.range.length - closeStart
            if closeLen > 0 {
                let closeRange = NSRange(location: closeStart, length: closeLen)
                textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: closeRange)
            }
        }
        // Color YAML keys within the body (group 1)
        if match.numberOfRanges >= 2 {
            let bodyRange = match.range(at: 1)
            if bodyRange.location != NSNotFound, let keyRegex = Self.frontmatterKeyRegex {
                let body = nsText.substring(with: bodyRange)
                let localRange = NSRange(location: 0, length: (body as NSString).length)
                keyRegex.enumerateMatches(in: body, range: localRange) { keyMatch, _, _ in
                    guard let keyMatch, keyMatch.numberOfRanges >= 3 else { return }
                    let keyRange = NSRange(
                        location: keyMatch.range(at: 1).location + bodyRange.location,
                        length: keyMatch.range(at: 1).length
                    )
                    let colonRange = NSRange(
                        location: keyMatch.range(at: 2).location + bodyRange.location,
                        length: keyMatch.range(at: 2).length
                    )
                    textStorage.addAttribute(Attr.foregroundColor, value: Theme.headingColor, range: keyRange)
                    textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: colonRange)
                }
            }
        }
    }

    // MARK: - Style Application

    /// Apply one inline pattern match. `offset` maps match ranges (which may
    /// be relative to a paragraph substring) into text-storage coordinates.
    private func applyInlineStyle(
        _ style: HighlightStyle,
        match: NSTextCheckingResult,
        offset: Int,
        to textStorage: PlatformTextStorage,
        styles: Styles
    ) {
        func shift(_ range: NSRange) -> NSRange {
            offset == 0 ? range : NSRange(location: range.location + offset, length: range.length)
        }
        let fullMatchRange = shift(match.range)

        switch style {
        case .heading:
            // Group 1: syntax (##), Group 2: content
            if match.numberOfRanges >= 3 {
                textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: shift(match.range(at: 1)))
                textStorage.addAttributes([
                    Attr.foregroundColor: Theme.headingColor,
                    Attr.font: styles.heading
                ], range: shift(match.range(at: 2)))
            }

        case .bold:
            if match.numberOfRanges >= 4 {
                textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: shift(match.range(at: 1)))
                textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: shift(match.range(at: 3)))
                textStorage.addAttributes([
                    Attr.foregroundColor: Theme.boldColor,
                    Attr.font: styles.bold
                ], range: shift(match.range(at: 2)))
            }

        case .boldItalic:
            if match.numberOfRanges >= 4 {
                textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: shift(match.range(at: 1)))
                textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: shift(match.range(at: 3)))
                textStorage.addAttributes([
                    Attr.foregroundColor: Theme.boldColor,
                    Attr.font: styles.boldItalic
                ], range: shift(match.range(at: 2)))
            }

        case .italic:
            if match.numberOfRanges >= 3 {
                textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: shift(match.range(at: 1)))
                // Apply to the closing marker too
                let closingStart = shift(match.range(at: 2)).upperBound
                let closingRange = NSRange(location: closingStart, length: match.range(at: 1).length)
                if closingRange.upperBound <= textStorage.length {
                    textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: closingRange)
                }
                textStorage.addAttributes([
                    Attr.foregroundColor: Theme.italicColor,
                    Attr.font: styles.italic
                ], range: shift(match.range(at: 2)))
            }

        case .strikethrough:
            if match.numberOfRanges >= 4 {
                textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: shift(match.range(at: 1)))
                textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: shift(match.range(at: 3)))
                textStorage.addAttributes([
                    Attr.strikethroughStyle: Attr.singleUnderlineStyleValue,
                    Attr.foregroundColor: Theme.syntaxColor
                ], range: shift(match.range(at: 2)))
            }

        case .inlineCode:
            if match.numberOfRanges >= 4 {
                textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: shift(match.range(at: 1)))
                textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: shift(match.range(at: 3)))
                textStorage.addAttribute(Attr.font, value: styles.code, range: fullMatchRange)
                textStorage.addAttribute(Attr.foregroundColor, value: Theme.codeColor, range: shift(match.range(at: 2)))
            }

        case .link:
            if match.numberOfRanges >= 4 {
                textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: shift(match.range(at: 1)))
                textStorage.addAttribute(Attr.foregroundColor, value: Theme.linkColor, range: shift(match.range(at: 2)))
                textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: shift(match.range(at: 3)))
            }

        case .blockquote:
            if match.numberOfRanges >= 3 {
                textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: shift(match.range(at: 1)))
                textStorage.addAttribute(Attr.foregroundColor, value: Theme.blockquoteColor, range: shift(match.range(at: 2)))
            }

        case .listMarker, .syntax:
            textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: fullMatchRange)

        case .mathInline:
            if match.numberOfRanges >= 2 {
                let openRange = NSRange(location: fullMatchRange.location, length: 1)
                let closeRange = NSRange(location: fullMatchRange.location + fullMatchRange.length - 1, length: 1)
                textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: openRange)
                textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: closeRange)
                textStorage.addAttribute(Attr.foregroundColor, value: Theme.mathColor, range: shift(match.range(at: 1)))
            }

        case .highlight:
            if match.numberOfRanges >= 4 {
                textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: shift(match.range(at: 1)))
                textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: shift(match.range(at: 3)))
                textStorage.addAttributes([
                    Attr.foregroundColor: Theme.highlightColor,
                    Attr.backgroundColor: Theme.highlightBackgroundColor
                ], range: shift(match.range(at: 2)))
            }

        case .footnote:
            textStorage.addAttribute(Attr.foregroundColor, value: Theme.footnoteColor, range: fullMatchRange)

        case .htmlTag:
            textStorage.addAttribute(Attr.foregroundColor, value: Theme.htmlTagColor, range: fullMatchRange)

        case .codeBlock, .mathBlock, .frontmatter:
            // Block styles are handled by the callers, which know whether
            // they're doing a full pass (protect + style) or an incremental
            // fence-line touch-up.
            break
        }
    }

    // MARK: - Incremental Highlighting

    /// Block-level delimiters that can change the meaning of everything below them.
    /// If the edited region contains one, fall back to full re-highlight.
    private static let blockDelimiterRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "^(`{3,}|\\${2}|---\\s*$)", options: .anchorsMatchLines
    )

    private func rebuildProtectedRanges(for text: String) -> [ProtectedRange] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var protectedRanges: [ProtectedRange] = []

        Self.frontmatterBlockRegex?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            let matchedText = nsText.substring(with: match.range)
            guard FrontmatterSupport.extract(from: matchedText) != nil else { return }
            protectedRanges.append(ProtectedRange(range: match.range, kind: .frontmatter))
        }

        Self.fencedCodeBlockRegex?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            protectedRanges.append(ProtectedRange(range: match.range, kind: .code))
        }

        Self.displayMathBlockRegex?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            protectedRanges.append(ProtectedRange(range: match.range, kind: .math))
        }

        protectedRanges.sort { lhs, rhs in
            lhs.range.location < rhs.range.location
        }
        return protectedRanges
    }

    /// Re-highlight only the region around the edit, expanded to paragraph boundaries.
    /// Falls back to highlightAll if the edit touches a block delimiter (```, $$, ---).
    public func highlightAround(_ textStorage: PlatformTextStorage, editedRange: NSRange, replacementLength: Int, caller: String = "") {
        guard !isHighlighting else { return }

        // Live view of the backing store — bridging `textStorage.string` to a
        // Swift String snapshots the whole document (NSMutableString.copy),
        // which is exactly the per-keystroke O(n) this path exists to avoid.
        let storageText = textStorage.mutableString

        // Compute the post-edit affected range and expand to paragraph boundaries.
        // iOS predictive text / marked-text composition can fire textViewDidChange
        // without a matching shouldChangeTextIn, so the cached editedRange may no
        // longer fit the live string. Validate before calling paragraphRange, which
        // throws NSRangeException on out-of-bounds input.
        let textLength = storageText.length
        let safeLocation = max(0, min(editedRange.location, textLength))
        let safeLength = max(0, min(replacementLength, textLength - safeLocation))
        if safeLocation != editedRange.location || safeLength != replacementLength {
            highlightAll(textStorage, caller: "\(caller)-stale-range")
            return
        }
        let postEditRange = NSRange(location: safeLocation, length: safeLength)
        let paragraphRange = storageText.paragraphRange(for: postEditRange)

        // A "paragraph" here is a `\n`-bounded run. A file with no newlines (binary blob,
        // pasted log dump) is one paragraph the size of the whole file — running the regex
        // pipeline over multi-MB input is the catastrophic case. Bail; the file-size cap on
        // open already keeps these out of the editor in normal use.
        guard paragraphRange.length <= Limits.maxHighlightAllLength else {
            DiagnosticLog.log("MarkdownSyntaxHighlighter: skipping highlightAround over \(paragraphRange.length)-char paragraph")
            return
        }

        // Everything below matches against the paragraph substring with
        // ranges mapped back through `offset` — never against the full text.
        let paragraphText = storageText.substring(with: paragraphRange)
        let offset = paragraphRange.location
        let localRange = NSRange(location: 0, length: paragraphRange.length)

        // If the edited paragraph contains a block delimiter, the change could affect
        // everything below (opening/closing a code block or math block). Signal the caller
        // to schedule a deferred full re-highlight, but still highlight the current paragraph
        // immediately for responsive feedback.
        let editedBlockDelimiter = Self.blockDelimiterRegex?.firstMatch(
            in: paragraphText,
            range: localRange
        ) != nil
        if editedBlockDelimiter {
            needsFullHighlight = true
        }

        isHighlighting = true
        defer { isHighlighting = false }
        let startTime = CACurrentMediaTime()
        let styles = Styles.current()

        textStorage.beginEditing()

        // Reset attributes in the affected range. Only reset font/paragraph/baseline
        // when the range actually has non-default fonts (headings, code, bold, italic).
        // Skipping the font reset for plain text avoids glyph regeneration, which is
        // the main per-keystroke cost on large documents.
        var needsFontReset = false
        textStorage.enumerateAttribute(Attr.font, in: paragraphRange, options: .longestEffectiveRangeNotRequired) { value, _, stop in
            if let font = value as? PlatformFont, font != styles.body {
                needsFontReset = true
                stop.pointee = true
            }
        }

        if needsFontReset {
            let paragraph = PlatformParagraphStyle()
            paragraph.minimumLineHeight = styles.lineHeight
            paragraph.maximumLineHeight = styles.lineHeight
            textStorage.addAttributes([
                Attr.font: styles.body,
                Attr.paragraphStyle: paragraph,
                Attr.baselineOffset: styles.baselineOffset
            ], range: paragraphRange)
        }
        textStorage.addAttribute(Attr.foregroundColor, value: Theme.textColor, range: paragraphRange)
        textStorage.removeAttribute(Attr.backgroundColor, range: paragraphRange)
        textStorage.removeAttribute(Attr.strikethroughStyle, range: paragraphRange)

        // Keep cached protected ranges aligned with the edit. Most edits can cheaply
        // shift the cached ranges; block delimiters need a full protected-range rescan
        // so semantic queries stay correct until the deferred highlightAll runs.
        let protectedRanges: [ProtectedRange]
        if editedBlockDelimiter {
            // Keep protected-range queries correct until the deferred highlightAll runs.
            // (Rebuilding needs the whole document — the one remaining full-copy
            // path in incremental highlighting, taken only on delimiter edits.)
            protectedRanges = rebuildProtectedRanges(for: textStorage.string)
        } else {
            let delta = replacementLength - editedRange.length
            var shiftedProtectedRanges: [ProtectedRange] = []
            shiftedProtectedRanges.reserveCapacity(cachedProtectedRanges.count)
            for protectedRange in cachedProtectedRanges {
                let range = protectedRange.range
                if NSMaxRange(range) <= editedRange.location {
                    shiftedProtectedRanges.append(protectedRange)
                } else if range.location >= NSMaxRange(editedRange) {
                    shiftedProtectedRanges.append(ProtectedRange(
                        range: NSRange(location: range.location + delta, length: range.length),
                        kind: protectedRange.kind
                    ))
                } else {
                    shiftedProtectedRanges.append(ProtectedRange(
                        range: NSRange(location: range.location, length: max(0, range.length + delta)),
                        kind: protectedRange.kind
                    ))
                }
            }
            protectedRanges = shiftedProtectedRanges
        }
        cachedProtectedRanges = protectedRanges

        // If the paragraph is entirely inside a protected block, apply that block's base style.
        if let block = protectedRanges.first(where: { NSIntersectionRange($0.range, paragraphRange).length == paragraphRange.length }) {
            applyProtectedBlockStyle(block, to: textStorage, range: paragraphRange, paragraphText: paragraphText, styles: styles)
            textStorage.endEditing()
            let elapsed = (CACurrentMediaTime() - startTime) * 1000
            if elapsed >= Self.slowPassLogThresholdMs {
                DiagnosticLog.log("highlightAround(\(caller)): inside protected block, \(paragraphRange) in \(Int(elapsed))ms")
            }
            return
        }

        let merged = Self.mergedRanges(protectedRanges)

        // Run block patterns first (a fence line partially matching inside the
        // paragraph gets code styling), then inline patterns.
        for (regex, style) in Self.blockPatterns {
            regex.enumerateMatches(in: paragraphText, range: localRange) { match, _, _ in
                guard let match else { return }
                switch style {
                case .codeBlock:
                    // Code blocks are multi-line; handled via the full-document
                    // scan. Within the paragraph range, a match means we're at
                    // a fence line — color it as code.
                    let fullMatch = NSRange(location: match.range.location + offset, length: match.range.length)
                    textStorage.addAttributes([
                        Attr.font: styles.code,
                        Attr.foregroundColor: Theme.codeColor
                    ], range: fullMatch)
                    if match.numberOfRanges >= 2 {
                        let fence = match.range(at: 1)
                        textStorage.addAttribute(
                            Attr.foregroundColor, value: Theme.syntaxColor,
                            range: NSRange(location: fence.location + offset, length: fence.length)
                        )
                    }
                default:
                    // Math blocks and frontmatter are multi-line; skip in
                    // incremental mode (handled by the blockDelimiter check).
                    break
                }
            }
        }

        for (regex, style) in Self.inlinePatterns {
            regex.enumerateMatches(in: paragraphText, range: localRange) { match, _, _ in
                guard let match else { return }
                let globalRange = NSRange(location: match.range.location + offset, length: match.range.length)
                if Self.intersects(globalRange, merged: merged) { return }
                self.applyInlineStyle(style, match: match, offset: offset, to: textStorage, styles: styles)
            }
        }

        textStorage.endEditing()

        let elapsed = (CACurrentMediaTime() - startTime) * 1000
        if elapsed >= Self.slowPassLogThresholdMs {
            DiagnosticLog.log("highlightAround(\(caller)): \(paragraphRange) in \(Int(elapsed))ms")
        }
    }

    // MARK: - Public Query

    /// Returns true if the given character position is inside a code block, math block, or frontmatter.
    public func isInsideProtectedRange(at position: Int) -> Bool {
        cachedProtectedRanges.contains { NSLocationInRange(position, $0.range) }
    }

    private func applyProtectedBlockStyle(
        _ block: ProtectedRange,
        to textStorage: PlatformTextStorage,
        range: NSRange,
        paragraphText: String,
        styles: Styles
    ) {
        switch block.kind {
        case .code:
            textStorage.addAttributes([
                Attr.font: styles.code,
                Attr.foregroundColor: Theme.codeColor
            ], range: range)

        case .math:
            textStorage.addAttribute(Attr.foregroundColor, value: Theme.mathColor, range: range)

        case .frontmatter:
            textStorage.addAttribute(Attr.foregroundColor, value: Theme.frontmatterColor, range: range)
            guard let keyRegex = Self.frontmatterKeyRegex else { return }
            let localRange = NSRange(location: 0, length: range.length)
            keyRegex.enumerateMatches(in: paragraphText, range: localRange) { match, _, _ in
                guard let match, match.numberOfRanges >= 3 else { return }
                let keyRange = NSRange(
                    location: match.range(at: 1).location + range.location,
                    length: match.range(at: 1).length
                )
                let colonRange = NSRange(
                    location: match.range(at: 2).location + range.location,
                    length: match.range(at: 2).length
                )
                textStorage.addAttribute(Attr.foregroundColor, value: Theme.headingColor, range: keyRange)
                textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: colonRange)
            }
        }
    }
}
