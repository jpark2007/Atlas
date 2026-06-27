import Foundation

/// Pure, deterministic starter content for empty projects. Used by
/// `ProjectDetailView` so a brand-new project never renders blank: it shows an
/// editable starter (prompt overview + a few sample-task placeholders the user
/// can edit or delete). Class-appropriate vs generic content keys off
/// `Project.isClass`. No persistence — these are editable defaults, not saved.
enum ProjectTemplate {

    /// Returns a prompt overview and a few sample-task placeholders appropriate
    /// to the project kind. Deterministic for a given `project.isClass`.
    static func starter(for project: Project) -> (overview: String, sampleTasks: [String]) {
        if project.isClass {
            return (
                overview: "What is this class about? Drop in the syllabus, the grading "
                    + "breakdown, and the key dates (exams, papers, projects) so everything "
                    + "for this class lives in one place.",
                sampleTasks: [
                    "Read the syllabus & note key dates",
                    "Add the next assignment's due date",
                    "Link the course page / required resources",
                ]
            )
        } else {
            return (
                overview: "What is this project about? Capture the goal, the scope, and the "
                    + "immediate next steps so you always know what to pick up next.",
                sampleTasks: [
                    "Define the goal in one sentence",
                    "Outline the first milestone",
                    "Add key links & resources",
                ]
            )
        }
    }
}
