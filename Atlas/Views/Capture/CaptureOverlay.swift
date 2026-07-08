import SwiftUI
import AtlasCore

// MARK: - Public entry point
//
// Quick-capture command bar — a floating, liquid-glass NL task input.
//
// Wiring: attach ONE modifier to RootView's root view:
//
//     RootView()
//         .atlasCaptureOverlay()
//
// The modifier:
//   • Installs a hidden keyboard shortcut (⌘⇧K) that flips `state.presentCapture = true`.
//   • Overlays a centered-near-top command bar whenever `state.presentCapture == true`.
//   • Dismisses on Esc and on click-outside.
//   • On Return: calls the AI edge function to auto-sort the text into the right Space.
//     Falls back to a plain task on ANY error (offline, 404, timeout, bad JSON, etc.)
//     so ⌘⇧K ALWAYS works even when the edge function is not yet deployed.

extension View {
    /// Overlays the Atlas quick-capture command bar and installs its keyboard shortcut.
    /// Reads `AppState` and `AuthService` from `@EnvironmentObject`, so it must be
    /// applied inside a view hierarchy that already injects both.
    func atlasCaptureOverlay() -> some View {
        modifier(AtlasCaptureOverlayModifier())
    }
}

// MARK: - The modifier

struct AtlasCaptureOverlayModifier: ViewModifier {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var auth: AuthService

    func body(content: Content) -> some View {
        content
            // ⌘⇧K is owned by the global Carbon hotkey → floating CapturePanelController,
            // so there's no in-app keyboard shortcut here (it would double-fire when Atlas
            // is focused). This overlay still renders for the menu-bar "Quick Capture".
            .overlay(alignment: .top) {
                if state.presentCapture {
                    CaptureCommandBar(
                        isPresented: presentationBinding,
                        atlasAI: AtlasAI(session: { auth.session })
                    )
                    .transition(.opacity)
                    .zIndex(1_000)
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: state.presentCapture)
    }

    private var presentationBinding: Binding<Bool> {
        Binding(
            get: { state.presentCapture },
            set: { state.presentCapture = $0 }
        )
    }
}

// MARK: - The command bar

struct CaptureCommandBar: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var auth: AuthService

    @Binding var isPresented: Bool
    let atlasAI: AtlasAI
    /// When hosted in the floating NSPanel, drop the full-bleed scrim + top offset —
    /// the panel itself is the surface and handles click-outside / Esc dismissal.
    var inPanel: Bool = false

    @State private var text: String = ""
    @FocusState private var fieldFocused: Bool
    @State private var confirmation: String? = nil
    @State private var isProcessing: Bool = false

    // Click-to-talk dictation. NEVER listens on open — only when the mic button
    // is tapped. The live transcript streams into `text`.
    @StateObject private var speech = SpeechCaptureService()
    @State private var dotPulse = false

    private let barWidth: CGFloat = 560
    private let corner: CGFloat = 18

    var body: some View {
        Group {
            if inPanel {
                // Hosted in the floating panel — just the bar; the panel handles
                // click-outside + Esc dismissal (CapturePanelController). The padding gives
                // the bar's drop shadow room so it renders soft instead of clipped.
                bar.frame(width: barWidth).padding(18)
            } else {
                ZStack(alignment: .top) {
                    // Click-outside catcher + subtle scrim for focus.
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { dismiss() }

                    bar
                        .frame(width: barWidth)
                        .padding(.top, 96)
                }
                .onExitCommand { dismiss() }
                .background(
                    Button("", action: dismiss)
                        .keyboardShortcut(.cancelAction)
                        .opacity(0)
                        .accessibilityHidden(true)
                )
            }
        }
        .onAppear {
            DispatchQueue.main.async { fieldFocused = true }
        }
        // When dictation stops, re-focus the text field so the user can press
        // Return to submit without having to click first.
        .onChange(of: speech.isListening) { _, isListening in
            if !isListening {
                DispatchQueue.main.async { fieldFocused = true }
            }
        }
    }

    // MARK: - Bar layout

    private var bar: some View {
        HStack(spacing: 14) {
            // Spinner while AI is thinking, sparkle otherwise.
            if isProcessing {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(AtlasTheme.Colors.accent)
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "sparkles")
                    .atlasFont(size: 18, weight: .semibold)
                    .foregroundStyle(AtlasTheme.Colors.accent)
            }

            TextField("Capture anything — a task, a thought…", text: $text)
                .textFieldStyle(.plain)
                .atlasFont(size: 19, weight: .regular, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .tint(AtlasTheme.Colors.accent)
                .focused($fieldFocused)
                .disabled(isProcessing)
                .onSubmit(submit)

            // Inline status: confirmation > live dictation > permission note > hint.
            trailingStatus

            // Mic button in the trailing corner of the bar — click to talk.
            micButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(glassBackground)
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(AtlasTheme.Colors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 22, x: 0, y: 10)
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
        .animation(.easeInOut(duration: 0.2), value: confirmation)
    }

    private var glassBackground: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(AtlasTheme.Colors.bgBase)
    }

    // MARK: - Trailing status + mic

    @ViewBuilder
    private var trailingStatus: some View {
        if let msg = confirmation {
            Text(msg)
                .atlasFont(size: 13, weight: .semibold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.accentText)
                .fixedSize()
                .transition(.opacity)
        } else if speech.isListening {
            listeningLabel
        } else if speech.state == .denied {
            statusLabel("Enable mic & speech in Settings", color: AtlasTheme.Colors.danger)
        } else if speech.state == .unavailable {
            statusLabel("Dictation unavailable", color: AtlasTheme.Colors.textMuted)
        } else {
            hint
        }
    }

    private var listeningLabel: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(AtlasTheme.Colors.accent)          // live dot = brand accent (graphics)
                .frame(width: 8, height: 8)
                .opacity(dotPulse ? 1 : 0.3)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: dotPulse)
            Text("Listening…")
                .atlasFont(size: 12, weight: .semibold, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.accentText)
        }
        .fixedSize()
        .onAppear { dotPulse = true }
        .onDisappear { dotPulse = false }
    }

    private func statusLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .atlasFont(size: 12, weight: .medium, design: .rounded)
            .foregroundStyle(color)
            .fixedSize()
            .transition(.opacity)
    }

    private var micButton: some View {
        Button(action: toggleVoice) {
            ZStack {
                Image(systemName: speech.isListening ? "stop.fill" : "mic.fill")
                    .atlasFont(size: 14, weight: .semibold)
                    .foregroundStyle(speech.isListening
                                     ? AtlasTheme.Colors.accent
                                     : AtlasTheme.Colors.textPrimary)
            }
            .frame(width: 32, height: 32)
            .overlay(
                Circle().strokeBorder(
                    speech.isListening
                        ? AtlasTheme.Colors.accent
                        : AtlasTheme.Colors.textPrimary,
                    lineWidth: AtlasTheme.rule)
            )
        }
        .buttonStyle(.plain)
        .help(speech.isListening ? "Stop dictation" : "Click to talk")
        .disabled(isProcessing)
    }

    private func toggleVoice() {
        speech.toggle(currentText: text) { merged in
            text = merged
        }
    }

    private var hint: some View {
        HStack(spacing: 8) {
            Text("Atlas files it for you")
                .atlasFont(size: 12, weight: .medium, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textMuted)

            Text("\u{21A9}") // ↩ return glyph
                .atlasMono(size: 12, weight: .semibold)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(AtlasTheme.Colors.bgDeep)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(AtlasTheme.Colors.border, lineWidth: 1)
                )
        }
        .fixedSize()
    }

    // MARK: - Submit logic

    private func submit() {
        let rawText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty, !isProcessing else { return }

        // Clear the field immediately so the bar feels responsive.
        text = ""
        isProcessing = true

        Task { @MainActor in
            defer { isProcessing = false }

            // Offline or no session → plain-task fallback, no network call.
            guard auth.session != nil else {
                state.addTask(title: rawText)
                await showConfirmation(CaptureOutcome.degraded.confirmation)
                return
            }

            // Try the AI edge function. It returns an ARRAY — a multi-item
            // paragraph splits into several captures, each routed individually.
            do {
                let results = try await atlasAI.parse(
                    rawText,
                    spaces: AtlasAI.context(from: state.spaces)
                )
                guard !results.isEmpty else {
                    // Parsed OK but nothing actionable — never lose the text.
                    state.addTask(title: rawText)
                    await showConfirmation(CaptureOutcome.degraded.confirmation)
                    return
                }
                let outcomes = results.map { state.applyCapture($0) }
                await showConfirmation(CaptureOutcome.confirmation(for: outcomes))
            } catch {
                // ANY error (network, 404 — function not deployed, parse failure):
                // always fall through to a plain task so capture never breaks.
                state.addTask(title: rawText)
                await showConfirmation(CaptureOutcome.degraded.confirmation)
            }
        }
    }

    /// Displays `message` for ~1 second then dismisses the capture bar.
    @MainActor
    private func showConfirmation(_ message: String) async {
        withAnimation { confirmation = message }
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 s
        withAnimation { confirmation = nil }
        dismiss()
    }

    private func dismiss() {
        speech.stop()
        fieldFocused = false
        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            isPresented = false
        }
    }
}
