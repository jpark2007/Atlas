import SwiftUI
import AtlasCore

/// Settings → History. Lists past quick-captures newest first — each shows its
/// text snippet and when it ran, expands (RevealRow idiom) to the items it
/// created, and offers a single Undo that deletes those items. Undo is enabled
/// only while every item still matches its capture-time snapshot.
struct CaptureHistorySection: View {
    @EnvironmentObject private var state: AppState

    /// Which entries are expanded to show their item list.
    @State private var expanded: Set<UUID> = []
    /// The entry pending an Undo confirmation.
    @State private var confirmingUndo: CaptureHistoryEntry? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if state.captureHistory.isEmpty {
                    emptyState
                } else {
                    ForEach(state.captureHistory) { entry in
                        entryRow(entry)
                    }
                }
                Spacer(minLength: 8)
            }
            .padding(28)
        }
        .confirmationDialog(
            "Undo this capture?",
            isPresented: Binding(get: { confirmingUndo != nil },
                                 set: { if !$0 { confirmingUndo = nil } }),
            titleVisibility: .visible,
            presenting: confirmingUndo
        ) { entry in
            Button("Delete \(entry.items.count) \(itemNoun(entry.items.count))", role: .destructive) {
                state.undoCapture(entry)
                confirmingUndo = nil
            }
            Button("Cancel", role: .cancel) { confirmingUndo = nil }
        } message: { _ in
            Text("This deletes everything this capture created. This can't be undone.")
        }
    }

    // MARK: – Header + empty state

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("CAPTURE HISTORY")
            Text("Recent quick-captures and the items they created. Undo removes a capture's items, and stays available only while they haven't changed.")
                .atlasFont(size: 11, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
    }

    private var emptyState: some View {
        Text("No captures yet. Anything you add from the quick-capture bar shows up here.")
            .atlasFont(size: 13, weight: .medium, design: .rounded)
            .foregroundStyle(AtlasTheme.Colors.textMuted)
            .padding(.top, 4)
    }

    // MARK: – One capture row

    @ViewBuilder
    private func entryRow(_ entry: CaptureHistoryEntry) -> some View {
        let isOpen = expanded.contains(entry.id)
        let eligible = state.captureUndoEligible(entry)

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.snippet.isEmpty ? "Capture" : entry.snippet)
                        .atlasFont(size: 14, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        .lineLimit(2)
                    Text(Self.dateLabel(entry.date))
                        .atlasMono(size: 11)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                Spacer()
                undoControl(entry, eligible: eligible)
            }

            RevealRow(count: entry.items.count,
                      noun: itemNoun(entry.items.count),
                      isOpen: binding(for: entry.id))

            if isOpen {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entry.items) { item in
                        itemRow(item)
                    }
                }
                .padding(.leading, 2)
                .padding(.bottom, 2)
            }

            // Quiet note when undo is off because the items were touched.
            if entry.undoneAt == nil && !eligible {
                Text("Items changed since capture")
                    .atlasFont(size: 11, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .atlasHairlineBelow()
    }

    @ViewBuilder
    private func undoControl(_ entry: CaptureHistoryEntry, eligible: Bool) -> some View {
        if entry.undoneAt != nil {
            Text("Undone")
                .atlasMono(size: 10, weight: .semibold).tracking(1)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
        } else {
            Button("Undo") { confirmingUndo = entry }
                .buttonStyle(.plain)
                .atlasFont(size: 13, weight: .medium, design: .rounded)
                .foregroundStyle(eligible ? AtlasTheme.Colors.danger : AtlasTheme.Colors.textMuted)
                .disabled(!eligible)
        }
    }

    private func itemRow(_ item: CaptureHistoryItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: Self.icon(for: item.kind))
                .atlasFont(size: 12, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
                .frame(width: 16)
            Text(item.title.isEmpty ? "Untitled" : item.title)
                .atlasFont(size: 13, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .lineLimit(1)
            Spacer()
            Text(item.kind.rawValue.uppercased())
                .atlasMono(size: 9, weight: .semibold).tracking(1)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
    }

    // MARK: – Helpers

    private func binding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { open in
                if open { expanded.insert(id) } else { expanded.remove(id) }
            }
        )
    }

    private func itemNoun(_ count: Int) -> String { count == 1 ? "item" : "items" }

    private func label(_ t: String) -> some View {
        Text(t).atlasMono(size: 11, weight: .semibold).tracking(1.2)
            .foregroundStyle(AtlasTheme.Colors.textMuted)
    }

    private static func icon(for kind: CaptureHistoryItem.Kind) -> String {
        switch kind {
        case .task:  return "checkmark.circle"
        case .event: return "calendar"
        case .note:  return "note.text"
        }
    }

    private static func dateLabel(_ date: Date) -> String {
        formatter.string(from: date)
    }
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d · h:mm a"
        return f
    }()
}
