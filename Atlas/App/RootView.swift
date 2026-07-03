import SwiftUI
import AtlasCore

/// What the sidebar can select. Drives the detail pane.
enum Route: Hashable {
    case dashboard
    case calendar
    case focus
    case project(UUID)
    case calendarDetail
    case space(UUID)
    case task(UUID)
    case settings
}

/// Sections within the full-page Settings route. Metrics lives here now — it is no
/// longer a sidebar item or a popup sheet.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general, integrations, metrics
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general:      return "General"
        case .integrations: return "Integrations"
        case .metrics:      return "Metrics"
        }
    }
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
                case .settings:
                    SettingsView()
                case .project(let id):
                    if let project = state.project(id) {
                        ProjectDetailView(project: project)
                    } else {
                        PlaceholderView(title: "Not found", systemImage: "questionmark")
                    }
                case .calendarDetail:
                    if let item = state.calendarDetailItem {
                        CalendarEventDetailView(item: item).id(item.id)
                    } else {
                        CalendarView()
                    }
                case .space(let id):
                    if let space = state.spaces.first(where: { $0.id == id }) {
                        SpaceDetailView(space: space)
                    } else {
                        PlaceholderView(title: "Not found", systemImage: "questionmark")
                    }
                case .task(let id):
                    if let task = state.tasks.first(where: { $0.id == id }) {
                        TaskDetailView(task: task)
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
        .toolbar(removing: .sidebarToggle)
        // Do NOT add `.toolbar(.hidden, for: .windowToolbar)` here — it strips the entire
        // window toolbar INCLUDING the traffic-light controls (close/min/zoom). That was
        // the real cause of the missing buttons. The gray toolbar strip is instead
        // suppressed by WindowConfigurator (window.toolbar = nil), which is button-safe.
        .background(WindowConfigurator())
        .atlasCaptureOverlay()   // ⌘⇧K quick-capture pill
        .atlasCommandPalette()   // ⌘K search / command palette
        .overlay {
            if state.presentGraph {
                GraphView()
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: state.presentGraph)
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
                .foregroundStyle(AtlasTheme.Colors.textMuted)
            Text(title)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
            Text("Coming next.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AtlasTheme.Colors.bgBase)
    }
}
