import SwiftUI

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
                        .font(.system(size: 12))
                        .foregroundStyle(AtlasTheme.Colors.accent)
                    Text("At a glance")
                        .font(AtlasTheme.Font.cardTitle())
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    Spacer()
                    Button { state.settingsSection = .metrics; state.route = .settings } label: {
                        HStack(spacing: 4) {
                            Text("Details")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AtlasTheme.Colors.accent)
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
                        .font(AtlasTheme.Font.sectionLabel())
                        .tracking(1.1)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                    Spacer()
                    Text("\(Int(m.goalAvgProgress * 100))%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(
                            m.goalAvgProgress >= 0.7
                                ? AtlasTheme.Colors.accent
                                : AtlasTheme.Colors.textSecondary
                        )
                }
            }
        }
    }
}
