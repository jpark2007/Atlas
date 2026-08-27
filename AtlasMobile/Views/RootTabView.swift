import SwiftUI

enum MobileTab: Hashable {
    case schedule, capture, tasks, notes
}

/// The signed-in shell: Schedule / Capture / Tasks / Notes tabs. Each screen carries its
/// own inline gear (→ Settings sheet), so no per-tab NavigationStack. A top error
/// banner surfaces `store.lastError`. Opens on Schedule. Deep links switch tabs.
///
/// **iPad (v1.1).** The tabs stay tabs — four peer surfaces with no parent/child
/// relationship between them, so a `NavigationSplitView` sidebar would only add a
/// permanent column of four words. What changes at regular width is the column each
/// tab draws into (`edContentColumn`): the schedule gets the widest page because its
/// day grid is the one thing that genuinely uses horizontal room, capture the
/// narrowest because it is a single centred hero.
struct RootTabView: View {
    @EnvironmentObject private var store: MobileStore
    @State private var selection: MobileTab = .schedule

    var body: some View {
        TabView(selection: $selection) {
            tab(ScheduleView(), column: 900, wide: 1040,
                tag: .schedule, label: "Schedule", symbol: "calendar")
            tab(CaptureView(), column: 620,
                tag: .capture, label: "Capture", symbol: "mic")
            // School has no tab of its own: it's a section at the top of Tasks.
            tab(TasksView(), column: 720,
                tag: .tasks, label: "Tasks", symbol: "checklist")
            tab(NotesView(), column: 720,
                tag: .notes, label: "Notes", symbol: "note.text")
        }
        .tint(MobileTheme.ink)
        .overlay(alignment: .top) { errorBanner }
        .animation(MobileTheme.spring, value: store.lastError)
        .task(id: store.lastError) {
            // Debounced auto-clear: a new error restarts the 4 s timer.
            guard store.lastError != nil else { return }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            store.lastError = nil
        }
        .onChange(of: store.pendingDeepLink) { _, link in
            guard let link else { return }
            switch link {
            case .today, .todaySpace, .unscheduled: selection = .schedule
            case .capture:                          selection = .capture
            }
            store.pendingDeepLink = nil
        }
        // Long-press placement (from Tasks / Needs-a-time) jumps to Schedule, where
        // ScheduleView consumes `pendingPlacement`. TaskItem isn't Equatable → key on id.
        .onChange(of: store.pendingPlacement?.id) { _, id in
            if id != nil { selection = .schedule }
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let message = store.lastError {
            Text(message)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(MobileTheme.ink)
                .padding(.vertical, 10)
                .padding(.horizontal, 18)
                .background(Capsule().fill(MobileTheme.bg))
                .overlay(Capsule().strokeBorder(MobileTheme.hairline, lineWidth: 1))
                .padding(.top, 8)
                .contentShape(Capsule())
                .onTapGesture { store.lastError = nil }
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func tab(_ content: some View, column: CGFloat, wide: CGFloat? = nil,
                     tag: MobileTab, label: String, symbol: String) -> some View {
        content
            .edContentColumn(column, wide: wide)
            .tabItem { Label(label, systemImage: symbol) }
            .tag(tag)
    }
}
