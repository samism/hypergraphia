import Foundation

/// Semantic color tokens used by the preview/export HTML. A `PreviewPalette` carries one value per token;
/// `PreviewCSS.css(...)` emits three palettes as `:root` blocks (base, dark, print) and rule bodies reference
/// tokens exclusively via `var(--c-*)` — no hex/rgba literals live in selectors.
public struct PreviewPalette: Sendable {
    public var text: String
    public var headingSecondary: String
    public var background: String
    public var accent: String
    public var link: String
    public var wiki: String
    public var wikiBorder: String
    public var wikiBroken: String
    public var wikiBrokenBorder: String
    public var tag: String
    public var tagBg: String
    public var tagBgHover: String
    public var codeBg: String
    public var codeFg: String
    public var codeFilenameBg: String
    public var codeFilenameFg: String
    public var preBg: String
    public var preFg: String
    public var btnBg: String
    public var btnBgHover: String
    public var btnBgActive: String
    public var btnFg: String
    public var btnSuccess: String
    public var blockquoteBg: String
    public var blockquoteFg: String
    public var borderSubtle: String
    public var borderStrong: String
    public var thHoverBg: String
    public var rowHoverBg: String
    public var caption: String
    public var hrBorder: String
    public var markBg: String
    public var calloutDefault: String
    public var calloutTip: String
    public var calloutImportant: String
    public var calloutWarning: String
    public var calloutCaution: String
    public var calloutAbstract: String
    public var calloutExample: String
    public var calloutQuote: String
    public var calloutQuestion: String
    public var tocBg: String
    public var anchor: String
    public var popoverBg: String
    public var popoverCodeBg: String
    public var popoverShadow1: String
    public var popoverShadow2: String
    public var frontmatterBg: String
    public var lightboxBg: String
    public var mermaidLightboxBg: String
    public var lightboxControlSurface: String
    public var lightboxControlSurfaceHover: String
    public var lightboxControlBorder: String
    public var lightboxControlButtonHover: String

    public init(
        text: String,
        headingSecondary: String,
        background: String,
        accent: String,
        link: String,
        wiki: String,
        wikiBorder: String,
        wikiBroken: String,
        wikiBrokenBorder: String,
        tag: String,
        tagBg: String,
        tagBgHover: String,
        codeBg: String,
        codeFg: String,
        codeFilenameBg: String,
        codeFilenameFg: String,
        preBg: String,
        preFg: String,
        btnBg: String,
        btnBgHover: String,
        btnBgActive: String,
        btnFg: String,
        btnSuccess: String,
        blockquoteBg: String,
        blockquoteFg: String,
        borderSubtle: String,
        borderStrong: String,
        thHoverBg: String,
        rowHoverBg: String,
        caption: String,
        hrBorder: String,
        markBg: String,
        calloutDefault: String,
        calloutTip: String,
        calloutImportant: String,
        calloutWarning: String,
        calloutCaution: String,
        calloutAbstract: String,
        calloutExample: String,
        calloutQuote: String,
        calloutQuestion: String,
        tocBg: String,
        anchor: String,
        popoverBg: String,
        popoverCodeBg: String,
        popoverShadow1: String,
        popoverShadow2: String,
        frontmatterBg: String,
        lightboxBg: String,
        mermaidLightboxBg: String,
        lightboxControlSurface: String,
        lightboxControlSurfaceHover: String,
        lightboxControlBorder: String,
        lightboxControlButtonHover: String
    ) {
        self.text = text
        self.headingSecondary = headingSecondary
        self.background = background
        self.accent = accent
        self.link = link
        self.wiki = wiki
        self.wikiBorder = wikiBorder
        self.wikiBroken = wikiBroken
        self.wikiBrokenBorder = wikiBrokenBorder
        self.tag = tag
        self.tagBg = tagBg
        self.tagBgHover = tagBgHover
        self.codeBg = codeBg
        self.codeFg = codeFg
        self.codeFilenameBg = codeFilenameBg
        self.codeFilenameFg = codeFilenameFg
        self.preBg = preBg
        self.preFg = preFg
        self.btnBg = btnBg
        self.btnBgHover = btnBgHover
        self.btnBgActive = btnBgActive
        self.btnFg = btnFg
        self.btnSuccess = btnSuccess
        self.blockquoteBg = blockquoteBg
        self.blockquoteFg = blockquoteFg
        self.borderSubtle = borderSubtle
        self.borderStrong = borderStrong
        self.thHoverBg = thHoverBg
        self.rowHoverBg = rowHoverBg
        self.caption = caption
        self.hrBorder = hrBorder
        self.markBg = markBg
        self.calloutDefault = calloutDefault
        self.calloutTip = calloutTip
        self.calloutImportant = calloutImportant
        self.calloutWarning = calloutWarning
        self.calloutCaution = calloutCaution
        self.calloutAbstract = calloutAbstract
        self.calloutExample = calloutExample
        self.calloutQuote = calloutQuote
        self.calloutQuestion = calloutQuestion
        self.tocBg = tocBg
        self.anchor = anchor
        self.popoverBg = popoverBg
        self.popoverCodeBg = popoverCodeBg
        self.popoverShadow1 = popoverShadow1
        self.popoverShadow2 = popoverShadow2
        self.frontmatterBg = frontmatterBg
        self.lightboxBg = lightboxBg
        self.mermaidLightboxBg = mermaidLightboxBg
        self.lightboxControlSurface = lightboxControlSurface
        self.lightboxControlSurfaceHover = lightboxControlSurfaceHover
        self.lightboxControlBorder = lightboxControlBorder
        self.lightboxControlButtonHover = lightboxControlButtonHover
    }

    /// Palette applied by default (base `:root`). Notes-style light paper with yellow accent.
    public static let light = PreviewPalette(
        text: "#1C1C1E",
        headingSecondary: "rgba(28, 28, 30, 0.55)",
        background: "#FFFFFF",
        accent: "#FFCC00",
        link: "#997000",
        wiki: "#997000",
        wikiBorder: "rgba(153, 112, 0, 0.32)",
        wikiBroken: "#6E5200",
        wikiBrokenBorder: "rgba(110, 82, 0, 0.4)",
        tag: "#997000",
        tagBg: "rgba(0, 0, 0, 0.05)",
        tagBgHover: "rgba(255, 204, 0, 0.14)",
        codeBg: "rgba(0, 0, 0, 0.06)",
        codeFg: "#1C1C1E",
        codeFilenameBg: "#F2F2F7",
        codeFilenameFg: "#6E6E73",
        preBg: "#F2F2F7",
        preFg: "#1C1C1E",
        btnBg: "rgba(0, 0, 0, 0.06)",
        btnBgHover: "rgba(0, 0, 0, 0.10)",
        btnBgActive: "rgba(0, 0, 0, 0.14)",
        btnFg: "#6E6E73",
        btnSuccess: "#34C759",
        blockquoteBg: "rgba(0, 0, 0, 0.05)",
        blockquoteFg: "#3A3A3C",
        borderSubtle: "rgba(0, 0, 0, 0.08)",
        borderStrong: "rgba(0, 0, 0, 0.16)",
        thHoverBg: "rgba(0, 0, 0, 0.04)",
        rowHoverBg: "rgba(0, 0, 0, 0.03)",
        caption: "#6E6E73",
        hrBorder: "rgba(0, 0, 0, 0.12)",
        markBg: "rgba(255, 204, 0, 0.35)",
        calloutDefault: "rgba(0, 0, 0, 0.05)",
        calloutTip: "rgba(0, 0, 0, 0.05)",
        calloutImportant: "rgba(0, 0, 0, 0.05)",
        calloutWarning: "rgba(255, 204, 0, 0.14)",
        calloutCaution: "rgba(255, 59, 48, 0.09)",
        calloutAbstract: "rgba(0, 0, 0, 0.05)",
        calloutExample: "rgba(0, 0, 0, 0.05)",
        calloutQuote: "rgba(0, 0, 0, 0.05)",
        calloutQuestion: "rgba(0, 0, 0, 0.05)",
        tocBg: "rgba(0, 0, 0, 0.05)",
        anchor: "#B0A16A",
        popoverBg: "#FFFFFF",
        popoverCodeBg: "rgba(0, 0, 0, 0.06)",
        popoverShadow1: "rgba(0, 0, 0, 0.10)",
        popoverShadow2: "rgba(0, 0, 0, 0.06)",
        frontmatterBg: "rgba(0, 0, 0, 0.05)",
        lightboxBg: "rgba(0, 0, 0, 0.75)",
        mermaidLightboxBg: "rgba(245, 245, 247, 0.94)",
        lightboxControlSurface: "rgba(40, 40, 40, 0.92)",
        lightboxControlSurfaceHover: "rgba(60, 60, 60, 0.95)",
        lightboxControlBorder: "rgba(255, 255, 255, 0.08)",
        lightboxControlButtonHover: "rgba(255, 255, 255, 0.14)"
    )

    /// Palette applied inside `@media (prefers-color-scheme: dark)`: Notes charcoal with yellow accent.
    public static let dark = PreviewPalette(
        text: "#F2F2F7",
        headingSecondary: "rgba(242, 242, 247, 0.55)",
        background: "#1C1C1E",
        accent: "#FFD60A",
        link: "#FFD60A",
        wiki: "#FFD60A",
        wikiBorder: "rgba(255, 214, 10, 0.35)",
        wikiBroken: "#E6C84F",
        wikiBrokenBorder: "rgba(230, 200, 79, 0.45)",
        tag: "#FFD60A",
        tagBg: "rgba(255, 255, 255, 0.08)",
        tagBgHover: "rgba(255, 214, 10, 0.16)",
        codeBg: "#2C2C2E",
        codeFg: "#F2F2F7",
        codeFilenameBg: "#2C2C2E",
        codeFilenameFg: "#A1A1A6",
        preBg: "#2C2C2E",
        preFg: "#F2F2F7",
        btnBg: "rgba(255, 255, 255, 0.08)",
        btnBgHover: "rgba(255, 255, 255, 0.12)",
        btnBgActive: "rgba(255, 255, 255, 0.16)",
        btnFg: "#D1D1D6",
        btnSuccess: "#30D158",
        blockquoteBg: "#2C2C2E",
        blockquoteFg: "#E5E5EA",
        borderSubtle: "rgba(255, 255, 255, 0.10)",
        borderStrong: "rgba(255, 255, 255, 0.18)",
        thHoverBg: "rgba(255, 255, 255, 0.06)",
        rowHoverBg: "rgba(255, 255, 255, 0.04)",
        caption: "#A1A1A6",
        hrBorder: "rgba(255, 255, 255, 0.14)",
        markBg: "rgba(255, 214, 10, 0.32)",
        calloutDefault: "#2C2C2E",
        calloutTip: "#2C2C2E",
        calloutImportant: "#2C2C2E",
        calloutWarning: "rgba(255, 214, 10, 0.13)",
        calloutCaution: "rgba(255, 69, 58, 0.16)",
        calloutAbstract: "#2C2C2E",
        calloutExample: "#2C2C2E",
        calloutQuote: "rgba(255, 255, 255, 0.08)",
        calloutQuestion: "#2C2C2E",
        tocBg: "#2C2C2E",
        anchor: "rgba(255, 214, 10, 0.30)",
        popoverBg: "#2C2C2E",
        popoverCodeBg: "#3A3A3C",
        popoverShadow1: "rgba(0, 0, 0, 0.55)",
        popoverShadow2: "rgba(255, 255, 255, 0.08)",
        frontmatterBg: "#2C2C2E",
        lightboxBg: "rgba(0, 0, 0, 0.75)",
        mermaidLightboxBg: "rgba(0, 0, 0, 0.85)",
        lightboxControlSurface: "rgba(40, 40, 40, 0.92)",
        lightboxControlSurfaceHover: "rgba(60, 60, 60, 0.95)",
        lightboxControlBorder: "rgba(255, 255, 255, 0.08)",
        lightboxControlButtonHover: "rgba(255, 255, 255, 0.14)"
    )

    /// Palette applied inside `@media print` (and inlined into `:root` when `forExport: true`).
    /// Matches light, with print-friendly tag and mark contrast.
    public static let print: PreviewPalette = {
        var p = PreviewPalette.light
        p.tagBg = "rgba(255, 204, 0, 0.10)"
        p.markBg = "rgba(255, 204, 0, 0.45)"
        return p
    }()
}

public enum PreviewCSS {
    private static let sansFontFamily = "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"Helvetica Neue\", Arial, sans-serif"
    private static let monoFontFamily = "\"JetBrains Mono\", \"JetBrainsMono-Regular\", \"SF Mono\", SFMono-Regular, Menlo, monospace"

    /// Generates the preview/export stylesheet. Colors are driven by CSS custom properties defined in a
    /// `:root` block built from `light`; `@media (prefers-color-scheme: dark)` and `@media print` each
    /// redeclare `:root` with their respective palettes. When `forExport: true`, the print palette is
    /// inlined into the base `:root` so contexts that don't fire `@media print` (web-view-driven PDF
    /// export flows) still get the print colors.
    public static func css(
        fontSize: CGFloat = 18,
        fontFamily: String = "sanFrancisco",
        forExport: Bool = false,
        bodyMaxWidth: String = "61em",
        light: PreviewPalette = .light,
        dark: PreviewPalette = .dark,
        print: PreviewPalette = .print
    ) -> String {
        let bodyFontFamily: String
        let headingFontFamily: String
        switch fontFamily {
        case "newYork":
            bodyFontFamily = "\"New York\", \"Iowan Old Style\", Georgia, serif"
            headingFontFamily = "\"New York\", \"Iowan Old Style\", Georgia, serif"
        case "sfMono":
            bodyFontFamily = Self.monoFontFamily
            headingFontFamily = Self.monoFontFamily
        default:
            bodyFontFamily = Self.sansFontFamily
            headingFontFamily = Self.sansFontFamily
        }

        let basePalette = forExport ? print : light
        let baseRoot = rootBlock(for: basePalette, selector: ":root")
        let darkRoot = rootBlock(for: dark, selector: ":root", indent: "    ")
        let printRoot = rootBlock(for: print, selector: ":root", indent: "    ")
        let darkBlock = "@media (prefers-color-scheme: dark) {\n\(darkRoot)\n}"
        let printBlock = "@media print {\n\(printRoot)\n}"

        let exportStructural = forExport ? """
        .live-editor { display: none !important; }
        .live-img-zoom { display: none !important; }
        .code-copy-btn { display: none !important; }
        .code-fold-btn { display: none !important; }
        .code-block-wrapper.is-folded > pre { display: block !important; }
        .code-block-wrapper.is-folded > .code-fold-summary { display: none !important; }
        .table-copy-btn { display: none !important; }
        .sort-indicator { display: none !important; }
        thead { position: static !important; display: table-header-group; }
        tr:hover td { background-color: transparent !important; }
        th { cursor: default !important; }
        body {
            max-width: none !important;
            margin: 0 !important;
            padding: 0 !important;
        }
        details.callout > summary::before { content: "" !important; }
        .heading-anchor { display: none !important; }
        .lightbox-overlay { display: none !important; }
        .mermaid-lightbox { display: none !important; }
        .mermaid-zoom-icon { display: none !important; }
        .mermaid-wrapper .mermaid,
        .mermaid-wrapper .mermaid svg { cursor: default !important; }
        .footnote-popover { display: none !important; }
        .wiki-link, .wiki-link-broken { border-bottom: none !important; }
        .callout { border: none !important; }
        .page-break {
            height: 0 !important;
            border: none !important;
            margin: 0 !important;
        }
        h1, h2, h3, h4, h5, h6 {
            page-break-after: avoid;
            break-after: avoid;
            page-break-inside: avoid;
            break-inside: avoid;
        }
        p, pre, blockquote, table, .frontmatter, .math-block, .mermaid, img, ul, ol {
            page-break-inside: avoid;
            break-inside: avoid;
        }
        tr {
            page-break-inside: avoid;
            break-inside: avoid;
        }
        img {
            display: block;
        }
        """ : ""

        return """
        \(baseRoot)

        \(darkBlock)

        \(printBlock)

        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: \(bodyFontFamily);
            font-size: \(Int(fontSize))px;
            line-height: 1.45;
            font-weight: 400;
            max-width: \(bodyMaxWidth);
            margin: 0;
            padding-top: calc(env(safe-area-inset-top) + 42px);
            padding-right: calc(env(safe-area-inset-right) + 40px);
            /* VS Code-style overscroll: the last line can always reach the
               vertical middle of the viewport. */
            padding-bottom: calc(env(safe-area-inset-bottom) + 30vh);
            padding-left: calc(env(safe-area-inset-left) + 40px);
            color: var(--c-text);
            background-color: var(--c-bg);
            -webkit-font-smoothing: antialiased;
            -webkit-text-size-adjust: 100%;
        }

        h1, h2, h3, h4, h5, h6 {
            font-family: \(headingFontFamily);
            line-height: 1.18;
            margin-top: 1.2em;
            margin-bottom: 0.35em;
            letter-spacing: 0;
            position: relative;
        }

        body > *:first-child {
            margin-top: 0;
        }

        /* Frontmatter metadata */
        .frontmatter {
            margin-bottom: 1.5em;
            padding: 1em 1.25em;
            background-color: var(--c-frontmatter-bg);
            border-radius: 8px;
            font-size: 0.85em;
        }

        .frontmatter-anchor {
            height: 0;
            margin: 0;
            padding: 0;
        }

        .frontmatter dl {
            margin: 0;
        }

        .frontmatter .frontmatter-row {
            display: flex;
            gap: 0.5em;
            padding: 0.15em 0;
        }

        .frontmatter dt {
            font-weight: 600;
            color: var(--c-caption);
            min-width: 6em;
        }

        .frontmatter dt::after {
            content: ":";
        }

        .frontmatter dd {
            margin: 0;
            color: var(--c-text);
            white-space: pre-wrap;
        }

        .frontmatter pre {
            margin: 0;
            padding: 0 !important;
            background: none !important;
            border: 0 !important;
            color: inherit !important;
            white-space: pre-wrap;
            font-size: 0.95em;
        }

        h1 { font-size: 1.7em; font-weight: 700; }
        h2 { font-size: 1.35em; font-weight: 700; }
        h3 { font-size: 1.1em; font-weight: 700; }
        h4 { font-size: 1em; font-weight: 700; }
        h5 { font-size: 1em; font-weight: 600; }
        h6 { font-size: 0.9375em; font-weight: 600; text-transform: uppercase; letter-spacing: 0.05em; color: var(--c-heading-secondary); }

        p {
            margin-bottom: 0.85em;
        }

        a {
            color: var(--c-link);
            text-decoration: underline;
            text-decoration-color: color-mix(in srgb, var(--c-link) 45%, transparent);
            text-underline-offset: 2px;
        }
        a:hover {
            text-decoration-color: var(--c-link);
        }
        sup a, a.footnote-backref {
            text-decoration: none;
        }
        .wiki-link {
            color: var(--c-wiki);
            text-decoration: none;
            border-bottom: 1px solid var(--c-wiki-border);
        }
        .wiki-link:hover {
            text-decoration: none;
            border-bottom-color: var(--c-wiki);
        }
        .wiki-link-broken {
            color: var(--c-wiki-broken);
            border-bottom: 1px dashed var(--c-wiki-broken-border);
        }
        .wiki-link-broken:hover {
            text-decoration: none;
            border-bottom-color: var(--c-wiki-broken);
        }
        .md-tag {
            color: var(--c-tag);
            text-decoration: none;
            background: var(--c-tag-bg);
            padding: 1px 5px;
            border-radius: 3px;
            font-size: 0.9em;
        }
        .md-tag:hover {
            background: var(--c-tag-bg-hover);
        }

        code {
            font-family: \(Self.monoFontFamily);
            font-size: 0.875em;
            background-color: var(--c-code-bg);
            color: var(--c-code-fg);
            padding: 0.125em 0.375em;
            border-radius: 4px;
        }

        .code-filename {
            font-family: \(Self.monoFontFamily);
            font-size: 0.8em;
            padding: 0.5em 1.25em;
            background: var(--c-code-filename-bg);
            border: none;
            border-radius: 8px 8px 0 0;
            color: var(--c-code-filename-fg);
        }

        pre {
            position: relative;
            background-color: var(--c-pre-bg);
            border: none;
            border-radius: 8px;
            padding: 1.125em 1.25em;
            margin-bottom: 1.25em;
            overflow-x: auto;
            color: var(--c-pre-fg);
        }

        .code-filename + pre {
            border-top-left-radius: 0;
            border-top-right-radius: 0;
            margin-top: 0;
        }

        .code-block-wrapper {
            position: relative;
            margin-bottom: 1.25em;
        }

        .code-block-wrapper > pre {
            margin-bottom: 0;
        }

        .code-block-wrapper:hover .code-copy-btn {
            opacity: 1;
        }

        .code-copy-btn {
            position: absolute;
            top: 6px;
            right: 6px;
            z-index: 1;
            width: 28px;
            height: 28px;
            padding: 0;
            margin: 0;
            border: none;
            border-radius: 5px;
            background: var(--c-btn-bg);
            color: var(--c-btn-fg);
            cursor: pointer;
            opacity: 0;
            transition: opacity 0.15s ease;
            display: flex;
            align-items: center;
            justify-content: center;
        }

        .code-copy-btn svg {
            display: block;
        }

        .code-copy-btn.copied {
            color: var(--c-btn-success);
        }

        .code-copy-btn:hover {
            background: var(--c-btn-bg-hover);
        }

        .code-copy-btn:active {
            background: var(--c-btn-bg-active);
        }

        .frontmatter .code-copy-btn {
            display: none;
        }

        .code-fold-btn {
            position: absolute;
            top: 6px;
            right: 40px;
            z-index: 1;
            width: 28px;
            height: 28px;
            padding: 0;
            margin: 0;
            border: none;
            border-radius: 5px;
            background: var(--c-btn-bg);
            color: var(--c-btn-fg);
            cursor: pointer;
            opacity: 0;
            transition: opacity 0.15s ease, transform 0.15s ease;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 14px;
            line-height: 1;
        }

        .code-block-wrapper:hover .code-fold-btn,
        .code-block-wrapper.is-folded .code-fold-btn {
            opacity: 1;
        }

        .code-block-wrapper.is-folded .code-fold-btn {
            transform: rotate(-90deg);
        }

        .code-fold-btn:hover {
            background: var(--c-btn-bg-hover);
        }

        .code-fold-btn:active {
            background: var(--c-btn-bg-active);
        }

        .code-fold-btn:focus-visible {
            outline: 2px solid var(--c-link);
            outline-offset: 2px;
        }

        .frontmatter .code-fold-btn {
            display: none;
        }

        .code-block-wrapper.is-folded > pre {
            display: none;
        }

        .code-block-wrapper.is-folded > .code-filename {
            border-radius: 8px 8px 0 0;
        }

        .code-fold-summary {
            display: none;
            font-family: \(Self.monoFontFamily);
            font-size: 0.8em;
            padding: 1.125em 1.25em;
            background-color: var(--c-pre-bg);
            color: var(--c-pre-fg);
            border-radius: 8px;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
            opacity: 0.85;
            cursor: pointer;
        }

        .code-block-wrapper.is-folded > .code-fold-summary {
            display: block;
        }

        .code-block-wrapper.is-folded > .code-filename + .code-fold-summary {
            border-radius: 0 0 8px 8px;
        }

        .code-fold-lang {
            display: inline-block;
            padding: 0 0.5em;
            margin-right: 0.5em;
            border-radius: 3px;
            background: var(--c-code-filename-bg);
            color: var(--c-code-filename-fg);
        }

        .code-fold-firstline {
            opacity: 0.85;
        }

        .code-fold-meta {
            margin-left: 0.5em;
            opacity: 0.65;
        }

        pre code {
            background: none;
            color: inherit;
            padding: 0;
            font-size: 0.875em;
        }

        blockquote {
            position: relative;
            border: none;
            background-color: transparent;
            padding: 0.1em 0 0.1em calc(0.95em + 3px);
            margin-left: 0;
            margin-bottom: 1em;
            color: var(--c-blockquote-fg);
        }
        /* The bar lives on a pseudo-element so it keeps square ends even
           when the block itself gets rounded hover treatment. */
        blockquote::before {
            content: "";
            position: absolute;
            left: 0;
            top: 0;
            bottom: 0;
            width: 3px;
            background-color: var(--c-border-strong);
        }
        blockquote > *:last-child {
            margin-bottom: 0;
        }

        ul, ol {
            margin-bottom: 0.85em;
            padding-left: 1.45em;
        }

        li {
            margin-bottom: 0.18em;
        }

        /* Task lists. cmark-gfm emits plain <li><input type="checkbox">
           without task-list classes, so hook on structure via :has(). */
        ul:has(> li > input[type="checkbox"]) {
            list-style: none;
            padding-left: 0;
        }

        li:has(> input[type="checkbox"]) {
            display: flex;
            align-items: flex-start;
            gap: 0.5em;
        }

        /* Notes-style circular checkboxes: gray ring, filled yellow with a
           dark check when done (black-on-yellow reads better than white at
           small sizes). Drawn as a background SVG because WebKit doesn't
           render ::after on inputs. */
        li > input[type="checkbox"] {
            -webkit-appearance: none;
            appearance: none;
            /* Form controls don't inherit font; without this, WebKit resolves
               the em/lh units below against the ~13px UA control font and the
               circle renders small and rides high of the text. */
            font: inherit;
            width: 1.15em;
            height: 1.15em;
            margin: 0;
            /* Center the circle on the first text line: (line box − circle) / 2. */
            margin-top: calc((1lh - 1.15em) / 2);
            flex-shrink: 0;
            border: 1.5px solid color-mix(in srgb, var(--c-text) 30%, transparent);
            border-radius: 50%;
            background-color: transparent;
            cursor: pointer;
            -webkit-print-color-adjust: exact;
            print-color-adjust: exact;
        }

        li > input[type="checkbox"]:checked {
            border-color: var(--c-accent);
            background-color: var(--c-accent);
            background-image: url('data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"%3E%3Cpath d="M4.2 8.6l2.5 2.5 5.1-5.7" fill="none" stroke="%231C1C1E" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/%3E%3C/svg%3E');
            background-size: 78% 78%;
            background-position: center;
            background-repeat: no-repeat;
        }

        /* Tables */
        .table-shell {
            position: relative;
            overflow: visible;
            margin-bottom: 1em;
            --table-copy-top: 6px;
        }

        .table-shell.has-copy-btn::after {
            content: "";
            position: absolute;
            top: calc(var(--table-copy-top) - 6px);
            right: -44px;
            width: 44px;
            height: 40px;
            pointer-events: auto;
        }

        .table-wrapper {
            overflow-x: auto;
        }

        table {
            border-collapse: collapse;
            border: 1px solid var(--c-border-subtle);
            width: 100%;
            font-variant-numeric: tabular-nums;
        }

        th, td {
            padding: 0.625em 0.875em;
            max-width: 20em;
            overflow-wrap: break-word;
        }

        /* Notes tables are a full grid, not just row rules */
        th + th, td + td {
            border-left: 1px solid var(--c-border-subtle);
        }

        thead {
            position: sticky;
            top: 0;
            z-index: 1;
        }

        th {
            font-weight: 600;
            background-color: transparent;
            border-bottom: 1px solid var(--c-border-strong);
            cursor: pointer;
            user-select: none;
            white-space: nowrap;
        }

        th:hover {
            background-color: var(--c-th-hover-bg);
        }

        td {
            border-bottom: 1px solid var(--c-border-subtle);
        }

        tr:nth-child(even) {
            background-color: transparent;
        }

        tr:hover td {
            background-color: var(--c-row-hover-bg);
        }

        .sort-indicator {
            font-size: 0.7em;
            margin-left: 0.3em;
            opacity: 0.3;
        }

        th.sort-asc .sort-indicator,
        th.sort-desc .sort-indicator {
            opacity: 1;
        }

        caption {
            caption-side: top;
            text-align: left;
            font-size: 0.9em;
            font-weight: 500;
            color: var(--c-caption);
            padding-bottom: 0.5em;
        }

        .table-copy-btn {
            position: absolute;
            right: -36px;
            width: 28px;
            height: 28px;
            padding: 0;
            margin: 0;
            border: none;
            border-radius: 5px;
            background: var(--c-btn-bg);
            color: var(--c-btn-fg);
            cursor: pointer;
            opacity: 0;
            pointer-events: none;
            transform: translateX(-4px);
            transition: opacity 0.15s ease, transform 0.15s ease;
            display: flex;
            align-items: center;
            justify-content: center;
            z-index: 2;
        }

        .table-copy-btn svg {
            display: block;
        }

        .table-copy-btn.copied {
            color: var(--c-btn-success);
        }

        .table-shell:hover .table-copy-btn,
        .table-copy-btn:hover,
        .table-copy-btn:focus-visible {
            opacity: 1;
            pointer-events: auto;
            transform: translateX(0);
        }

        .table-copy-btn:hover {
            background: var(--c-btn-bg-hover);
        }

        .table-copy-btn:active {
            background: var(--c-btn-bg-active);
        }

        /* Strikethrough */
        del {
            text-decoration: line-through;
            opacity: 0.6;
        }

        hr {
            border: none;
            border-top: 0.5px solid var(--c-hr-border);
            margin: 2.5em 0;
        }

        .page-break {
            display: block;
            height: 0;
            border-top: 1px dashed var(--c-border-strong);
            margin: 2em 0;
        }

        /* Highlight/Mark */
        mark {
            background-color: var(--c-mark-bg);
            color: inherit !important;
            padding: 0.1em 0.2em;
            border-radius: 3px;
        }
        /* Superscript/Subscript */
        sup, sub {
            font-size: 0.75em;
            line-height: 0;
        }

        /* Live mode (editable preview) */
        body.live-mode:not(:has(.live-block, .live-editor))::before {
            content: "Click to start writing";
            color: var(--c-caption);
        }
        body.live-mode .live-block {
            cursor: text;
            border-radius: 4px;
            transition: box-shadow 0.12s ease, background-color 0.12s ease;
        }
        body.live-mode .live-block:hover {
            background-color: var(--c-row-hover-bg);
            box-shadow: 0 0 0 5px var(--c-row-hover-bg);
        }
        /* Blocks that carry their own card background keep it (and their own
           radius) on hover — repainting them with the tint reads as flicker.
           The halo alone marks them. */
        body.live-mode pre.live-block { border-radius: 8px; }
        body.live-mode pre.live-block:hover { background-color: var(--c-pre-bg); }
        body.live-mode .frontmatter.live-block { border-radius: 8px; }
        body.live-mode .frontmatter.live-block:hover { background-color: var(--c-frontmatter-bg); }
        body.live-mode .toc.live-block { border-radius: 8px; }
        body.live-mode .toc.live-block:hover { background-color: var(--c-toc-bg); }
        /* A code card with a filename header hovers as one unit: the halo
           wraps the whole wrapper, not just the pre inside it. */
        body.live-mode .code-block-wrapper:has(pre.live-block:hover) {
            border-radius: 8px;
            box-shadow: 0 0 0 5px var(--c-row-hover-bg);
            transition: box-shadow 0.12s ease;
        }
        body.live-mode .code-block-wrapper pre.live-block:hover {
            box-shadow: none;
        }
        body.live-mode .code-block-wrapper .code-filename + pre.live-block {
            border-top-left-radius: 0;
            border-top-right-radius: 0;
        }
        body.live-mode.live-append-zone {
            cursor: text;
        }
        /* Images edit on click like any block; the hover button opens the
           lightbox instead. Overrides the inline zoom-in cursor. */
        body.live-mode .live-block img {
            cursor: text !important;
        }
        .live-img-zoom {
            position: absolute;
            width: 28px;
            height: 28px;
            display: flex;
            align-items: center;
            justify-content: center;
            border: none;
            padding: 0;
            border-radius: 5px;
            background: var(--c-popover-bg);
            color: var(--c-text);
            box-shadow: 0 1px 3px var(--c-popover-shadow-1);
            cursor: zoom-in;
            z-index: 50;
        }
        .live-editor {
            margin-bottom: 0.85em;
        }
        /* Bare in-place editing: the source text sits exactly where the
           rendered block was — no box, no border, just the caret. */
        .live-editor textarea {
            display: block;
            width: 100%;
            box-sizing: border-box;
            font: inherit;
            line-height: inherit;
            color: var(--c-text);
            caret-color: var(--c-accent);
            background: transparent;
            border: none;
            border-radius: 0;
            padding: 0;
            margin: 0;
            resize: none;
            outline: none;
            overflow: hidden;
            white-space: pre-wrap;
        }
        .live-editor textarea.live-mono {
            font-family: \(Self.monoFontFamily);
            font-size: 0.875em;
            line-height: 1.45;
        }
        /* Heading sources edit at their rendered scale. */
        .live-editor.live-h1 textarea { font-size: 1.7em; font-weight: 700; line-height: 1.18; }
        .live-editor.live-h2 textarea { font-size: 1.35em; font-weight: 700; line-height: 1.18; }
        .live-editor.live-h3 textarea { font-size: 1.1em; font-weight: 700; line-height: 1.18; }
        .live-editor.live-h4 textarea { font-size: 1em; font-weight: 700; line-height: 1.18; }
        .live-editor.live-h5 textarea { font-size: 1em; font-weight: 600; line-height: 1.18; }
        .live-editor.live-h6 textarea { font-size: 0.9375em; font-weight: 600; line-height: 1.18; }

        /* Callouts/Admonitions */
        .callout {
            border: none;
            border-radius: 8px;
            padding: 1em 1.25em;
            margin-bottom: 1.25em;
            background-color: var(--c-callout-default);
        }
        .callout-title {
            font-weight: 600;
            margin-bottom: 0.375em;
            display: flex;
            align-items: center;
            gap: 0.4em;
        }
        .callout-icon { flex-shrink: 0; }
        .callout-content > *:last-child { margin-bottom: 0; }
        .callout-content blockquote { padding-left: 0; color: inherit; }
        .callout-content blockquote::before { display: none; }

        details.callout > summary { cursor: pointer; list-style: none; }
        /* Collapsed foldable callouts: drop the title's bottom margin so the
           summary sits vertically centered in the card. */
        details.callout:not([open]) > summary { margin-bottom: 0; }
        details.callout > summary::-webkit-details-marker { display: none; }
        details.callout > summary::before { content: "▶"; font-size: 0.7em; margin-right: 0.3em; transition: transform 0.2s; display: inline-block; }
        details.callout[open] > summary::before { transform: rotate(90deg); }

        .callout-note, .callout-info { background-color: var(--c-callout-default); }
        .callout-tip { background-color: var(--c-callout-tip); }
        .callout-important { background-color: var(--c-callout-important); }
        .callout-warning { background-color: var(--c-callout-warning); }
        .callout-caution, .callout-danger { background-color: var(--c-callout-caution); }
        .callout-abstract { background-color: var(--c-callout-abstract); }
        .callout-todo { background-color: var(--c-callout-default); }
        .callout-example { background-color: var(--c-callout-example); }
        .callout-quote { background-color: var(--c-callout-quote); }
        .callout-bug, .callout-failure { background-color: var(--c-callout-caution); }
        .callout-success { background-color: var(--c-callout-tip); }
        .callout-question { background-color: var(--c-callout-question); }

        /* Table of Contents */
        .toc {
            background-color: var(--c-toc-bg);
            border: none;
            border-radius: 8px;
            padding: 1.25em 1.5em;
            margin-bottom: 1.5em;
        }
        .toc::before {
            content: "Table of Contents";
            display: block;
            font-weight: 600;
            font-size: 0.9em;
            margin-bottom: 0.5em;
            color: var(--c-caption);
        }
        .toc ul {
            margin-bottom: 0;
            padding-left: 1.2em;
            list-style: none;
        }
        .toc > ul { padding-left: 0; }
        .toc li { margin-bottom: 0.15em; }
        .toc a {
            color: var(--c-text);
            font-size: 0.9em;
            text-decoration: none;
        }
        .toc a:hover {
            color: var(--c-link);
        }

        /* Heading anchor links */
        .heading-anchor {
            position: absolute;
            left: -1.2em;
            opacity: 0;
            text-decoration: none;
            color: var(--c-anchor);
            font-weight: 400;
            transition: opacity 0.15s ease;
        }
        h1:hover .heading-anchor, h2:hover .heading-anchor, h3:hover .heading-anchor,
        h4:hover .heading-anchor, h5:hover .heading-anchor, h6:hover .heading-anchor {
            opacity: 0.4;
        }
        .heading-anchor:hover { opacity: 1 !important; }

        /* Collapsible details animation */
        details::details-content {
            transition: block-size 0.3s ease, opacity 0.3s ease, content-visibility 0.3s ease allow-discrete;
            block-size: 0;
            opacity: 0;
            overflow: clip;
        }
        details[open]::details-content {
            block-size: auto;
            opacity: 1;
        }

        /* Image lightbox */
        .lightbox-overlay {
            position: fixed;
            inset: 0;
            background: var(--c-lightbox-bg);
            display: flex;
            align-items: center;
            justify-content: center;
            z-index: 9999;
            cursor: zoom-out;
            opacity: 0;
            transition: opacity 0.2s ease;
        }
        .lightbox-img {
            max-width: 90vw;
            max-height: 90vh;
            object-fit: contain;
            border-radius: 7px;
        }

        /* Footnote popovers */
        .footnote-popover {
            position: absolute;
            max-width: 400px;
            padding: 14px 18px;
            background: var(--c-popover-bg);
            border: none;
            border-radius: 8px;
            box-shadow: 0 4px 20px var(--c-popover-shadow-1), 0 0 0 0.5px var(--c-popover-shadow-2);
            color: var(--c-text);
            font-size: 0.9em;
            z-index: 100;
            line-height: 1.5;
        }
        .footnote-popover p { margin-bottom: 0.5em; }
        .footnote-popover p:last-child { margin-bottom: 0; }
        .footnote-popover code {
            background-color: var(--c-popover-code-bg);
            color: var(--c-text);
        }

        .math-block {
            text-align: center;
            margin: 1em 0;
            overflow-x: auto;
        }

        .math-inline {
            display: inline;
        }

        img {
            max-width: 100%;
            height: auto;
        }

        .img-placeholder {
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 8px;
            padding: 24px 16px;
            border-radius: 8px;
            background-color: var(--c-blockquote-bg);
            border: 1px dashed var(--c-border-strong);
            color: var(--c-anchor);
            font-size: 0.85em;
            margin-bottom: 1em;
            overflow: hidden;
        }

        .img-placeholder span {
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }

        .img-placeholder svg {
            flex-shrink: 0;
            opacity: 0.5;
        }

        /* Mermaid diagrams */
        .mermaid {
            text-align: center;
            margin-bottom: 1em;
            overflow-x: auto;
            color: var(--c-text);
        }

        .mermaid svg {
            max-width: 100%;
            height: auto;
        }

        .mermaid-wrapper {
            position: relative;
            display: block;
        }
        .mermaid-wrapper .mermaid,
        .mermaid-wrapper .mermaid svg {
            cursor: zoom-in;
        }
        .mermaid-zoom-icon {
            position: absolute;
            top: 8px;
            right: 8px;
            width: 28px;
            height: 28px;
            display: flex;
            align-items: center;
            justify-content: center;
            border-radius: 5px;
            background: var(--c-popover-bg);
            color: var(--c-text);
            box-shadow: 0 1px 3px var(--c-popover-shadow-1);
            opacity: 0;
            transition: opacity 0.15s ease;
            pointer-events: none;
        }
        .mermaid-wrapper:hover .mermaid-zoom-icon {
            opacity: 0.9;
        }
        /* In live mode the diagram body edits on click, so the zoom icon
           becomes the (clickable) way into the lightbox. */
        body.live-mode .mermaid-zoom-icon {
            pointer-events: auto;
            cursor: zoom-in;
        }
        body.live-mode .mermaid-wrapper .mermaid,
        body.live-mode .mermaid-wrapper .mermaid svg {
            cursor: text;
        }

        .mermaid-lightbox {
            position: fixed;
            inset: 0;
            background: var(--c-mermaid-lightbox-bg);
            z-index: 10000;
            opacity: 0;
            transition: opacity 0.18s ease;
            touch-action: none;
            -webkit-user-select: none;
            user-select: none;
            outline: none;
        }
        .mermaid-lightbox.mermaid-lightbox--open {
            opacity: 1;
        }
        .mermaid-lightbox-stage {
            position: absolute;
            inset: max(16px, 5vh) max(16px, 5vw);
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .mermaid-lightbox-stage svg {
            width: 100% !important;
            height: 100% !important;
            max-width: none !important;
        }
        .mermaid-lightbox-controls {
            position: absolute;
            bottom: max(20px, env(safe-area-inset-bottom, 0px));
            left: 50%;
            transform: translateX(-50%);
            display: flex;
            align-items: center;
            gap: 2px;
            padding: 4px 6px;
            background: var(--c-lightbox-control-surface);
            border: 1px solid var(--c-lightbox-control-border);
            border-radius: 999px;
        }
        .mermaid-lightbox-controls button {
            background: transparent;
            border: none;
            color: #FFF;
            font-size: 14px;
            min-width: 32px;
            height: 28px;
            padding: 0 10px;
            border-radius: 999px;
            cursor: pointer;
            font-family: inherit;
        }
        .mermaid-lightbox-controls button:hover {
            background: var(--c-lightbox-control-button-hover);
        }
        .mermaid-lightbox-controls .zoom-readout {
            min-width: 52px;
            font-variant-numeric: tabular-nums;
            text-align: center;
            color: #FFF;
            opacity: 0.85;
            font-size: 12px;
            padding: 0 4px;
        }
        .mermaid-lightbox-close {
            position: absolute;
            top: max(16px, env(safe-area-inset-top, 0px));
            right: max(16px, env(safe-area-inset-right, 0px));
            width: 36px;
            height: 36px;
            display: flex;
            align-items: center;
            justify-content: center;
            border: 1px solid var(--c-lightbox-control-border);
            border-radius: 50%;
            background: var(--c-lightbox-control-surface);
            color: #FFF;
            cursor: pointer;
            padding: 0;
        }
        .mermaid-lightbox-close:hover {
            background: var(--c-lightbox-control-surface-hover);
        }

        @media print {
            mark {
                -webkit-print-color-adjust: exact;
                print-color-adjust: exact;
            }
            .callout {
                -webkit-print-color-adjust: exact;
                print-color-adjust: exact;
            }
            .code-copy-btn { display: none !important; }
            .code-fold-btn { display: none !important; }
            .code-block-wrapper.is-folded > pre { display: block !important; }
            .code-block-wrapper.is-folded > .code-fold-summary { display: none !important; }
            .table-copy-btn { display: none !important; }
            .sort-indicator { display: none !important; }
            thead { position: static !important; display: table-header-group; }
            tr:hover td { background-color: transparent !important; }
            th { cursor: default !important; }
            body {
                max-width: none;
                padding: 0;
                margin: 0;
            }
            .wiki-link, .wiki-link-broken { border-bottom: none !important; }
            details.callout > summary::before { content: "" !important; }
            .heading-anchor { display: none !important; }
            .lightbox-overlay { display: none !important; }
            .mermaid-lightbox { display: none !important; }
            .mermaid-zoom-icon { display: none !important; }
            .mermaid-wrapper .mermaid,
            .mermaid-wrapper .mermaid svg { cursor: default !important; }
            .footnote-popover { display: none !important; }
            .page-break {
                page-break-after: always;
                break-after: page;
                height: 0;
                border: none;
            }
            h1, h2, h3, h4, h5, h6 {
                page-break-after: avoid;
                break-after: avoid;
                page-break-inside: avoid;
                break-inside: avoid;
            }
            p, pre, blockquote, table, .frontmatter, .math-block, .mermaid, img, ul, ol {
                page-break-inside: avoid;
                break-inside: avoid;
            }
            tr {
                page-break-inside: avoid;
                break-inside: avoid;
            }
            img {
                display: block;
            }
        }
        \(exportStructural)
        """
    }

    /// Renders a `:root { ... }` block (or any single-selector variant) with the palette's tokens.
    /// Exposed so tests can compare block-level output without re-parsing the whole stylesheet.
    public static func rootBlock(for palette: PreviewPalette, selector: String = ":root", indent: String = "") -> String {
        let pairs: [(String, String)] = [
            ("--c-text", palette.text),
            ("--c-heading-secondary", palette.headingSecondary),
            ("--c-bg", palette.background),
            ("--c-accent", palette.accent),
            ("--c-link", palette.link),
            ("--c-wiki", palette.wiki),
            ("--c-wiki-border", palette.wikiBorder),
            ("--c-wiki-broken", palette.wikiBroken),
            ("--c-wiki-broken-border", palette.wikiBrokenBorder),
            ("--c-tag", palette.tag),
            ("--c-tag-bg", palette.tagBg),
            ("--c-tag-bg-hover", palette.tagBgHover),
            ("--c-code-bg", palette.codeBg),
            ("--c-code-fg", palette.codeFg),
            ("--c-code-filename-bg", palette.codeFilenameBg),
            ("--c-code-filename-fg", palette.codeFilenameFg),
            ("--c-pre-bg", palette.preBg),
            ("--c-pre-fg", palette.preFg),
            ("--c-btn-bg", palette.btnBg),
            ("--c-btn-bg-hover", palette.btnBgHover),
            ("--c-btn-bg-active", palette.btnBgActive),
            ("--c-btn-fg", palette.btnFg),
            ("--c-btn-success", palette.btnSuccess),
            ("--c-blockquote-bg", palette.blockquoteBg),
            ("--c-blockquote-fg", palette.blockquoteFg),
            ("--c-border-subtle", palette.borderSubtle),
            ("--c-border-strong", palette.borderStrong),
            ("--c-th-hover-bg", palette.thHoverBg),
            ("--c-row-hover-bg", palette.rowHoverBg),
            ("--c-caption", palette.caption),
            ("--c-hr-border", palette.hrBorder),
            ("--c-mark-bg", palette.markBg),
            ("--c-callout-default", palette.calloutDefault),
            ("--c-callout-tip", palette.calloutTip),
            ("--c-callout-important", palette.calloutImportant),
            ("--c-callout-warning", palette.calloutWarning),
            ("--c-callout-caution", palette.calloutCaution),
            ("--c-callout-abstract", palette.calloutAbstract),
            ("--c-callout-example", palette.calloutExample),
            ("--c-callout-quote", palette.calloutQuote),
            ("--c-callout-question", palette.calloutQuestion),
            ("--c-toc-bg", palette.tocBg),
            ("--c-anchor", palette.anchor),
            ("--c-popover-bg", palette.popoverBg),
            ("--c-popover-code-bg", palette.popoverCodeBg),
            ("--c-popover-shadow-1", palette.popoverShadow1),
            ("--c-popover-shadow-2", palette.popoverShadow2),
            ("--c-frontmatter-bg", palette.frontmatterBg),
            ("--c-lightbox-bg", palette.lightboxBg),
            ("--c-mermaid-lightbox-bg", palette.mermaidLightboxBg),
            ("--c-lightbox-control-surface", palette.lightboxControlSurface),
            ("--c-lightbox-control-surface-hover", palette.lightboxControlSurfaceHover),
            ("--c-lightbox-control-border", palette.lightboxControlBorder),
            ("--c-lightbox-control-button-hover", palette.lightboxControlButtonHover),
        ]
        let inner = pairs.map { "\(indent)    \($0.0): \($0.1);" }.joined(separator: "\n")
        return "\(indent)\(selector) {\n\(inner)\n\(indent)}"
    }
}
