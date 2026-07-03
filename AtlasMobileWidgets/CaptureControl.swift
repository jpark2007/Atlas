import WidgetKit
import SwiftUI
import AppIntents

/// Control Center / Action Button capture control (iOS 18+): a refined mic glyph +
/// "Capture" that opens the app to `atlas://capture`. Guarded so the extension still
/// builds/runs on iOS 17.
@available(iOS 18.0, *)
struct CaptureControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "AtlasCapture") {
            ControlWidgetButton(action: OpenCaptureIntent()) {
                Label("Capture", systemImage: "mic")
            }
        }
        .displayName("Capture")
        .description("Dump a thought into Atlas.")
    }
}

@available(iOS 18.0, *)
struct OpenCaptureIntent: AppIntent {
    static var title: LocalizedStringResource { "Capture" }
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "atlas://capture")!))
    }
}
