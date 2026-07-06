import Foundation
import AtlasCore

/// Concrete two-way Google-Doc write-back — the impl injected into
/// `\.docNoteWriteBack` at the app root. Posts a linked note's Markdown to the
/// `drive-writeback` edge function, which performs the staleness guard and converts
/// Markdown → Doc via Drive `files.update` (see the design doc's §Server-flow 4 and
/// `supabase/functions/drive-writeback/index.ts`).
///
/// The note body is already persisted by the normal note-save path; this only drives
/// the Drive side. On a stale conflict the edge function returns `409 {error:"stale"}`,
/// surfaced here as `.changedInGoogle` so `NoteEditorView` can offer refresh/overwrite.
struct GoogleDocWriteBackClient: DocNoteWriteBack {
    /// Supplies a currently-valid Supabase access token (JWT), refreshing if needed.
    /// `nil` when signed out/offline — a write-back then throws (`NoteEditorView`
    /// keeps the local Markdown copy).
    let accessToken: () async -> String?

    func writeBack(reference: Reference, markdown: String, overwrite: Bool) async throws -> DocWriteBackOutcome {
        guard let noteID = reference.noteID else { throw WriteBackError.notLinked }
        guard let jwt = await accessToken() else { throw WriteBackError.notSignedIn }

        let url = SupabaseConfig.functionsBase.appendingPathComponent("drive-writeback")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "noteId": noteID.uuidString,
            "markdown": markdown,
            "overwrite": overwrite,
        ]
        // The client's own baseline catches a Google-side edit the cron pulled into the
        // DB but not yet into this in-memory reference — send it when we have one; the
        // server falls back to its stored baseline otherwise.
        if let mt = reference.modifiedTime {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            body["expectedModifiedTime"] = f.string(from: mt)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        if code == 200, (payload?["ok"] as? Bool) == true {
            // Drive's re-baselined modifiedTime (the value the server also stored) — let
            // the editor refresh its in-memory reference so a rapid re-save doesn't stale.
            var newModifiedTime: Date?
            if let iso = payload?["modifiedTime"] as? String {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                newModifiedTime = f.date(from: iso) ?? {
                    f.formatOptions = [.withInternetDateTime]
                    return f.date(from: iso)
                }()
            }
            return .written(modifiedTime: newModifiedTime)
        }
        // Only the explicit "stale" guard maps to the refresh/overwrite dialog; any
        // other 4xx/5xx (not connected, trashed, Drive error) is a hard failure.
        if code == 409, (payload?["error"] as? String) == "stale" {
            return .changedInGoogle
        }
        throw WriteBackError.server((payload?["error"] as? String) ?? "HTTP \(code)")
    }

    enum WriteBackError: LocalizedError {
        case notLinked
        case notSignedIn
        case server(String)

        var errorDescription: String? {
            switch self {
            case .notLinked:   return "This note isn't linked to a Google Doc."
            case .notSignedIn: return "Sign in to Atlas to sync with Google Docs."
            case .server(let message): return message
            }
        }
    }
}
