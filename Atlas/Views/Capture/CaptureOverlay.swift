import SwiftUI

// MARK: - Public entry point
//
// Quick-capture command bar — a floating, liquid-glass NL task input.
//
// Wiring (Stage 2): attach ONE modifier to RootView's root view:
//
//     RootView()
//         .atlasCaptureOverlay()
//
// The modifier:
//   • Installs a hidden keyboard shortcut (⌘⇧K) that flips `state.presentCapture = true`.
//   • Overlays a centered-near-top command bar whenever `state.presentCapture == true`.
//   • Dismisses on Esc and on click-outside; Enter files the task via `state.addTask(title:)`.
//
// AppState is read from the environment, so callers wire it in one line.

extension View {
    /// Overlays the Atlas quick-capture command bar and installs its keyboard shortcut.
    /// Reads `AppState` from `@EnvironmentObject`, so it must be applied inside a view
    /// hierarchy that already injects `AppState`.
    func atlasCaptureOverlay() -> some View {
        modifier(AtlasCaptureOverlayModifier())
    }
}

// MARK: - The modifier (self-contained wiring)

struct AtlasCaptureOverlayModifier: ViewModifier {
    @EnvironmentObject private var state: AppState

    func body(content: Content) -> some View {
        content
            // Hidden ⌘⇧K shortcut. Lives in a background layer so it never
            // affects layout or steals visual focus.
            .background(shortcutInstaller)
            .overlay(alignment: .top) {
                if state.presentCapture {
                    CaptureCommandBar(
                        isPresented: presentationBinding,
                        onSubmit: { title in
                            _ = state.addTask(title: title)
                        }
                    )
                    .transition(.opacity)
                    .zIndex(1_000)
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: state.presentCapture)
    }

    /// Bridges the (possibly computed) `presentCapture` to a `Binding` the bar can mutate.
    private var presentationBinding: Binding<Bool> {
        Binding(
            get: { state.presentCapture },
            set: { state.presentCapture = $0 }
        )
    }

    private var shortcutInstaller: some View {
        Button("Quick capture") {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                state.presentCapture = true
            }
        }
        .keyboardShortcut("k", modifiers: [.command, .shift])
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

// MARK: - The command bar

struct CaptureCommandBar: View {
    @Binding var isPresented: Bool
    var onSubmit: (String) -> Void

    @State private var text: String = ""
    @FocusState private var fieldFocused: Bool

    private let barWidth: CGFloat = 560
    private let corner: CGFloat = 18

    var body: some View {
        ZStack(alignment: .top) {
            // Click-outside catcher + subtle scrim for focus.
            Color.black.opacity(0.16)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            bar
                .frame(width: barWidth)
                .padding(.top, 96)
        }
        // Esc dismisses — `.onExitCommand` plus a hidden cancelAction button so
        // Escape still fires while the TextField holds first responder on macOS.
        .onExitCommand { dismiss() }
        .background(
            Button("", action: dismiss)
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .accessibilityHidden(true)
        )
        .onAppear {
            // Focus on the next runloop tick so the field is in the hierarchy.
            DispatchQueue.main.async { fieldFocused = true }
        }
    }

    private var bar: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AtlasTheme.Colors.accent)

            TextField("Capture anything — a task, a thought…", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .tint(AtlasTheme.Colors.accent)
                .focused($fieldFocused)
                .onSubmit(submit)

            hint
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(glassBackground)
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 30, x: 0, y: 18)
        .shadow(color: .black.opacity(0.22), radius: 6, x: 0, y: 2)
    }

    private var glassBackground: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                // Warm tint so the glass reads as Atlas, not stock macOS.
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(AtlasTheme.Colors.bgElevated.opacity(0.45))
            )
    }

    private var hint: some View {
        HStack(spacing: 8) {
            Text("Atlas files it for you")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AtlasTheme.Colors.textMuted)

            Text("\u{21A9}") // ↩ return glyph
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AtlasTheme.Colors.textSecondary)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
        .fixedSize()
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed)
        text = ""
        dismiss()
    }

    private func dismiss() {
        fieldFocused = false
        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            isPresented = false
        }
    }
}
