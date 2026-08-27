import SwiftUI
import Quartz
import AtlasCore

/// The syllabus itself, downloaded from the private `syllabi` bucket and shown with
/// QuickLook — so a PDF and a photographed page both render without Atlas caring which.
struct SyllabusPreviewSheet: View {
    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss

    let project: Project

    @State private var file: URL?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(AtlasTheme.Colors.hairline)
            Group {
                if let file {
                    QuickLookView(url: file)
                } else if failed {
                    message("Atlas couldn't open the stored syllabus. Check your connection, or scan it again.")
                } else {
                    VStack(spacing: 10) {
                        AtlasLoader(size: 24)
                        Text("Opening your syllabus…")
                            .atlasFont(size: 13, weight: .medium, design: .rounded)
                            .foregroundStyle(AtlasTheme.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(width: 760, height: 720, alignment: .topLeading)
        .background(AtlasTheme.Colors.bgBase)
        .task(id: project.syllabusPath) { await load() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(project.name) syllabus")
                    .atlasFont(size: 18, weight: .semibold, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                Text("The file this class's scan was read from.")
                    .atlasFont(size: 12, weight: .medium, design: .rounded)
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            }
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.plain)
                .atlasFont(size: 14, weight: .semibold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 18)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .atlasFont(size: 13, weight: .medium, design: .rounded)
            .foregroundStyle(AtlasTheme.Colors.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func load() async {
        guard let path = project.syllabusPath else { failed = true; return }
        do {
            file = try await SyllabusStorage.downloadToTemporaryFile(path: path,
                                                                    session: auth.session)
        } catch {
            AtlasLog.append("syllabus download failed: \(error)")
            failed = true
        }
    }
}

/// QuickLook, embedded. `QLPreviewView` renders whatever the extension says it is.
private struct QuickLookView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = true
        view.previewItem = url as QLPreviewItem
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? URL) != url { view.previewItem = url as QLPreviewItem }
    }
}
