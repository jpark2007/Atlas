import SwiftUI

/// The constrained Atlas notes editor (WS-10). A focused rich-text view over a
/// `RichDoc` whose ONLY styling is the allowed subset:
///   • Block levels: Heading / Sub-heading / Normal — each with custom AtlasTheme
///     typography.
///   • Inline marks: bold / italic / underline (applied per focused block).
///   • Lists: bulleted / numbered.
/// Nothing else. The backing Google Doc is the styling master; this editor maps
/// onto that subset (see `GoogleDocsMapper`). Edits a working copy and commits on
/// Done — `init(note:onDone:)` is preserved so existing hosts keep compiling.
struct NoteEditorView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Note
    @State private var doc: RichDoc
    @FocusState private var focusedBlock: UUID?

    private let onDone: ((Note) -> Void)?

    init(note: Note, onDone: ((Note) -> Void)? = nil) {
        _draft = State(initialValue: note)
        _doc = State(initialValue: RichDoc.fromPlainText(note.body))
        self.onDone = onDone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Title", text: $draft.title)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 10)

            styleBar

            Divider().overlay(AtlasTheme.Colors.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(doc.blocks.enumerated()), id: \.element.id) { index, block in
                        blockRow(index: index, block: block)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .frame(minHeight: 200)

            Divider().overlay(AtlasTheme.Colors.border)

            footer
        }
        .frame(width: 560)
        .frame(minHeight: 420)
        .background(AtlasTheme.Colors.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: AtlasTheme.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AtlasTheme.Radius.lg, style: .continuous)
                .stroke(AtlasTheme.Colors.border, lineWidth: 1)
        )
    }

    // MARK: - Style bar (the only styling Atlas allows)

    private var styleBar: some View {
        HStack(spacing: 6) {
            levelButton("Heading", kind: .heading)
            levelButton("Sub-heading", kind: .subheading)
            levelButton("Normal", kind: .normal)

            Divider().frame(height: 16).overlay(AtlasTheme.Colors.border)

            markButton("bold", mark: .bold)
            markButton("italic", mark: .italic)
            markButton("underline", mark: .underline)

            Divider().frame(height: 16).overlay(AtlasTheme.Colors.border)

            listButton("list.bullet", kind: .bulleted)
            listButton("list.number", kind: .numbered)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func levelButton(_ title: String, kind: RichDoc.BlockKind) -> some View {
        Button { doc.setKind(kind, at: activeIndex) } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isActiveKind(kind) ? AtlasTheme.Colors.bgDeep : AtlasTheme.Colors.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isActiveKind(kind) ? AtlasTheme.Colors.accent : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func markButton(_ systemImage: String, mark: RichDoc.InlineMarks) -> some View {
        Button { doc.toggleMark(mark, at: activeIndex) } label: {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isActiveMark(mark) ? AtlasTheme.Colors.accent : AtlasTheme.Colors.textSecondary)
                .frame(width: 24, height: 22)
                .background(isActiveMark(mark) ? AtlasTheme.Colors.accent.opacity(0.14) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func listButton(_ systemImage: String, kind: RichDoc.BlockKind) -> some View {
        Button { doc.toggleListKind(kind, at: activeIndex) } label: {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isActiveKind(kind) ? AtlasTheme.Colors.accent : AtlasTheme.Colors.textSecondary)
                .frame(width: 24, height: 22)
                .background(isActiveKind(kind) ? AtlasTheme.Colors.accent.opacity(0.14) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Block row

    @ViewBuilder
    private func blockRow(index: Int, block: RichDoc.Block) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if block.kind.isList {
                Text(listGlyph(for: index, block: block))
                    .font(AtlasTheme.Font.body())
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .frame(minWidth: 18, alignment: .trailing)
            }
            TextField("", text: textBinding(for: index), axis: .vertical)
                .textFieldStyle(.plain)
                .font(font(for: block.kind))
                .bold(block.uniformMarks.contains(.bold))
                .italic(block.uniformMarks.contains(.italic))
                .underline(block.uniformMarks.contains(.underline))
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .focused($focusedBlock, equals: block.id)
                .onSubmit { addBlockAfter(index) }
        }
    }

    private func listGlyph(for index: Int, block: RichDoc.Block) -> String {
        block.kind == .numbered ? "\(numberOrdinal(at: index))." : "•"
    }

    /// Ordinal within the contiguous run of numbered blocks ending at `index`.
    private func numberOrdinal(at index: Int) -> Int {
        var ordinal = 1
        var i = index - 1
        while i >= 0, doc.blocks[i].kind == .numbered {
            ordinal += 1
            i -= 1
        }
        return ordinal
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text(draft.googleDocId == nil
                 ? "Saved in Atlas · constrained editor"
                 : "Synced with Google Doc")
                .font(AtlasTheme.Font.small())
                .foregroundStyle(AtlasTheme.Colors.textMuted)
            Spacer()
            Button { addBlockAfter(doc.blocks.count - 1) } label: {
                Label("Block", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            Button(action: commit) {
                Text("Done")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AtlasTheme.Colors.bgDeep)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 7)
                    .background(AtlasTheme.Colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - Editing helpers

    /// The block the style bar acts on — the focused block, else the last block.
    private var activeIndex: Int {
        if let id = focusedBlock, let index = doc.blocks.firstIndex(where: { $0.id == id }) {
            return index
        }
        return max(0, doc.blocks.count - 1)
    }

    private func isActiveKind(_ kind: RichDoc.BlockKind) -> Bool {
        doc.blocks.indices.contains(activeIndex) && doc.blocks[activeIndex].kind == kind
    }

    private func isActiveMark(_ mark: RichDoc.InlineMarks) -> Bool {
        doc.blocks.indices.contains(activeIndex) && doc.blocks[activeIndex].uniformMarks.contains(mark)
    }

    private func textBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { doc.blocks.indices.contains(index) ? doc.blocks[index].text : "" },
            set: { newValue in
                guard doc.blocks.indices.contains(index) else { return }
                doc.blocks[index].setText(newValue)
            })
    }

    private func addBlockAfter(_ index: Int) {
        let newID = doc.insertBlock(after: index)
        DispatchQueue.main.async { focusedBlock = newID }
    }

    private func font(for kind: RichDoc.BlockKind) -> Font {
        switch kind {
        case .heading:    return .system(size: 22, weight: .bold)
        case .subheading: return .system(size: 17, weight: .semibold)
        case .normal, .bulleted, .numbered: return AtlasTheme.Font.body()
        }
    }

    private func commit() {
        doc.normalize()
        var updated = draft
        updated.body = doc.plainText
        state.updateNote(updated)
        onDone?(updated)
        dismiss()
    }
}
