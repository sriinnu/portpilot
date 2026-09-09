import XCTest
@testable import TerminalTUI

/// Terminal column-width math: CJK/emoji take two cells, combining marks and
/// joiners take none. Layout that ignores this makes every column drift.
final class TextWidthTests: XCTestCase {
    func testAsciiIsOneColumn() {
        XCTAssertEqual(TextWidth.displayWidth("hello"), 5)
        XCTAssertEqual(TextWidth.displayWidth("a"), 1)
    }

    func testCJKIsTwoColumns() {
        XCTAssertEqual(TextWidth.displayWidth("日"), 2)
        XCTAssertEqual(TextWidth.displayWidth("日本語"), 6)
    }

    func testEmojiIsTwoColumns() {
        XCTAssertEqual(TextWidth.displayWidth("👍"), 2)
    }

    func testZWJFamilyClampsToTwo() {
        // 3 people + 2 zero-width joiners — rendered as one glyph, 2 cells.
        XCTAssertEqual(TextWidth.displayWidth("👨‍👩‍👧"), 2)
    }

    func testCombiningMarkIsZeroWidth() {
        XCTAssertEqual(TextWidth.displayWidth("e\u{0301}"), 1)  // é as e + acute
        XCTAssertEqual(TextWidth.displayWidth("a\u{200B}b"), 2)  // zero-width space
    }

    // MARK: - truncate

    func testTruncateNeverSplitsWideGlyph() {
        XCTAssertEqual(TextWidth.truncate("日本語", toWidth: 5), "日本")  // 4 cols, next glyph would overflow
        XCTAssertEqual(TextWidth.truncate("日本語", toWidth: 4), "日本")
        XCTAssertEqual(TextWidth.truncate("日本語", toWidth: 2), "日")
        XCTAssertEqual(TextWidth.truncate("日本語", toWidth: 0), "")
    }

    func testTruncateASCII() {
        XCTAssertEqual(TextWidth.truncate("hello", toWidth: 3), "hel")
        XCTAssertEqual(TextWidth.truncate("hi", toWidth: 5), "hi")
    }

    // MARK: - Widget alignment helpers

    func testFitStringPadsToExactWidth() {
        XCTAssertEqual(fitString("ab", width: 5), "ab   ")
        XCTAssertEqual(fitString("日本語", width: 5), "日本 ")
        XCTAssertEqual(fitString("toolong", width: 3), "too")
        XCTAssertEqual(fitString("x", width: 0), "")
        XCTAssertEqual(TextWidth.displayWidth(fitString("日本語x", width: 7)), 7)
    }

    func testRightAlignPadsLeft() {
        XCTAssertEqual(rightAlign("ab", width: 5), "   ab")
        XCTAssertEqual(rightAlign("日本", width: 5), " 日本")  // 4 cols + 1 pad
        XCTAssertEqual(TextWidth.displayWidth(rightAlign("日本語", width: 3)), 3)  // truncates to one glyph
    }

    func testCenterStringSplitsPadding() {
        XCTAssertEqual(centerString("ab", width: 5), " ab  ")  // extra column goes right
        XCTAssertEqual(centerString("ab", width: 4), " ab ")
        XCTAssertEqual(centerString("日本", width: 6), " 日本 ")
    }
}
