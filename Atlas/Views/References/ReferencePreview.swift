import AppKit
import Quartz
import UniformTypeIdentifiers
import AtlasCore

/// Quick Look for view-only file references. A `.file` reference keeps only a
/// Drive `driveFileId` + `mimeType` — the bytes live in Drive — so previewing means
/// (1) resolving a locally cached copy, or (2) best-effort downloading one via the
/// connected Google token, then handing the local URL to `QLPreviewPanel`.
///
/// CAVEAT (see the design doc's fidelity/scope contract): under `drive.file` scope,
/// a file is readable only by the OAuth **client** that opened it. The Picker import
/// is served by the server's *web* client, so the Mac's *desktop* client token may
/// get a 403/404 for Picker-imported files — the download then fails and the caller
/// falls back to "Open in Drive". A server-seeded preview cache (net-new, not in this
/// change) is what makes in-app Quick Look reliable end-to-end.

enum ReferencePreviewError: Error {
    case notDownloadable          // no driveFileId (e.g. a `.link` reference)
    case requestFailed(Int)       // Drive returned non-2xx (often 403 under drive.file)
}

/// Downloads + caches Drive file bytes for Quick Look. Pure networking/IO — no UI.
enum ReferencePreviewLoader {

    /// `~/Library/Caches/<app>/references`. Created on first use.
    static var cacheDir: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("AtlasReferences", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// An already-downloaded copy for this reference, if one is cached. Files are
    /// named `<driveFileId>.<ext>`, so we match on the base name.
    static func cachedURL(for reference: Reference) -> URL? {
        guard let fid = reference.driveFileId else { return nil }
        let items = (try? FileManager.default.contentsOfDirectory(
            at: cacheDir, includingPropertiesForKeys: nil)) ?? []
        return items.first { $0.deletingPathExtension().lastPathComponent == fid }
    }

    /// Downloads the reference's bytes into the cache and returns the local URL.
    /// Google-native files (Sheets/Slides/Drawings) are exported to PDF for preview;
    /// everything else is fetched raw (`alt=media`). Throws on any non-2xx.
    static func download(_ reference: Reference, auth: GoogleAuthService) async throws -> URL {
        guard let fid = reference.driveFileId else { throw ReferencePreviewError.notDownloadable }
        let token = try await auth.validAccessToken()
        let mime = reference.mimeType ?? ""

        let endpoint: URL
        let ext: String
        if mime.hasPrefix("application/vnd.google-apps.") {
            // Google-native (non-Doc): export a PDF Quick Look can render.
            endpoint = URL(string: "https://www.googleapis.com/drive/v3/files/\(fid)/export?mimeType=application/pdf")!
            ext = "pdf"
        } else {
            endpoint = URL(string: "https://www.googleapis.com/drive/v3/files/\(fid)?alt=media")!
            ext = UTType(mimeType: mime)?.preferredFilenameExtension ?? "bin"
        }

        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw ReferencePreviewError.requestFailed(code) }

        let dest = cacheDir.appendingPathComponent("\(fid).\(ext)")
        try data.write(to: dest, options: .atomic)
        return dest
    }
}

/// Presents a single local file in the shared `QLPreviewPanel`. A retained singleton
/// so the data source outlives the async present. (Setting the panel's data source
/// directly + `reloadData()` is the pragmatic path; the responder-chain control
/// handshake is not wired, which is fine for a one-shot transient preview.)
@MainActor
final class ReferencePreviewController: NSObject, QLPreviewPanelDataSource {
    static let shared = ReferencePreviewController()

    private var url: URL?

    func present(_ url: URL) {
        self.url = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { url == nil ? 0 : 1 }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        url as NSURL?
    }
}
