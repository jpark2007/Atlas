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
    @State private var appeared = false

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
                    let index = drafts.firstIndex { $0.id == draft.id } ?? 0
                    row($draft)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 14)
                        .animation(MobileTheme.heroSpring.delay(Double(index) * 0.07),
                                   value: appeared)
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
        .onAppear { appeared = true }
        .sheet(isPresented: dueSheetPresented) {
            if let id = editingDueID, let i = drafts.firstIndex(where: { $0.id == id }) {
                DueEditorSheet(
                    draft: Binding(get: { drafts[i] }, set: { drafts[i] = $0 }),
                    onClose: { editingDueID = nil })
            }
        }
    }

    private var commitTitle: String {
        drafts.count == 1 ? "Looks good — add it" : "Looks good — add all \(drafts.count)"
    }

    // MARK: - Row

    private func row(_ draft: Binding<DraftItem>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Space-color edge (spec §4): routing is visible at a glance.
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color(for: draft.wrappedValue.spaceName))
                .frame(width: 3)
                .padding(.vertical, 2)

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
                    Button { editingDueID = draft.wrappedValue.id } label: {
                        if draft.wrappedValue.kind == "event" {
                            eventLabel(draft.wrappedValue)
                        } else {
                            dueLabel(draft.wrappedValue)
                        }
                    }
                    .buttonStyle(.plain)
                }
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

    /// Event chip — the stated start time is sacred, so it's visible pre-commit:
    /// "Jul 3 · 5:30 PM" (+ "· 60 min" when a duration is set).
    private func eventLabel(_ draft: DraftItem) -> some View {
        Text(CaptureResultCard.eventLabelText(draft))
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(draft.start == nil ? MobileTheme.faint : MobileTheme.muted)
    }

    private static func eventLabelText(_ draft: DraftItem) -> String {
        guard let start = draft.start else { return "add time" }
        let d = DateFormatter(); d.dateFormat = "MMM d"
        let t = DateFormatter(); t.dateFormat = "h:mm a"
        var s = "\(d.string(from: start)) · \(t.string(from: start))"
        if let dur = draft.durationMin { s += " · \(dur) min" }
        return s
    }

    // MARK: - Due editor

    private var dueSheetPresented: Binding<Bool> {
        Binding(get: { editingDueID != nil },
                set: { if !$0 { editingDueID = nil } })
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

/// Edits one draft's date/time before commit. Tasks write into `due`; events edit
/// `start`'s day + time (stated times are sacred). Local state so Cancel discards —
/// Done is the only path that writes back. Mirrors ManualAddSheet's `dueSection`.
private struct DueEditorSheet: View {
    @Binding var draft: DraftItem
    let onClose: () -> Void

    @State private var day: Date
    @State private var setTime: Bool
    @State private var timeOfDay: Date

    private var isEvent: Bool { draft.kind == "event" }

    init(draft: Binding<DraftItem>, onClose: @escaping () -> Void) {
        _draft = draft
        self.onClose = onClose
        let d = draft.wrappedValue
        let base = (d.kind == "event" ? d.start : d.due) ?? Date()
        _day = State(initialValue: base)
        _timeOfDay = State(initialValue: base)
        // Events always carry a time; tasks only when their date has a clock time.
        let c = Calendar.current.dateComponents([.hour, .minute], from: base)
        _setTime = State(initialValue: d.kind == "event" || c.hour != 0 || c.minute != 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(isEvent ? "Event time" : "Due date").edScreenTitle()

            DatePicker("", selection: $day, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(MobileTheme.accentText)

            Toggle(isOn: $setTime.animation()) {
                Text("Set a time").edCapsLabel()
            }
            .tint(MobileTheme.ink)
            .padding(.vertical, 14)
            .edHairlineBelow()

            if setTime {
                DatePicker("", selection: $timeOfDay, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
            }

            Button(action: apply) {
                Text("Done")
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
                    .frame(maxWidth: .infinity)
                    .edOutlineControl()
            }
            .buttonStyle(.plain)

            HStack {
                Button { onClose() } label: {
                    Text("Cancel").edCapsLabel()
                }
                .buttonStyle(.plain)

                if !isEvent {
                    Spacer()
                    Button {
                        draft.due = nil
                        onClose()
                    } label: {
                        Text("Remove due date")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(MobileTheme.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MobileTheme.bg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    private func apply() {
        let cal = Calendar.current
        let base = cal.startOfDay(for: day)
        let final: Date
        if setTime {
            let c = cal.dateComponents([.hour, .minute], from: timeOfDay)
            final = cal.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: base) ?? base
        } else {
            final = base
        }
        if isEvent { draft.start = final } else { draft.due = final }
        onClose()
    }
}
