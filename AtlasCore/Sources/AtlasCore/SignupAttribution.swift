import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Signup attribution — "how did you hear about Atlas?" + "what school?", asked
// once right after account creation and stored on the profile row (0051).
// ─────────────────────────────────────────────────────────────────────────────

/// The answers to "How did you hear about Atlas?". Raw values are exactly what
/// lands in `profiles.referral_source`, so the admin dashboard groups on them —
/// never rename one without a migration.
public enum ReferralSource: String, CaseIterable, Codable, Sendable {
    case friend       = "friend"
    case tiktok       = "tiktok"
    case instagram    = "instagram"
    case reddit       = "reddit"
    case googleSearch = "google_search"
    case professor    = "professor"
    case other        = "other"
    /// Written when the step is dismissed without an answer, so it never
    /// re-asks on another device.
    case skipped      = "skipped"

    /// The chips, in the order they're shown. `skipped` is not a choice.
    public static let choices: [ReferralSource] =
        [.friend, .tiktok, .instagram, .reddit, .googleSearch, .professor, .other]

    public var label: String {
        switch self {
        case .friend:       return "Friend / Classmate"
        case .tiktok:       return "TikTok"
        case .instagram:    return "Instagram"
        case .reddit:       return "Reddit"
        case .googleSearch: return "Google search"
        case .professor:    return "Professor / school"
        case .other:        return "Other"
        case .skipped:      return "Skipped"
        }
    }
}

/// One row of the bundled US school list.
public struct School: Codable, Hashable, Sendable, Identifiable {
    public let name: String
    public let domain: String
    public var id: String { name }

    public init(name: String, domain: String) {
        self.name = name
        self.domain = domain
    }
}

/// The bundled US university list, and the type-ahead behind the school picker.
///
/// Data: Hipo `university-domains-list` (MIT) filtered to the United States —
/// see `Resources/us-schools-LICENSE.txt`.
public enum USSchools {
    /// Loaded once from the package resource; `[]` if the resource is missing.
    public static let all: [School] = load()

    /// Type-ahead over the bundled list: case-insensitive, prefix matches
    /// before mid-string ones, each group in the list's own (alphabetical)
    /// order. An empty query returns the head of the list.
    public static func search(_ query: String, limit: Int = 40) -> [School] {
        search(query, in: all, limit: limit)
    }

    /// Testable core of `search(_:limit:)`.
    public static func search(_ query: String, in schools: [School], limit: Int = 40) -> [School] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return Array(schools.prefix(limit)) }
        var prefix: [School] = []
        var contains: [School] = []
        for s in schools {
            let name = s.name.lowercased()
            if name.hasPrefix(q) {
                prefix.append(s)
            } else if name.contains(q) {
                contains.append(s)
            }
        }
        return Array((prefix + contains).prefix(limit))
    }

    /// The resource is `[[name, domain], …]` — the flattest shape that still
    /// carries the domain, which keeps the bundled file around 100 KB.
    private static func load() -> [School] {
        guard let url = Bundle.module.url(forResource: "us-schools", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([[String]].self, from: data)
        else { return [] }
        return rows.compactMap { row in
            guard let name = row.first, !name.isEmpty else { return nil }
            return School(name: name, domain: row.count > 1 ? row[1] : "")
        }
    }
}
