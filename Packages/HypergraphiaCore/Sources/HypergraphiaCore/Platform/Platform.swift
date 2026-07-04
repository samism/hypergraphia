import Foundation
import SwiftUI

#if os(macOS)
import AppKit

public typealias PlatformFont = NSFont
public typealias PlatformColor = NSColor
public typealias PlatformImage = NSImage
public typealias PlatformPasteboard = NSPasteboard
public typealias PlatformTextView = NSTextView
public typealias PlatformTextStorage = NSTextStorage
public typealias PlatformParagraphStyle = NSMutableParagraphStyle
#elseif os(iOS)
import UIKit

public typealias PlatformFont = UIFont
public typealias PlatformColor = UIColor
public typealias PlatformImage = UIImage
public typealias PlatformPasteboard = UIPasteboard
public typealias PlatformTextView = UITextView
public typealias PlatformTextStorage = NSTextStorage
public typealias PlatformParagraphStyle = NSMutableParagraphStyle
#endif

public enum PlatformFontWeight {
    case regular
    case bold
}

public enum PlatformDevice {
    /// User-visible device name, used in conflict sibling filenames.
    public static func currentName() -> String {
        #if os(iOS)
        return UIDevice.current.name
        #else
        return Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        #endif
    }
}

public enum PlatformTextAttributes {
    public static let font = NSAttributedString.Key.font
    public static let foregroundColor = NSAttributedString.Key.foregroundColor
    public static let backgroundColor = NSAttributedString.Key.backgroundColor
    public static let paragraphStyle = NSAttributedString.Key.paragraphStyle
    public static let baselineOffset = NSAttributedString.Key.baselineOffset
    public static let strikethroughStyle = NSAttributedString.Key.strikethroughStyle
    public static let singleUnderlineStyleValue = NSUnderlineStyle.single.rawValue
}

public extension PlatformFont {
    static func clearlySansSystemFont(ofSize size: CGFloat, weight: PlatformFontWeight) -> PlatformFont {
        #if os(macOS)
        let platformWeight: NSFont.Weight = weight == .bold ? .bold : .regular
        return NSFont.systemFont(ofSize: size, weight: platformWeight)
        #else
        let platformWeight: UIFont.Weight = weight == .bold ? .bold : .regular
        return UIFont.systemFont(ofSize: size, weight: platformWeight)
        #endif
    }

    static func clearlyMonospacedSystemFont(ofSize size: CGFloat, weight: PlatformFontWeight) -> PlatformFont {
        #if os(macOS)
        let fontName = weight == .bold ? "JetBrainsMono-Bold" : "JetBrainsMono-Regular"
        if let font = NSFont(name: fontName, size: size) { return font }
        let platformWeight: NSFont.Weight = weight == .bold ? .bold : .regular
        return NSFont.monospacedSystemFont(ofSize: size, weight: platformWeight)
        #else
        let fontName = weight == .bold ? "JetBrainsMono-Bold" : "JetBrainsMono-Regular"
        if let font = UIFont(name: fontName, size: size) { return font }
        let platformWeight: UIFont.Weight = weight == .bold ? .bold : .regular
        return UIFont.monospacedSystemFont(ofSize: size, weight: platformWeight)
        #endif
    }

    /// Returns a font with italic trait applied. Falls back to `self` if unavailable.
    func withItalicTrait() -> PlatformFont {
        #if os(macOS)
        return NSFontManager.shared.convert(self, toHaveTrait: .italicFontMask)
        #else
        var traits = fontDescriptor.symbolicTraits
        traits.insert(.traitItalic)
        if let descriptor = fontDescriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: descriptor, size: pointSize)
        }
        return self
        #endif
    }

    /// Builds a bold + italic monospaced system font at the given size.
    static func clearlyMonospacedBoldItalic(size: CGFloat) -> PlatformFont {
        #if os(macOS)
        if let font = NSFont(name: "JetBrainsMono-BoldItalic", size: size) { return font }
        let bold = NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
        return NSFontManager.shared.convert(bold, toHaveTrait: .italicFontMask)
        #else
        if let font = UIFont(name: "JetBrainsMono-BoldItalic", size: size) { return font }
        let bold = UIFont.monospacedSystemFont(ofSize: size, weight: .bold)
        var traits = bold.fontDescriptor.symbolicTraits
        traits.insert(.traitItalic)
        if let descriptor = bold.fontDescriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return bold
        #endif
    }
}

public extension PlatformColor {
    static func clearlyColor(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> PlatformColor {
        #if os(macOS)
        return NSColor(red: red, green: green, blue: blue, alpha: alpha)
        #else
        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
        #endif
    }

    /// Loads a named color from the `HypergraphiaCore` asset catalog (`Bundle.module`).
    /// The asset must exist — unresolved names trap in app builds.
    static func clearlyAsset(named name: String) -> PlatformColor {
        #if os(macOS)
        if let color = NSColor(named: NSColor.Name(name), bundle: .module) {
            return color
        }
        #else
        if let color = UIColor(named: name, in: .module, compatibleWith: nil) {
            return color
        }
        #endif
        // Pure-SwiftPM builds (`swift test`) copy the raw .xcassets JSON into
        // the resource bundle instead of compiling it with actool, so named
        // lookup fails there even though every app build resolves it. Parse
        // the colorset JSON so core logic stays testable from the CLI.
        if let parsed = rawColorsetAsset(named: name) {
            return parsed
        }
        fatalError("Missing color asset '\(name)' in HypergraphiaCore Colors.xcassets")
    }

    /// Reads `Colors.xcassets/<name>.colorset/Contents.json` from
    /// `Bundle.module` and builds a dynamic light/dark color from it.
    private static func rawColorsetAsset(named name: String) -> PlatformColor? {
        guard let jsonURL = Bundle.module.url(
            forResource: "Contents",
            withExtension: "json",
            subdirectory: "Colors.xcassets/\(name).colorset"
        ),
        let data = try? Data(contentsOf: jsonURL),
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let colors = root["colors"] as? [[String: Any]] else { return nil }

        func component(_ components: [String: Any], _ key: String) -> CGFloat? {
            if let s = components[key] as? String, let v = Double(s) { return CGFloat(v) }
            if let v = components[key] as? Double { return CGFloat(v) }
            return nil
        }

        var light: PlatformColor?
        var dark: PlatformColor?
        for entry in colors {
            guard let color = entry["color"] as? [String: Any],
                  let components = color["components"] as? [String: Any],
                  let r = component(components, "red"),
                  let g = component(components, "green"),
                  let b = component(components, "blue"),
                  let a = component(components, "alpha") else { continue }
            let resolved = PlatformColor.clearlyColor(red: r, green: g, blue: b, alpha: a)
            let appearances = entry["appearances"] as? [[String: Any]] ?? []
            let isDark = appearances.contains { ($0["value"] as? String) == "dark" }
            if isDark { dark = resolved } else if light == nil { light = resolved }
        }
        guard let anyColor = light ?? dark else { return nil }
        guard let light, let dark else { return anyColor }

        #if os(macOS)
        return NSColor(name: NSColor.Name(name)) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        }
        #else
        return UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        }
        #endif
    }

    enum Appearance: Sendable {
        case light
        case dark
    }

    /// Resolves this color's sRGB components for the given appearance and returns a CSS
    /// color string: `#RRGGBB` when alpha rounds to 1, `rgba(r, g, b, a)` otherwise.
    func cssHexString(for appearance: Appearance) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        #if os(macOS)
        let target = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua) ?? NSAppearance(named: .aqua)!
        var resolved: NSColor?
        target.performAsCurrentDrawingAppearance {
            resolved = self.usingColorSpace(.sRGB)
        }
        if let resolved {
            r = resolved.redComponent
            g = resolved.greenComponent
            b = resolved.blueComponent
            a = resolved.alphaComponent
        }
        #else
        let traits = UITraitCollection(userInterfaceStyle: appearance == .dark ? .dark : .light)
        self.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        let ri = Int((r * 255).rounded())
        let gi = Int((g * 255).rounded())
        let bi = Int((b * 255).rounded())
        if a >= 0.9995 {
            return String(format: "#%02X%02X%02X", ri, gi, bi)
        }
        let alpha = (a * 1000).rounded() / 1000
        let alphaStr: String
        if alpha == alpha.rounded() {
            alphaStr = String(Int(alpha))
        } else {
            alphaStr = String(format: "%g", alpha)
        }
        return "rgba(\(ri), \(gi), \(bi), \(alphaStr))"
    }
}

public extension Color {
    init(platformColor: PlatformColor) {
        #if os(macOS)
        self.init(nsColor: platformColor)
        #else
        self.init(uiColor: platformColor)
        #endif
    }
}
