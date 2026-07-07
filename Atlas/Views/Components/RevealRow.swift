import SwiftUI
import AtlasCore

/// The quiet mono footer under a task/event list that expands a hidden
/// completed/past group in place — "3 COMPLETED ˅". Shared by the project
/// and space detail views.
struct RevealRow: View {
    let count: Int
    let noun: String
    @Binding var isOpen: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { isOpen.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text("\(count) \(noun)")
                    .atlasMono(size: 10, weight: .medium)
                Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(AtlasTheme.Colors.textMuted)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// "JUL 3" — the short mono date completed/past rows carry.
enum LifecycleDate {
    static func short(_ date: Date) -> String {
        formatter.string(from: date).uppercased()
    }
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
}
