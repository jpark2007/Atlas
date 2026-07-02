import SwiftUI

enum MobileTab: Hashable {
    case schedule, capture, tasks
}

/// The signed-in shell: Schedule / Capture / Tasks tabs. Each screen carries its
/// own inline gear (→ Settings sheet), so no per-tab NavigationStack. A top error
/// banner surfaces `store.lastError`. Opens on Schedule. Deep links switch tabs.
struct RootTabView: View {
    @EnvironmentObject private var store: MobileStore
    @State private var selection: MobileTab = .schedule

    var body: some View {
        TabView(selection: $selection) {
            tab(ScheduleView(),
                tag: .schedule, label: "Schedule", symbol: "calendar")
            tab(CaptureView(),
                tag: .capture, label: "Capture", symbol: "mic")
            tab(TasksView(),
                tag: .tasks, label: "Tasks", symbol: "checklist")
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

    private func tab(_ content: some View, tag: MobileTab, label: String, symbol: String) -> some View {
        content
            .tabItem { Label(label, systemImage: symbol) }
            .tag(tag)
    }
}
