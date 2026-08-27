import Foundation

/// The scanned syllabus itself, kept in the private `syllabi` bucket (migration 0044).
///
/// The scan reads pages and discards them; this is what keeps the DOCUMENT, so a class
/// page can always show the real wording of a policy. One object per class, overwritten
/// on rescan — there is no versioning, on purpose.
///
/// Supabase has no Swift storage SDK here, so this speaks the storage REST API with the
/// same anon-key + bearer-session pattern `SyllabusScan` uses.
public enum SyllabusStorage {

    /// The bucket created by 0044. Private; every read is RLS'd to the owner.
    public static let bucket = "syllabi"

    /// Where a class's syllabus lives: `{user_id}/{project_id}/syllabus.{ext}`. The first
    /// segment is the owner check the storage policies make, so it is never optional.
    public static func path(userID: String, projectID: UUID, fileExtension: String) -> String {
        let ext = fileExtension.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return "\(userID)/\(projectID.uuidString.lowercased())/syllabus.\(ext.isEmpty ? "pdf" : ext)"
    }

    /// The file name a downloaded object should be written under — the extension matters
    /// because QuickLook decides how to render from it.
    public static func fileExtension(ofPath path: String) -> String {
        let ext = (path as NSString).pathExtension
        return ext.isEmpty ? "pdf" : ext.lowercased()
    }

    /// Upload (or replace) the syllabus for a class. Returns the stored path so the caller
    /// can put it on the project row.
    ///
    /// Throws `AtlasAIError.notAuthenticated` without a session and `AtlasAIError.httpError`
    /// on a non-2xx — a failed upload must never be reported as a stored file.
    @discardableResult
    public static func upload(_ data: Data,
                              contentType: String,
                              fileExtension: String,
                              projectID: UUID,
                              session: SupabaseSession?,
                              urlSession: URLSession = .shared) async throws -> String {
        guard let session else { throw AtlasAIError.notAuthenticated }
        let objectPath = path(userID: session.user.id,
                              projectID: projectID,
                              fileExtension: fileExtension)

        var request = URLRequest(url: objectURL(objectPath))
        request.httpMethod = "POST"
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        // A rescan writes over the previous document rather than piling up copies.
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        request.httpBody = data

        let (body, response) = try await urlSession.data(for: request)
        try check(response, body: body)
        return objectPath
    }

    /// Download a stored syllabus and write it to a temp file QuickLook can open.
    /// The extension is taken from the stored path so the previewer picks the right type.
    public static func downloadToTemporaryFile(path objectPath: String,
                                               session: SupabaseSession?,
                                               urlSession: URLSession = .shared) async throws -> URL {
        guard let session else { throw AtlasAIError.notAuthenticated }

        var request = URLRequest(url: objectURL(objectPath))
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        try check(response, body: data)

        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("syllabus-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension(ofPath: objectPath))
        try data.write(to: file, options: .atomic)
        return file
    }

    // MARK: - Plumbing

    /// `…/storage/v1/object/{bucket}/{path}`. Every segment we build is a UUID or a
    /// fixed name, so there is nothing here that needs percent-encoding.
    private static func objectURL(_ objectPath: String) -> URL {
        SupabaseConfig.url
            .appendingPathComponent("storage/v1/object")
            .appendingPathComponent(bucket)
            .appendingPathComponent(objectPath)
    }

    private static func check(_ response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AtlasAIError.httpError(0, "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AtlasAIError.from(status: http.statusCode,
                                    body: String(data: body, encoding: .utf8) ?? "(empty)")
        }
    }
}
