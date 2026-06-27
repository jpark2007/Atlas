import SwiftUI

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
            // Hidden ⌘⇧K shortcut in a background layer so it never
            // affects layout or steals visual focus.
            .background(shortcutInstaller)
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
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var auth: AuthService

    @Binding var isPresented: Bool
    let atlasAI: AtlasAI

    @State private var text: String = ""
    @FocusState private var fieldFocused: Bool
    @State private var confirmation: String? = nil
    @State private var isProcessing: Bool = false

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
        .onExitCommand { dismiss() }
        .background(
            Button("", action: dismiss)
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .accessibilityHidden(true)
        )
        .onAppear {
            DispatchQueue.main.async { fieldFocused = true }
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
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AtlasTheme.Colors.accent)
            }

            TextField("Capture anything — a task, a thought…", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(AtlasTheme.Colors.textPrimary)
                .tint(AtlasTheme.Colors.accent)
                .focused($fieldFocused)
                .disabled(isProcessing)
                .onSubmit(submit)

            // Show inline confirmation OR the default hint.
            if let msg = confirmation {
                Text(msg)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AtlasTheme.Colors.accent)
                    .fixedSize()
                    .transition(.opacity)
            } else {
                hint
            }
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
        .animation(.easeInOut(duration: 0.2), value: confirmation)
    }

    private var glassBackground: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
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
                await showConfirmation("✓ Saved as task")
                return
            }

            // Try the AI edge function.
            do {
                let result = try await atlasAI.parse(rawText)
                switch result.kind {
                case "event":
                    await handleEvent(result: result, rawText: rawText)
                case "note":
                    state.addNote(
                        title: result.title,
                        body: result.notes ?? "",
                        spaceName: result.spaceName,
                        isExternal: false
                    )
                    await showConfirmation("✓ Added note")
                case "task":
                    state.addTask(title: result.title)
                    await showConfirmation("✓ Added task")
                default:
                    // Unrecognized kind — safe fallback.
                    state.addTask(title: rawText)
                    await showConfirmation("✓ Saved as task")
                }
            } catch {
                // ANY error (network, 404 — function not deployed, parse failure):
                // always fall through to a plain task so capture never breaks.
                state.addTask(title: rawText)
                await showConfirmation("✓ Saved as task")
            }
        }
    }

    /// Build a CalendarEvent from the AI result. Falls back to a plain task if
    /// `startISO` is missing or unparseable (the only required field for an event).
    @MainActor
    private func handleEvent(result: CaptureResult, rawText: String) async {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Try with fractional seconds first, then without.
        var start: Date? = result.startISO.flatMap { formatter.date(from: $0) }
        if start == nil {
            formatter.formatOptions = [.withInternetDateTime]
            start = result.startISO.flatMap { formatter.date(from: $0) }
        }

        guard let eventStart = start else {
            // Can't place this on the calendar without a time — save as task.
            state.addTask(title: rawText)
            await showConfirmation("✓ Saved as task")
            return
        }

        let durationSeconds = Double(result.durationMin ?? 60) * 60
        let eventEnd = eventStart.addingTimeInterval(durationSeconds)
        let color = state.calendarSpaceColor(named: result.spaceName)

        let event = CalendarEvent(
            title: result.title,
            subtitle: "",
            start: eventStart,
            end: eventEnd,
            color: color,
            spaceName: result.spaceName
        )
        state.addEvent(event)
        await showConfirmation("✓ Added event")
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
        fieldFocused = false
        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            isPresented = false
        }
    }
}
