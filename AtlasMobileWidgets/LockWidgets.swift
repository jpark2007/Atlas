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
        let entry = LockEntry(date: Date(), snapshot: SharedSnapshot.read() ?? .empty)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

// MARK: - Rectangular (next item + "then …")

struct LockRectangularWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AtlasLockRect", provider: LockProvider()) { entry in
            LockRectView(snapshot: entry.snapshot)
                .containerBackground(.clear, for: .widget)
                .widgetURL(URL(string: "atlas://today")!)
        }
        .configurationDisplayName("Next up")
        .description("Your next item and what follows.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct LockRectView: View {
    let snapshot: SharedSnapshot

    var body: some View {
        if let first = snapshot.today.first {
            HStack(spacing: 6) {
                Capsule().fill(.tint).frame(width: 2.5)   // thin leading accent bar (system-tinted)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(first.time)  \(first.title)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    if snapshot.today.count > 1 {
                        Text("then \(snapshot.today[1].title)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if snapshot.needTimeCount > 0 {
                        Text("\(snapshot.needTimeCount) need a time")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
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

    private var total: Int { max(snapshot.leftCount + snapshot.today.count, 1) }

    var body: some View {
        Gauge(value: Double(snapshot.leftCount), in: 0...Double(total)) {
            Text("LEFT")
        } currentValueLabel: {
            Text("\(snapshot.leftCount)")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
        }
        .gaugeStyle(.accessoryCircular)
    }
}
