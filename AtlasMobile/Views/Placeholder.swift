import SwiftUI

/// Temporary editorial-styled placeholder for a not-yet-built screen — a single
/// centered caps label on the bg. Later tasks replace these (Schedule/Tasks, and
/// Capture in Task 2).
struct EditorialPlaceholder: View {
    let title: String

    var body: some View {
        Text(title)
            .edCapsLabel()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MobileTheme.bg.ignoresSafeArea())
    }
}
