import SwiftUI
import AtlasCore
import TipKit

struct SidebarView: View {
    @EnvironmentObject var state: AppState

    // MARK: - Onboarding tips
    @State private var searchTip = AtlasTips.CommandPalette()
    @State private var bugTip = AtlasTips.ReportBug()
    @State private var globalCaptureTip = AtlasTips.GlobalCapture()

    /// Non-nil while the create-project sheet is up; carries the target space.
    @State private var newProjectTarget: NewProjectTarget?

    /// Drives the create-Space sheet (top-level bucket).
    @State private var presentNewSpace = false

    /// Drives the pending-invites inbox sheet.
    @State private var presentInvites = false

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
                                .atlasFont(size: 10, weight: .semibold)
                            Text("Space")
                                .atlasFont(size: 12, weight: .semibold, design: .rounded)
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

                if !state.sharedWithMeProjects.isEmpty {
                    HStack(spacing: 4) {
                        Text("SHARED WITH ME").atlasCapsLabel()
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 14)
                    .padding(.bottom, 6)

                    ForEach(state.sharedWithMeProjects) { project in
                        projectRow(project)
                    }
                }

                Spacer(minLength: 20)

                hairline
                    .padding(.horizontal, 10)

                profileRow
                    .padding(.top, 8)

                reportBugRow

                if !state.pendingInvites.isEmpty {
                    Button {
                        presentInvites = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "envelope.fill").atlasFont(size: 11)
                            Text(state.pendingInvites.count == 1 ? "1 invitation" : "\(state.pendingInvites.count) invitations")
                                .atlasMono(size: 11, weight: .medium)
                        }
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                }
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
        .sheet(isPresented: $presentInvites) {
            InviteInboxSheet()
        }
    }

    // MARK: - Editorial primitives

    /// The black-8% section separator.
    private var hairline: some View {
        Rectangle()
            .fill(AtlasTheme.Colors.hairline)
            .frame(height: 1)
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
                        .atlasFont(size: 12, weight: .medium).foregroundStyle(AtlasTheme.Colors.textSecondary))
                Text(state.userName)
                    .atlasFont(size: 14, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                Spacer()
                Image(systemName: "gearshape")
                    .atlasFont(size: 13, weight: .medium).foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .rowChrome(selected: state.route == .settings, hovered: hovered == .settings)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { track(.settings, $0) }
    }

    /// Quiet "Report a bug" affordance under the profile row — opens the app-wide
    /// report sheet (`AppState.presentBugReport`), the same one ⌘K offers.
    private var reportBugRow: some View {
        Button {
            state.reportBug()
            Task { await AtlasTipEvents.reportedBug.donate() }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "ant")
                    .atlasFont(size: 12, weight: .medium)
                    .frame(width: 24)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                Text("Report a bug")
                    .atlasFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onboardingTip(bugTip, when: AtlasBuild.isBeta)
    }

    // MARK: - Logo

    private var logo: some View {
        HStack(spacing: 10) {
            BrandLogo(size: 26)
            Text("Atlas")
                .atlasFont(size: 19, weight: .bold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .popoverTip(globalCaptureTip, arrowEdge: .trailing)
    }

    // MARK: - Search

    private var searchField: some View {
        Button {
            state.presentSearch = true
            searchTip.invalidate(reason: .actionPerformed)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .atlasFont(size: 13, weight: .medium)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                Text("Search notes, classes…")
                    .atlasFont(size: 13, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                Spacer()
                Text("⌘K")
                    .atlasMono(size: 10, weight: .medium)
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
        .popoverTip(searchTip, arrowEdge: .bottom)
    }

    // MARK: - Nav row

    private func navRow(title: String, icon: String, route: Route, trailing: String?) -> some View {
        let selected = state.route == route
        return Button {
            state.route = route
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .atlasFont(size: 14)
                    .frame(width: 18)
                    .foregroundStyle(selected ? AtlasTheme.Colors.textPrimary : AtlasTheme.Colors.textSecondary)
                Text(title)
                    .atlasFont(size: 14, weight: selected ? .semibold : .regular, design: .rounded)
                    .foregroundStyle(selected ? AtlasTheme.Colors.textPrimary : AtlasTheme.Colors.textSecondary)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .atlasMono(size: 11, weight: .regular)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .rowChrome(selected: selected, hovered: hovered == route)
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
                            .atlasFont(size: 14,
                                       weight: state.route == spaceRoute ? .semibold : .medium,
                                       design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        if state.isSharedSpace(space) {
                            sharedSpaceMemberCluster(for: space)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Chevron → expand/collapse projects
                Button { state.toggleSpace(space.id) } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .atlasFont(size: 10, weight: .semibold)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Expand or collapse")

                Button {
                    newProjectTarget = NewProjectTarget(spaceName: space.name)
                } label: {
                    Image(systemName: "plus")
                        .atlasFont(size: 11, weight: .semibold)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Add a project to \(space.name)")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .rowChrome(selected: state.route == spaceRoute, hovered: hovered == spaceRoute)
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
                    .atlasFont(size: 12)
                Text("Add your first project")
                    .atlasFont(size: 13, design: .rounded)
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
                // A project with its own color wears it as a filled dot (mirrors the
                // space dot); one that inherits the space color keeps the hollow glyph.
                if let token = project.colorToken {
                    Circle()
                        .fill(ColorToken.color(for: token))
                        .frame(width: 8, height: 8)
                } else {
                    Image(systemName: project.isClass ? "circle.dotted" : "circle")
                        .atlasFont(size: 8)
                        .foregroundStyle(selected ? AtlasTheme.Colors.textPrimary : AtlasTheme.Colors.textMuted)
                }
                Text(project.name)
                    .atlasFont(size: 14, weight: selected ? .semibold : .regular, design: .rounded)
                    .foregroundStyle(selected ? AtlasTheme.Colors.textPrimary : AtlasTheme.Colors.textSecondary)
                if state.isShared(project) {
                    sharedMemberCluster(for: project)
                }
                Spacer()
            }
            .padding(.leading, 27)
            .padding(.trailing, 10)
            .padding(.vertical, 5)
            .rowChrome(selected: selected, hovered: hovered == projectRoute)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { track(projectRoute, $0) }
    }

    /// Two overlapping small-caps initial circles — the sidebar's only visual
    /// tell that a project is shared. Deliberately quiet: no badge, no color,
    /// no "SHARED" label, per the editorial-minimal design direction.
    @ViewBuilder
    private func sharedMemberCluster(for project: Project) -> some View {
        let members = state.projectMembers[project.id] ?? []
        HStack(spacing: -6) {
            ForEach(members.prefix(2), id: \.userId) { member in
                Circle()
                    .fill(AtlasTheme.Colors.bgSidebar)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle().strokeBorder(AtlasTheme.Colors.textMuted.opacity(0.4), lineWidth: 0.75)
                    )
            }
        }
    }

    /// Space-level counterpart to `sharedMemberCluster(for:)` — same minimal
    /// placeholder-circle treatment, one level up.
    @ViewBuilder
    private func sharedSpaceMemberCluster(for space: Space) -> some View {
        let members = state.spaceMembers[space.id] ?? []
        HStack(spacing: -6) {
            ForEach(members.prefix(2), id: \.userId) { member in
                Circle()
                    .fill(AtlasTheme.Colors.bgSidebar)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle().strokeBorder(AtlasTheme.Colors.textMuted.opacity(0.4), lineWidth: 0.75)
                    )
            }
        }
    }
}

// MARK: - Row chrome (paper language)

private extension View {
    /// Attach an onboarding tip only while `condition` holds — the macOS 14-safe form of a
    /// conditional `.popoverTip` (the optional-tip overload needs macOS 26).
    @ViewBuilder
    func onboardingTip(_ tip: some Tip, when condition: Bool, arrowEdge: Edge = .top) -> some View {
        if condition { popoverTip(tip, arrowEdge: arrowEdge) } else { self }
    }

    /// Paper-language selection/hover chrome for a sidebar row. The active row
    /// gets a 2px accent (clay) tick on the left edge and no fill; a
    /// hovered-but-inactive row gets a soft full-row ink wash with square
    /// corners — the Mac stand-in for a haptic. No pills, no shadows.
    func rowChrome(selected: Bool, hovered: Bool) -> some View {
        self
            .background(hovered && !selected ? AtlasTheme.Colors.textPrimary.opacity(0.05) : Color.clear)
            .overlay(alignment: .leading) {
                if selected {
                    Rectangle()
                        .fill(AtlasTheme.Colors.accent)
                        .frame(width: 2)
                }
            }
    }
}
