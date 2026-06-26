import SwiftUI

/// What the sidebar can select. Drives the detail pane.
enum Route: Hashable {
    case dashboard
    case calendar
    case focus
    case project(UUID)
}

struct RootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 234, max: 300)
        } detail: {
            Group {
                switch state.route {
                case .dashboard:
                    DashboardView()
                case .calendar:
                    CalendarView()
                case .focus:
                    FocusView()
                case .project(let id):
                    if let project = state.project(id) {
                        ProjectDetailView(project: project)
                    } else {
                        PlaceholderView(title: "Not found", systemImage: "questionmark")
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AtlasTheme.Colors.bgBase)
        }
        .navigationSplitViewStyle(.balanced)
        .background(AtlasTheme.Colors.bgBase)
        .atlasCaptureOverlay()   // ⌘⇧K quick-capture pill
        .atlasCommandPalette()   // ⌘K search / command palette
    }
}

/// Simple stub for screens not built yet.
struct PlaceholderView: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(AtlasTheme.Colors.accent)
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
            Text("Coming next.")
                .font(.system(size: 13))
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AtlasTheme.Colors.bgBase)
    }
}
