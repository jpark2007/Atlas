import SwiftUI

// Helpers for the shared `Note` type (declared in Atlas/Models/Models.swift).
// This file intentionally does NOT redeclare `Note` — only extends it.

extension Note {
    /// Highlights `[[mention]]` tokens in the accent color for display surfaces.
    static func highlighted(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        let pattern = #"\[\[([^\]]+)\]\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for match in matches {
            guard let swiftRange = Range(match.range, in: text),
                  let attrRange = Range(swiftRange, in: result) else { continue }
            result[attrRange].foregroundColor = AtlasTheme.Colors.accent
            result[attrRange].font = .system(size: 13, weight: .medium)
        }
        return result
    }

    /// Convenience seed (the app's real seed lives in `MockData.notes`).
    static let mock: [Note] = [
        Note(title: "Midterm study plan",
             body: "Cover trees, heaps, and graph traversal. Re-derive Dijkstra before the [[Data Structures]] midterm.",
             spaceName: "School"),
        Note(title: "Graph algorithms",
             body: "Graph traversal — BFS vs DFS. Remember to track visited set. Reuse the impl from [[Trailhead App]].",
             spaceName: "School"),
    ]
}
