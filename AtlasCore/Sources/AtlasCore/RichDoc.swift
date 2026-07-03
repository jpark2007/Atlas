import Foundation

/// The constrained rich-text document model backing the Atlas notes editor.
///
/// It captures EXACTLY the styling subset Atlas allows — nothing more:
///   • Block levels: `heading`, `subheading`, `normal`, `bulleted`, `numbered`.
///   • Inline marks: `bold`, `italic`, `underline`.
///
/// No arbitrary fonts / sizes / colors / tables. The Google Doc is the styling
/// MASTER (full fidelity); this model is the slimmed-down subset Atlas edits and
/// maps cleanly onto Doc heading styles, lists, and bold/italic/underline.
public struct RichDoc: Equatable, Codable {
    public var blocks: [Block]

    public init(blocks: [Block] = []) {
        self.blocks = blocks
    }
}

extension RichDoc {

    // MARK: - Block kind

    /// A paragraph's block level. `heading`/`subheading`/`normal` are exclusive
    /// text levels; `bulleted`/`numbered` are list items.
    public enum BlockKind: String, Codable, CaseIterable {
        case heading
        case subheading
        case normal
        case bulleted
        case numbered

        public var isList: Bool { self == .bulleted || self == .numbered }
    }

    // MARK: - Inline marks

    /// The inline character styling Atlas supports. Stored as a bitset so a run
    /// can carry any combination of bold/italic/underline.
    public struct InlineMarks: OptionSet, Equatable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let bold      = InlineMarks(rawValue: 1 << 0)
        public static let italic    = InlineMarks(rawValue: 1 << 1)
        public static let underline = InlineMarks(rawValue: 1 << 2)
    }

    // MARK: - Run

    /// A maximal span of text sharing one set of inline marks.
    public struct Run: Equatable, Codable {
        public var text: String
        public var marks: InlineMarks

        public init(_ text: String, marks: InlineMarks = []) {
            self.text = text
            self.marks = marks
        }
    }

    // MARK: - Block

    /// A single paragraph: a block level plus the inline runs that compose it.
    /// Canonical form keeps `runs` non-empty (an empty paragraph is `[Run("")]`)
    /// so the carrier run can still hold marks (e.g. a freshly bolded empty line).
    public struct Block: Equatable, Codable, Identifiable {
        public var id: UUID
        public var kind: BlockKind
        public var runs: [Run]

        public init(id: UUID = UUID(), kind: BlockKind = .normal, runs: [Run] = [Run("")]) {
            self.id = id
            self.kind = kind
            self.runs = runs.isEmpty ? [Run("")] : runs
        }

        /// Content equality ignores `id` (which is identity-only, for `ForEach`).
        /// Two blocks are equal when their level and runs match — what
        /// `NoteSync.reconcile` and the Docs round-trip tests care about.
        public static func == (lhs: Block, rhs: Block) -> Bool {
            lhs.kind == rhs.kind && lhs.runs == rhs.runs
        }

        /// The block's plain text (no list glyphs).
        public var text: String { runs.map(\.text).joined() }

        /// Marks active across the *whole* block — a mark counts only when every
        /// run carries it. Drives the editor's B/I/U toggle highlight state.
        public var uniformMarks: InlineMarks {
            guard let first = runs.first else { return [] }
            return runs.dropFirst().reduce(first.marks) { $0.intersection($1.marks) }
        }

        /// Replaces the block's text wholesale (the plain-`TextField` edit path),
        /// collapsing to one run that inherits `marks` (defaults to the current
        /// uniform marks so toggling B then typing keeps bold).
        public mutating func setText(_ newText: String, marks: InlineMarks? = nil) {
            runs = [Run(newText, marks: marks ?? uniformMarks)]
        }

        /// Toggles an inline mark over `range` (character offsets into `text`),
        /// or the whole block when `range` is nil. If every character in range
        /// already has the mark it's removed, otherwise added — then runs are
        /// re-coalesced so adjacent equal-mark spans merge.
        public mutating func toggleMark(_ mark: InlineMarks, range: Range<Int>? = nil) {
            let chars = Array(text)
            // Empty paragraph: toggle on the single carrier run.
            if chars.isEmpty {
                var m = runs.first?.marks ?? []
                if m.contains(mark) { m.remove(mark) } else { m.insert(mark) }
                runs = [Run("", marks: m)]
                return
            }
            let full = 0..<chars.count
            let r = Self.clamp(range ?? full, to: full)
            guard !r.isEmpty else { return }

            var marks = charMarks()
            let allHave = r.allSatisfy { marks[$0].contains(mark) }
            for i in r {
                if allHave { marks[i].remove(mark) } else { marks[i].insert(mark) }
            }
            runs = Self.buildRuns(chars: chars, marks: marks)
        }

        /// Re-coalesces runs (merges adjacent equal-mark spans, drops the
        /// redundant structure). A no-op on already-canonical blocks.
        public mutating func normalize() {
            let chars = Array(text)
            runs = chars.isEmpty ? [Run("", marks: runs.first?.marks ?? [])]
                                 : Self.buildRuns(chars: chars, marks: charMarks())
        }

        /// Per-character marks expanded from the runs.
        public func charMarks() -> [InlineMarks] {
            var out: [InlineMarks] = []
            for run in runs {
                out.append(contentsOf: Array(repeating: run.marks, count: run.text.count))
            }
            return out
        }

        /// Groups a (chars, per-char marks) pair back into maximal runs.
        static func buildRuns(chars: [Character], marks: [InlineMarks]) -> [Run] {
            guard !chars.isEmpty else { return [Run("")] }
            var runs: [Run] = []
            var currentMarks = marks[0]
            var currentText = String(chars[0])
            for i in 1..<chars.count {
                if marks[i] == currentMarks {
                    currentText.append(chars[i])
                } else {
                    runs.append(Run(currentText, marks: currentMarks))
                    currentMarks = marks[i]
                    currentText = String(chars[i])
                }
            }
            runs.append(Run(currentText, marks: currentMarks))
            return runs
        }

        private static func clamp(_ range: Range<Int>, to bounds: Range<Int>) -> Range<Int> {
            let lower = Swift.max(bounds.lowerBound, Swift.min(range.lowerBound, bounds.upperBound))
            let upper = Swift.max(lower, Swift.min(range.upperBound, bounds.upperBound))
            return lower..<upper
        }
    }
}

// MARK: - Document-level helpers

extension RichDoc {

    /// The whole document's plain text (blocks joined by newlines, no list
    /// glyphs) — what Atlas stores in `Note.body` for ⌘K search and `[[mentions]]`.
    public var plainText: String {
        blocks.map(\.text).joined(separator: "\n")
    }

    /// Seeds a document from plain text: each line becomes a `.normal` block.
    /// An empty string yields a single empty block (never zero blocks).
    public static func fromPlainText(_ text: String) -> RichDoc {
        let lines = text.isEmpty ? [""] : text.components(separatedBy: "\n")
        return RichDoc(blocks: lines.map { Block(kind: .normal, runs: [Run($0)]) })
    }

    /// Sets a block's level (no-op for an out-of-range index).
    public mutating func setKind(_ kind: BlockKind, at index: Int) {
        guard blocks.indices.contains(index) else { return }
        blocks[index].kind = kind
    }

    /// Toggles a list level: applies it, or reverts to `.normal` if the block is
    /// already that list kind (clicking "bulleted" twice un-bullets).
    public mutating func toggleListKind(_ kind: BlockKind, at index: Int) {
        guard kind.isList, blocks.indices.contains(index) else { return }
        blocks[index].kind = (blocks[index].kind == kind) ? .normal : kind
    }

    /// Toggles an inline mark on a block (whole block, or a character range).
    public mutating func toggleMark(_ mark: InlineMarks, at index: Int, range: Range<Int>? = nil) {
        guard blocks.indices.contains(index) else { return }
        blocks[index].toggleMark(mark, range: range)
    }

    /// Inserts an empty `.normal` block after `index` and returns its id.
    @discardableResult
    public mutating func insertBlock(after index: Int, kind: BlockKind = .normal) -> UUID {
        let block = Block(kind: kind)
        let target = blocks.indices.contains(index) ? index + 1 : blocks.count
        blocks.insert(block, at: target)
        return block.id
    }

    /// Removes a block, keeping at least one (clearing the last block instead of
    /// emptying the document).
    public mutating func removeBlock(at index: Int) {
        guard blocks.indices.contains(index) else { return }
        if blocks.count == 1 {
            blocks[0] = Block()
        } else {
            blocks.remove(at: index)
        }
    }

    /// Re-coalesces every block's runs.
    public mutating func normalize() {
        for i in blocks.indices { blocks[i].normalize() }
    }
}

// MARK: - InlineMarks Codable

extension RichDoc.InlineMarks: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(Int.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
