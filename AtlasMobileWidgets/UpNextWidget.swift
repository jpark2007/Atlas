import WidgetKit
import SwiftUI

/// The small home widget: ONE thing, big — what's next, when, and which room it's in
/// (class meetings carry a room). A quiet second line names the one after it.
/// Reuses `LockProvider`, so it and the lock widgets are always showing the same day.
struct UpNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AtlasUpNext", provider: LockProvider()) { entry in
            UpNextView(snapshot: entry.snapshot, date: entry.date)
                .containerBackground(WidgetTheme.bg, for: .widget)
        }
        .configurationDisplayName("Up next")
        .description("The one thing that's next, and where.")
        .supportedFamilies([.systemSmall])
    }
}

struct UpNextView: View {
    let snapshot: SharedSnapshot
    let date: Date

    private var rows: [SharedSnapshot.Row] { snapshot.rows(notEndedAt: date) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(rows.first.map { $0.isNow(at: date) ? "NOW" : "UP NEXT" } ?? "TODAY")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(rows.first?.isNow(at: date) == true ? WidgetTheme.accentText : WidgetTheme.faint)

            if let next = rows.first {
                Text(next.rangeText)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(next.isNow(at: date) ? WidgetTheme.accentText : WidgetTheme.muted)
                    .padding(.top, 3)

                Text(next.title)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 1)

                if let room = next.location, !room.isEmpty {
                    HStack(spacing: 3) {
                        Circle().fill(Color(hex: next.spaceColorHex)).frame(width: 5, height: 5)
                        Text(room)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(WidgetTheme.muted)
                            .lineLimit(1)
                    }
                    .padding(.top, 3)
                }

                Spacer(minLength: 4)
                thenLine
            } else {
                Spacer(minLength: 0)
                Text("Nothing scheduled")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(WidgetTheme.ink)
                Text("tap to capture")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .foregroundStyle(WidgetTheme.faint)
                    .padding(.top, 2)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: rows.isEmpty ? "atlas://capture" : "atlas://today")!)
    }

    /// The item after the next one — or, with nothing after it, whatever is still owed.
    @ViewBuilder private var thenLine: some View {
        if rows.count > 1 {
            Text("then \(rows[1].time) · \(rows[1].title)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(WidgetTheme.faint)
                .lineLimit(1)
        } else if snapshot.needTimeCount > 0 {
            Text("\(snapshot.needTimeCount) need a time")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(WidgetTheme.faint)
                .lineLimit(1)
        } else {
            Text("nothing after")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(WidgetTheme.faint)
        }
    }
}

extension SharedSnapshot.Row {
    /// "10 AM – 10:50 AM" for a timed row; the stored label ("all-day") otherwise.
    var rangeText: String {
        guard startEpoch < endEpoch else { return time }
        return "\(time) – \(Self.clock(Date(timeIntervalSince1970: endEpoch)))"
    }

    private static let hourFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h a"; return f }()
    private static let minuteFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h:mm a"; return f }()

    /// Mirrors the app writer's clock: whole hours drop the ":00".
    static func clock(_ date: Date) -> String {
        (Calendar.current.component(.minute, from: date) == 0 ? hourFormatter : minuteFormatter).string(from: date)
    }
}
