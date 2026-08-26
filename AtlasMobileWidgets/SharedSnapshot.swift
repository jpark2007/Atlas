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
        /// Room / building when the item has one — class meetings carry it
        /// ("B120"). Optional, so a row written before this field existed decodes
        /// as `nil` instead of throwing.
        var location: String? = nil

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

    /// A class, tinted — one chip in a "This week" day row.
    struct ClassChip: Codable, Hashable {
        let name: String         // code when the class has one ("EN 101"), else its name
        let colorHex: String
    }

    /// One weekday of the "This week" widget: what meets, and how much is due.
    struct WeekDay: Codable, Hashable {
        let label: String        // "Mon"
        let startEpoch: Double   // that day's midnight, so the widget marks today live
        let meets: [ClassChip]   // in time order
        let dueCount: Int
    }

    /// A class offered in the "One class" widget's configuration.
    struct ClassRef: Codable, Hashable {
        let id: String
        let name: String
        let colorHex: String
    }

    /// One piece of open work filed under a class.
    struct ClassWork: Codable, Hashable {
        let classId: String
        let title: String
        let dueLabel: String     // "" when undated
        let dueEpoch: Double     // 0 = undated; lets the widget flag overdue live
    }

    var today: [Row]
    var needTimeCount: Int
    var leftCount: Int
    var dateLabel: String        // "Wed, Jul 1" for the header
    var spaces: [SpaceRef]       // powers the home-widget space configuration
    var generatedAt: Date
    // Fields below arrived after 1.0. Every one defaults to empty and decodes
    // `IfPresent`, so the snapshot an older app version left on disk still reads —
    // a throwing decode here would blank every widget until the app next runs.
    var week: [WeekDay] = []     // Mon–Fri, powers "This week"
    var classes: [ClassRef] = [] // the "One class" picker
    var classWork: [ClassWork] = []

    enum CodingKeys: String, CodingKey {
        case today, needTimeCount, leftCount, dateLabel, spaces, generatedAt, week, classes, classWork
    }

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

    static let appGroup = "group.com.atlaslm.mobile"
    static let fileName = "today.json"
    private static let log = Logger(subsystem: "com.atlaslm.AtlasMobile", category: "appgroup")

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

/// Hand-written decoding (in an extension, so the memberwise init survives): EVERY
/// key is optional with an empty default. The file on disk was written by whichever
/// app version ran last — an older one, right after an update — and a widget that
/// throws here renders blank until the app is next opened.
extension SharedSnapshot {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        today         = try c.decodeIfPresent([Row].self, forKey: .today) ?? []
        needTimeCount = try c.decodeIfPresent(Int.self, forKey: .needTimeCount) ?? 0
        leftCount     = try c.decodeIfPresent(Int.self, forKey: .leftCount) ?? 0
        dateLabel     = try c.decodeIfPresent(String.self, forKey: .dateLabel) ?? ""
        spaces        = try c.decodeIfPresent([SpaceRef].self, forKey: .spaces) ?? []
        generatedAt   = try c.decodeIfPresent(Date.self, forKey: .generatedAt) ?? Date()
        week          = try c.decodeIfPresent([WeekDay].self, forKey: .week) ?? []
        classes       = try c.decodeIfPresent([ClassRef].self, forKey: .classes) ?? []
        classWork     = try c.decodeIfPresent([ClassWork].self, forKey: .classWork) ?? []
    }
}
