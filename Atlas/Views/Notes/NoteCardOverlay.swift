import SwiftUI
import AtlasCore

/// Gmail-compose-style floating editor card, docked to the host view's
/// bottom-trailing corner so the project stays visible behind it. Drag the
/// header's diagonal grip to resize (size persists across opens), ⤢ toggles
/// near-fullscreen. The card owns the chrome; the embedded `NoteEditorView`
/// runs chromeless and closes the card through `onDismiss`.
struct NoteCardOverlay: View {
    let note: Note
    let onClose: () -> Void

    @AppStorage("notes.card.width")  private var storedWidth  = 560.0
    @AppStorage("notes.card.height") private var storedHeight = 580.0
    @State private var isExpanded = false
    /// Size at drag start — deltas apply to this, not the live value, so the
    /// resize doesn't compound per frame.
    @State private var dragStartSize: CGSize?

    private let margin: CGFloat = 16
    private let minSize = CGSize(width: 480, height: 420)

    var body: some View {
        GeometryReader { geo in
            let maxW = max(geo.size.width  - margin * 2, minSize.width)
            let maxH = max(geo.size.height - margin * 2, minSize.height)
            let width  = isExpanded ? maxW : min(max(storedWidth,  minSize.width),  maxW)
            let height = isExpanded ? maxH : min(max(storedHeight, minSize.height), maxH)

            VStack(spacing: 0) {
                header
                Divider().overlay(AtlasTheme.Colors.border)
                NoteEditorView(note: note, chromeless: true, onDismiss: onClose)
                    .id(note.id)   // fresh editor state when a different note opens
            }
            .frame(width: width, height: height)
            .background(AtlasTheme.Colors.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: AtlasTheme.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AtlasTheme.Radius.lg, style: .continuous)
                    .stroke(AtlasTheme.Colors.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.16), radius: 26, x: 0, y: 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(margin)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if !isExpanded { resizeGrip }
            Text("NOTE")
                .atlasMono(size: 10, weight: .bold)
                .tracking(1.2)
                .foregroundStyle(AtlasTheme.Colors.textMuted)
            Spacer()
            headerButton(isExpanded
                         ? "arrow.down.right.and.arrow.up.left"
                         : "arrow.up.left.and.arrow.down.right") {
                isExpanded.toggle()
            }
            .help(isExpanded ? "Restore size" : "Expand")
            headerButton("xmark") { onClose() }
                .help("Close")
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func headerButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Diagonal grip: the card is anchored bottom-trailing, so dragging toward
    /// the window's top-left (negative translation) grows it.
    private var resizeGrip: some View {
        Image(systemName: "line.diagonal")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AtlasTheme.Colors.textMuted)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .help("Drag to resize")
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartSize == nil {
                            dragStartSize = CGSize(width: storedWidth, height: storedHeight)
                        }
                        guard let start = dragStartSize else { return }
                        storedWidth  = max(minSize.width,  start.width  - value.translation.width)
                        storedHeight = max(minSize.height, start.height - value.translation.height)
                    }
                    .onEnded { _ in dragStartSize = nil }
            )
    }
}
