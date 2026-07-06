import Foundation

/// Re-nests the flat `projects` array (as loaded from Supabase) into their
/// parent spaces. `spaceID` is authoritative when present; `spaceName` is the
/// fallback for rows written before migration 0015. Projects matching no
/// space are dropped (the caller logs them as orphans).
public enum SpaceNesting {
    public static func nest(projects: [Project], into spaces: [Space]) -> [Space] {
        var spaces = spaces
        for i in spaces.indices {
            let s = spaces[i]
            spaces[i].projects = projects.filter { p in
                if let sid = p.spaceID { return sid == s.id }
                return p.spaceName == s.name
            }
        }
        return spaces
    }
}
