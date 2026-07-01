import SwiftUI

enum MobileTab: Hashable {
    case schedule, capture, tasks
}

/// The signed-in shell: Schedule / Capture / Tasks tabs, each with a gear in the
/// toolbar that pushes the Settings placeholder. Opens on Schedule. Deep links
/// switch the selected tab.
struct RootTabView: View {
    @EnvironmentObject private var store: MobileStore
    @State private var selection: MobileTab = .schedule

    var body: some View {
        TabView(selection: $selection) {
            tab(EditorialPlaceholder(title: "Schedule"),
                tag: .schedule, label: "Schedule", symbol: "calendar")
            tab(EditorialPlaceholder(title: "Capture"),
                tag: .capture, label: "Capture", symbol: "mic")
            tab(EditorialPlaceholder(title: "Tasks"),
                tag: .tasks, label: "Tasks", symbol: "checklist")
        }
        .tint(MobileTheme.ink)
        .onChange(of: store.pendingDeepLink) { _, link in
            guard let link else { return }
            switch link {
            case .today, .todaySpace, .unscheduled: selection = .schedule
            case .capture:                          selection = .capture
            }
            store.pendingDeepLink = nil
        }
    }

    private func tab(_ content: some View, tag: MobileTab, label: String, symbol: String) -> some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            EditorialPlaceholder(title: "Settings")
                                .navigationTitle("Settings")
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
        }
        .tabItem { Label(label, systemImage: symbol) }
        .tag(tag)
    }
}
