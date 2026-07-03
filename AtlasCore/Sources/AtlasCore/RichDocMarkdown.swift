import Foundation

// MARK: - RichDoc ⇄ Markdown

/// Round-trip between `RichDoc` and Markdown, covering EXACTLY RichDoc's vocabulary
/// (block levels heading/subheading/normal/bulleted/numbered; inline bold/italic/
/// underline). This is the wire form for the Google-Docs two-way sync the design
/// doc mandates: the cron exports a Doc as Markdown → `RichDoc.fromMarkdown`, and
/// writes a note back as `richDoc.markdown` → Drive update-with-conversion.
///
/// **Round-trip guarantee:** within RichDoc's own vocabulary,
/// `fromMarkdown(doc.markdown)` reproduces `doc` for every block/inline combination
/// (see `RichDocMarkdownTests`). Delimiter-significant characters in text
/// (`\`, `*`, `<`) and leading block markers (`#`, `-`, `N.`) are backslash-escaped
/// so literal text never re-parses as structure.
///
/// **Lossy edge — underline → Google Doc:** underline has no standard-Markdown
/// token, so it is carried here as an inline `<u>…</u>` HTML span. That round-trips
/// through THIS converter, but Google Docs' Markdown→Doc import may not honor `<u>`,
/// so underline can still be dropped on the Doc side (the design doc's fidelity
/// contract — an Atlas save rewrites the Doc from Markdown).
extension RichDoc {

    /// The document rendered as Markdown, one block per line.
    public var markdown: String {
        var lines: [String] = []
        var numberedCounter = 0   // resets whenever a non-numbered block breaks the run
        for block in blocks {
            if block.kind == .numbered { numberedCounter += 1 } else { numberedCounter = 0 }
            let inline = Self.inlineMarkdown(for: block.runs)
            let line: String
            switch block.kind {
            case .heading:    line = "# " + inline
            case .subheading: line = "## " + inline
            case .bulleted:   line = "- " + inline
            case .numbered:   line = "\(numberedCounter). " + inline
            case .normal:     line = Self.escapingLeadingMarker(inline)
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    /// Parses Markdown (one block per line) back into a `RichDoc`. Recognizes the
    /// exact structure `markdown` emits, plus what Google Docs' `files.export`
    /// produces for the same vocabulary. Anything richer degrades to a `.normal`
    /// block of parsed inline runs. An empty string yields one empty `.normal`
    /// block (never zero blocks), matching `fromPlainText`.
    public static func fromMarkdown(_ text: String) -> RichDoc {
        let lines = text.isEmpty ? [""] : text.components(separatedBy: "\n")
        let blocks = lines.map { line -> Block in
            let (kind, content) = classify(line)
            return Block(kind: kind, runs: parseInline(content))
        }
        return RichDoc(blocks: blocks)
    }

    // MARK: Block classification (leading marker → kind + content)

    /// Maps a raw line to its block kind and the inline content that follows the
    /// marker. Order matters: `## ` is checked before `# `. An escaped leading
    /// marker (`\#`, `\-`, …) or any other line falls through to `.normal`, with the
    /// escape left in place for `parseInline` to unescape.
    static func classify(_ line: String) -> (RichDoc.BlockKind, String) {
        if line.hasPrefix("## ") { return (.subheading, String(line.dropFirst(3))) }
        if line.hasPrefix("# ")  { return (.heading,    String(line.dropFirst(2))) }
        if line.hasPrefix("- ")  { return (.bulleted,   String(line.dropFirst(2))) }
        if let content = numberedContent(line) { return (.numbered, content) }
        return (.normal, line)
    }

    /// Returns the content after a `N. ` ordered-list marker, or nil if the line
    /// isn't an ordered-list item.
    static func numberedContent(_ line: String) -> String? {
        let chars = Array(line)
        var i = 0
        while i < chars.count, chars[i].isNumber { i += 1 }
        guard i > 0, i + 1 < chars.count, chars[i] == ".", chars[i + 1] == " " else { return nil }
        return String(chars[(i + 2)...])
    }

    /// Backslash-escapes a leading `#`/`-`/`N.` so a `.normal` block whose text
    /// begins with a Markdown marker doesn't re-parse as a heading/list. Inline
    /// escaping (below) already handles a leading `*`/`<`/`\`.
    static func escapingLeadingMarker(_ inline: String) -> String {
        if inline.hasPrefix("# ") || inline.hasPrefix("## ") || inline.hasPrefix("- ")
            || numberedContent(inline) != nil {
            return "\\" + inline
        }
        return inline
    }

    // MARK: Inline serialization (runs → Markdown)

    /// Renders a block's runs as inline Markdown. Marks nest italic → bold →
    /// underline so `[bold,italic]` → `***text***` and `[all]` → `<u>***text***</u>`.
    /// Marks on an empty carrier run are dropped (they're invisible and would emit
    /// degenerate `****`).
    static func inlineMarkdown(for runs: [RichDoc.Run]) -> String {
        runs.map { run -> String in
            let escaped = escapeInline(run.text)
            guard !run.text.isEmpty else { return escaped }
            var s = escaped
            if run.marks.contains(.italic)    { s = "*\(s)*" }
            if run.marks.contains(.bold)      { s = "**\(s)**" }
            if run.marks.contains(.underline) { s = "<u>\(s)</u>" }
            return s
        }.joined()
    }

    /// Escapes the three delimiter-significant characters so literal text survives
    /// the inline parser: `\` `*` `<`.
    static func escapeInline(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text {
            switch ch {
            case "\\": out += "\\\\"
            case "*":  out += "\\*"
            case "<":  out += "\\<"
            default:   out.append(ch)
            }
        }
        return out
    }

    // MARK: Inline parsing (Markdown → runs)

    /// Parses inline Markdown into coalesced runs. Handles `\X` escapes, `<u>`/`</u>`
    /// underline spans, and `*`/`**`/`***` emphasis via toggle semantics (an opening
    /// delimiter turns a mark on, the matching one turns it off) — which is exactly
    /// what `inlineMarkdown` emits and what balanced Markdown provides.
    static func parseInline(_ s: String) -> [RichDoc.Run] {
        let chars = Array(s)
        var runs: [RichDoc.Run] = []
        var current = ""
        var marks: RichDoc.InlineMarks = []
        var i = 0

        func flush() {
            guard !current.isEmpty else { return }
            runs.append(RichDoc.Run(current, marks: marks))
            current = ""
        }

        while i < chars.count {
            let c = chars[i]
            // Escape: the next character is literal.
            if c == "\\", i + 1 < chars.count {
                current.append(chars[i + 1])
                i += 2
                continue
            }
            // Underline spans.
            if c == "<" {
                if matches(chars, at: i, "<u>")  { flush(); marks.insert(.underline);  i += 3; continue }
                if matches(chars, at: i, "</u>") { flush(); marks.remove(.underline);  i += 4; continue }
                current.append(c); i += 1; continue
            }
            // Emphasis: toggle by the length of the asterisk run.
            if c == "*" {
                var n = 0
                while i + n < chars.count, chars[i + n] == "*" { n += 1 }
                flush()
                switch n {
                case 1:  marks.formSymmetricDifference(.italic)
                case 2:  marks.formSymmetricDifference(.bold)
                default: marks.formSymmetricDifference([.bold, .italic]) // 3+ ⇒ both
                }
                i += n
                continue
            }
            current.append(c)
            i += 1
        }
        flush()
        return runs.isEmpty ? [RichDoc.Run("")] : runs
    }

    /// True when `token` appears at `index` in `chars`.
    static func matches(_ chars: [Character], at index: Int, _ token: String) -> Bool {
        let t = Array(token)
        guard index + t.count <= chars.count else { return false }
        for k in t.indices where chars[index + k] != t[k] { return false }
        return true
    }
}
