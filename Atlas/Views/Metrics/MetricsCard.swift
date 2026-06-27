import SwiftUI

/// Dashboard card for metrics — fleshed out in Task 8.
struct MetricsCard: View {
    var body: some View {
        AtlasCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(AtlasTheme.Colors.accent)
                    Text("Metrics")
                        .font(AtlasTheme.Font.cardTitle())
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                }
                Text("Full metrics coming in Task 8.")
                    .font(AtlasTheme.Font.body())
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
        }
    }
}
