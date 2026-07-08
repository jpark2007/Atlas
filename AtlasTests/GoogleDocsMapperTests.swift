import XCTest
@testable import AtlasCore
@testable import Atlas

/// WS-10 — pure RichDoc ⇄ Google Docs mapping. Fixtures only, no network/consent.
/// Both directions plus a round-trip and the last-write reconciler are covered.
final class GoogleDocsMapperTests: XCTestCase {

    // MARK: - Decode: Google Doc JSON → RichDoc

    /// A realistic `documents.get` slice: heading, sub-heading, a normal
    /// paragraph with a mid-run bold span, a bullet, and a numbered item.
    private let fixture = """
    {
      "documentId": "doc-1",
      "title": "Syllabus",
      "body": { "content": [
        { "paragraph": {
            "paragraphStyle": { "namedStyleType": "HEADING_1" },
            "elements": [ { "textRun": { "content": "Week 1\\n" } } ] } },
        { "paragraph": {
            "paragraphStyle": { "namedStyleType": "HEADING_2" },
            "elements": [ { "textRun": { "content": "Readings\\n" } } ] } },
        { "paragraph": {
            "paragraphStyle": { "namedStyleType": "NORMAL_TEXT" },
            "elements": [
              { "textRun": { "content": "Read " } },
              { "textRun": { "content": "chapter 3", "textStyle": { "bold": true } } },
              { "textRun": { "content": " tonight\\n", "textStyle": { "italic": true } } }
            ] } },
        { "paragraph": {
            "paragraphStyle": { "namedStyleType": "NORMAL_TEXT" },
            "bullet": { "listId": "list-bullet" },
            "elements": [ { "textRun": { "content": "buy textbook\\n" } } ] } },
        { "paragraph": {
            "paragraphStyle": { "namedStyleType": "NORMAL_TEXT" },
            "bullet": { "listId": "list-number" },
            "elements": [ { "textRun": { "content": "first step\\n" } } ] } }
      ] },
      "lists": {
        "list-bullet": { "listProperties": { "nestingLevels": [ { "glyphSymbol": "●" } ] } },
        "list-number": { "listProperties": { "nestingLevels": [ { "glyphType": "DECIMAL" } ] } }
      }
    }
    """.data(using: .utf8)!

    func testDecodeMapsBlockLevels() throws {
        let doc = try GoogleDocsMapper.decodeDocument(from: fixture)
        XCTAssertEqual(doc.blocks.map(\.kind),
                       [.heading, .subheading, .normal, .bulleted, .numbered])
    }

    func testDecodeStripsTrailingNewlineFromText() throws {
        let doc = try GoogleDocsMapper.decodeDocument(from: fixture)
        XCTAssertEqual(doc.blocks[0].text, "Week 1")
        XCTAssertEqual(doc.blocks[1].text, "Readings")
        XCTAssertEqual(doc.blocks[3].text, "buy textbook")
    }

    func testDecodePreservesInlineMarksPerRun() throws {
        let doc = try GoogleDocsMapper.decodeDocument(from: fixture)
        let normal = doc.blocks[2]
        XCTAssertEqual(normal.text, "Read chapter 3 tonight")
        XCTAssertEqual(normal.runs, [
            RichDoc.Run("Read "),
            RichDoc.Run("chapter 3", marks: .bold),
            RichDoc.Run(" tonight", marks: .italic),
        ])
    }

    func testDecodeDistinguishesBulletedFromNumberedByGlyph() throws {
        let doc = try GoogleDocsMapper.decodeDocument(from: fixture)
        XCTAssertEqual(doc.blocks[3].kind, .bulleted)
        XCTAssertEqual(doc.blocks[4].kind, .numbered)
    }

    func testDecodeEmptyDocument() throws {
        let doc = try GoogleDocsMapper.decodeDocument(from: "{}".data(using: .utf8)!)
        XCTAssertTrue(doc.blocks.isEmpty)
    }

    // MARK: - Encode: RichDoc → Google Doc JSON

    func testEncodeMapsHeadingToNamedStyle() throws {
        var doc = RichDoc.fromPlainText("Big title")
        doc.setKind(.heading, at: 0)

        let object = try jsonObject(GoogleDocsMapper.encodeDocument(doc))
        let paragraph = try firstParagraph(object)
        let style = try XCTUnwrap(paragraph["paragraphStyle"] as? [String: Any])
        XCTAssertEqual(style["namedStyleType"] as? String, GoogleDocsMapper.headingStyle)
    }

    func testEncodeEmitsBulletWithListAndGlyph() throws {
        var doc = RichDoc.fromPlainText("a thing")
        doc.setKind(.bulleted, at: 0)

        let object = try jsonObject(GoogleDocsMapper.encodeDocument(doc))
        let paragraph = try firstParagraph(object)
        let bullet = try XCTUnwrap(paragraph["bullet"] as? [String: Any])
        XCTAssertEqual(bullet["listId"] as? String, GoogleDocsMapper.bulletedListID)

        let lists = try XCTUnwrap(object["lists"] as? [String: Any])
        XCTAssertNotNil(lists[GoogleDocsMapper.bulletedListID])
    }

    func testEncodeNumberedListUsesOrderedGlyph() throws {
        var doc = RichDoc.fromPlainText("step")
        doc.setKind(.numbered, at: 0)

        let object = try jsonObject(GoogleDocsMapper.encodeDocument(doc))
        let lists = try XCTUnwrap(object["lists"] as? [String: Any])
        let list = try XCTUnwrap(lists[GoogleDocsMapper.numberedListID] as? [String: Any])
        let props = try XCTUnwrap(list["listProperties"] as? [String: Any])
        let levels = try XCTUnwrap(props["nestingLevels"] as? [[String: Any]])
        let glyph = try XCTUnwrap(levels.first?["glyphType"] as? String)
        XCTAssertTrue(GoogleDocsMapper.orderedGlyphTypes.contains(glyph))
    }

    func testEncodeTerminatesLastRunWithNewline() throws {
        var doc = RichDoc.fromPlainText("hello")
        doc.toggleMark(.bold, at: 0)

        let object = try jsonObject(GoogleDocsMapper.encodeDocument(doc))
        let paragraph = try firstParagraph(object)
        let elements = try XCTUnwrap(paragraph["elements"] as? [[String: Any]])
        let textRun = try XCTUnwrap(elements.first?["textRun"] as? [String: Any])
        XCTAssertEqual(textRun["content"] as? String, "hello\n")
        let style = try XCTUnwrap(textRun["textStyle"] as? [String: Any])
        XCTAssertEqual(style["bold"] as? Bool, true)
    }

    func testEncodeOmitsListsWhenNoListBlocks() throws {
        let doc = RichDoc.fromPlainText("plain")
        let object = try jsonObject(GoogleDocsMapper.encodeDocument(doc))
        XCTAssertNil(object["lists"])
    }

    // MARK: - Round-trip: encode → decode

    func testRoundTripPreservesStructureAndMarks() throws {
        var doc = RichDoc.fromPlainText("Heading\nbody text\nitem")
        doc.setKind(.heading, at: 0)
        doc.toggleMark(.bold, at: 1, range: 0..<4)   // "body" bold
        doc.toggleMark(.underline, at: 1, range: 5..<9) // "text" underline
        doc.setKind(.numbered, at: 2)
        doc.normalize()

        let encoded = GoogleDocsMapper.encodeDocument(doc)
        let decoded = try GoogleDocsMapper.decodeDocument(from: encoded)

        XCTAssertEqual(decoded, doc)
    }

    func testRoundTripFromGoogleFixture() throws {
        // Doc JSON (master) → RichDoc → Doc JSON → RichDoc is stable.
        let once = try GoogleDocsMapper.decodeDocument(from: fixture)
        let reencoded = GoogleDocsMapper.encodeDocument(once)
        let twice = try GoogleDocsMapper.decodeDocument(from: reencoded)
        XCTAssertEqual(once, twice)
    }

    // MARK: - batchUpdate write payload

    func testBatchUpdateInsertsTextAndStylesParagraph() throws {
        var doc = RichDoc.fromPlainText("Title")
        doc.setKind(.heading, at: 0)

        let object = try jsonObject(
            GoogleDocsMapper.batchUpdateBody(for: doc, currentEndIndex: 1))
        let requests = try XCTUnwrap(object["requests"] as? [[String: Any]])

        XCTAssertTrue(requests.contains { ($0["insertText"] as? [String: Any]) != nil })
        let paraStyle = requests.compactMap { $0["updateParagraphStyle"] as? [String: Any] }.first
        let style = try XCTUnwrap((paraStyle?["paragraphStyle"]) as? [String: Any])
        XCTAssertEqual(style["namedStyleType"] as? String, GoogleDocsMapper.headingStyle)
    }

    func testBatchUpdateDeletesExistingContentWhenPresent() throws {
        let doc = RichDoc.fromPlainText("new")
        let object = try jsonObject(
            GoogleDocsMapper.batchUpdateBody(for: doc, currentEndIndex: 50))
        let requests = try XCTUnwrap(object["requests"] as? [[String: Any]])
        XCTAssertTrue(requests.contains { ($0["deleteContentRange"] as? [String: Any]) != nil })
    }

    func testBatchUpdateCreatesBulletsForListBlocks() throws {
        var doc = RichDoc.fromPlainText("item")
        doc.setKind(.numbered, at: 0)
        let object = try jsonObject(
            GoogleDocsMapper.batchUpdateBody(for: doc, currentEndIndex: 1))
        let requests = try XCTUnwrap(object["requests"] as? [[String: Any]])
        XCTAssertTrue(requests.contains { ($0["createParagraphBullets"] as? [String: Any]) != nil })
    }

    // MARK: - Reconciliation

    func testReconcileEqualContentIsInSync() {
        let a = RichDoc.fromPlainText("same")
        XCTAssertEqual(
            NoteSync.reconcile(local: a, localModified: Date(),
                               remote: a, remoteModified: Date()),
            .inSync)
    }

    func testReconcileNewerLocalWins() {
        let local = RichDoc.fromPlainText("local edit")
        let remote = RichDoc.fromPlainText("remote edit")
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(
            NoteSync.reconcile(local: local, localModified: now.addingTimeInterval(10),
                               remote: remote, remoteModified: now),
            .useLocal)
    }

    func testReconcileNewerRemoteWins() {
        let local = RichDoc.fromPlainText("local edit")
        let remote = RichDoc.fromPlainText("remote edit")
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(
            NoteSync.reconcile(local: local, localModified: now,
                               remote: remote, remoteModified: now.addingTimeInterval(10)),
            .useRemote)
    }

    func testReconcileAmbiguousIsConflictNotSilentLoss() {
        let local = RichDoc.fromPlainText("local edit")
        let remote = RichDoc.fromPlainText("remote edit")
        // Missing a timestamp → can't order → conflict (never drop a side).
        XCTAssertEqual(
            NoteSync.reconcile(local: local, localModified: nil,
                               remote: remote, remoteModified: Date()),
            .conflict)
        // Equal timestamps but differing content → conflict.
        let now = Date()
        XCTAssertEqual(
            NoteSync.reconcile(local: local, localModified: now,
                               remote: remote, remoteModified: now),
            .conflict)
    }

    // MARK: - Helpers

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func firstParagraph(_ object: [String: Any]) throws -> [String: Any] {
        let body = try XCTUnwrap(object["body"] as? [String: Any])
        let content = try XCTUnwrap(body["content"] as? [[String: Any]])
        return try XCTUnwrap(content.first?["paragraph"] as? [String: Any])
    }
}
