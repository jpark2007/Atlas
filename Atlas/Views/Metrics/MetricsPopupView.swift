import SwiftUI

/// Popup sheet for metrics — fleshed out in Task 8.
struct MetricsPopupView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Metrics")
                    .font(AtlasTheme.Font.cardTitle())
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                .buttonStyle(.plain)
            }

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

            Spacer()
        }
        .padding(24)
        .frame(width: 480, height: 360)
        .background(AtlasTheme.Colors.bgCard)
    }
}
