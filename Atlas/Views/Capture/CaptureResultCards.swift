import SwiftUI
import AtlasCore

// MARK: - Committed capture results with chip corrections (Phase 4 §3)
//
// Enter commits. These cards are NOT a review screen — everything on them is
// already saved. They exist so a wrong guess is ≤2 clicks from right:
// Class ▾ · Type ▾ · Due ▾, plus per-item Undo and "Undo all".

/// One committed item on screen: its live history snapshot plus whether the
/// model told us it was unsure (which only ever shows as a quiet marker).
struct CommittedCapture: Identifiable, Equatable {
    var item: CaptureHistoryItem
    var lowConfidence: Bool
    var id: UUID { item.id }
}

struct CaptureResultCards: View {
    @EnvironmentObject private var state: AppState

    @Binding var items: [CommittedCapture]
    let entryID: UUID
    let onUndoAll: () -> Void

    /// The card whose "Pick a date…" popover is open.
    @State private var pickingDateFor: UUID?
    @State private var pickedDate = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { entry in
                        card(entry)
                        if entry.id != items.last?.id {
                            Rectangle()
                                .fill(AtlasTheme.Colors.border)
                                .frame(height: 1)
                        }
                    }
                }
            }
            .frame(maxHeight: 260)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    private var header: some View {
        HStack {
            Text(items.count == 1 ? "Added 1 item" : "Added \(items.count) items")
                .atlasFont(size: 12, weight: .semibold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
            Spacer()
            Button(action: onUndoAll) {
                Text("Undo all")
                    .atlasFont(size: 12, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.accentText)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
    }

    // MARK: - One card

    private func card(_ entry: CommittedCapture) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text(entry.item.title)
                    .atlasFont(size: 14, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    classChip(entry)
                    typeChip(entry)
                    dueChip(entry)
                }
            }
            Spacer(minLength: 8)
            Button { undoOne(entry) } label: {
                Text("Undo")
                    .atlasFont(size: 12, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            .buttonStyle(.plain)
            .help("Remove this item")
        }
        .padding(.vertical, 11)
    }

    // MARK: - Chips

    private func classChip(_ entry: CommittedCapture) -> some View {
        Menu {
            if !classes.isEmpty {
                Section("Classes") {
                    ForEach(classes) { project in
                        Button(classLabel(project)) {
                            apply(entry) {
                                state.recaptureSpace($0, spaceName: project.spaceName,
                                                     projectName: project.name)
                            }
                        }
                    }
                }
            }
            Section("Spaces") {
                ForEach(state.spaces) { space in
                    Button(space.name) {
                        apply(entry) {
                            state.recaptureSpace($0, spaceName: space.name, projectName: "")
                        }
                    }
                }
            }
        } label: {
            chipLabel(classChipText(entry.item), unsure: entry.lowConfidence)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func typeChip(_ entry: CommittedCapture) -> some View {
        Menu {
            ForEach(CaptureItemType.allCases) { type in
                Button(type.label) {
                    apply(entry) { state.recaptureType($0, to: type) }
                }
            }
        } label: {
            chipLabel(CaptureItemType.of(entry.item).label, unsure: entry.lowConfidence)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        // Converting an item capture only UPDATED would delete something the
        // user already had, so the chip reads but doesn't change there.
        .disabled(entry.item.priorTask != nil)
    }

    private func dueChip(_ entry: CommittedCapture) -> some View {
        Menu {
            Button("Today") { setDue(entry, Self.startOfToday) }
            Button("Tomorrow") { setDue(entry, Self.offsetDays(1)) }
            Button("Next week") { setDue(entry, Self.offsetDays(7)) }
            Button("Pick a date…") {
                pickedDate = entry.item.dueDate ?? entry.item.start ?? Date()
                pickingDateFor = entry.id
            }
            if entry.item.kind == .task {
                Divider()
                Button("No date") { setDue(entry, nil) }
            }
        } label: {
            chipLabel(dueChipText(entry.item), unsure: entry.lowConfidence)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(entry.item.kind == .note)
        .popover(isPresented: datePopover(entry.id), arrowEdge: .bottom) {
            VStack(spacing: 12) {
                DatePicker("", selection: $pickedDate)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                Button("Set") {
                    setDue(entry, pickedDate)
                    pickingDateFor = nil
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
    }

    /// The chip itself. An unsure parse gets a quiet dashed underline — never a
    /// dialog, never a word of alarm (Phase 4 §3).
    private func chipLabel(_ text: String, unsure: Bool) -> some View {
        HStack(spacing: 3) {
            Text(text)
                .atlasFont(size: 11.5, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .atlasFont(size: 8, weight: .semibold)
                .foregroundStyle(AtlasTheme.Colors.textMuted.opacity(0.7))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    unsure ? AtlasTheme.Colors.accentText.opacity(0.55) : AtlasTheme.Colors.border,
                    style: StrokeStyle(lineWidth: 1, dash: unsure ? [3, 2] : [])
                )
        )
        .help(unsure ? "Atlas wasn’t sure — click to fix" : "Click to change")
    }

    // MARK: - Chip copy

    private func classChipText(_ item: CaptureHistoryItem) -> String {
        if !item.projectName.isEmpty { return item.projectName }
        return item.spaceName.isEmpty ? "Unfiled" : item.spaceName
    }

    private func dueChipText(_ item: CaptureHistoryItem) -> String {
        guard let date = item.dueDate ?? item.start else { return "No date" }
        return Self.dayFormatter.string(from: date)
    }

    private var classes: [Project] {
        state.spaces.flatMap(\.projects).filter(\.isClass)
    }

    private func classLabel(_ project: Project) -> String {
        guard let code = project.code?.trimmingCharacters(in: .whitespacesAndNewlines),
              !code.isEmpty else { return project.name }
        return "\(code) · \(project.name)"
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static var startOfToday: Date { Calendar.current.startOfDay(for: Date()) }

    private static func offsetDays(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: startOfToday) ?? startOfToday
    }

    // MARK: - Applying a correction

    /// Run one correction and swap the refreshed snapshot into both the cards and
    /// the recorded capture entry, so per-item Undo keeps pointing at the object
    /// that actually exists. A correction that can't apply leaves the card alone.
    private func apply(_ entry: CommittedCapture,
                       _ mutate: (CaptureHistoryItem) -> CaptureHistoryItem?) {
        guard let updated = mutate(entry.item),
              let index = items.firstIndex(where: { $0.id == entry.id }) else { return }
        state.replaceCapturedItem(entry.item, with: updated, inEntry: entryID)
        // A correction is the user's own choice — it is no longer an unsure guess.
        items[index] = CommittedCapture(item: updated, lowConfidence: false)
    }

    private func setDue(_ entry: CommittedCapture, _ date: Date?) {
        apply(entry) { state.recaptureDue($0, date: date) }
    }

    private func undoOne(_ entry: CommittedCapture) {
        state.undoCapturedItem(entry.item, inEntry: entryID)
        items.removeAll { $0.id == entry.id }
        if items.isEmpty { onUndoAll() }
    }

    private func datePopover(_ id: UUID) -> Binding<Bool> {
        Binding(get: { pickingDateFor == id },
                set: { if !$0 { pickingDateFor = nil } })
    }
}
