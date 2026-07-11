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
    case completed
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
    @EnvironmentObject var focus: FocusViewModel

    /// Collapses the sidebar to a clean, detail-only canvas while a focus session
    /// is active (restored when it ends) — and permanently in hover mode, where
    /// the sidebar lives in the left-edge overlay instead of the split column.
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    /// Arc-style sidebar behavior — "always" pins the split-view column (default);
    /// "hover" hides it and slides an overlay in from the left screen edge.
    /// Chosen in Settings → General.
    @AppStorage("sidebar.mode") private var sidebarMode = "always"
    /// Whether the hover-mode overlay sidebar is currently slid out.
    @State private var hoverSidebarVisible = false
    /// Debounces the overlay's retract so the cursor can travel from the edge
    /// strip onto the panel without a flicker-hide between the two hover zones.
    @State private var hoverHideTask: Task<Void, Never>?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
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
                    if let task = state.task(id) {
                        TaskDetailView(task: task)
                    } else {
                        PlaceholderView(title: "Not found", systemImage: "questionmark")
                    }
                case .completed:
                    CompletedView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AtlasTheme.Colors.bgBase)
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear { applyColumnVisibility() }
        .onChange(of: focus.sessionActive) { _, _ in
            applyColumnVisibility()
            // A session can start while the overlay is out (menu-bar/palette) —
            // it must not reappear stuck open when the session ends.
            hoverHideTask?.cancel()
            hoverSidebarVisible = false
        }
        .onChange(of: sidebarMode) { _, _ in
            applyColumnVisibility()
            hoverSidebarVisible = false
            // Sidebar mode is a synced preference — push the change (debounced).
            state.pushSyncedSettings()
        }
        // Navigating from the overlay sidebar retracts it — the destination is
        // what you asked for; the panel shouldn't keep covering it.
        .onChange(of: state.route) { _, _ in hoverSidebarVisible = false }
        // Arc-style hover sidebar: in hover mode the split column stays hidden and
        // the sidebar slides over the content when the cursor touches the left edge.
        .overlay(alignment: .leading) { hoverSidebarOverlay }
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

    // MARK: - Arc-style hover sidebar

    /// Hover mode is suspended while a focus session runs — Focus owns the whole
    /// canvas and already collapses the column itself.
    private var hoverModeActive: Bool {
        sidebarMode == "hover" && !focus.sessionActive
    }

    private func applyColumnVisibility() {
        columnVisibility = (focus.sessionActive || sidebarMode == "hover") ? .detailOnly : .automatic
    }

    @ViewBuilder
    private var hoverSidebarOverlay: some View {
        if hoverModeActive {
            ZStack(alignment: .leading) {
                // Invisible reveal strip along the window's left edge.
                Color.clear
                    .frame(width: 14)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onHover(perform: sidebarHover)
                if hoverSidebarVisible {
                    SidebarView()
                        .frame(width: 234)
                        .frame(maxHeight: .infinity)
                        .background(AtlasTheme.Colors.bgBase)
                        .overlay(alignment: .trailing) {
                            Rectangle().fill(AtlasTheme.Colors.border).frame(width: 1)
                        }
                        .shadow(color: .black.opacity(0.14), radius: 18, x: 6, y: 0)
                        .transition(.move(edge: .leading))
                        .onHover(perform: sidebarHover)
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.86), value: hoverSidebarVisible)
        }
    }

    /// Shared by the edge strip and the panel: entering either zone reveals (and
    /// cancels a pending retract); leaving schedules a short-delay retract so the
    /// cursor can cross the gap between the two zones without a flicker.
    private func sidebarHover(_ inside: Bool) {
        hoverHideTask?.cancel()
        if inside {
            hoverSidebarVisible = true
        } else {
            hoverHideTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard !Task.isCancelled else { return }
                hoverSidebarVisible = false
            }
        }
    }
}

/// Simple stub for screens not built yet.
struct PlaceholderView: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .atlasFont(size: 40, weight: .light)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
            Text(title)
                .atlasFont(size: 24, weight: .semibold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
            Text("Coming next.")
                .atlasFont(size: 14, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AtlasTheme.Colors.bgBase)
    }
}
