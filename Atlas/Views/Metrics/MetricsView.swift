import SwiftUI

/// Full-page metrics view — fleshed out in Task 8.
struct MetricsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("METRICS")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)

                AtlasCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Metrics")
                            .font(AtlasTheme.Font.cardTitle())
                            .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        Text("Full metrics coming in Task 8.")
                            .font(AtlasTheme.Font.body())
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                    }
                }
            }
            .padding(28)
        }
        .background(AtlasTheme.Colors.bgBase)
    }
}
