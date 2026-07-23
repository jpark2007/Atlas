import SwiftUI
import AtlasCore
import TipKit

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
//   • Installs a hidden keyboard shortcut (⌥Space) that flips `state.presentCapture = true`.
//   • Overlays a centered-near-top command bar whenever `state.presentCapture == true`.
//   • Dismisses on Esc and on click-outside.
//   • On Return: calls the AI edge function to auto-sort the text into the right Space.
//     Falls back to a plain task on ANY error (offline, 404, timeout, bad JSON, etc.)
//     so ⌥Space ALWAYS works even when the edge function is not yet deployed.

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
            // ⌥Space is owned by the global Carbon hotkey → floating CapturePanelController,
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
    @State private var errorMessage: String? = nil
    // The text we restored alongside an error, so a programmatic restore doesn't
    // trip the "clear on edit" onChange — only a real keystroke (text ≠ anchor) does.
    @State private var errorAnchor: String = ""
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

            // When adding from a project page, show which project it lands in.
            if let ctx = state.captureContext {
                atlasTag(text: ctx.projectName, color: AtlasTheme.Colors.accentText)
            }

            TextField(state.captureContext == nil
                      ? "Capture anything — a task, a thought…"
                      : "Add a task…", text: $text)
                .textFieldStyle(.plain)
                .atlasFont(size: 19, weight: .regular, design: .rounded)
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .tint(AtlasTheme.Colors.accent)
                .focused($fieldFocused)
                .disabled(isProcessing)
                .onSubmit(submit)
                // A real keystroke (text ≠ the restored anchor) clears a lingering
                // error label; the programmatic restore in showError doesn't.
                .onChange(of: text) { _, newValue in
                    if errorMessage != nil, newValue != errorAnchor {
                        withAnimation { errorMessage = nil }
                    }
                }

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
        .animation(.easeInOut(duration: 0.2), value: errorMessage)
    }

    private var glassBackground: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(AtlasTheme.Colors.bgBase)
    }

    // MARK: - Trailing status + mic

    @ViewBuilder
    private var trailingStatus: some View {
        if let err = errorMessage {
            statusLabel(err, color: AtlasTheme.Colors.danger)
        } else if let msg = confirmation {
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
        errorMessage = nil
        isProcessing = true

        // From a project's "Add Task": force-tag the task to that project/space and
        // skip AI routing entirely, so it always lands where the user asked.
        if let ctx = state.captureContext {
            state.addTask(title: rawText,
                          spaceName: ctx.spaceName,
                          projectName: ctx.projectName)
            Task { @MainActor in
                defer { isProcessing = false }
                await showConfirmation(CaptureOutcome.task(hasDate: false).confirmation)
            }
            return
        }

        Task { @MainActor in
            defer { isProcessing = false }

            // Oversized paste (> server cap): skip the AI round-trip entirely —
            // the function would 413 — and tell the user, restoring their text so
            // nothing is lost. Same message as a server 413 below.
            guard rawText.count <= 20_000 else {
                showError(Self.tooLongMessage, restoring: rawText)
                return
            }

            // Offline or no session → plain-task fallback, no network call.
            guard auth.session != nil else {
                fallbackTask(rawText)
                await showConfirmation(CaptureOutcome.degraded.confirmation)
                return
            }

            // Try the AI edge function. It returns an ARRAY — a multi-item
            // paragraph splits into several captures, each routed individually.
            do {
                let response = try await atlasAI.parse(
                    rawText,
                    spaces: AtlasAI.context(from: state.spaces)
                )
                let results = response.results
                guard !results.isEmpty else {
                    // Parsed OK but nothing actionable — never lose the text.
                    fallbackTask(rawText)
                    await showConfirmation(CaptureOutcome.degraded.confirmation)
                    return
                }
                let outcomes = results.map { state.applyCapture($0) }
                if response.truncated {
                    // Server capped the paste at 50 — the items were still added.
                    await showConfirmation(Self.truncatedMessage, duration: 3)
                } else {
                    await showConfirmation(CaptureOutcome.confirmation(for: outcomes))
                }
            } catch AtlasAIError.tooLong {
                // Server rejected the size (413) — surface it, keep the text.
                showError(Self.tooLongMessage, restoring: rawText)
            } catch AtlasAIError.serverUnavailable, AtlasAIError.rateLimited {
                // Server down / busy (5xx / 429) — surface it, keep the text.
                showError(Self.serverDownMessage, restoring: rawText)
            } catch {
                // ANY other error (offline, 404 — function not deployed, parse
                // failure): fall through to a fallback task so capture never breaks.
                fallbackTask(rawText)
                await showConfirmation(CaptureOutcome.degraded.confirmation)
            }
        }
    }

    /// The never-lose-text fallback. A long or multi-line paste keeps its FULL
    /// text in the task's notes and uses its first non-empty line (≤ 80 chars) as
    /// a clean title; short single-line text stays the title verbatim (as before).
    private func fallbackTask(_ rawText: String) {
        let isLong = rawText.contains("\n") || rawText.count > 120
        guard isLong else {
            state.addTask(title: rawText)
            return
        }
        let firstLine = rawText
            .split(separator: "\n")
            .map(String.init)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }?
            .trimmingCharacters(in: .whitespaces) ?? rawText
        let title = firstLine.count > 80
            ? String(firstLine.prefix(80)) + "…"
            : firstLine
        state.addTask(title: title, notes: rawText)
    }

    // The two user-facing failure strings (kept verbatim, shared with iOS).
    static let tooLongMessage = "Sorry — that message is too long to sort"
    static let serverDownMessage = "Servers are down — please try again later"
    // Rare: the server's defensive item bound trimmed an enormous paste. Most items
    // WERE added; suggest splitting the remainder. (Normal long pastes fan out and
    // are not capped.)
    static let truncatedMessage = "That was a lot — some items may not have been added. Try splitting it up"

    /// Surface a failure inline WITHOUT committing anything: stop the spinner,
    /// restore the user's text into the field, and show `message` in danger color.
    /// The message auto-clears on the next edit or submit (see `errorMessage`
    /// reset in `submit` and the field's `onChange`). No task is created.
    @MainActor
    private func showError(_ message: String, restoring rawText: String) {
        isProcessing = false
        errorAnchor = rawText
        text = rawText
        withAnimation { errorMessage = message }
        fieldFocused = true
    }

    /// Displays `message` for `duration` seconds (default 1) then dismisses the
    /// capture bar. The longer window is for the truncation notice, which the user
    /// needs a moment to read.
    @MainActor
    private func showConfirmation(_ message: String, duration: TimeInterval = 1) async {
        // Every path that reaches here has committed at least one item — donate once.
        Task { await AtlasTipEvents.captured.donate() }
        withAnimation { confirmation = message }
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        withAnimation { confirmation = nil }
        dismiss()
    }

    private func dismiss() {
        speech.stop()
        fieldFocused = false
        state.captureContext = nil
        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            isPresented = false
        }
    }
}
