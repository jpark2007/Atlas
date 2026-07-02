import SwiftUI

/// The flagship check-off control (spec §5): a space-tinted ring that springs
/// full with the space color and draws a checkmark when done. Fires the standard
/// tap haptic. Color = the task's space — informative, never decorative.
struct CheckCircle: View {
    let done: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button {
            MobileTheme.Haptic.tap()
            withAnimation(MobileTheme.spring) { action() }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(done ? color : color.opacity(0.5), lineWidth: MobileTheme.rule)
                Circle()
                    .fill(color)
                    .scaleEffect(done ? 1 : 0.001)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .scaleEffect(done ? 1 : 0.001)
            }
            .frame(width: 20, height: 20)
            .animation(MobileTheme.spring, value: done)
        }
        .buttonStyle(.plain)
    }
}
