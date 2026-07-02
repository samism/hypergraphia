import XCTest
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
@testable import ClearlyCore

final class ThemeFontTests: XCTestCase {
    func testEditorFontTokensUsePreferredFamilies() {
        XCTAssertFalse(Theme.editorFont.fontName.isEmpty)
        XCTAssertFalse(Theme.editorBoldFont.fontName.isEmpty)
        XCTAssertNotEqual(Theme.editorFont.fontName, Theme.editorCodeFont.fontName)
        if PlatformFont(name: "JetBrainsMono-Regular", size: Theme.editorFontSize) != nil {
            XCTAssertEqual(Theme.editorCodeFont.fontName, "JetBrainsMono-Regular")
        } else {
            XCTAssertFalse(Theme.editorCodeFont.fontName.isEmpty)
        }
    }
}
