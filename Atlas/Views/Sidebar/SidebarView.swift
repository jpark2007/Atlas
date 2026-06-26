import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var state: AppState

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

                Text("SPACES")
                    .font(AtlasTheme.Font.sectionLabel())
                    .tracking(1.2)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                    .padding(.horizontal, 10)
                    .padding(.top, 18)
                    .padding(.bottom, 6)

                ForEach(state.spaces) { space in
                    spaceSection(space)
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 12)
        }
        .scrollContentBackground(.hidden)
        .background(AtlasTheme.Colors.bgSidebar)
    }

    // MARK: - Logo

    private var logo: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(colors: [AtlasTheme.Colors.accent, AtlasTheme.Colors.accentDeep],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                )
            Text("Atlas")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Search

    private var searchField: some View {
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
            Button {
                state.toggleSpace(space.id)
            } label: {
                HStack(spacing: 9) {
                    Circle()
                        .fill(space.color)
                        .frame(width: 8, height: 8)
                    Text(space.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            if expanded {
                ForEach(space.projects) { project in
                    projectRow(project)
                }
            }
        }
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
