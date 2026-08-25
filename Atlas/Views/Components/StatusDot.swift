import SwiftUI
import AtlasCore

/// The small live-state dot that leads a connection row's mono status line.
///
/// Four honest states, no new colors — the existing semantic tokens carry them.
/// Only `.live` moves: a slow opacity breath so a healthy sync reads as *running*
/// rather than merely green. Reduce Motion turns that into a solid dot.
///
/// The health value is always derived from the SAME logic that writes the row's
/// status sentence, so the dot and the words can never disagree; `textColor`
/// exists so the sentence takes its color from that one state too.
struct StatusDot: View {
    enum Health {
        /// Connected and syncing.
        case live
        /// Connected, but the sync is overdue — nothing to fix yet.
        case stalled
        /// Needs the user: denied, blocked, or a stopped connection.
        case error
        /// Switched off or not connected.
        case off
    }

    let health: Health

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SwiftUI.State private var breathing = false

    /// The dot's own color, and the color of the status sentence beside it.
    static func textColor(_ health: Health) -> Color {
        switch health {
        case .live:    return AtlasTheme.Colors.green
        case .stalled: return AtlasTheme.Colors.warning
        case .error:   return AtlasTheme.Colors.danger
        case .off:     return AtlasTheme.Colors.textMuted
        }
    }

    private var pulses: Bool { health == .live && !reduceMotion }

    var body: some View {
        Circle()
            .fill(Self.textColor(health))
            .frame(width: 7, height: 7)
            .opacity(pulses && breathing ? 0.55 : 1)
            .animation(pulses ? .easeInOut(duration: 1).repeatForever(autoreverses: true) : nil,
                       value: breathing)
            .onAppear { if pulses { breathing = true } }
            .accessibilityHidden(true)
    }
}
