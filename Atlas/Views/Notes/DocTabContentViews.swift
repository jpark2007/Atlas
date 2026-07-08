import SwiftUI
import AppKit
import AtlasCore

/// Display views for the parts of a Google-Doc tab the constrained editor can't
/// represent as plain editable blocks: re-hosted inline images and pipe tables.
/// Both are read-only surfaces — the editor renders them in place of the raw
/// `![image:…]` placeholder / `| … |` lines the pull pipeline emits.

// MARK: - Image cache

/// A tiny process-wide cache of decoded Doc images, keyed by Storage path. Keeps an
/// image from re-downloading each time its row scrolls back into view or the tab is
/// re-selected. `NSCache` evicts under memory pressure on its own.
private enum DocImageCache {
    static let shared = NSCache<NSString, NSImage>()
}

// MARK: - Inline image block

/// Renders one re-hosted inline image from the private `doc-images` bucket. Shows a
/// spinner while the bytes load, the decoded image once ready, and falls back to the
/// literal `![image:…]` placeholder text if the download or decode fails (so the
/// block never silently vanishes).
struct DocImageBlockView: View {
    let image: DocNoteImage
    /// Fetches the object's bytes for a Storage path (wraps `AppState.downloadDocImage`).
    let download: (String) async throws -> Data
    /// The literal placeholder line to show if the image can't be loaded.
    let placeholder: String

    @State private var nsImage: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 360, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: AtlasTheme.Radius.sm, style: .continuous))
            } else if failed {
                Text(placeholder)
                    .font(AtlasTheme.Font.body())
                    .foregroundStyle(AtlasTheme.Colors.textMuted)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            }
        }
        .task(id: image.storagePath) { await load() }
    }

    private func load() async {
        if let cached = DocImageCache.shared.object(forKey: image.storagePath as NSString) {
            nsImage = cached
            return
        }
        do {
            let data = try await download(image.storagePath)
            guard let decoded = NSImage(data: data) else { failed = true; return }
            DocImageCache.shared.setObject(decoded, forKey: image.storagePath as NSString)
            nsImage = decoded
        } catch {
            failed = true
        }
    }
}

// MARK: - Pipe table

/// Renders a run of `| a | b |` pipe lines as a grid: hairline borders, semibold
/// header row, scrolls horizontally when it's wider than the editor. Read-only —
/// tables lock the tab, so this is display-only.
struct PipeTableView: View {
    let rows: [[String]]

    private var columnCount: Int { rows.map(\.count).max() ?? 0 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(0..<columnCount, id: \.self) { col in
                            Text(col < row.count ? row[col] : "")
                                .font(AtlasTheme.Font.body())
                                .fontWeight(rowIndex == 0 ? .semibold : .regular)
                                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .overlay(
                                    Rectangle()
                                        .stroke(AtlasTheme.Colors.border, lineWidth: AtlasTheme.rule)
                                )
                        }
                    }
                }
            }
        }
    }
}

/// Splits `| a | b | c |` pipe lines into cell rows: split on `|`, trim each cell,
/// and drop the empty leading/trailing cells the outer pipes produce. The pull
/// pipeline never emits a Markdown separator row (`|---|---|`), so none is stripped.
func parsePipeTable(lines: [String]) -> [[String]] {
    lines.map { line in
        var cells = line
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if cells.first == "" { cells.removeFirst() }
        if cells.last == "" { cells.removeLast() }
        return cells
    }
}
