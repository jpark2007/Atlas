import SwiftUI

/// Modal sheet bound to `AppState.presentMetrics`.
/// Shows a fuller metrics breakdown: per-space load bars, event counts,
/// completion rate, goal progress, note count.
struct MetricsPopupView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let m = AtlasMetrics.compute(from: state)

        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 7) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(AtlasTheme.Colors.accent)
                    Text("Metrics")
                        .font(AtlasTheme.Font.cardTitle())
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                }
                Spacer()
                Button {
                    state.presentMetrics = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                        .frame(width: 22, height: 22)
                        .background(AtlasTheme.Colors.bgElevated)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Divider().overlay(AtlasTheme.Colors.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {

                    // ── Summary stats ──────────────────────────────────────
                    AtlasCard {
                        VStack(alignment: .leading, spacing: 14) {
                            sectionLabel("OVERVIEW")

                            HStack(spacing: 0) {
                                MetricsStatCell(value: "\(m.openTasks)",   label: "open tasks")
                                Divider().frame(height: 36)
                                MetricsStatCell(value: "\(m.doneTasks)",   label: "done", accent: true)
                                    .padding(.leading, 12)
                                Divider().frame(height: 36)
                                MetricsStatCell(value: "\(m.noteCount)",   label: "notes")
                                    .padding(.leading, 12)
                            }

                            MetricsCompletionDonut(rate: m.completionRate, size: 112)
                        }
                    }

                    // ── Calendar ───────────────────────────────────────────
                    AtlasCard {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionLabel("CALENDAR")

                            HStack(spacing: 0) {
                                MetricsStatCell(value: "\(m.eventsToday)",    label: "events today")
                                Divider().frame(height: 36)
                                MetricsStatCell(value: "\(m.eventsThisWeek)", label: "this week")
                                    .padding(.leading, 12)
                            }
                        }
                    }

                    // ── By space ───────────────────────────────────────────
                    if !m.perSpace.isEmpty {
                        AtlasCard {
                            VStack(alignment: .leading, spacing: 12) {
                                sectionLabel("BY SPACE")
                                MetricsSpaceDonut(loads: m.perSpace)
                            }
                        }
                    }

                    // ── Goals ──────────────────────────────────────────────
                    AtlasCard {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionLabel("GOALS")
                            HStack {
                                Text("Average progress")
                                    .font(.system(size: 12))
                                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
                                Spacer()
                                Text("\(Int(m.goalAvgProgress * 100))%")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(
                                        m.goalAvgProgress >= 0.7
                                            ? AtlasTheme.Colors.accent
                                            : AtlasTheme.Colors.textSecondary
                                    )
                            }
                            MetricsCompletionDonut(rate: m.goalAvgProgress, label: "GOAL AVG", size: 100)
                        }
                    }

                    // ── Open Metrics page ──────────────────────────────────
                    Button {
                        state.presentMetrics = false
                        state.route = .metrics
                    } label: {
                        HStack {
                            Text("View full metrics page")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AtlasTheme.Colors.accent)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(AtlasTheme.Colors.accent)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 4)
                }
                .padding(16)
            }
        }
        .frame(width: 440, height: 520)
        .background(AtlasTheme.Colors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: AtlasTheme.Radius.lg, style: .continuous))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(AtlasTheme.Font.sectionLabel())
            .tracking(1.1)
            .foregroundStyle(AtlasTheme.Colors.textMuted)
    }
}
