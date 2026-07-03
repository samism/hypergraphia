import Foundation

public enum MermaidSupport {
    /// Base URL pointing to the bundle's resource directory,
    /// allowing WKWebView to load bundled JS files via relative <script src>.
    public static var resourceBaseURL: URL? {
        Bundle.main.resourceURL
    }

    /// Mermaid <script> tag + initialization JS for preview HTML.
    /// Vendored mermaid.min.js v11 — see Shared/Resources/mermaid.min.js
    public static var scriptHTML: String {
        guard let mermaidURL = resourceURL(named: "mermaid.min.js") else {
            return ""
        }

        return """
        <script src="\(mermaidURL)"></script>
        <script>
        (function() {
            var isDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
            // Diagrams dress like the document: colors come from the theme's
            // CSS variables and the label font is the body font, so mermaid
            // follows the user's font choice and light/dark appearance.
            var styles = getComputedStyle(document.body);
            function v(name) { return styles.getPropertyValue(name).trim(); }
            var labelSize = Math.round(parseFloat(styles.fontSize) * 0.85) + 'px';
            mermaid.initialize({
                startOnLoad: false,
                securityLevel: 'antiscript',
                theme: 'base',
                themeVariables: {
                    darkMode: isDark,
                    fontFamily: styles.fontFamily,
                    fontSize: labelSize,
                    background: v('--c-bg'),
                    mainBkg: v('--c-pre-bg'),
                    primaryColor: v('--c-pre-bg'),
                    primaryTextColor: v('--c-text'),
                    primaryBorderColor: v('--c-border-strong'),
                    secondaryColor: v('--c-blockquote-bg'),
                    secondaryBorderColor: v('--c-border-subtle'),
                    tertiaryColor: v('--c-row-hover-bg'),
                    tertiaryBorderColor: v('--c-border-subtle'),
                    textColor: v('--c-text'),
                    nodeTextColor: v('--c-text'),
                    titleColor: v('--c-text'),
                    lineColor: v('--c-caption'),
                    edgeLabelBackground: v('--c-bg'),
                    clusterBkg: v('--c-blockquote-bg'),
                    clusterBorder: v('--c-border-subtle'),
                    actorBkg: v('--c-pre-bg'),
                    actorBorder: v('--c-border-strong'),
                    actorTextColor: v('--c-text'),
                    actorLineColor: v('--c-caption'),
                    signalColor: v('--c-caption'),
                    signalTextColor: v('--c-text'),
                    labelBoxBkgColor: v('--c-pre-bg'),
                    labelBoxBorderColor: v('--c-border-strong'),
                    labelTextColor: v('--c-text'),
                    loopTextColor: v('--c-text'),
                    noteBkgColor: v('--c-blockquote-bg'),
                    noteTextColor: v('--c-text'),
                    noteBorderColor: v('--c-border-subtle')
                },
                flowchart: { curve: 'basis' }
            });
            document.querySelectorAll('pre code.language-mermaid').forEach(function(codeEl) {
                var pre = codeEl.parentElement;
                var container = document.createElement('div');
                container.className = 'mermaid';
                container.textContent = codeEl.textContent;
                var sp = pre.getAttribute('data-sourcepos');
                if (sp) container.setAttribute('data-sourcepos', sp);
                pre.replaceWith(container);
            });
            mermaid.run().then(function() {
                window.__mermaidReady = true;
                window.dispatchEvent(new Event('mermaid-ready'));
                if (window._scheduleCacheRebuild) {
                    window._scheduleCacheRebuild();
                }
            });
        })();
        </script>
        """
    }

    private static func resourceURL(named name: String) -> String? {
        Bundle.main.url(forResource: name, withExtension: nil)?.absoluteString
    }
}

public enum MathSupport {
    // MathJax/Obsidian whitespace rule + markdown-it-katex "no digit after close" — blocks currency like `$5.12 on soda and $4.42`.
    public static let inlineMathPattern =
        #"(?<![\\$])\$(?![\s$])([^\n$]+?)(?<![\s\\$])\$(?![\d$])"#

    public static let displayMathPattern = #"\$\$(.+?)\$\$"#

    public static func scriptHTML(for htmlBody: String) -> String {
        guard htmlBody.contains("math-inline") || htmlBody.contains("math-block") else {
            return ""
        }

        guard let cssURL = Bundle.main.url(forResource: "katex.min.css", withExtension: nil)?.absoluteString,
              let jsURL = Bundle.main.url(forResource: "katex.min.js", withExtension: nil)?.absoluteString else {
            return ""
        }

        return """
        <link rel="stylesheet" href="\(cssURL)">
        <script src="\(jsURL)"></script>
        <script>
        if (window.katex) {
            document.querySelectorAll('.math-block').forEach(function(el) {
                katex.render(el.textContent, el, { displayMode: true, throwOnError: false });
            });
            document.querySelectorAll('.math-inline').forEach(function(el) {
                katex.render(el.textContent, el, { displayMode: false, throwOnError: false });
            });
        }
        </script>
        """
    }
}
