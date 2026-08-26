import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Configuration (class picker)

/// A class offered in the widget's configuration — same shape as `WidgetSpaceEntity`,
/// sourced from the same shared JSON.
struct WidgetClassEntity: AppEntity {
    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Class" }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    static var defaultQuery = WidgetClassQuery()
}

struct WidgetClassQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetClassEntity] {
        all().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [WidgetClassEntity] { all() }
    private func all() -> [WidgetClassEntity] {
        (SharedSnapshot.read()?.classes ?? []).map { WidgetClassEntity(id: $0.id, name: $0.name) }
    }
}

struct ClassConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "One class" }
    static var description: IntentDescription { "One class's open work." }

    @Parameter(title: "Class")
    var klass: WidgetClassEntity?
}

// MARK: - Timeline

struct ClassEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedSnapshot
    let classId: String?
}

struct ClassProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ClassEntry {
        ClassEntry(date: Date(), snapshot: .empty, classId: nil)
    }
    func snapshot(for configuration: ClassConfigIntent, in context: Context) async -> ClassEntry {
        entry(configuration)
    }
    func timeline(for configuration: ClassConfigIntent, in context: Context) async -> Timeline<ClassEntry> {
        let now = Date()
        // Due labels are written by the app; only the overdue line moves on its own,
        // and that turns over at midnight.
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))
        return Timeline(entries: [entry(configuration)],
                        policy: .after(midnight ?? now.addingTimeInterval(3600)))
    }
    private func entry(_ config: ClassConfigIntent) -> ClassEntry {
        ClassEntry(date: Date(), snapshot: SharedSnapshot.read() ?? .empty, classId: config.klass?.id)
    }
}

// MARK: - Widget

struct ClassWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "AtlasClass", intent: ClassConfigIntent.self, provider: ClassProvider()) { entry in
            ClassWidgetView(entry: entry)
                .containerBackground(WidgetTheme.bg, for: .widget)
        }
        .configurationDisplayName("One class")
        .description("What's open in one class.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - View

struct ClassWidgetView: View {
    let entry: ClassEntry

    /// The configured class, or — before the user has picked one — their first, so a
    /// freshly dropped widget says something real instead of "choose a class".
    private var klass: SharedSnapshot.ClassRef? {
        entry.snapshot.classes.first { $0.id == entry.classId } ?? entry.snapshot.classes.first
    }

    private var work: [SharedSnapshot.ClassWork] {
        guard let klass else { return [] }
        return entry.snapshot.classWork.filter { $0.classId == klass.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let klass {
                header(klass)
                if work.isEmpty {
                    empty(title: "All clear", hint: "nothing open")
                } else {
                    ForEach(Array(work.prefix(3).enumerated()), id: \.offset) { _, item in
                        workRow(item)
                    }
                    Spacer(minLength: 0)
                    if work.count > 3 {
                        Text("+\(work.count - 3) more")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .textCase(.uppercase)
                            .foregroundStyle(WidgetTheme.faint)
                    }
                }
            } else {
                empty(title: "No classes yet", hint: "add a class in school")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "atlas://today")!)
    }

    private func header(_ klass: SharedSnapshot.ClassRef) -> some View {
        HStack(spacing: 7) {
            Circle().fill(Color(hex: klass.colorHex)).frame(width: 8, height: 8)
            Text(klass.name)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text("\(work.count) open")
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .foregroundStyle(WidgetTheme.faint)
        }
    }

    private func workRow(_ item: SharedSnapshot.ClassWork) -> some View {
        // Overdue is computed against THIS entry's date, never stamped by the app.
        let overdue = item.dueEpoch > 0 && item.dueEpoch < entry.date.timeIntervalSince1970
        return HStack(spacing: 9) {
            Text(item.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            if !item.dueLabel.isEmpty {
                Text(item.dueLabel)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(overdue ? WidgetTheme.accentText : WidgetTheme.muted)
                    .lineLimit(1)
            }
        }
    }

    private func empty(title: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer(minLength: 0)
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(WidgetTheme.ink)
            Text(hint)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .foregroundStyle(WidgetTheme.faint)
            Spacer(minLength: 0)
        }
    }
}
