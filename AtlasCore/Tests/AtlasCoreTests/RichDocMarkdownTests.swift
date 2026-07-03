import XCTest
@testable import AtlasCore

/// Round-trip coverage for `RichDoc.markdown` ⇄ `RichDoc.fromMarkdown` across
/// every block level and inline mark RichDoc supports. The guarantee under test:
/// within RichDoc's vocabulary, `fromMarkdown(doc.markdown)` reproduces `doc`.
///
/// Both sides are normalized before comparison so run coalescing (never a semantic
/// difference) can't cause a spurious failure. A handful of exact-string assertions
/// pin the emitted Markdown so the wire format doesn't silently drift.
final class RichDocMarkdownTests: XCTestCase {

    // MARK: Helpers

    private typealias Block = RichDoc.Block
    private typealias Run = RichDoc.Run
    private typealias Marks = RichDoc.InlineMarks

    /// Asserts `fromMarkdown(doc.markdown) == doc` (both normalized).
    private func assertRoundTrips(_ doc: RichDoc, file: StaticString = #filePath, line: UInt = #line) {
        var original = doc
        original.normalize()
        var restored = RichDoc.fromMarkdown(doc.markdown)
        restored.normalize()
        XCTAssertEqual(restored, original,
                       "markdown was:\n\(doc.markdown)", file: file, line: line)
    }

    // MARK: Block levels

    func test_heading_roundTrips() {
        let doc = RichDoc(blocks: [Block(kind: .heading, runs: [Run("Chapter One")])])
        XCTAssertEqual(doc.markdown, "# Chapter One")
        assertRoundTrips(doc)
    }

    func test_subheading_roundTrips() {
        let doc = RichDoc(blocks: [Block(kind: .subheading, runs: [Run("Section")])])
        XCTAssertEqual(doc.markdown, "## Section")
        assertRoundTrips(doc)
    }

    func test_normal_roundTrips() {
        let doc = RichDoc(blocks: [Block(kind: .normal, runs: [Run("Just a paragraph.")])])
        XCTAssertEqual(doc.markdown, "Just a paragraph.")
        assertRoundTrips(doc)
    }

    func test_bulleted_roundTrips() {
        let doc = RichDoc(blocks: [Block(kind: .bulleted, runs: [Run("A point")])])
        XCTAssertEqual(doc.markdown, "- A point")
        assertRoundTrips(doc)
    }

    func test_numbered_sequenceIncrements() {
        let doc = RichDoc(blocks: [
            Block(kind: .numbered, runs: [Run("first")]),
            Block(kind: .numbered, runs: [Run("second")]),
            Block(kind: .numbered, runs: [Run("third")]),
        ])
        XCTAssertEqual(doc.markdown, "1. first\n2. second\n3. third")
        assertRoundTrips(doc)
    }

    func test_numbered_counterResetsAfterBreak() {
        let doc = RichDoc(blocks: [
            Block(kind: .numbered, runs: [Run("one")]),
            Block(kind: .normal,   runs: [Run("break")]),
            Block(kind: .numbered, runs: [Run("one again")]),
        ])
        XCTAssertEqual(doc.markdown, "1. one\nbreak\n1. one again")
        assertRoundTrips(doc)
    }

    // MARK: Inline marks

    func test_bold_roundTrips() {
        let doc = RichDoc(blocks: [Block(kind: .normal, runs: [Run("hi", marks: .bold)])])
        XCTAssertEqual(doc.markdown, "**hi**")
        assertRoundTrips(doc)
    }

    func test_italic_roundTrips() {
        let doc = RichDoc(blocks: [Block(kind: .normal, runs: [Run("hi", marks: .italic)])])
        XCTAssertEqual(doc.markdown, "*hi*")
        assertRoundTrips(doc)
    }

    func test_underline_carriedAsHTMLSpan() {
        let doc = RichDoc(blocks: [Block(kind: .normal, runs: [Run("hi", marks: .underline)])])
        XCTAssertEqual(doc.markdown, "<u>hi</u>")
        assertRoundTrips(doc)
    }

    func test_boldItalic_roundTrips() {
        let doc = RichDoc(blocks: [Block(kind: .normal, runs: [Run("hi", marks: [.bold, .italic])])])
        XCTAssertEqual(doc.markdown, "***hi***")
        assertRoundTrips(doc)
    }

    func test_boldUnderline_roundTrips() {
        assertRoundTrips(RichDoc(blocks: [Block(kind: .normal, runs: [Run("x", marks: [.bold, .underline])])]))
    }

    func test_italicUnderline_roundTrips() {
        assertRoundTrips(RichDoc(blocks: [Block(kind: .normal, runs: [Run("x", marks: [.italic, .underline])])]))
    }

    func test_allThreeMarks_roundTrips() {
        let doc = RichDoc(blocks: [Block(kind: .normal, runs: [Run("x", marks: [.bold, .italic, .underline])])])
        XCTAssertEqual(doc.markdown, "<u>***x***</u>")
        assertRoundTrips(doc)
    }

    // MARK: Mixed runs & documents

    func test_mixedRunsInOneBlock_roundTrips() {
        let doc = RichDoc(blocks: [Block(kind: .normal, runs: [
            Run("plain "),
            Run("bold", marks: .bold),
            Run(" and "),
            Run("italic", marks: .italic),
            Run(" done"),
        ])])
        XCTAssertEqual(doc.markdown, "plain **bold** and *italic* done")
        assertRoundTrips(doc)
    }

    func test_fullDocument_mixedKinds_roundTrips() {
        let doc = RichDoc(blocks: [
            Block(kind: .heading,    runs: [Run("Title")]),
            Block(kind: .subheading, runs: [Run("Subtitle")]),
            Block(kind: .normal,     runs: [Run("Intro with "), Run("emphasis", marks: .bold), Run(".")]),
            Block(kind: .bulleted,   runs: [Run("bullet a")]),
            Block(kind: .bulleted,   runs: [Run("bullet b")]),
            Block(kind: .numbered,   runs: [Run("step 1")]),
            Block(kind: .numbered,   runs: [Run("step 2")]),
            Block(kind: .normal,     runs: [Run("outro", marks: [.italic, .underline])]),
        ])
        assertRoundTrips(doc)
    }

    // MARK: Escaping — literal text must not re-parse as structure

    func test_literalAsterisk_isEscaped() {
        let doc = RichDoc(blocks: [Block(kind: .normal, runs: [Run("2 * 3 = 6")])])
        XCTAssertEqual(doc.markdown, "2 \\* 3 = 6")
        assertRoundTrips(doc)
    }

    func test_literalAngleBracket_isEscaped() {
        assertRoundTrips(RichDoc(blocks: [Block(kind: .normal, runs: [Run("a <u> tag typed by hand")])]))
    }

    func test_literalBackslash_isEscaped() {
        assertRoundTrips(RichDoc(blocks: [Block(kind: .normal, runs: [Run("path\\to\\file")])]))
    }

    func test_normalTextLeadingHash_isNotAHeading() {
        let doc = RichDoc(blocks: [Block(kind: .normal, runs: [Run("# not a heading")])])
        XCTAssertEqual(doc.markdown, "\\# not a heading")
        var restored = RichDoc.fromMarkdown(doc.markdown)
        restored.normalize()
        XCTAssertEqual(restored.blocks.first?.kind, .normal)
        XCTAssertEqual(restored.blocks.first?.text, "# not a heading")
    }

    func test_normalTextLeadingDash_isNotABullet() {
        let doc = RichDoc(blocks: [Block(kind: .normal, runs: [Run("- not a bullet")])])
        XCTAssertEqual(doc.markdown, "\\- not a bullet")
        assertRoundTrips(doc)
    }

    func test_normalTextLeadingNumber_isNotAList() {
        let doc = RichDoc(blocks: [Block(kind: .normal, runs: [Run("1. not a list item")])])
        XCTAssertEqual(doc.markdown, "\\1. not a list item")
        assertRoundTrips(doc)
    }

    // MARK: Edge cases

    func test_emptyString_yieldsOneEmptyBlock() {
        let doc = RichDoc.fromMarkdown("")
        XCTAssertEqual(doc.blocks.count, 1)
        XCTAssertEqual(doc.blocks.first?.kind, .normal)
        XCTAssertEqual(doc.blocks.first?.text, "")
    }

    func test_emptyBlocksAmongContent_roundTrip() {
        let doc = RichDoc(blocks: [
            Block(kind: .normal, runs: [Run("above")]),
            Block(kind: .normal, runs: [Run("")]),
            Block(kind: .normal, runs: [Run("below")]),
        ])
        XCTAssertEqual(doc.markdown, "above\n\nbelow")
        assertRoundTrips(doc)
    }

    func test_plainTextParity_matchesFromPlainText() {
        // A plain multi-line note (no markers) parses the same via either seed.
        let text = "line one\nline two\nline three"
        XCTAssertEqual(RichDoc.fromMarkdown(text), RichDoc.fromPlainText(text))
    }
}
