import SwiftUI

extension AppState {

    /// Last Canvas sync error; nil when the most recent sync succeeded.
    /// Stored as a dynamic property via associated object so it lives on AppState
    /// without touching the main file.
    // NOTE: @Published can't live in an extension, so sync errors are reported
    // through lastCanvasSyncError which is declared in AppState.swift.

    // MARK: - Sync entry point

    /// Fetches Canvas courses, matches them to existing projects by course code
    /// (primary) or exact name (secondary), and populates each matched project's
    /// `assignments` array. Unmatched courses are skipped — we only merge into
    /// projects the user already created. The `canvasSynced` flag is persisted on
    /// any newly-matched project.
    func syncCanvas(using canvas: CanvasService) async {
        do {
            let courses = try await canvas.fetchCourses()
            for course in courses {
                guard let (si, pi) = findProject(for: course) else { continue }
                let assignments = (try? await canvas.fetchAssignments(courseId: course.id)) ?? []
                let taskItems = assignments.compactMap { taskItem(from: $0, project: spaces[si].projects[pi]) }
                spaces[si].projects[pi].assignments = taskItems
                if !spaces[si].projects[pi].canvasSynced {
                    spaces[si].projects[pi].canvasSynced = true
                    let updated = spaces[si].projects[pi]
                    Task { try? await self.db?.upsertProject(updated) }
                }
            }
            lastCanvasSyncError = nil
        } catch {
            lastCanvasSyncError = error.localizedDescription
        }
    }

    // MARK: - Matching

    /// Returns the (spaceIndex, projectIndex) of the project that best matches
    /// the Canvas course, or nil if no high-confidence match exists.
    ///
    /// Match rules (applied in priority order):
    ///   1. Normalized course code == normalized project code  (e.g. "CS201" == "CS 201")
    ///   2. Exact case-insensitive name match
    private func findProject(for course: CanvasCourse) -> (Int, Int)? {
        let normalizedCourseCode = course.courseCode.map(normalize) ?? ""
        let normalizedCourseName = course.name.lowercased().trimmingCharacters(in: .whitespaces)

        for (si, space) in spaces.enumerated() {
            for (pi, project) in space.projects.enumerated() {
                // Primary: code match
                if !normalizedCourseCode.isEmpty,
                   let projectCode = project.code,
                   normalize(projectCode) == normalizedCourseCode {
                    return (si, pi)
                }
                // Secondary: exact name match
                if project.name.lowercased().trimmingCharacters(in: .whitespaces) == normalizedCourseName {
                    return (si, pi)
                }
            }
        }
        return nil
    }

    private func normalize(_ code: String) -> String {
        code.replacingOccurrences(of: " ", with: "").uppercased()
    }

    // MARK: - Mapping

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func taskItem(from assignment: CanvasAssignment, project: Project) -> TaskItem {
        let dueDate = assignment.dueAt.flatMap { Self.iso8601.date(from: $0) }
        var item = TaskItem(
            title:    assignment.name,
            dueLabel: TaskItem.dueLabel(for: dueDate),
            dueDate:  dueDate
        )
        item.spaceName   = project.spaceName
        item.spaceColor  = project.spaceColor
        item.projectName = project.name
        return item
    }
}
