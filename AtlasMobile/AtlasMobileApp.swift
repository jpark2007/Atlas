import SwiftUI

@main
struct AtlasMobileApp: App {
    @StateObject private var store = MobileStore()
    @StateObject private var scheduler = NotificationScheduler()
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("notificationPrefs") private var prefs = NotificationPrefs.default

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

    /// Re-plan notifications and refresh the widget snapshot from the latest data.
    private func reschedule() {
        scheduler.reschedule(snapshot: store.snapshot, prefs: prefs)
        WidgetSnapshotWriter.write(store.snapshot)
    }
}
