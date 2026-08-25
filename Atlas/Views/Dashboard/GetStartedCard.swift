import SwiftUI
import AtlasCore

/// The Mac port of the iOS "Get started" card (`AtlasMobile/Views/Schedule/GetStartedCard.swift`),
/// in Atlas paper styling. Four items, each auto-checked by the action itself — no wizard,
/// no modal. Dismissible, and it disappears for good once all four are done.
///
/// Completion keys mirror the iOS names so the two apps read the same way; "connected"
/// comes straight off `AppState.hasAnyConnection` (live truth on Mac) instead of a key.
enum AtlasChecklist {
    static let captured  = "checklist.captured"
    static let scheduled = "checklist.scheduled"
    static let month     = "checklist.month"

    /// Records a first-time milestone. Cheap and idempotent — safe to call every time.
    static func mark(_ key: String) {
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
    }
}

struct GetStartedCard: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var shortcuts: ShortcutStore

    @AppStorage(AtlasChecklist.captured)  private var captured = false
    @AppStorage(AtlasChecklist.scheduled) private var scheduled = false
    @AppStorage(AtlasChecklist.month)     private var month = false
    @AppStorage("checklist.dismissed")    private var dismissed = false

    private var connected: Bool { state.hasAnyConnection }
    private var doneCount: Int { [connected, captured, scheduled, month].filter { $0 }.count }

    var body: some View {
        if dismissed || doneCount == 4 {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Get started").atlasCapsLabel()
                    Spacer()
                    Text("\(doneCount) of 4")
                        .atlasMono(size: 11, weight: .semibold)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                    Button { dismissed = true } label: {
                        Image(systemName: "xmark")
                            .atlasFont(size: 11, weight: .semibold)
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Hide this")
                }

                row(connected, "Connect Google or Canvas") {
                    state.settingsSection = .calendars
                    state.route = .settings
                }
                row(captured, "Capture your first task — \(shortcuts.binding(for: .capture).displayString)")
                row(scheduled, "Put something on the calendar") { state.route = .calendar }
                row(month, "Peek at month view") { state.route = .calendar }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: AtlasTheme.Radius.card, style: .continuous)
                    .strokeBorder(AtlasTheme.Colors.border, lineWidth: 1)
            )
        }
    }

    /// One checklist line. With an `action` the whole line is a button that takes you
    /// where the item happens; without one it's a plain instruction.
    @ViewBuilder
    private func row(_ done: Bool, _ title: String, action: (() -> Void)? = nil) -> some View {
        let line = HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .atlasFont(size: 13)
                .foregroundStyle(done ? AtlasTheme.Colors.green : AtlasTheme.Colors.textMuted)
            Text(title)
                .atlasFont(size: 13, weight: .medium, design: .rounded)
                .foregroundStyle(done ? AtlasTheme.Colors.textMuted : AtlasTheme.Colors.textPrimary)
                .strikethrough(done, color: AtlasTheme.Colors.textMuted)
            Spacer()
        }
        .contentShape(Rectangle())

        if let action, !done {
            Button(action: action) { line }.buttonStyle(.plain)
        } else {
            line
        }
    }
}
