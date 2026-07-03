import AppKit
import AtlasCore

/// Launches the server-hosted Google Picker page in the system browser — the
/// Docs → Notes import entry point. Mirrors the existing connect flows
/// (`GoogleAuthService.connect()` opens Google consent via `NSWorkspace`); the
/// consent + file-pick can only be done by the human, in the browser.
///
/// CONTRACT — matches the deployed `drive-import` edge function
/// (`supabase/functions/drive-import/index.ts`):
///   • Page URL:  `<functionsBase>/drive-import` (GET serves the picker page).
///   • The Supabase access token AND the target projectId both ride the URL
///     **fragment** (`#token=…&project=…`), NOT query items, so they are never sent
///     to the server on the GET and never land in an access log. The page reads
///     `location.hash` client-side, mints a `drive.file` token, and POSTs the picked
///     fileIds back to the same function with the JWT as a `Bearer` header (the POST
///     re-verifies it via `auth.getUser`).
enum DrivePickerLauncher {

    /// The URL the browser opens to run the picker for `projectID`. `nil` only if
    /// the components fail to compose (never in practice).
    static func importURL(projectID: UUID, supabaseAccessToken: String) -> URL? {
        var comps = URLComponents(
            url: SupabaseConfig.functionsBase.appendingPathComponent("drive-import"),
            resolvingAgainstBaseURL: false)
        // Both the JWT and the target project ride the fragment (client-only — never
        // in the request line / access log). Keys must match the page's
        // `location.hash` parser: `token` and `project`.
        comps?.fragment = "token=\(supabaseAccessToken)&project=\(projectID.uuidString)"
        return comps?.url
    }

    /// Opens the picker in the system browser. Returns `false` if the URL couldn't
    /// be built or the open failed.
    @discardableResult
    static func launch(projectID: UUID, supabaseAccessToken: String) -> Bool {
        guard let url = importURL(projectID: projectID, supabaseAccessToken: supabaseAccessToken)
        else { return false }
        return NSWorkspace.shared.open(url)
    }
}
