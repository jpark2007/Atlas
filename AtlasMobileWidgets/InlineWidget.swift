import WidgetKit
import SwiftUI

/// The one-line lock-screen widget (above the clock): next item and when. Same
/// `LockProvider` — and so the same snapshot — as "Next up".
struct LockInlineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AtlasInline", provider: LockProvider()) { entry in
            LockInlineView(snapshot: entry.snapshot, date: entry.date)
                .containerBackground(.clear, for: .widget)
                .widgetURL(URL(string: "atlas://today")!)
        }
        .configurationDisplayName("Inline")
        .description("Your next item, on one line.")
        .supportedFamilies([.accessoryInline])
    }
}

struct LockInlineView: View {
    let snapshot: SharedSnapshot
    let date: Date

    var body: some View {
        // Inline renders as a single Text; iOS tints and truncates it for us.
        if let next = snapshot.rows(notEndedAt: date).first {
            Text("\(next.time) · \(next.title)")
        } else {
            Text("Nothing scheduled")
        }
    }
}
