// CARRYOVER — from old Atlas prototype. Depends on old `DS` design system. Restyle before use.
// Post-session reflection sheet (optional notes).
import SwiftUI
import SwiftData

struct FocusReflectionSheet: View {
    let vm: FocusViewModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var notes: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What did you work on?")
                .font(DS.Typography.heading)
                .foregroundColor(DS.Colors.textPrimary)

            Text("A quick note helps you remember the session later. Optional.")
                .font(DS.Typography.caption)
                .foregroundColor(DS.Colors.textMuted)

            TextEditor(text: $notes)
                .font(DS.Typography.body)
                .foregroundColor(DS.Colors.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 100, maxHeight: 180)
                .padding(10)
                .background(DS.Colors.bgPrimary)
                .cornerRadius(DS.Radius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .stroke(DS.Colors.borderSubtle, lineWidth: 1)
                )

            HStack {
                Button("Skip") {
                    vm.discardReflection(context: context)
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(DS.Colors.textSecondary)
                Spacer()
                Button("Save") {
                    vm.commitSession(notes: notes.isEmpty ? nil : notes, context: context)
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(DS.Colors.accentAction)
                .fontWeight(.semibold)
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(DS.Colors.bgCard)
    }
}
