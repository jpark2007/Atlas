import Foundation

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
        let isNow: Bool
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

    // MARK: - App-group I/O

    static let appGroup = "group.com.atlas.mobile"
    static let fileName = "today.json"

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(fileName)
    }

    static func read() -> SharedSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SharedSnapshot.self, from: data)
    }

    func write() {
        guard let url = SharedSnapshot.fileURL,
              let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static let empty = SharedSnapshot(today: [], needTimeCount: 0, leftCount: 0,
                                      dateLabel: "", spaces: [], generatedAt: Date())
}
