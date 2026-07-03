import SwiftUI
import AtlasCore

struct SidebarView: View {
    @EnvironmentObject var state: AppState

    /// Non-nil while the create-project sheet is up; carries the target space.
    @State private var newProjectTarget: NewProjectTarget?

    /// Drives the create-Space sheet (top-level bucket).
    @State private var presentNewSpace = false

    /// The row the cursor is over — drives the subtle ink hover tint that
    /// replaces the mobile app's haptics. Keyed on Route so every kind of row
    /// (nav / space / project / profile→settings) shares one piece of state.
    @State private var hovered: Route?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                logo
                    .padding(.top, 18)
                    .padding(.bottom, 14)

                searchField
                    .padding(.bottom, 12)

                navRow(title: "Dashboard", icon: "square.grid.2x2.fill", route: .dashboard, trailing: nil)
                navRow(title: "Calendar", icon: "calendar", route: .calendar, trailing: "Today")
                navRow(title: "Focus", icon: "timer", route: .focus, trailing: nil)

                hairline
                    .padding(.horizontal, 10)
                    .padding(.top, 12)

                HStack(spacing: 4) {
                    Text("SPACES")
                        .atlasCapsLabel()
                    Spacer()
                    Button {
                        presentNewSpace = true
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "plus")
                                .font(.system(size: 9, weight: .semibold))
                            Text("Space")
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Add a new top-level Space")
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 6)

                ForEach(state.spaces) { space in
                    spaceSection(space)
                }

                Spacer(minLength: 20)

                hairline
                    .padding(.horizontal, 10)

                profileRow
                    .padding(.top, 8)
            }
            .padding(.horizontal, 12)
        }
        .scrollContentBackground(.hidden)
        .background(AtlasTheme.Colors.bgSidebar)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: state.route)
        .sheet(item: $newProjectTarget) { target in
            NewProjectSheet(spaceName: target.spaceName)
        }
        .sheet(isPresented: $presentNewSpace) {
            NewSpaceSheet()
        }
    }

    // MARK: - Editorial primitives

    /// The black-8% section separator.
    private var hairline: some View {
        Rectangle()
            .fill(AtlasTheme.Colors.hairline)
            .frame(height: 1)
    }

    /// Row background: selection is a subtle ink tint (never an accent fill or a
    /// pill), hover is a fainter ink tint (the Mac stand-in for a haptic).
    private func rowTint(selected: Bool, hovered: Bool) -> Color {
        if selected { return AtlasTheme.Colors.textPrimary.opacity(0.06) }
        if hovered  { return AtlasTheme.Colors.textPrimary.opacity(0.035) }
        return .clear
    }

    private func track(_ route: Route, _ inside: Bool) {
        if inside { hovered = route }
        else if hovered == route { hovered = nil }
    }

    // MARK: - Profile / settings

    private var profileRow: some View {
        Button { state.settingsSection = .general; state.route = .settings } label: {
            HStack(spacing: 9) {
                Circle().fill(AtlasTheme.Colors.textPrimary.opacity(0.06))
                    .frame(width: 24, height: 24)
                    .overlay(Image(systemName: "person.fill")
                        .font(.system(size: 11)).foregroundStyle(AtlasTheme.Colors.textSecondary))
                Text(state.userName)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                Spacer()
                Image(systemName: "gearshape")
                    .font(.system(size: 12)).foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(rowTint(selected: state.route == .settings, hovered: hovered == .settings))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { track(.settings, $0) }
    }

    // MARK: - Logo

    private var logo: some View {
        HStack(spacing: 10) {
            BrandLogo(size: 26)
            Text("Atlas")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Search

    private var searchField: some View {
        Button { state.presentSearch = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                Text("Search notes, classes…")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                Spacer()
                Text("⌘K")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(AtlasTheme.Colors.border, lineWidth: 1)
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AtlasTheme.Colors.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Nav row

    private func navRow(title: String, icon: String, route: Route, trailing: String?) -> some View {
        let selected = state.route == route
        return Button {
            state.route = route
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                    .foregroundStyle(selected ? AtlasTheme.Colors.textPrimary : AtlasTheme.Colors.textSecondary)
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular, design: .rounded))
                    .foregroundStyle(selected ? AtlasTheme.Colors.textPrimary : AtlasTheme.Colors.textSecondary)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(rowTint(selected: selected, hovered: hovered == route))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { track(route, $0) }
    }

    // MARK: - Space section

    private func spaceSection(_ space: Space) -> some View {
        let expanded = state.expandedSpaces.contains(space.id)
        let spaceRoute = Route.space(space.id)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                // Space name → navigate to space detail
                Button { state.route = spaceRoute } label: {
                    HStack(spacing: 9) {
                        Circle()
                            .fill(space.color)
                            .frame(width: 8, height: 8)
                        Text(space.name)
                            .font(.system(size: 13,
                                          weight: state.route == spaceRoute ? .semibold : .medium,
                                          design: .rounded))
                            .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Chevron → expand/collapse projects
                Button { state.toggleSpace(space.id) } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    newProjectTarget = NewProjectTarget(spaceName: space.name)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Add a project to \(space.name)")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(rowTint(selected: state.route == spaceRoute, hovered: hovered == spaceRoute))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onHover { track(spaceRoute, $0) }
            .contextMenu {
                Button {
                    newProjectTarget = NewProjectTarget(spaceName: space.name)
                } label: {
                    Label("Add Project…", systemImage: "plus")
                }
            }

            if expanded {
                if space.projects.isEmpty {
                    emptySpaceRow(space)
                } else {
                    ForEach(space.projects) { project in
                        projectRow(project)
                    }
                }
            }
        }
    }

    /// Friendly affordance shown when an expanded Space has no projects yet —
    /// "Add your first project" instead of empty space.
    private func emptySpaceRow(_ space: Space) -> some View {
        Button {
            newProjectTarget = NewProjectTarget(spaceName: space.name)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.dotted")
                    .font(.system(size: 11))
                Text("Add your first project")
                    .font(.system(size: 12, design: .rounded))
                Spacer()
            }
            .foregroundStyle(AtlasTheme.Colors.textMuted)
            .padding(.leading, 27)
            .padding(.trailing, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Add the first project to \(space.name)")
    }

    private func projectRow(_ project: Project) -> some View {
        let projectRoute = Route.project(project.id)
        let selected = state.route == projectRoute
        return Button {
            state.route = projectRoute
        } label: {
            HStack(spacing: 9) {
                Image(systemName: project.isClass ? "circle.dotted" : "circle")
                    .font(.system(size: 7))
                    .foregroundStyle(selected ? AtlasTheme.Colors.textPrimary : AtlasTheme.Colors.textMuted)
                Text(project.name)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .regular, design: .rounded))
                    .foregroundStyle(selected ? AtlasTheme.Colors.textPrimary : AtlasTheme.Colors.textSecondary)
                Spacer()
            }
            .padding(.leading, 27)
            .padding(.trailing, 10)
            .padding(.vertical, 5)
            .background(rowTint(selected: selected, hovered: hovered == projectRoute))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { track(projectRoute, $0) }
    }
}
