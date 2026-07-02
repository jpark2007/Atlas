import SwiftUI
import AtlasCore

/// An editable, date-parsed version of a `CaptureResult` — the result card mutates
/// these (fix the space, fix the due date, remove a row) before committing.
struct DraftItem: Identifiable {
    let id = UUID()
    var kind: String            // "task" | "event" | "note"
    var title: String
    var spaceName: String
    var projectName: String?
    var due: Date?
    var start: Date?
    var durationMin: Int?
    var notes: String?

    init(_ r: CaptureResult) {
        kind = r.kind
        title = r.title
        spaceName = r.spaceName
        projectName = r.projectName
        due = CaptureDateParser.date(from: r.dueISO)
        start = CaptureDateParser.date(from: r.startISO)
        durationMin = r.durationMin
        notes = r.notes
    }
}

/// The shared result card for voice + typed capture (spec §4.2 / §6). Editorial:
/// a titled block on the bg, rows separated by hairlines — no card chrome. Tap a
/// space/due chip to fix it, swipe a row to remove it, then commit or undo.
struct CaptureResultCard: View {
    @Binding var drafts: [DraftItem]
    let spaces: [Space]
    let onCommit: () -> Void
    let onUndo: () -> Void

    @State private var editingDueID: UUID?

    private var hasNote: Bool { drafts.contains { $0.kind == "note" } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Here’s what I made").edScreenTitle()
                Text(drafts.count == 1 ? "1 item" : "\(drafts.count) items").edCapsLabel()
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 12)

            List {
                ForEach($drafts) { $draft in
                    row($draft)
                        .listRowInsets(EdgeInsets(top: 14, leading: 28, bottom: 14, trailing: 28))
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(MobileTheme.hairline)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { remove(draft.id) } label: {
                                Label("Remove", systemImage: "xmark")
                            }
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            VStack(alignment: .leading, spacing: 16) {
                if hasNote {
                    Text("Notes are kept as tasks").edCapsLabel()
                }
                Button(action: onCommit) {
                    Text(commitTitle)
                        .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(MobileTheme.ink)
                        .frame(maxWidth: .infinity)
                        .edOutlineControl()
                }
                .buttonStyle(.plain)

                Button(action: onUndo) {
                    Text("Undo this batch")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(MobileTheme.muted)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: dueSheetPresented) {
            if let id = editingDueID, let i = drafts.firstIndex(where: { $0.id == id }) {
                dueEditor(index: i)
            }
        }
    }

    private var commitTitle: String {
        drafts.count == 1 ? "Looks good — add it" : "Looks good — add all \(drafts.count)"
    }

    // MARK: - Row

    private func row(_ draft: Binding<DraftItem>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(draft.wrappedValue.title)
                .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                .foregroundStyle(MobileTheme.ink)

            HStack(spacing: 10) {
                spaceMenu(draft)
                dot
                Text(draft.wrappedValue.kind)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .tracking(0.84).textCase(.uppercase)
                    .foregroundStyle(MobileTheme.muted)
                dot
                Button { editingDueID = draft.wrappedValue.id } label: { dueLabel(draft.wrappedValue) }
                    .buttonStyle(.plain)
            }
        }
    }

    private var dot: some View {
        Text("·").font(.system(size: 13, weight: .bold)).foregroundStyle(MobileTheme.faint)
    }

    private func spaceMenu(_ draft: Binding<DraftItem>) -> some View {
        Menu {
            ForEach(spaces) { s in
                Button(s.name) { draft.wrappedValue.spaceName = s.name }
            }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(color(for: draft.wrappedValue.spaceName)).frame(width: 8, height: 8)
                Text(draft.wrappedValue.spaceName)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.muted)
            }
        }
    }

    private func dueLabel(_ draft: DraftItem) -> some View {
        Text(draft.due == nil ? "add due" : "due \(TaskItem.dueLabel(for: draft.due))")
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(draft.due == nil ? MobileTheme.faint : MobileTheme.muted)
    }

    // MARK: - Due editor

    private var dueSheetPresented: Binding<Bool> {
        Binding(get: { editingDueID != nil },
                set: { if !$0 { editingDueID = nil } })
    }

    private func dueEditor(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Due date").edScreenTitle()
            DatePicker("", selection: Binding(
                get: { drafts[index].due ?? Date() },
                set: { drafts[index].due = $0 }),
                displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(MobileTheme.accentText)

            Button {
                drafts[index].due = nil
                editingDueID = nil
            } label: {
                Text("Remove due date")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(MobileTheme.muted)
            }
            .buttonStyle(.plain)

            Button { editingDueID = nil } label: {
                Text("Done")
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
                    .frame(maxWidth: .infinity)
                    .edOutlineControl()
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MobileTheme.bg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    // MARK: - Helpers

    private func remove(_ id: UUID) {
        drafts.removeAll { $0.id == id }
        if drafts.isEmpty { onUndo() }   // nothing left → dismiss the card
    }

    private func color(for spaceName: String) -> Color {
        spaces.first { $0.name.caseInsensitiveCompare(spaceName) == .orderedSame }?.color
            ?? MobileTheme.accent
    }
}
