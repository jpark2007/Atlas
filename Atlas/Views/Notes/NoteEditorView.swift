import SwiftUI

/// Full-fidelity note editor matching `screenshots/note-edit.png`:
/// a title field, a multiline body editor, a "Saved in Atlas · backlinks live"
/// footer, and an orange Done button. Edits a working copy and commits on Done.
struct NoteEditorView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Note
    @FocusState private var bodyFocused: Bool

    /// `onDone` lets non-sheet hosts react; sheets can ignore it.
    private let onDone: ((Note) -> Void)?

    init(note: Note, onDone: ((Note) -> Void)? = nil) {
        _draft = State(initialValue: note)
        self.onDone = onDone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title
            TextField("Title", text: $draft.title)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 10)

            // Body editor with a faint mention-highlighted hint underneath.
            ZStack(alignment: .topLeading) {
                if draft.body.isEmpty {
                    Text("Start writing… use [[mentions]] to link classes, tasks and notes.")
                        .font(AtlasTheme.Font.body())
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                        .padding(.horizontal, 22)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $draft.body)
                    .focused($bodyFocused)
                    .font(AtlasTheme.Font.body())
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 14)
                    .padding(.top, 2)
            }
            .frame(minHeight: 160)

            // Live preview of the linked mentions (optional nicety).
            if draft.body.contains("[[") {
                Divider().overlay(AtlasTheme.Colors.border).padding(.horizontal, 18)
                Text(Note.highlighted(draft.body))
                    .font(AtlasTheme.Font.body())
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
            }

            Divider().overlay(AtlasTheme.Colors.border)

            // Footer
            HStack {
                Text("Saved in Atlas · backlinks live")
                    .font(AtlasTheme.Font.small())
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                Spacer()
                Button(action: commit) {
                    Text("Done")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
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
        .frame(width: 520)
        .frame(minHeight: 360)
        .background(AtlasTheme.Colors.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: AtlasTheme.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AtlasTheme.Radius.lg, style: .continuous)
                .stroke(AtlasTheme.Colors.border, lineWidth: 1)
        )
    }

    private func commit() {
        state.updateNote(draft)
        onDone?(draft)
        dismiss()
    }
}
