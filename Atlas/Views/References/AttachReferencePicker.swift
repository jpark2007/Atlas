import SwiftUI
import AtlasCore

// MARK: - Reference display helpers (shared across the notes-import UI)

extension Reference {
    /// SF Symbol for the row's type glyph — doc / file (by mimeType) / link.
    var typeGlyph: String {
        switch kind {
        case .docNote: return "doc.richtext"
        case .link:    return "link"
        case .file:
            switch mimeType {
            case let m? where m.contains("pdf"):          return "doc.fill"
            case let m? where m.hasPrefix("image/"):      return "photo"
            case let m? where m.contains("spreadsheet"):  return "tablecells"
            case let m? where m.contains("presentation"): return "rectangle.on.rectangle"
            default:                                       return "doc"
            }
        }
    }

    /// Where "open" sends the user: the link URL, the Google Doc, or the Drive file.
    var externalURL: URL? {
        switch kind {
        case .link:
            return url.flatMap { URL(string: $0) }
        case .docNote:
            return driveFileId.flatMap { URL(string: "https://docs.google.com/document/d/\($0)/edit") }
        case .file:
            return driveFileId.flatMap { URL(string: "https://drive.google.com/file/d/\($0)/view") }
        }
    }
}

// MARK: - Attached-reference row (task / event detail lists, creation sheet)

/// One reference in an item's attached list — glyph + title, taps out to the source,
/// optional remove affordance. Editorial: hairline-separated, no card chrome.
struct ReferenceListRow: View {
    @Environment(\.openURL) private var openURL
    let reference: Reference
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Button { if let u = reference.externalURL { openURL(u) } } label: {
                HStack(spacing: 10) {
                    Image(systemName: reference.typeGlyph)
                        .atlasFont(size: 14)
                        .foregroundStyle(reference.kind == .docNote
                                         ? AtlasTheme.Colors.accentText
                                         : AtlasTheme.Colors.textMuted)
                        .frame(width: 18)
                    Text(reference.title.isEmpty ? "Untitled" : reference.title)
                        .atlasFont(size: 14, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        .lineLimit(1)
                    if reference.externalURL != nil {
                        Image(systemName: "arrow.up.right")
                            .atlasFont(size: 10, weight: .semibold)
                            .foregroundStyle(AtlasTheme.Colors.textMuted)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .atlasFont(size: 14, weight: .medium)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 9)
        .atlasHairlineBelow()
    }
}

// MARK: - Attach reference picker

/// Multi-select over a project's reference pool. Pure selector: it toggles ids in
/// the bound `selection` set and never writes to the DB itself — the host decides
/// when to persist (immediately on a live task/event, or on save for a new event).
struct AttachReferencePicker: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    /// The project whose pool is shown. `nil` when the item has no project yet.
    let projectID: UUID?
    @Binding var selection: Set<UUID>

    private var pool: [Reference] {
        guard let projectID else { return [] }
        return state.references(in: projectID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Attach reference")
                    .atlasFont(size: 19, weight: .bold, design: .rounded)
                    .tracking(-0.3)
                    .foregroundStyle(AtlasTheme.Colors.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Text("Done")
                        .atlasFont(size: 14, weight: .semibold, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: AtlasTheme.Radius.control, style: .continuous)
                                .strokeBorder(AtlasTheme.Colors.textPrimary, lineWidth: AtlasTheme.rule)
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Divider().overlay(AtlasTheme.Colors.border)

            if projectID == nil {
                emptyState("Assign this to a project first — references come from the project's pool.")
            } else if pool.isEmpty {
                emptyState("This project has no references yet. Import from Drive or add a link in the project.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(pool) { ref in row(ref) }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(width: 460)
        .frame(minHeight: 320)
        .background(AtlasTheme.Colors.bgBase)
    }

    private func row(_ ref: Reference) -> some View {
        let selected = selection.contains(ref.id)
        return Button {
            if selected { selection.remove(ref.id) } else { selection.insert(ref.id) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: ref.typeGlyph)
                    .atlasFont(size: 14)
                    .foregroundStyle(ref.kind == .docNote
                                     ? AtlasTheme.Colors.accentText
                                     : AtlasTheme.Colors.textMuted)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ref.title.isEmpty ? "Untitled" : ref.title)
                        .atlasFont(size: 14, weight: .medium, design: .rounded)
                        .foregroundStyle(AtlasTheme.Colors.textPrimary)
                        .lineLimit(1)
                    Text(kindLabel(ref))
                        .atlasFont(size: 12, weight: .medium)
                        .foregroundStyle(AtlasTheme.Colors.textMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .atlasFont(size: 17)
                    .foregroundStyle(selected ? AtlasTheme.Colors.accentText : AtlasTheme.Colors.textMuted)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .atlasHairlineBelow()
        }
        .buttonStyle(.plain)
    }

    private func kindLabel(_ ref: Reference) -> String {
        switch ref.kind {
        case .docNote: return "Google Doc"
        case .file:    return "File"
        case .link:    return "Link"
        }
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .atlasFont(size: 14, weight: .medium, design: .rounded)
            .foregroundStyle(AtlasTheme.Colors.textMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
            .padding(28)
    }
}
