import SwiftUI
import UniformTypeIdentifiers
import AtlasCore

/// One editorial row in a project's References section. Type glyph → title +
/// source/sync line → a `Doc ↗` badge for linked Docs → an ellipsis menu. The whole
/// leading area is the primary tap (`onTap`); the menu carries the explicit actions.
/// Visuals only — the parent owns the navigation/open/preview/remove behavior.
struct ReferenceRowView: View {
    let reference: Reference
    /// The menu's "open outside Atlas" label, decided by the parent:
    /// "Open in Google Docs" / "Open in Drive" / "Open link".
    let externalActionTitle: String
    var onTap: () -> Void
    var onOpenExternal: () -> Void
    var onQuickLook: (() -> Void)?      // `.file` only
    var onEditNote: (() -> Void)?       // `.docNote` only — opens the linked note in Atlas
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onTap) { content }
                .buttonStyle(.plain)
            // A linked Doc's primary row click edits it in Atlas (`onTap`); this small
            // trailing badge is the demoted secondary "open in Google Docs" action.
            if reference.kind == .docNote {
                Button(action: onOpenExternal) {
                    Text("Doc ↗")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.accentText)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(externalActionTitle)
            }
            menu
        }
        .padding(.vertical, 9)
    }

    private var content: some View {
        HStack(spacing: 12) {
            Image(systemName: glyph)
                .font(.system(size: 14))
                .foregroundStyle(reference.kind == .docNote
                                 ? AtlasTheme.Colors.accentText
                                 : AtlasTheme.Colors.textMuted)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(reference.title.isEmpty ? "Untitled" : reference.title)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(sourceLabel)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                        .lineLimit(1)
                    if reference.kind != .link { syncChip }
                }
            }

            Spacer(minLength: 8)
        }
        .contentShape(Rectangle())
    }

    private var menu: some View {
        Menu {
            if let onEditNote {
                Button { onEditNote() } label: { Label("Edit in Atlas", systemImage: "square.and.pencil") }
            }
            if let onQuickLook {
                Button { onQuickLook() } label: { Label("Quick Look", systemImage: "eye") }
            }
            Button { onOpenExternal() } label: {
                Label(externalActionTitle, systemImage: "arrow.up.right.square")
            }
            Divider()
            Button(role: .destructive) { onRemove() } label: {
                Label("Remove", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13))
                .foregroundStyle(AtlasTheme.Colors.textMuted)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Derived presentation

    private var glyph: String {
        switch reference.kind {
        case .link:    return "link"
        case .docNote: return "doc.text"
        case .file:
            let mime = reference.mimeType ?? ""
            if mime.contains("pdf")                                   { return "doc.richtext" }
            if mime.hasPrefix("image/")                              { return "photo" }
            if mime.hasPrefix("video/")                              { return "play.rectangle" }
            if mime.hasPrefix("audio/")                              { return "waveform" }
            if mime.contains("spreadsheet") || mime.contains("sheet") { return "tablecells" }
            if mime.contains("presentation") || mime.contains("slide") { return "rectangle.on.rectangle" }
            if mime.contains("folder")                               { return "folder" }
            return "doc"
        }
    }

    private var sourceLabel: String {
        switch reference.kind {
        case .link:
            if let raw = reference.url, let host = URL(string: raw)?.host { return host }
            return reference.url ?? "Link"
        case .docNote:
            return "Google Doc"
        case .file:
            if let mime = reference.mimeType,
               let desc = UTType(mimeType: mime)?.localizedDescription {
                return "\(desc) · Drive"
            }
            return "Drive file"
        }
    }

    private var syncChip: some View {
        atlasTag(text: syncLabel, color: syncColor)
    }

    private var syncLabel: String {
        switch reference.syncState {
        case .pending: return "Pending"
        case .synced:  return "Synced"
        case .stale:   return "Changed in Drive"
        case .error:   return "Sync error"
        }
    }

    private var syncColor: Color {
        switch reference.syncState {
        case .pending: return AtlasTheme.Colors.textMuted
        case .synced:  return AtlasTheme.Colors.green
        case .stale:   return AtlasTheme.Colors.warning
        case .error:   return AtlasTheme.Colors.danger
        }
    }
}
