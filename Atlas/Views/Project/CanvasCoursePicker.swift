import SwiftUI
import AtlasCore

/// Links a class (this project) to a Canvas course so items from that course wear
/// the class's color and file under it. Lists the courses present in the synced
/// feed (`AppState.canvasCoursesInFeed`); picking one runs the retroactive remap +
/// persists the link for future syncs. Self-contained subview so its hook into
/// `ProjectDetailView` stays a single line.
///
/// Shown only for classes that actually have Canvas items in the feed — no feed
/// courses means nothing to link, so the row hides itself.
struct CanvasCoursePicker: View {
    @EnvironmentObject var state: AppState
    let project: Project

    /// The feed's courses, plus this project's current link if it has dropped out of
    /// the feed (so the selection still shows rather than going blank).
    private var courses: [String] {
        var set = Set(state.canvasCoursesInFeed)
        if let linked = project.canvasCourse { set.insert(linked) }
        return set.sorted()
    }

    var body: some View {
        if !courses.isEmpty {
            HStack(spacing: 8) {
                Text("CANVAS COURSE").atlasCapsLabel()
                Picker("", selection: Binding(
                    get: { project.canvasCourse ?? "" },
                    set: { state.linkProjectToCanvasCourse(projectID: project.id,
                                                           course: $0.isEmpty ? nil : $0) }
                )) {
                    Text("Not linked").tag("")
                    ForEach(courses, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            .padding(.top, 2)
        }
    }
}
