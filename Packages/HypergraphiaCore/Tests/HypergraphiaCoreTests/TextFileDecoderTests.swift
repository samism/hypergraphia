import Testing
import Foundation
@testable import HypergraphiaCore

@Suite("Text file decoding")
struct TextFileDecoderTests {

    @Test func utf8PassesThroughExactly() {
        let text = "# Héllo\n\nCafé ☕️ — em-dash and emoji 🎉\n"
        #expect(TextFileDecoder.decode(Data(text.utf8)) == text)
    }

    @Test func emptyDataDecodesToEmptyString() {
        #expect(TextFileDecoder.decode(Data()) == "")
    }

    @Test func utf16LittleEndianWithBOMDecodes() {
        let text = "# UTF-16 export\n\nsmart “quotes”\n"
        var data = Data([0xFF, 0xFE])
        data.append(text.data(using: .utf16LittleEndian)!)
        #expect(TextFileDecoder.decode(data) == text)
    }

    @Test func utf16BigEndianWithBOMDecodes() {
        let text = "Title\nBody\n"
        var data = Data([0xFE, 0xFF])
        data.append(text.data(using: .utf16BigEndian)!)
        #expect(TextFileDecoder.decode(data) == text)
    }

    @Test func windowsCP1252SmartQuotesDecode() {
        // “Notes” — 0x93/0x94 are curly quotes in CP-1252, control chars in
        // Latin-1. The sniffer should produce real punctuation, not U+FFFD
        // mojibake (which is what the old lossy UTF-8 decode yielded).
        let data = Data([0x93, 0x4E, 0x6F, 0x74, 0x65, 0x73, 0x94, 0x20, 0xE9])
        let decoded = TextFileDecoder.decode(data)
        #expect(!decoded.contains("\u{FFFD}"))
        #expect(decoded.contains("Notes"))
    }

    @Test func arbitraryBinaryNeverFails() {
        var data = Data()
        for byte in stride(from: 0, through: 255, by: 1) {
            data.append(UInt8(byte))
        }
        // Whatever the sniffer decides, decoding must return something
        // rather than trapping or throwing.
        _ = TextFileDecoder.decode(data)
    }

    @Test func truncationCutsAtLineBoundary() {
        let text = "line one\nline two\nline three\n"
        let data = Data(text.utf8)

        // Under the limit: untouched.
        let (whole, wasTruncated) = TextFileDecoder.truncatedAtLineBoundary(data, limit: 1000)
        #expect(!wasTruncated)
        #expect(whole == data)

        // Limit lands mid-"line two": cut backs off to the end of line one.
        let (cut, truncated) = TextFileDecoder.truncatedAtLineBoundary(data, limit: 13)
        #expect(truncated)
        #expect(String(decoding: cut, as: UTF8.self) == "line one")
    }

    @Test func truncationWithoutNewlineKeepsPrefix() {
        let data = Data("abcdefghij".utf8)
        let (cut, truncated) = TextFileDecoder.truncatedAtLineBoundary(data, limit: 4)
        #expect(truncated)
        #expect(String(decoding: cut, as: UTF8.self) == "abcd")
    }
}
