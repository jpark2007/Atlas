import SwiftUI
import AtlasCore
import Charts

// MARK: - Shared subviews (used by MetricsView, MetricsPopupView, MetricsCard)

/// Single stat "number + label" display used in summary grids.
struct MetricsStatCell: View {
    let value: String
    let label: String
    var accent: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .atlasMono(size: 22, weight: .semibold)
                .foregroundStyle(accent ? AtlasTheme.Colors.accentText : AtlasTheme.Colors.textPrimary)
            Text(label)
                .atlasFont(size: 12, weight: .medium)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Completion ring (Swift Charts donut) with a center percentage label.
/// Replaces the old linear `MetricsCompletionBar`; same `rate` (0…1) input.
struct MetricsCompletionDonut: View {
    let rate: Double            // 0…1
    var label: String = "COMPLETION"
    var size: CGFloat = 128

    private var clamped: Double { min(max(rate, 0), 1) }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Chart {
                    SectorMark(
                        angle: .value("Done", clamped),
                        innerRadius: .ratio(0.70),
                        angularInset: 1.5
                    )
                    .cornerRadius(4)
                    .foregroundStyle(AtlasTheme.Colors.accent)

                    SectorMark(
                        angle: .value("Remaining", 1 - clamped),
                        innerRadius: .ratio(0.70),
                        angularInset: 1.5
                    )
                    .cornerRadius(4)
                    .foregroundStyle(AtlasTheme.Colors.border)
                }
                .chartLegend(.hidden)
                .frame(width: size, height: size)

                Text("\(Int((clamped * 100).rounded()))%")
                    .atlasMono(size: size * 0.24, weight: .semibold)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
            }

            Text(label)
                .atlasCapsLabel()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Per-space task distribution as a Swift Charts donut (sectors sized by each
/// space's total task count, colored by space color) plus a compact legend.
/// Replaces the old linear `MetricsSpaceLoadBars`; same `[SpaceLoad]` input.
struct MetricsSpaceDonut: View {
    let loads: [SpaceLoad]
    var size: CGFloat = 124

    private var hasData: Bool { loads.contains { $0.totalCount > 0 } }

    var body: some View {
        if hasData {
            HStack(alignment: .center, spacing: 18) {
                Chart(loads) { load in
                    SectorMark(
                        angle: .value("Tasks", load.totalCount),
                        innerRadius: .ratio(0.62),
                        angularInset: 1.5
                    )
                    .cornerRadius(3)
                    .foregroundStyle(load.color)
                }
                .chartLegend(.hidden)
                .frame(width: size, height: size)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(loads) { load in
                        HStack(spacing: 8) {
                            Circle().fill(load.color).frame(width: 7, height: 7)
                            Text(load.spaceName)
                                .atlasFont(size: 13, weight: .medium, design: .rounded)
                                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                            Spacer(minLength: 10)
                            Text("\(load.openCount) open / \(load.totalCount) total")
                                .atlasMono(size: 11)
                                .foregroundStyle(AtlasTheme.Colors.textMuted)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("No task data yet.")
                .atlasFont(size: 13, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
    }
}

// MARK: - Full-page MetricsView

struct MetricsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let m = AtlasMetrics.compute(from: state)

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {

                // Page kicker + relationship-graph entry
                HStack {
                    Text("METRICS")
                        .atlasCapsLabel()
                    Spacer()
                    Button { state.presentGraph = true } label: {
                        HStack(spacing: 6) {
                            BrandLogo(size: 16).opacity(0.85)
                            Text("Graph").atlasFont(size: 13, weight: .medium, design: .rounded)
                                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Open relationship graph")
                }

                // ── Summary ────────────────────────────────────────────────
                AtlasCard {
                    VStack(alignment: .leading, spacing: 14) {
                        cardTitle("At a glance", icon: "chart.bar.fill")

                        HStack(spacing: 0) {
                            MetricsStatCell(value: "\(m.openTasks)",    label: "open tasks")
                            Divider().frame(height: 38)
                            MetricsStatCell(value: "\(m.doneTasks)",    label: "completed",   accent: true)
                                .padding(.leading, 12)
                            Divider().frame(height: 38)
                            MetricsStatCell(value: "\(m.eventsToday)",  label: "events today")
                                .padding(.leading, 12)
                            Divider().frame(height: 38)
                            MetricsStatCell(value: "\(m.noteCount)",    label: "notes")
                                .padding(.leading, 12)
                        }

                        MetricsCompletionDonut(rate: m.completionRate)
                    }
                }

                // ── By Space ───────────────────────────────────────────────
                if !m.perSpace.isEmpty {
                    AtlasCard {
                        VStack(alignment: .leading, spacing: 14) {
                            cardTitle("By space", icon: "square.grid.2x2.fill")
                            MetricsSpaceDonut(loads: m.perSpace)
                        }
                    }
                }

                // ── Calendar ───────────────────────────────────────────────
                AtlasCard {
                    VStack(alignment: .leading, spacing: 14) {
                        cardTitle("Calendar", icon: "calendar")

                        HStack(spacing: 0) {
                            MetricsStatCell(value: "\(m.eventsToday)",    label: "events today")
                            Divider().frame(height: 38)
                            MetricsStatCell(value: "\(m.eventsThisWeek)", label: "events this week")
                                .padding(.leading, 12)
                        }
                    }
                }

                // ── Goals ──────────────────────────────────────────────────
                AtlasCard {
                    VStack(alignment: .leading, spacing: 14) {
                        cardTitle("Goals", icon: "target")

                        HStack(spacing: 0) {
                            MetricsStatCell(
                                value: "\(Int(m.goalAvgProgress * 100))%",
                                label: "avg goal progress",
                                accent: m.goalAvgProgress >= 0.7
                            )
                        }

                        MetricsCompletionDonut(rate: m.goalAvgProgress, label: "GOAL AVG", size: 112)
                    }
                }
            }
            .padding(28)
        }
        .background(AtlasTheme.Colors.bgBase)
    }

    private func cardTitle(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .atlasFont(size: 12, weight: .semibold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
            Text(title)
                .atlasCapsLabel()
        }
    }
}
