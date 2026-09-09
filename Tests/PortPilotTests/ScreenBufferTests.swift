import XCTest
@testable import TerminalTUI

/// Screen buffer layout: wide glyphs mark their right half as a continuation
/// cell, and nothing is written past the last column.
final class ScreenBufferTests: XCTestCase {
    func testAsciiPut() {
        var screen = Screen(width: 10, height: 3)
        screen.put(row: 0, col: 0, text: "hi", style: "S")
        XCTAssertEqual(screen.buffer[0][0].char, "h")
        XCTAssertEqual(screen.buffer[0][0].style, "S")
        XCTAssertEqual(screen.buffer[0][1].char, "i")
        XCTAssertFalse(screen.buffer[0][1].isContinuation)
        XCTAssertEqual(screen.buffer[0][2], Cell.empty)
    }

    func testWideGlyphWritesContinuationCell() {
        var screen = Screen(width: 10, height: 1)
        screen.put(row: 0, col: 0, text: "日本語")
        XCTAssertEqual(screen.buffer[0][0].char, "日")
        XCTAssertTrue(screen.buffer[0][1].isContinuation)
        XCTAssertEqual(screen.buffer[0][2].char, "本")
        XCTAssertTrue(screen.buffer[0][3].isContinuation)
        XCTAssertEqual(screen.buffer[0][4].char, "語")
        XCTAssertTrue(screen.buffer[0][5].isContinuation)
        XCTAssertEqual(screen.buffer[0][6], Cell.empty)
    }

    func testWideGlyphClippedAtRightEdge() {
        // Width 5: 日(0-1) 本(2-3), then 語 would need columns 4-5 — no room,
        // and a half-written glyph must never land in the buffer.
        var screen = Screen(width: 5, height: 1)
        screen.put(row: 0, col: 0, text: "日本語")
        XCTAssertEqual(screen.buffer[0][2].char, "本")
        XCTAssertEqual(screen.buffer[0][4], Cell.empty)
    }

    func testPutStartingAtLastColumnRejectsWideGlyph() {
        var screen = Screen(width: 4, height: 1)
        screen.put(row: 0, col: 3, text: "日")
        XCTAssertEqual(screen.buffer[0][3], Cell.empty)
    }

    func testMixedContentAdvancesByDisplayWidth() {
        var screen = Screen(width: 10, height: 1)
        screen.put(row: 0, col: 0, text: "a日b")
        XCTAssertEqual(screen.buffer[0][0].char, "a")
        XCTAssertEqual(screen.buffer[0][1].char, "日")
        XCTAssertEqual(screen.buffer[0][3].char, "b")
    }

    func testPutBeyondBoundsIsIgnored() {
        var screen = Screen(width: 3, height: 2)
        screen.put(row: 5, col: 0, text: "x")   // off-screen row
        screen.put(row: 0, col: 9, text: "x")   // off-screen column
        XCTAssertEqual(screen.buffer[0], [Cell](repeating: .empty, count: 3))
    }
}
