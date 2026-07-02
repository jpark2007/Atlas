import WidgetKit
import SwiftUI

// MARK: - Timeline (shared by both lock widgets)

struct LockEntry: TimelineEntry {
    let date: Date
    let snapshot: SharedSnapshot
}

struct LockProvider: TimelineProvider {
    func placeholder(in context: Context) -> LockEntry {
        LockEntry(date: Date(), snapshot: .empty)
    }
    func getSnapshot(in context: Context, completion: @escaping (LockEntry) -> Void) {
        completion(LockEntry(date: Date(), snapshot: SharedSnapshot.read() ?? .empty))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LockEntry>) -> Void) {
        let snapshot = SharedSnapshot.read() ?? .empty
        let dates = SharedSnapshot.timelineDates(for: snapshot.today)
        let entries = dates.map { LockEntry(date: $0, snapshot: snapshot) }
        let refresh = (dates.last ?? Date()).addingTimeInterval(15 * 60)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

// MARK: - Rectangular (next item + "then …")

struct LockRectangularWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AtlasLockRect", provider: LockProvider()) { entry in
            LockRectView(snapshot: entry.snapshot, date: entry.date)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Next up")
        .description("Your next item and what follows.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct LockRectView: View {
    let snapshot: SharedSnapshot
    let date: Date

    private var rows: [SharedSnapshot.Row] { snapshot.rows(notEndedAt: date) }

    var body: some View {
        content
            // Empty state deep-links to capture (spec §8); otherwise to today.
            .widgetURL(URL(string: rows.isEmpty ? "atlas://capture" : "atlas://today")!)
    }

    // Drew's wish in one widget: a leading "how many left" count column, a thin
    // full-height divider, then the "next item" content taking the remaining width.
    // iOS anchors lock widgets, so the CONTENT fills the whole frame edge to edge.
    @ViewBuilder private var content: some View {
        HStack(spacing: 8) {
            VStack(spacing: 0) {
                Text("\(snapshot.leftCount)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                Text("LEFT")
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
            }
            .fixedSize()

            Divider()

            nextUp
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var nextUp: some View {
        if let first = rows.first {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(first.time)  \(first.title)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                if rows.count > 1 {
                    Text("then \(rows[1].title)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if snapshot.needTimeCount > 0 {
                    Text("\(snapshot.needTimeCount) need a time")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Text("Nothing scheduled")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text("tap to capture")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Circular (count-left gauge)

struct LockCircularWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AtlasLockCircular", provider: LockProvider()) { entry in
            LockCircularView(snapshot: entry.snapshot)
                .containerBackground(.clear, for: .widget)
                .widgetURL(URL(string: "atlas://today")!)
        }
        .configurationDisplayName("Left today")
        .description("How much is left today.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct LockCircularView: View {
    let snapshot: SharedSnapshot

    // Honest count-only design: a full ring (no meaningless progress fill) around
    // the number left today. The old gauge divided leftCount by an arbitrary total.
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Circle().stroke(.tint, lineWidth: 3).padding(2)
            VStack(spacing: -1) {
                Text("\(snapshot.leftCount)")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.5)
                Text("LEFT")
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
