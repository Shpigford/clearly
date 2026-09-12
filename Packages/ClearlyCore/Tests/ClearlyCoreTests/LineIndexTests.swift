import Testing
import Foundation
@testable import ClearlyCore

struct LineIndexTests {
    @Test func emptyTextIsOneLine() {
        let index = LineIndex("")
        #expect(index.lineCount == 1)
        #expect(index.length == 0)
        #expect(index.line(forCharacterAt: 0) == 1)
        #expect(index.characterOffset(forLine: 1) == 0)
    }

    @Test func singleLineWithoutNewline() {
        let index = LineIndex("hello")
        #expect(index.lineCount == 1)
        #expect(index.line(forCharacterAt: 0) == 1)
        #expect(index.line(forCharacterAt: 4) == 1)
    }

    @Test func mapsOffsetsToLines() {
        //            0123 4567 89
        let index = LineIndex("abc\ndef\ngh")
        #expect(index.lineCount == 3)
        #expect(index.line(forCharacterAt: 0) == 1)
        #expect(index.line(forCharacterAt: 2) == 1)
        #expect(index.line(forCharacterAt: 3) == 1)  // the newline itself
        #expect(index.line(forCharacterAt: 4) == 2)
        #expect(index.line(forCharacterAt: 7) == 2)
        #expect(index.line(forCharacterAt: 8) == 3)
        #expect(index.line(forCharacterAt: 9) == 3)
    }

    @Test func mapsLinesToOffsets() {
        let index = LineIndex("abc\ndef\ngh")
        #expect(index.characterOffset(forLine: 1) == 0)
        #expect(index.characterOffset(forLine: 2) == 4)
        #expect(index.characterOffset(forLine: 3) == 8)
    }

    @Test func trailingNewlineOpensAFinalLine() {
        let index = LineIndex("abc\n")
        #expect(index.lineCount == 2)
        #expect(index.characterOffset(forLine: 2) == 4)
        #expect(index.line(forCharacterAt: 4) == 2)
    }

    @Test func blankLinesAreCounted() {
        let index = LineIndex("a\n\n\nb")
        #expect(index.lineCount == 4)
        #expect(index.line(forCharacterAt: 2) == 2)
        #expect(index.line(forCharacterAt: 3) == 3)
        #expect(index.line(forCharacterAt: 4) == 4)
    }

    @Test func outOfRangeOffsetsClamp() {
        let index = LineIndex("abc\ndef")
        #expect(index.line(forCharacterAt: -5) == 1)
        #expect(index.line(forCharacterAt: 9_999) == 2)
        #expect(index.characterOffset(forLine: 0) == 0)
        #expect(index.characterOffset(forLine: 9_999) == 4)
    }

    @Test func crlfLineEndings() {
        let index = LineIndex("abc\r\ndef")
        #expect(index.lineCount == 2)
        #expect(index.line(forCharacterAt: 5) == 2)
    }

    /// Offsets are UTF-16, matching what NSLayoutManager hands back.
    @Test func usesUTF16OffsetsForAstralCharacters() {
        let index = LineIndex("a👍\nb")
        #expect(index.length == 5)          // a + surrogate pair + \n + b
        #expect(index.characterOffset(forLine: 2) == 4)
        #expect(index.line(forCharacterAt: 2) == 1)
        #expect(index.line(forCharacterAt: 4) == 2)
    }

    @Test func roundTripsEveryLineOfALongDocument() {
        let text = (1...500).map { "line \($0)" }.joined(separator: "\n")
        let index = LineIndex(text)
        #expect(index.lineCount == 500)
        for line in 1...500 {
            #expect(index.line(forCharacterAt: index.characterOffset(forLine: line)) == line)
        }
    }
}
