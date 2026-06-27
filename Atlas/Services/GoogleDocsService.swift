import Foundation

// MARK: - Pure mapping (testable, no network)

/// Value transforms between Google Docs' `documents` JSON and the Atlas
/// `RichDoc` subset. Kept pure so the structure/style mapping can be unit-tested
/// with fixtures — both directions — without hitting the network.
///
/// The Google Doc is the styling MASTER: `decodeDocument` collapses the Doc's
/// full fidelity down to Atlas's allowed subset (heading/subheading/normal +
/// bold/italic/underline + bulleted/numbered). `encodeDocument` maps the subset
/// back onto the same Doc-shaped JSON, so `encode → decode` round-trips.
enum GoogleDocsMapper {

    // MARK: Named paragraph styles

    static let headingStyle    = "HEADING_1"
    static let subheadingStyle = "HEADING_2"
    static let normalStyle     = "NORMAL_TEXT"

    /// Deterministic list ids so `encode → decode` is stable across calls.
    static let bulletedListID  = "atlas-bulleted"
    static let numberedListID  = "atlas-numbered"

    /// Glyph types Docs uses for *ordered* (numbered) lists. Anything else is a
    /// bullet.
    static let orderedGlyphTypes: Set<String> = [
        "DECIMAL", "ZERO_DECIMAL", "ALPHA", "UPPER_ALPHA", "ROMAN", "UPPER_ROMAN",
    ]

    // MARK: Decodable shapes (subset of documents.get)

    struct GDocument: Decodable {
        let documentId: String?
        let title: String?
        let body: GBody?
        let lists: [String: GList]?
    }
    struct GBody: Decodable { let content: [GStructuralElement]? }
    struct GStructuralElement: Decodable { let paragraph: GParagraph? }
    struct GParagraph: Decodable {
        let elements: [GParagraphElement]?
        let paragraphStyle: GParagraphStyle?
        let bullet: GBullet?
    }
    struct GParagraphElement: Decodable { let textRun: GTextRun? }
    struct GTextRun: Decodable { let content: String?; let textStyle: GTextStyle? }
    struct GTextStyle: Decodable { let bold: Bool?; let italic: Bool?; let underline: Bool? }
    struct GParagraphStyle: Decodable { let namedStyleType: String? }
    struct GBullet: Decodable { let listId: String? }
    struct GList: Decodable { let listProperties: GListProperties? }
    struct GListProperties: Decodable { let nestingLevels: [GNestingLevel]? }
    struct GNestingLevel: Decodable { let glyphType: String? }

    // MARK: Decode  (Google Doc → RichDoc)

    /// Decodes a `documents.get` response into the Atlas subset.
    static func decodeDocument(from data: Data) throws -> RichDoc {
        let doc = try JSONDecoder().decode(GDocument.self, from: data)
        return richDoc(from: doc)
    }

    static func richDoc(from doc: GDocument) -> RichDoc {
        let content = doc.body?.content ?? []
        let blocks: [RichDoc.Block] = content.compactMap { element in
            guard let paragraph = element.paragraph else { return nil }
            let kind = blockKind(for: paragraph, lists: doc.lists)
            let runs = runs(from: paragraph.elements ?? [])
            return RichDoc.Block(kind: kind, runs: runs)
        }
        return RichDoc(blocks: blocks)
    }

    /// Maps a paragraph's named style + bullet to an Atlas block level.
    static func blockKind(for paragraph: GParagraph, lists: [String: GList]?) -> RichDoc.BlockKind {
        if let bullet = paragraph.bullet {
            return isOrdered(listId: bullet.listId, lists: lists) ? .numbered : .bulleted
        }
        switch paragraph.paragraphStyle?.namedStyleType {
        case headingStyle, "TITLE":      return .heading
        case subheadingStyle, "SUBTITLE", "HEADING_3": return .subheading
        default:                         return .normal
        }
    }

    /// True when the referenced list's first nesting level uses an ordered glyph.
    static func isOrdered(listId: String?, lists: [String: GList]?) -> Bool {
        guard let listId, let glyph = lists?[listId]?.listProperties?.nestingLevels?.first?.glyphType
        else { return false }
        return orderedGlyphTypes.contains(glyph)
    }

    /// Maps a paragraph's text runs to Atlas runs, dropping the trailing newline
    /// Docs appends to each paragraph and skipping empty fragments.
    static func runs(from elements: [GParagraphElement]) -> [RichDoc.Run] {
        var runs: [RichDoc.Run] = []
        for element in elements {
            guard let run = element.textRun, var content = run.content else { continue }
            if content.hasSuffix("\n") { content.removeLast() }
            if content.isEmpty { continue }
            runs.append(RichDoc.Run(content, marks: marks(from: run.textStyle)))
        }
        return runs.isEmpty ? [RichDoc.Run("")] : runs
    }

    static func marks(from style: GTextStyle?) -> RichDoc.InlineMarks {
        var marks: RichDoc.InlineMarks = []
        if style?.bold == true { marks.insert(.bold) }
        if style?.italic == true { marks.insert(.italic) }
        if style?.underline == true { marks.insert(.underline) }
        return marks
    }

    // MARK: Encode  (RichDoc → Google Doc JSON, symmetric with decode)

    /// Builds Doc-shaped JSON from a RichDoc. Symmetric with `decodeDocument`
    /// (`encode → decode` round-trips). Used for fixtures/tests and as the model
    /// for the real `batchUpdate` write payload.
    static func encodeDocument(_ doc: RichDoc) -> Data {
        (try? JSONSerialization.data(withJSONObject: documentObject(doc))) ?? Data()
    }

    static func documentObject(_ doc: RichDoc) -> [String: Any] {
        var usesBulleted = false
        var usesNumbered = false

        let content: [[String: Any]] = doc.blocks.map { block in
            var paragraph: [String: Any] = [
                "elements": elementObjects(for: block),
                "paragraphStyle": ["namedStyleType": namedStyle(for: block.kind)],
            ]
            switch block.kind {
            case .bulleted:
                usesBulleted = true
                paragraph["bullet"] = ["listId": bulletedListID]
            case .numbered:
                usesNumbered = true
                paragraph["bullet"] = ["listId": numberedListID]
            default:
                break
            }
            return ["paragraph": paragraph]
        }

        var object: [String: Any] = ["body": ["content": content]]

        var lists: [String: Any] = [:]
        if usesBulleted {
            lists[bulletedListID] = listObject(glyphType: nil)        // bullet glyph
        }
        if usesNumbered {
            lists[numberedListID] = listObject(glyphType: "DECIMAL")  // ordered
        }
        if !lists.isEmpty { object["lists"] = lists }

        return object
    }

    /// The `textRun` element objects for a block. The last run carries the
    /// trailing `\n` Docs uses to terminate a paragraph.
    static func elementObjects(for block: RichDoc.Block) -> [[String: Any]] {
        let runs = block.runs.isEmpty ? [RichDoc.Run("")] : block.runs
        return runs.enumerated().map { index, run in
            let isLast = index == runs.count - 1
            var textRun: [String: Any] = ["content": run.text + (isLast ? "\n" : "")]
            let style = styleObject(for: run.marks)
            if !style.isEmpty { textRun["textStyle"] = style }
            return ["textRun": textRun]
        }
    }

    static func styleObject(for marks: RichDoc.InlineMarks) -> [String: Any] {
        var style: [String: Any] = [:]
        if marks.contains(.bold) { style["bold"] = true }
        if marks.contains(.italic) { style["italic"] = true }
        if marks.contains(.underline) { style["underline"] = true }
        return style
    }

    static func listObject(glyphType: String?) -> [String: Any] {
        var level: [String: Any] = [:]
        if let glyphType { level["glyphType"] = glyphType }
        else { level["glyphSymbol"] = "●" }
        return ["listProperties": ["nestingLevels": [level]]]
    }

    static func namedStyle(for kind: RichDoc.BlockKind) -> String {
        switch kind {
        case .heading:    return headingStyle
        case .subheading: return subheadingStyle
        case .normal, .bulleted, .numbered: return normalStyle
        }
    }

    // MARK: batchUpdate write payload

    /// The real write path: a `documents.batchUpdate` body that clears the doc
    /// (delete `[1, endIndex)`) then re-inserts the RichDoc as plain text with
    /// paragraph-style and text-style updates. Indices are 1-based per the Docs
    /// API (index 0 is the implicit document start). Structurally unit-tested;
    /// the live round-trip needs Google consent.
    static func batchUpdateBody(for doc: RichDoc, currentEndIndex: Int) -> Data {
        var requests: [[String: Any]] = []

        // 1. Clear existing body (if any content beyond the mandatory newline).
        if currentEndIndex > 2 {
            requests.append([
                "deleteContentRange": [
                    "range": ["startIndex": 1, "endIndex": currentEndIndex - 1],
                ],
            ])
        }

        // 2. Insert each block's text, then style the inserted range.
        var index = 1
        for block in doc.blocks {
            let text = block.text + "\n"
            requests.append([
                "insertText": ["location": ["index": index], "text": text],
            ])
            let blockStart = index
            let blockEnd = index + text.count

            // Paragraph style (heading/subheading/normal).
            requests.append([
                "updateParagraphStyle": [
                    "range": ["startIndex": blockStart, "endIndex": blockEnd],
                    "paragraphStyle": ["namedStyleType": namedStyle(for: block.kind)],
                    "fields": "namedStyleType",
                ],
            ])

            // Bullets for list blocks.
            if block.kind.isList {
                requests.append([
                    "createParagraphBullets": [
                        "range": ["startIndex": blockStart, "endIndex": blockEnd],
                        "bulletPreset": block.kind == .numbered
                            ? "NUMBERED_DECIMAL_ALPHA_ROMAN"
                            : "BULLET_DISC_CIRCLE_SQUARE",
                    ],
                ])
            }

            // Inline marks per run.
            var runStart = blockStart
            for run in block.runs {
                let runEnd = runStart + run.text.count
                if !run.marks.isEmpty, runEnd > runStart {
                    requests.append([
                        "updateTextStyle": [
                            "range": ["startIndex": runStart, "endIndex": runEnd],
                            "textStyle": styleObject(for: run.marks),
                            "fields": markFields(run.marks),
                        ],
                    ])
                }
                runStart = runEnd
            }

            index = blockEnd
        }

        return (try? JSONSerialization.data(withJSONObject: ["requests": requests])) ?? Data()
    }

    static func markFields(_ marks: RichDoc.InlineMarks) -> String {
        var fields: [String] = []
        if marks.contains(.bold) { fields.append("bold") }
        if marks.contains(.italic) { fields.append("italic") }
        if marks.contains(.underline) { fields.append("underline") }
        return fields.joined(separator: ",")
    }
}

// MARK: - Last-write reconciliation (pure, tested)

/// The outcome of comparing the local Atlas copy of a note against its backing
/// Google Doc. Ambiguous cases resolve to `.conflict` so a side is never
/// silently lost (spec §4 WS-10).
enum NoteSyncDecision: Equatable {
    case inSync       // content identical — nothing to do
    case useLocal     // local is newer — push to the Doc
    case useRemote    // Doc is newer — pull into Atlas
    case conflict     // diverged and can't be ordered — surface both
}

enum NoteSync {
    /// Last-write reconciliation. Equal content → `.inSync`. When both sides
    /// carry a modified timestamp the newer wins; when timestamps can't order
    /// the two differing copies → `.conflict`.
    static func reconcile(local: RichDoc,
                          localModified: Date?,
                          remote: RichDoc,
                          remoteModified: Date?) -> NoteSyncDecision {
        if local == remote { return .inSync }
        guard let localModified, let remoteModified else { return .conflict }
        if localModified == remoteModified { return .conflict }
        return localModified > remoteModified ? .useLocal : .useRemote
    }
}

// MARK: - Errors

enum GoogleDocsError: LocalizedError {
    case requestFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let code, let body):
            return "Google Docs request failed (HTTP \(code)): \(body)"
        }
    }
}

// MARK: - Service (scaffold)

/// Two-way sync between an Atlas note and its backing Google Doc. Reads pull the
/// Doc (styling master) into a `RichDoc`; writes push the Atlas subset back via
/// `documents.batchUpdate`. Backing docs are created/located through Drive
/// (`drive.file`). Every call obtains a fresh access token from
/// `GoogleAuthService` and no-ops (throws `.notConnected`) until the user has
/// authorized — the live round-trip needs the human consent click (same as WS-5).
final class GoogleDocsService {

    private let auth: GoogleAuthService
    private let urlSession: URLSession
    private let docsBase = "https://docs.googleapis.com/v1"
    private let driveBase = "https://www.googleapis.com/drive/v3"

    init(auth: GoogleAuthService, urlSession: URLSession = .shared) {
        self.auth = auth
        self.urlSession = urlSession
    }

    // MARK: Create a backing doc (Drive)

    /// Creates an empty Google Doc and returns its document id. Uses the Drive
    /// `files.create` endpoint with the Docs mime type (`drive.file` scope).
    @discardableResult
    func createBackingDoc(title: String) async throws -> String {
        let token = try await auth.validAccessToken()
        let url = URL(string: "\(driveBase)/files")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": title,
            "mimeType": "application/vnd.google-apps.document",
        ])

        let (data, response) = try await urlSession.data(for: request)
        try Self.checkOK(response, data)
        let file = try JSONDecoder().decode(DriveFile.self, from: data)
        return file.id
    }

    private struct DriveFile: Decodable { let id: String }

    // MARK: Read (Docs → RichDoc)

    /// Fetches a Google Doc and maps it into the Atlas subset.
    func fetchDoc(documentId: String) async throws -> RichDoc {
        let token = try await auth.validAccessToken()
        let url = URL(string: "\(docsBase)/documents/\(documentId)")!

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        try Self.checkOK(response, data)
        return try GoogleDocsMapper.decodeDocument(from: data)
    }

    /// Returns (doc, endIndex) — the body end index is needed to clear the doc on
    /// the next write.
    func fetchDocAndEndIndex(documentId: String) async throws -> (RichDoc, Int) {
        let token = try await auth.validAccessToken()
        let url = URL(string: "\(docsBase)/documents/\(documentId)")!

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        try Self.checkOK(response, data)
        let doc = try GoogleDocsMapper.decodeDocument(from: data)
        let endIndex = (try? JSONDecoder().decode(DocEndIndex.self, from: data))?.endIndex ?? 1
        return (doc, endIndex)
    }

    private struct DocEndIndex: Decodable {
        let endIndex: Int
        init(from decoder: Decoder) throws {
            // The doc's end index is the last structural element's `endIndex`.
            struct Body: Decodable { let content: [Element]? }
            struct Element: Decodable { let endIndex: Int? }
            struct Doc: Decodable { let body: Body? }
            let doc = try Doc(from: decoder)
            endIndex = doc.body?.content?.compactMap(\.endIndex).max() ?? 1
        }
    }

    // MARK: Write (RichDoc → Docs)

    /// Replaces the Doc's content with the RichDoc via `documents.batchUpdate`.
    func pushDoc(documentId: String, doc: RichDoc, currentEndIndex: Int) async throws {
        let token = try await auth.validAccessToken()
        let url = URL(string: "\(docsBase)/documents/\(documentId):batchUpdate")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = GoogleDocsMapper.batchUpdateBody(for: doc, currentEndIndex: currentEndIndex)

        let (data, response) = try await urlSession.data(for: request)
        try Self.checkOK(response, data)
    }

    // MARK: Helper

    private static func checkOK(_ response: URLResponse, _ data: Data) throws {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw GoogleDocsError.requestFailed(code, String(data: data, encoding: .utf8) ?? "(no body)")
        }
    }
}
