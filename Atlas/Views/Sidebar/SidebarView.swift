import SwiftUI
import AtlasCore

struct SidebarView: View {
    @EnvironmentObject var state: AppState

    /// Non-nil while the create-project sheet is up; carries the target space.
    @State private var newProjectTarget: NewProjectTarget?

    /// Drives the create-Space sheet (top-level bucket).
    @State private var presentNewSpace = false

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

                HStack(spacing: 4) {
                    Text("SPACES")
                        .font(AtlasTheme.Font.sectionLabel())
                        .tracking(1.2)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                    Spacer()
                    Button {
                        presentNewSpace = true
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "plus")
                                .font(.system(size: 9, weight: .semibold))
                            Text("Space")
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Add a new top-level Space")
                }
                .padding(.horizontal, 10)
                .padding(.top, 18)
                .padding(.bottom, 6)

                ForEach(state.spaces) { space in
                    spaceSection(space)
                }

                Spacer(minLength: 20)

                profileRow
                    .padding(.top, 8)
            }
            .padding(.horizontal, 12)
        }
        .scrollContentBackground(.hidden)
        .background(AtlasTheme.Colors.bgSidebar)
        .sheet(item: $newProjectTarget) { target in
            NewProjectSheet(spaceName: target.spaceName)
        }
        .sheet(isPresented: $presentNewSpace) {
            NewSpaceSheet()
        }
    }

    // MARK: - Profile / settings

    private var profileRow: some View {
        Button { state.settingsSection = .general; state.route = .settings } label: {
            HStack(spacing: 9) {
                Circle().fill(AtlasTheme.Colors.accent.opacity(0.15))
                    .frame(width: 24, height: 24)
                    .overlay(Image(systemName: "person.fill")
                        .font(.system(size: 11)).foregroundStyle(AtlasTheme.Colors.accent))
                Text(state.userName)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                Spacer()
                Image(systemName: "gearshape")
                    .font(.system(size: 12)).foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(AtlasTheme.Colors.bgElevated.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Logo

    private var logo: some View {
        HStack(spacing: 10) {
            BrandLogo(size: 26)
            Text("Atlas")
                .font(.system(size: 17, weight: .bold))
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
                    .font(.system(size: 12))
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                Spacer()
                Text("⌘K")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(AtlasTheme.Colors.bgElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(AtlasTheme.Colors.bgElevated.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                    .foregroundStyle(selected ? AtlasTheme.Colors.accent : AtlasTheme.Colors.textSecondary)
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? AtlasTheme.Colors.textPrimary : AtlasTheme.Colors.textSecondary)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 11))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(selected ? AtlasTheme.Colors.accent.opacity(0.12) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Space section

    private func spaceSection(_ space: Space) -> some View {
        let expanded = state.expandedSpaces.contains(space.id)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                // Space name → navigate to space detail
                Button { state.route = .space(space.id) } label: {
                    HStack(spacing: 9) {
                        Circle()
                            .fill(space.color)
                            .frame(width: 8, height: 8)
                        Text(space.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(state.route == .space(space.id)
                                             ? AtlasTheme.Colors.textPrimary
                                             : AtlasTheme.Colors.textPrimary)
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
                    .font(.system(size: 12))
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
        let selected = state.route == .project(project.id)
        return Button {
            state.route = .project(project.id)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: project.isClass ? "circle.dotted" : "circle")
                    .font(.system(size: 7))
                    .foregroundStyle(selected ? AtlasTheme.Colors.accent : AtlasTheme.Colors.textMuted)
                Text(project.name)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? AtlasTheme.Colors.textPrimary : AtlasTheme.Colors.textSecondary)
                Spacer()
            }
            .padding(.leading, 27)
            .padding(.trailing, 10)
            .padding(.vertical, 5)
            .background(selected ? AtlasTheme.Colors.accent.opacity(0.10) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
