import SwiftUI
import AtlasCore

/// "Create these as classes?" — the sheet the School section shows when a later Canvas
/// sync turns up courses Atlas has no class for. The wizard hosts the same list inline
/// (`CanvasCourseChecklistBody`), so the answer is the same shape every time.
///
/// Confirming creates one class per checked course and links it via
/// `linkProjectToCanvasCourse`, which files that course's already-imported items under
/// the new class and routes future ones there — the mapping is taught once.
struct CanvasCourseChecklist: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    /// The term the new classes belong to; nil only if the user has no term yet.
    let term: Term?
    let courses: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create these as classes?")
                        .atlasFont(size: 19, weight: .semibold, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Text(term.map { "They'll live in \($0.name), and their Canvas work files under them." }
                         ?? "Their Canvas work will file under them.")
                        .atlasFont(size: 12, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                Spacer()
                Button("Not now") { dismiss() }
                    .buttonStyle(.plain)
                    .atlasFont(size: 14, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 18)

            Divider().overlay(AtlasTheme.Colors.hairline)

            ScrollView {
                CanvasCourseChecklistBody(courses: courses) { chosen in
                    state.createClasses(fromCanvasCourses: chosen, term: term)
                    dismiss()
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 18)
            }
            .frame(maxHeight: 340)
        }
        .frame(width: 440, alignment: .topLeading)
        .background(AtlasTheme.Colors.bgBase)
    }
}
