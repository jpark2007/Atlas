import SwiftUI
import AtlasCore

/// The full-page list of all notes. Standalone it opens the editor in a sheet;
/// inside Focus mode it is the work surface and hands opens to `onOpen` (which
/// presents the chromeless `NoteCardOverlay` corner card instead).
struct NotesListView: View {
    @EnvironmentObject private var state: AppState
    @State private var editingNote: Note?

    /// When set (Focus mode), row taps and "New" route the note here instead of the
    /// standalone sheet. `nil` keeps the standalone sheet behaviour.
    var onOpen: ((Note) -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Notes").atlasScreenTitle()
                    Spacer()
                    Button(action: newNote) {
                        Label("New", systemImage: "plus")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(AtlasTheme.Colors.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .overlay(
                                RoundedRectangle(cornerRadius: AtlasTheme.Radius.control, style: .continuous)
                                    .strokeBorder(AtlasTheme.Colors.textPrimary, lineWidth: AtlasTheme.rule)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 6)

                ForEach(state.notes) { note in
                    Button { open(note) } label: {
                        row(note)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
        }
        .background(AtlasTheme.Colors.bgBase)
        .sheet(item: $editingNote) { note in
            NoteEditorView(note: note)
                .padding(24)
                .background(AtlasTheme.Colors.bgDeep)
        }
    }

    private func newNote() {
        // Open an UNSAVED draft — an instant local note with no project and no Doc
        // pairing. NoteEditorView.commit() persists via updateNote (which inserts on
        // no-match), so dismissing without Done leaves no stray "Untitled note" behind.
        open(Note(title: "", body: ""))
    }

    /// Routes an open to the Focus corner card (`onOpen`) or the standalone sheet.
    private func open(_ note: Note) {
        if let onOpen { onOpen(note) } else { editingNote = note }
    }

    /// A note is a linked Doc-note when a `.docNote` reference points back at it.
    private func isLinkedDoc(_ note: Note) -> Bool {
        state.references.contains { $0.kind == .docNote && $0.noteID == note.id }
    }

    private func row(_ note: Note) -> some View {
        let linkedDoc = isLinkedDoc(note)
        return AtlasCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: linkedDoc ? "doc.richtext" : (note.isExternal ? "doc.text.fill" : "note.text"))
                    .font(.system(size: 14))
                    .foregroundStyle(linkedDoc ? AtlasTheme.Colors.accentText : AtlasTheme.Colors.textMuted)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(note.title)
                        .atlasTitleSerif(size: 14)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Text(Note.highlighted(note.previewText))
                        .font(AtlasTheme.Font.small())
                        .foregroundStyle(AtlasTheme.Colors.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                if linkedDoc {
                    atlasTag(text: "Google Doc", color: AtlasTheme.Colors.accentText)
                } else if note.isExternal {
                    Text("Open ↗")
                        .font(AtlasTheme.Font.small())
                        .foregroundStyle(AtlasTheme.Colors.accentText)
                }
            }
        }
    }
}
