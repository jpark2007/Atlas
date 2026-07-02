import Foundation
import os.log

/// The whole contract between the app and the widget extension: a small JSON blob
/// in the shared app-group container. The app (`WidgetSnapshotWriter`) writes it;
/// the widget timeline providers read it. Deliberately Foundation-only so it can be
/// compiled into both targets without dragging AtlasCore into the extension.
struct SharedSnapshot: Codable {
    struct Row: Codable, Hashable {
        let time: String
        let title: String
        let spaceName: String
        let spaceColorHex: String
        /// Item start/end as epoch seconds so providers compute "now" live per
        /// timeline entry (both 0 = all-day / untimed → never "now").
        let startEpoch: Double
        let endEpoch: Double

        /// True when `date` falls inside this timed row — computed per widget
        /// timeline entry so the NOW indicator isn't frozen at app-write time.
        func isNow(at date: Date) -> Bool {
            guard startEpoch < endEpoch else { return false }
            let t = date.timeIntervalSince1970
            return t >= startEpoch && t < endEpoch
        }
    }

    struct SpaceRef: Codable, Hashable {
        let id: String
        let name: String
        let colorHex: String
    }

    var today: [Row]
    var needTimeCount: Int
    var leftCount: Int
    var dateLabel: String        // "Wed, Jul 1" for the header
    var spaces: [SpaceRef]       // powers the home-widget space configuration
    var generatedAt: Date

    // MARK: - Timeline helpers

    /// Entry dates for a widget timeline: now plus each timed row's future start/end
    /// boundary, so the widget flips NOW on/off at the right minute. Capped so we
    /// never flood WidgetKit.
    static func timelineDates(for rows: [Row], now: Date = Date(), cap: Int = 12) -> [Date] {
        var dates: Set<Date> = [now]
        for row in rows where row.startEpoch < row.endEpoch {
            let start = Date(timeIntervalSince1970: row.startEpoch)
            let end = Date(timeIntervalSince1970: row.endEpoch)
            if start > now { dates.insert(start) }
            if end > now { dates.insert(end) }
        }
        return Array(dates.sorted().prefix(cap))
    }

    /// Rows still relevant at `date` — timed rows not yet ended, all-day always kept —
    /// preserving order. Powers the live "next up" on the lock widget.
    func rows(notEndedAt date: Date) -> [Row] {
        let t = date.timeIntervalSince1970
        return today.filter { $0.endEpoch == 0 || $0.endEpoch > t }
    }

    // MARK: - App-group I/O

    static let appGroup = "group.com.atlas.mobile"
    static let fileName = "today.json"
    private static let log = Logger(subsystem: "com.atlas.AtlasMobile", category: "appgroup")

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(fileName)
    }

    static func read() -> SharedSnapshot? {
        guard let url = fileURL else {
            log.error("app-group container unavailable — cannot read snapshot")
            return nil
        }
        do {
            return try JSONDecoder().decode(SharedSnapshot.self, from: Data(contentsOf: url))
        } catch {
            log.debug("read snapshot failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func write() {
        guard let url = SharedSnapshot.fileURL else {
            SharedSnapshot.log.error("app-group container unavailable — cannot write snapshot")
            return
        }
        do {
            try JSONEncoder().encode(self).write(to: url, options: .atomic)
        } catch {
            SharedSnapshot.log.error("write snapshot failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static let empty = SharedSnapshot(today: [], needTimeCount: 0, leftCount: 0,
                                      dateLabel: "", spaces: [], generatedAt: Date())
}
