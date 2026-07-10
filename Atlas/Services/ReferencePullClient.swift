import Foundation
import AtlasCore

/// On-demand "Sync now" pull for one linked Doc-note reference. POSTs the
/// reference id to the `reference-pull` edge function, which mints a Google token
/// and runs the shared pull machinery (see `supabase/functions/reference-pull`).
///
/// Best-effort by contract: a failed pull is not something the user must act on —
/// the caller falls back to reloading the last cron result. This never throws.
struct ReferencePullClient {
    /// Supplies a currently-valid Supabase access token (JWT), refreshing if needed.
    /// `nil` when signed out/offline — the pull is then skipped (returns false).
    let accessToken: () async -> String?

    /// Pull the given reference now. Returns true only on a `{ ok: true }` response;
    /// false on any failure (no token, network, or a server error) so the caller can
    /// fall back to a plain reload of the last synced version.
    func pull(referenceID: UUID) async -> Bool {
        guard let jwt = await accessToken() else { return false }

        let url = SupabaseConfig.functionsBase.appendingPathComponent("reference-pull")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["referenceId": referenceID.uuidString])

        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            payload["ok"] as? Bool == true
        else { return false }
        return true
    }
}
