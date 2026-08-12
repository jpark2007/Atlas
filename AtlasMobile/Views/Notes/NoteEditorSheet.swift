import SwiftUI
import AtlasCore

/// Tap-to-edit sheet for a single note — title, space, body. Editorial field style
/// (caps label over a control, hairline below) matching `ItemDetailSheet`.
///
/// External notes (a linked Google Doc) render read-only: the Doc is the styling
/// master and Atlas only writes the constrained subset from the Mac's rich editor,
/// so a plain-text overwrite from the phone would flatten it.
struct NoteEditorSheet: View {

    let note: Note
    /// True when this sheet created the note — Cancel then discards it entirely
    /// rather than leaving an empty row behind.
    let isNew: Bool

    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var spaceName: String
    @State private var body_: String
    @State private var showDeleteConfirm = false

    init(note: Note, isNew: Bool = false) {
        self.note = note
        self.isNew = isNew
        _title = State(initialValue: note.title)
        _spaceName = State(initialValue: note.spaceName ?? "")
        _body_ = State(initialValue: note.body)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Note")
                    .edScreenTitle()
                    .padding(.bottom, 24)

                if note.isExternal {
                    Text("Linked Google Doc — read-only on iPhone")
                        .edCapsLabel()
                        .padding(.bottom, 8)
                    labeledRow("Title", note.title)
                    labeledRow("Space", note.spaceName ?? "No space")
                    labeledRow("Body", note.body.isEmpty ? "Open on Mac to read" : note.body)
                } else {
                    field("Title") { titleField }
                    field("Space") { spacePicker }
                    field("Body") { bodyEditor }
                }

                footer
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
        }
        .background(MobileTheme.bg.ignoresSafeArea())
        .presentationDetents([.large])
        .confirmationDialog("Delete this note?",
                            isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { await store.deleteNote(id: note.id) }
                dismiss()
            }
        }
    }

    private var titleField: some View {
        TextField("Untitled", text: $title)
            .textFieldStyle(.plain)
            .font(.system(size: 17, weight: .regular, design: .rounded))
            .foregroundStyle(MobileTheme.ink)
            .tint(MobileTheme.accent)
    }

    /// Space menu with a "None" rung — notes may be loose (`spaceName == nil`),
    /// unlike tasks and events.
    private var spacePicker: some View {
        Menu {
            Button { spaceName = "" } label: {
                if spaceName.isEmpty {
                    Label("None", systemImage: "checkmark")
                } else {
                    Text("None")
                }
            }
            ForEach(store.snapshot.spaces) { space in
                Button { spaceName = space.name } label: {
                    if space.name.caseInsensitiveCompare(spaceName) == .orderedSame {
                        Label(space.name, systemImage: "checkmark")
                    } else {
                        Text(space.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                if let space = selectedSpace {
                    Circle().fill(space.color).frame(width: 9, height: 9)
                    Text(space.name)
                        .font(.system(size: 17, weight: .regular, design: .rounded))
                        .foregroundStyle(MobileTheme.ink)
                } else {
                    Text("None")
                        .font(.system(size: 17, weight: .regular, design: .rounded))
                        .foregroundStyle(MobileTheme.faint)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MobileTheme.muted)
            }
        }
    }

    /// Plain-text editor. A `.md` note keeps its format — you're editing the
    /// Markdown source, which round-trips to the Mac's rich editor untouched.
    private var bodyEditor: some View {
        TextEditor(text: $body_)
            .scrollContentBackground(.hidden)
            .font(.system(size: 17, weight: .regular, design: .rounded))
            .foregroundStyle(MobileTheme.ink)
            .tint(MobileTheme.accent)
            .frame(minHeight: 260)
    }

    private func labeledRow(_ label: String, _ value: String) -> some View {
        field(label) {
            Text(value)
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .foregroundStyle(MobileTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        VStack(spacing: 16) {
            if !note.isExternal {
                Button(action: save) {
                    Text("Save")
                        .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(MobileTheme.ink)
                        .frame(maxWidth: .infinity)
                        .edOutlineControl()
                }
                .buttonStyle(.plain)
            }

            if !isNew {
                Button { showDeleteConfirm = true } label: {
                    Text("Delete")
                        .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.danger)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }

            Button { dismiss() } label: {
                Text("Cancel")
                    .edCapsLabel()
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 28)
        .padding(.bottom, 20)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).edCapsLabel()
            content()
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .edHairlineBelow()
    }

    private var selectedSpace: Space? {
        store.snapshot.spaces.first { $0.name.caseInsensitiveCompare(spaceName) == .orderedSame }
    }

    private func save() {
        var updated = note
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.title = trimmed.isEmpty ? "Untitled" : trimmed
        updated.body = body_
        updated.spaceName = selectedSpace?.name
        updated.spaceID = selectedSpace?.id
        updated.updatedAt = Date()
        Task {
            if isNew { await store.addNote(updated) } else { await store.updateNote(updated) }
        }
        MobileTheme.Haptic.success()
        dismiss()
    }
}
