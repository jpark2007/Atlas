import SwiftUI

@main
struct AtlasMobileApp: App {
    @StateObject private var store = MobileStore()

    var body: some Scene {
        WindowGroup {
            Group {
                if store.session == nil {
                    SignInView()
                } else {
                    RootTabView()
                }
            }
            .environmentObject(store)
            .preferredColorScheme(.light)   // Editorial Minimal is a LIGHT design
            .onOpenURL { url in
                if let link = DeepLink(url: url) { store.handle(link) }
            }
        }
    }
}
