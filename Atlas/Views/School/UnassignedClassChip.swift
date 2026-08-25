import SwiftUI
import AtlasCore

/// "Unassigned · pick a class" — what an imported Canvas item wears when Atlas knows the
/// course it came from but no class is linked to that course yet.
///
/// The rule this enforces: an unmatched import never drops and never blocks. It lands,
/// visible, wearing this. Picking a class calls `linkProjectToCanvasCourse`, which files
/// every already-imported item of that course under the class AND routes future ones —
/// so the first manual assignment teaches the mapping permanently.
struct UnassignedClassChip: View {
    @EnvironmentObject var state: AppState

    /// The Canvas course label carried by the item.
    let course: String

    private var classes: [Project] {
        guard let term = state.activeTerm else {
            return state.allProjects.filter { $0.isClass && $0.archivedAt == nil }
        }
        return state.classes(in: term).sorted { $0.name < $1.name }
    }

    var body: some View {
        Menu {
            if classes.isEmpty {
                Text("No classes yet — set up your semester first")
            } else {
                ForEach(classes) { klass in
                    Button(klass.name) {
                        state.linkProjectToCanvasCourse(projectID: klass.id, course: course)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "questionmark.circle").atlasFont(size: 10)
                Text("Unassigned · pick a class")
                    .atlasFont(size: 12, weight: .medium, design: .rounded)
            }
            .foregroundStyle(AtlasTheme.Colors.late)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(AtlasTheme.wash(AtlasTheme.Colors.late),
                        in: RoundedRectangle(cornerRadius: AtlasTheme.Radius.chip, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("This came from \(course). Pick the class it belongs to — Atlas remembers.")
    }
}
