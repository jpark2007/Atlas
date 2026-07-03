import SwiftUI
import WebKit
import AtlasCore

// MARK: - Config

/// Public Google Picker browser credentials — the Picker API key and the GCP
/// project number. Fed from the gitignored `Config/Secrets.xcconfig` into the
/// generated Info.plist (see project.yml), same wiring as `GoogleOAuthConfig`.
/// Both are browser keys, public by design — not secrets.
enum DrivePickerConfig {
    static var apiKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "DrivePickerAPIKey") as? String) ?? ""
    }
    static var appID: String {
        (Bundle.main.object(forInfoDictionaryKey: "DrivePickerAppID") as? String) ?? ""
    }
    /// True once both keys are present (Secrets.xcconfig wired). Gates the sheet.
    static var isConfigured: Bool { !apiKey.isEmpty && !appID.isEmpty }
}

/// Everything the bundled picker page needs at present-time. `Identifiable` so
/// `.sheet(item:)` rebuilds the webview per import — fresh tokens every run.
struct DrivePickerSession: Identifiable {
    let id = UUID()
    let googleAccessToken: String
    let supabaseJWT: String
}

// MARK: - Sheet

/// In-app Google Drive picker — replaces the old browser-tab flow (Supabase's
/// gateway rewrites the hosted page's Content-Type to text/plain on *.supabase.co,
/// and the picker should feel in-app anyway). Loads the bundled `DrivePicker.html`
/// in a WKWebView; the app's own `drive.file` access token + Supabase JWT +
/// projectId are injected via a WKUserScript, so no Google sign-in ever happens
/// inside the webview (Google blocks OAuth consent in embedded webviews — the
/// Picker itself is fine). The page POSTs picked files to the drive-import edge
/// function (contract unchanged) and reports done/cancel through the "atlas"
/// message handler; the sheet dismisses and `ProjectDetailView` re-pulls the
/// reference pool onDismiss.
struct DrivePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let projectID: UUID
    let session: DrivePickerSession

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().overlay(AtlasTheme.Colors.hairline)
            DrivePickerWebView(projectID: projectID, session: session) { event in
                switch event {
                case .done:
                    // Give the page's "Imported N" line a beat before closing.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { dismiss() }
                case .cancel:
                    dismiss()
                }
            }
        }
        .frame(width: 720, height: 560)
        .background(AtlasTheme.Colors.bgBase)
    }

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Import from Drive")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}

// MARK: - WebView

private struct DrivePickerWebView: NSViewRepresentable {
    enum Event { case done, cancel }

    let projectID: UUID
    let session: DrivePickerSession
    let onEvent: (Event) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onEvent: onEvent) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "atlas")
        // Inject the page's config before its own script runs (documentStart).
        if let script = configScript() {
            controller.addUserScript(WKUserScript(source: script,
                                                  injectionTime: .atDocumentStart,
                                                  forMainFrameOnly: true))
        }
        configuration.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = context.coordinator
        // Safari-like UA — mitigation against Google UA-sniffing embedded webviews.
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

        // https baseURL: the Picker iframe validates the embedding origin —
        // file:/about: origins can be rejected. The Supabase host is where the
        // page used to be served from and where the POST goes.
        if let url = Bundle.main.url(forResource: "DrivePicker", withExtension: "html"),
           let html = try? String(contentsOf: url, encoding: .utf8) {
            webView.loadHTMLString(html, baseURL: SupabaseConfig.url)
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        // WKUserContentController retains its handlers — break the cycle on teardown.
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "atlas")
    }

    /// `window.ATLAS_CONFIG = {…}` consumed by DrivePicker.html. JSON-encoded so
    /// every value is safely escaped.
    private func configScript() -> String? {
        let config: [String: String] = [
            "apiKey": DrivePickerConfig.apiKey,
            "appId": DrivePickerConfig.appID,
            "accessToken": session.googleAccessToken,
            "supabaseJwt": session.supabaseJWT,
            "projectId": projectID.uuidString,
            "postUrl": SupabaseConfig.functionsBase.appendingPathComponent("drive-import").absoluteString,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: config),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return "window.ATLAS_CONFIG = \(json);"
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKUIDelegate {
        let onEvent: (Event) -> Void

        init(onEvent: @escaping (Event) -> Void) {
            self.onEvent = onEvent
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "atlas",
                  let body = message.body as? [String: Any],
                  let event = body["event"] as? String else { return }
            switch event {
            case "done":   onEvent(.done)
            case "cancel": onEvent(.cancel)
            default:       break
            }
        }

        /// The Picker occasionally targets a new window; load it in the same
        /// webview instead of dropping it (we never spawn real popups).
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}
