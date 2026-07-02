import SwiftUI

@main
struct AtlasMobileApp: App {
    @StateObject private var store = MobileStore()
    @StateObject private var scheduler = NotificationScheduler()
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("notificationPrefs") private var prefs = NotificationPrefs.default

    /// Debounce so the several triggers below (launch, prefs, load, scenePhase)
    /// collapse into a single re-plan + widget write per burst.
    @State private var rescheduleTask: Task<Void, Never>?

    var body: some Scene {
        WindowGroup {
            Group {
                if store.session == nil {
                    SignInView()
                } else {
                    RootTabView()
                        .task {
                            scheduler.onDeepLink = { url in
                                if let link = DeepLink(url: url) { store.handle(link) }
                            }
                            scheduler.requestAuthorization()
                            reschedule()
                        }
                        .onChange(of: prefs) { _, _ in reschedule() }
                        .onChange(of: store.loading) { _, isLoading in
                            if !isLoading { reschedule() }   // snapshot just refreshed
                        }
                        .onChange(of: scenePhase) { _, phase in
                            if phase == .active || phase == .background { reschedule() }
                        }
                }
            }
            .environmentObject(store)
            .preferredColorScheme(.light)   // Editorial Minimal is a LIGHT design
            .onOpenURL { url in
                if let link = DeepLink(url: url) { store.handle(link) }
            }
        }
    }

    /// Re-plan notifications and refresh the widget snapshot from the latest data,
    /// debounced 1s so a burst of triggers does one removeAll+re-add+reload.
    private func reschedule() {
        rescheduleTask?.cancel()
        rescheduleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            self.scheduler.reschedule(snapshot: self.store.snapshot, prefs: self.prefs)
            WidgetSnapshotWriter.write(self.store.snapshot)
        }
    }
}
