import SwiftUI

// MARK: - Shared subviews (used by MetricsView, MetricsPopupView, MetricsCard)

/// Single stat "number + label" display used in summary grids.
struct MetricsStatCell: View {
    let value: String
    let label: String
    var accent: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(accent ? AtlasTheme.Colors.accent : AtlasTheme.Colors.textPrimary)
            Text(label)
                .font(AtlasTheme.Font.small())
                .foregroundStyle(AtlasTheme.Colors.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Labeled progress bar for completion rate.
struct MetricsCompletionBar: View {
    let rate: Double    // 0…1
    var label: String = "COMPLETION"

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(AtlasTheme.Font.sectionLabel())
                    .tracking(1.1)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
                Spacer()
                Text("\(Int(rate * 100))%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AtlasTheme.Colors.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AtlasTheme.Colors.bgElevated)
                    Capsule()
                        .fill(LinearGradient(
                            colors: [AtlasTheme.Colors.accent, AtlasTheme.Colors.accentDeep],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, geo.size.width * rate))
                }
            }
            .frame(height: 5)
        }
    }
}

/// Per-space task load bar rows.
struct MetricsSpaceLoadBars: View {
    let loads: [SpaceLoad]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(loads) { load in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Circle()
                            .fill(load.color)
                            .frame(width: 7, height: 7)
                        Text(load.spaceName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        Spacer()
                        Text("\(load.openCount) open / \(load.totalCount) total")
                            .font(AtlasTheme.Font.small())
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(AtlasTheme.Colors.bgElevated)
                            let fraction = load.totalCount > 0
                                ? Double(load.openCount) / Double(load.totalCount)
                                : 0
                            Capsule()
                                .fill(load.color.opacity(0.7))
                                .frame(width: max(4, geo.size.width * fraction))
                        }
                    }
                    .frame(height: 4)
                }
            }
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

                // Page kicker
                Text("METRICS")
                    .font(AtlasTheme.Font.sectionLabel())
                    .tracking(1.4)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)

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

                        MetricsCompletionBar(rate: m.completionRate)
                    }
                }

                // ── By Space ───────────────────────────────────────────────
                if !m.perSpace.isEmpty {
                    AtlasCard {
                        VStack(alignment: .leading, spacing: 14) {
                            cardTitle("By space", icon: "square.grid.2x2.fill")
                            MetricsSpaceLoadBars(loads: m.perSpace)
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

                        MetricsCompletionBar(rate: m.goalAvgProgress, label: "GOAL AVG")
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
                .font(.system(size: 12))
                .foregroundStyle(AtlasTheme.Colors.accent)
            Text(title)
                .font(AtlasTheme.Font.cardTitle())
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
        }
    }
}
