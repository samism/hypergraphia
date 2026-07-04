import Foundation

/// Decodes file bytes into editor text. Markdown files are overwhelmingly
/// UTF-8, but user folders accumulate strays: UTF-16 exports from Windows
/// tools, legacy CP-1252 / MacRoman notes full of smart quotes. Previously
/// those opened as mojibake (lossy UTF-8) and a save destroyed the original.
///
/// Strategy: strict UTF-8 first, BOM-guided UTF-16/32 next, then
/// Foundation's encoding sniffing over the common legacy encodings, with
/// lossy UTF-8 as the never-fail floor. Files are always written back as
/// UTF-8 regardless of what they decoded from.
public enum TextFileDecoder {
    public static func decode(_ data: Data) -> String {
        if data.isEmpty { return "" }
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }

        // BOM-guided Unicode variants. UTF-32 LE's BOM (FF FE 00 00) starts
        // with UTF-16 LE's (FF FE), so the 4-byte checks must come first.
        let bytes = [UInt8](data.prefix(4))
        if bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xFE, bytes[2] == 0x00, bytes[3] == 0x00,
           let utf32 = String(data: data, encoding: .utf32LittleEndian) {
            return utf32.strippingLeadingBOM()
        }
        if bytes.count >= 4, bytes[0] == 0x00, bytes[1] == 0x00, bytes[2] == 0xFE, bytes[3] == 0xFF,
           let utf32 = String(data: data, encoding: .utf32BigEndian) {
            return utf32.strippingLeadingBOM()
        }
        if bytes.count >= 2,
           (bytes[0] == 0xFF && bytes[1] == 0xFE) || (bytes[0] == 0xFE && bytes[1] == 0xFF),
           let utf16 = String(data: data, encoding: .utf16) {
            return utf16
        }

        // Legacy single-byte encodings: let Foundation pick among the ones
        // markdown files realistically show up in.
        var converted: NSString?
        let encoding = NSString.stringEncoding(
            for: data,
            encodingOptions: [
                .suggestedEncodingsKey: [
                    NSNumber(value: String.Encoding.windowsCP1252.rawValue),
                    NSNumber(value: String.Encoding.macOSRoman.rawValue),
                    NSNumber(value: String.Encoding.isoLatin1.rawValue),
                ],
                .allowLossyKey: NSNumber(value: false),
            ],
            convertedString: &converted,
            usedLossyConversion: nil
        )
        if encoding != 0, let converted {
            return converted as String
        }

        // Never fail to open: replace undecodable bytes with U+FFFD.
        return String(decoding: data, as: UTF8.self)
    }
}

private extension String {
    /// `String(data:encoding:.utf32LittleEndian)` keeps the BOM as a leading
    /// U+FEFF (unlike `.utf16`, which strips it). Remove it so the editor
    /// doesn't start with an invisible character.
    func strippingLeadingBOM() -> String {
        hasPrefix("\u{FEFF}") ? String(dropFirst()) : self
    }
}
