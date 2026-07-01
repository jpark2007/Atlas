import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Configuration (space picker)

/// A space offered in the widget's configuration — sourced from the shared JSON.
struct WidgetSpaceEntity: AppEntity {
    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Space" }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    static var defaultQuery = WidgetSpaceQuery()
}

struct WidgetSpaceQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetSpaceEntity] {
        all().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [WidgetSpaceEntity] { all() }
    private func all() -> [WidgetSpaceEntity] {
        (SharedSnapshot.read()?.spaces ?? []).map { WidgetSpaceEntity(id: $0.id, name: $0.name) }
    }
}

struct TodayConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Today" }
    static var description: IntentDescription { "Your day at a glance." }

    @Parameter(title: "Space")
    var space: WidgetSpaceEntity?
}

// MARK: - Timeline

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedSnapshot
    let spaceId: String?
    let spaceName: String?
}

struct TodayProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), snapshot: .empty, spaceId: nil, spaceName: nil)
    }
    func snapshot(for configuration: TodayConfigIntent, in context: Context) async -> TodayEntry {
        entry(configuration)
    }
    func timeline(for configuration: TodayConfigIntent, in context: Context) async -> Timeline<TodayEntry> {
        Timeline(entries: [entry(configuration)], policy: .after(Date().addingTimeInterval(15 * 60)))
    }
    private func entry(_ config: TodayConfigIntent) -> TodayEntry {
        TodayEntry(date: Date(), snapshot: SharedSnapshot.read() ?? .empty,
                   spaceId: config.space?.id, spaceName: config.space?.name)
    }
}

// MARK: - Widget

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "AtlasToday", intent: TodayConfigIntent.self, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(WidgetTheme.bg, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Your day at a glance.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - View

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    private var rows: [SharedSnapshot.Row] {
        guard let name = entry.spaceName else { return entry.snapshot.today }
        return entry.snapshot.today.filter { $0.spaceName.caseInsensitiveCompare(name) == .orderedSame }
    }

    private var maxRows: Int { family == .systemLarge ? 4 : 3 }
    private var todayURL: URL {
        if let id = entry.spaceId { return URL(string: "atlas://today?space=\(id)")! }
        return URL(string: "atlas://today")!
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if rows.isEmpty {
                emptyState
            } else {
                ForEach(Array(rows.prefix(maxRows).enumerated()), id: \.offset) { _, row in
                    rowView(row)
                }
                Spacer(minLength: 0)
                if entry.snapshot.needTimeCount > 0 { needTimePill }
            }
        }
        .widgetURL(todayURL)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Today")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(WidgetTheme.ink)
            Text(entry.snapshot.dateLabel)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(WidgetTheme.muted)
            Spacer()
            Text("\(entry.snapshot.leftCount) left")
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .foregroundStyle(WidgetTheme.faint)
            Link(destination: URL(string: "atlas://capture")!) {
                Image(systemName: "mic")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WidgetTheme.ink)
            }
        }
    }

    private func rowView(_ row: SharedSnapshot.Row) -> some View {
        HStack(spacing: 9) {
            if row.isNow {
                Capsule().fill(WidgetTheme.accent).frame(width: 3, height: 16)
            } else {
                Capsule().fill(.clear).frame(width: 3, height: 16)
            }
            Text(row.time)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(row.isNow ? WidgetTheme.accentText : WidgetTheme.muted)
                .frame(width: 52, alignment: .leading)
            Circle().fill(Color(hex: row.spaceColorHex)).frame(width: 7, height: 7)
            Text(row.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            if row.isNow {
                Text("NOW")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetTheme.accentText)
            }
        }
    }

    private var needTimePill: some View {
        Link(destination: URL(string: "atlas://unscheduled")!) {
            Text("Need a time · \(entry.snapshot.needTimeCount)")
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .foregroundStyle(WidgetTheme.ink)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(WidgetTheme.ink, lineWidth: 1.5))
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer(minLength: 0)
            Text("Nothing scheduled")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(WidgetTheme.ink)
            Text("tap to capture")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .foregroundStyle(WidgetTheme.faint)
            Spacer(minLength: 0)
        }
    }
}
