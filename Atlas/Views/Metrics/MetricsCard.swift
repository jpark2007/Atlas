import SwiftUI
import AtlasCore

/// Dashboard card in the right-column 320-wide VStack.
/// Shows a compact "at a glance" summary; tapping "Details" opens the popup.
struct MetricsCard: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let m = AtlasMetrics.compute(from: state)

        AtlasCard {
            VStack(alignment: .leading, spacing: 14) {

                // Header
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                    Text("At a glance")
                        .atlasCapsLabel()
                    Spacer()
                    Button { state.settingsSection = .metrics; state.route = .settings } label: {
                        HStack(spacing: 4) {
                            Text("Details")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                        }
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.accentText)
                    }
                    .buttonStyle(.plain)
                }

                // Stat row: open tasks · today's events
                HStack(spacing: 0) {
                    MetricsStatCell(value: "\(m.openTasks)",   label: "open tasks")
                    Divider().frame(height: 34)
                    MetricsStatCell(value: "\(m.eventsToday)", label: "events today")
                        .padding(.leading, 12)
                }

                // Completion rate ring
                MetricsCompletionDonut(rate: m.completionRate, size: 96)

                // Goal avg
                HStack {
                    Text("GOAL AVG")
                        .atlasCapsLabel()
                    Spacer()
                    Text("\(Int(m.goalAvgProgress * 100))%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(
                            m.goalAvgProgress >= 0.7
                                ? AtlasTheme.Colors.accentText
                                : AtlasTheme.Colors.textSecondary
                        )
                }
            }
        }
    }
}
