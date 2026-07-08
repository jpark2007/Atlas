import XCTest
@testable import AtlasCore
@testable import Atlas

/// WS-10 — the constrained notes document model. Pure value transforms, so the
/// suite is locale-independent and needs no network/consent.
final class RichDocTests: XCTestCase {

    // MARK: - Plain-text seed / derive

    func testFromPlainTextSplitsLinesIntoNormalBlocks() {
        let doc = RichDoc.fromPlainText("alpha\nbeta\ngamma")
        XCTAssertEqual(doc.blocks.count, 3)
        XCTAssertEqual(doc.blocks.map(\.text), ["alpha", "beta", "gamma"])
        XCTAssertTrue(doc.blocks.allSatisfy { $0.kind == .normal })
    }

    func testFromEmptyStringYieldsOneEmptyBlock() {
        let doc = RichDoc.fromPlainText("")
        XCTAssertEqual(doc.blocks.count, 1)
        XCTAssertEqual(doc.blocks.first?.text, "")
    }

    func testPlainTextRoundTrips() {
        let source = "one\ntwo\nthree"
        XCTAssertEqual(RichDoc.fromPlainText(source).plainText, source)
    }

    func testPlainTextHasNoListGlyphs() {
        var doc = RichDoc.fromPlainText("milk\neggs")
        doc.setKind(.bulleted, at: 0)
        doc.setKind(.numbered, at: 1)
        XCTAssertEqual(doc.plainText, "milk\neggs")
    }

    // MARK: - Block levels

    func testSetKindChangesBlockLevel() {
        var doc = RichDoc.fromPlainText("Title")
        doc.setKind(.heading, at: 0)
        XCTAssertEqual(doc.blocks[0].kind, .heading)
    }

    func testSetKindIgnoresOutOfRange() {
        var doc = RichDoc.fromPlainText("a")
        doc.setKind(.heading, at: 5)         // no crash, no change
        XCTAssertEqual(doc.blocks[0].kind, .normal)
    }

    func testToggleListKindSetsThenRevertsToNormal() {
        var doc = RichDoc.fromPlainText("item")
        doc.toggleListKind(.bulleted, at: 0)
        XCTAssertEqual(doc.blocks[0].kind, .bulleted)
        doc.toggleListKind(.bulleted, at: 0)  // same kind again → off
        XCTAssertEqual(doc.blocks[0].kind, .normal)
    }

    func testToggleListKindSwitchesBetweenListTypes() {
        var doc = RichDoc.fromPlainText("item")
        doc.toggleListKind(.bulleted, at: 0)
        doc.toggleListKind(.numbered, at: 0)  // different kind → switch, not off
        XCTAssertEqual(doc.blocks[0].kind, .numbered)
    }

    func testToggleListKindRejectsNonListKind() {
        var doc = RichDoc.fromPlainText("item")
        doc.toggleListKind(.heading, at: 0)   // not a list → ignored
        XCTAssertEqual(doc.blocks[0].kind, .normal)
    }

    // MARK: - Inline marks (whole block)

    func testToggleBoldOverWholeBlock() {
        var doc = RichDoc.fromPlainText("hello")
        doc.toggleMark(.bold, at: 0)
        XCTAssertEqual(doc.blocks[0].runs, [RichDoc.Run("hello", marks: .bold)])
        XCTAssertTrue(doc.blocks[0].uniformMarks.contains(.bold))
    }

    func testToggleMarkIsIdempotentPair() {
        var doc = RichDoc.fromPlainText("hello")
        doc.toggleMark(.italic, at: 0)
        doc.toggleMark(.italic, at: 0)
        XCTAssertEqual(doc.blocks[0].runs, [RichDoc.Run("hello")])
        XCTAssertFalse(doc.blocks[0].uniformMarks.contains(.italic))
    }

    func testMarksCompose() {
        var doc = RichDoc.fromPlainText("hi")
        doc.toggleMark(.bold, at: 0)
        doc.toggleMark(.underline, at: 0)
        let marks = doc.blocks[0].uniformMarks
        XCTAssertTrue(marks.contains(.bold))
        XCTAssertTrue(marks.contains(.underline))
        XCTAssertFalse(marks.contains(.italic))
    }

    // MARK: - Inline marks (range → run split + merge)

    func testToggleBoldOverRangeSplitsRuns() {
        var doc = RichDoc.fromPlainText("abcdef")
        doc.toggleMark(.bold, at: 0, range: 2..<4)   // "cd"
        XCTAssertEqual(doc.blocks[0].runs, [
            RichDoc.Run("ab"),
            RichDoc.Run("cd", marks: .bold),
            RichDoc.Run("ef"),
        ])
    }

    func testToggleRemovesMarkOnlyWhenEntireRangeHasIt() {
        var doc = RichDoc.fromPlainText("abcdef")
        doc.toggleMark(.bold, at: 0, range: 2..<4)   // bold "cd"
        // Range "bcde" is only partly bold → toggle ADDS bold to all of it.
        doc.toggleMark(.bold, at: 0, range: 1..<5)
        XCTAssertEqual(doc.blocks[0].text, "abcdef")
        XCTAssertEqual(doc.blocks[0].charMarks().map { $0.contains(.bold) },
                       [false, true, true, true, true, false])
    }

    func testToggleFullyBoldRangeRemovesIt() {
        var doc = RichDoc.fromPlainText("abcdef")
        doc.toggleMark(.bold, at: 0, range: 1..<5)   // bold "bcde"
        doc.toggleMark(.bold, at: 0, range: 1..<5)   // all bold → remove
        XCTAssertEqual(doc.blocks[0].runs, [RichDoc.Run("abcdef")])
    }

    func testAdjacentEqualRunsMergeOnNormalize() {
        var block = RichDoc.Block(kind: .normal, runs: [
            RichDoc.Run("foo", marks: .bold),
            RichDoc.Run("bar", marks: .bold),
            RichDoc.Run("baz"),
        ])
        block.normalize()
        XCTAssertEqual(block.runs, [
            RichDoc.Run("foobar", marks: .bold),
            RichDoc.Run("baz"),
        ])
    }

    // MARK: - Empty-block mark carrier

    func testToggleMarkOnEmptyBlockKeepsCarrierRun() {
        var doc = RichDoc.fromPlainText("")
        doc.toggleMark(.bold, at: 0)
        XCTAssertEqual(doc.blocks[0].text, "")
        XCTAssertTrue(doc.blocks[0].uniformMarks.contains(.bold))
    }

    // MARK: - setText

    func testSetTextInheritsUniformMarks() {
        var block = RichDoc.Block(kind: .normal, runs: [RichDoc.Run("x", marks: .bold)])
        block.setText("rewritten")
        XCTAssertEqual(block.runs, [RichDoc.Run("rewritten", marks: .bold)])
    }

    func testSetTextWithExplicitMarksOverrides() {
        var block = RichDoc.Block(kind: .normal, runs: [RichDoc.Run("x", marks: .bold)])
        block.setText("plain", marks: [])
        XCTAssertEqual(block.runs, [RichDoc.Run("plain")])
    }

    // MARK: - Block insert / remove

    func testInsertBlockAfter() {
        var doc = RichDoc.fromPlainText("a\nb")
        doc.insertBlock(after: 0)
        XCTAssertEqual(doc.blocks.count, 3)
        XCTAssertEqual(doc.blocks[1].text, "")     // inserted between a and b
        XCTAssertEqual(doc.blocks[2].text, "b")
    }

    func testRemoveBlockKeepsAtLeastOne() {
        var doc = RichDoc.fromPlainText("only")
        doc.removeBlock(at: 0)
        XCTAssertEqual(doc.blocks.count, 1)
        XCTAssertEqual(doc.blocks[0].text, "")
    }

    func testRemoveBlockFromMany() {
        var doc = RichDoc.fromPlainText("a\nb\nc")
        doc.removeBlock(at: 1)
        XCTAssertEqual(doc.blocks.map(\.text), ["a", "c"])
    }

    // MARK: - Codable

    func testRichDocCodableRoundTrips() throws {
        var doc = RichDoc.fromPlainText("Heading\nbody")
        doc.setKind(.heading, at: 0)
        doc.toggleMark(.bold, at: 1, range: 0..<2)

        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(RichDoc.self, from: data)
        XCTAssertEqual(decoded, doc)
    }
}
