import SwiftUI
import AtlasCore

/// "Fall 2026" from today's date — a starting point for a term prompt, always editable.
/// Months are the US academic split; the user names it whatever they call it.
func suggestedTermName(on date: Date = Date()) -> String {
    let cal = Calendar.current
    let year = cal.component(.year, from: date)
    switch cal.component(.month, from: date) {
    case 1...5: return "Spring \(year)"
    case 6...7: return "Summer \(year)"
    default:    return "Fall \(year)"
    }
}

/// The Canvas-course checklist body, hosted inline by the wizard and in a sheet by the
/// School screen's catch-up prompt — one list, one behaviour (mirrors the Mac).
struct CanvasCourseChecklistBody: View {
    let courses: [String]
    let onConfirm: ([String]) -> Void

    @State private var selected: Set<String> = []
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(courses, id: \.self) { course in
                Button {
                    MobileTheme.Haptic.selection()
                    if selected.contains(course) { selected.remove(course) } else { selected.insert(course) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selected.contains(course) ? "checkmark.square.fill" : "square")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(selected.contains(course) ? MobileTheme.ink : MobileTheme.faint)
                        Text(course)
                            .font(.system(size: 15.5, weight: .medium, design: .rounded))
                            .foregroundStyle(MobileTheme.ink)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .edHairlineBelow()
            }

            Button { onConfirm(courses.filter { selected.contains($0) }) } label: {
                Text(selected.isEmpty
                     ? "Skip for now"
                     : "Create \(selected.count) \(selected.count == 1 ? "class" : "classes")")
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
                    .frame(maxWidth: .infinity)
                    .edOutlineControl()
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            selected = Set(courses)   // accept-all by default
        }
    }
}

/// "Create these as classes?" as its own sheet — the School screen's catch-up prompt
/// when a later sync brings in courses no class is linked to.
struct CanvasCourseChecklistSheet: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss

    let term: Term?
    let courses: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Create these as classes?").edScreenTitle()
                        Text(term.map { "They'll live in \($0.name), and their Canvas work files under them." }
                             ?? "Their Canvas work will file under them.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(MobileTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Button { dismiss() } label: { Text("Not now").edCapsLabel() }
                        .buttonStyle(.plain)
                }
                .padding(.bottom, 20)

                CanvasCourseChecklistBody(courses: courses) { chosen in
                    store.createClasses(fromCanvasCourses: chosen, term: term)
                    MobileTheme.Haptic.success()
                    dismiss()
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
        }
        .background(MobileTheme.bg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }
}
