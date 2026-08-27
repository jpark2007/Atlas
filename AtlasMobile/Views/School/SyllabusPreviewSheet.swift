import SwiftUI
import QuickLook
import AtlasCore

/// The syllabus itself, downloaded from the private `syllabi` bucket and shown with
/// QuickLook — so a PDF and a photographed page both render without Atlas caring which.
struct SyllabusPreviewSheet: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss

    let project: Project

    @State private var file: URL?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if let file {
                    QuickLookView(url: file)
                } else if failed {
                    Text("Atlas couldn't open the stored syllabus. Check your connection, or scan it again.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(MobileTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(28)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    VStack(spacing: 10) {
                        AtlasLoader(size: 24)
                        Text("Opening your syllabus…")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(MobileTheme.muted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(MobileTheme.bg.ignoresSafeArea())
            .navigationTitle("Syllabus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: project.syllabusPath) { await load() }
    }

    private func load() async {
        guard let path = project.syllabusPath else { failed = true; return }
        do {
            file = try await SyllabusStorage.downloadToTemporaryFile(path: path,
                                                                    session: store.session)
        } catch {
            AtlasLog.append("syllabus download failed: \(error)")
            failed = true
        }
    }
}

/// QuickLook, embedded. `QLPreviewController` renders whatever the extension says it is.
private struct QuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController,
                               previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}
