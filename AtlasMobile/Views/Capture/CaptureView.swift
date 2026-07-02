import SwiftUI
import AtlasCore

/// The Capture hero. A small state machine drives the screen: empty → listening /
/// thinking → result (typed or spoken — one shared flow). Offline dumps are held
/// in `PendingCaptureQueue` and drained when Capture next appears / the app
/// foregrounds with a connection.
struct CaptureView: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    /// Shared with Settings (Task 7) — the capture routing fallback space.
    @AppStorage("defaultSpaceName") private var defaultSpaceName = ""

    enum Phase: Equatable { case empty, listening, thinking, result }

    @State private var phase: Phase = .empty
    @State private var text = ""
    @State private var drafts: [DraftItem] = []
    @State private var showManualAdd = false
    @State private var note: String?
    @State private var isDraining = false
    @State private var thinkingText = ""
    @State private var dissolve = false
    @State private var showSettings = false
    @FocusState private var editorFocused: Bool

    @StateObject private var pending = PendingCaptureQueue()
    @StateObject private var speech = SpeechCapture()

    var body: some View {
        ZStack {
            MobileTheme.bg.ignoresSafeArea()
            switch phase {
            case .empty:     emptyState
            case .listening: listeningState
            case .thinking:  thinkingState
            case .result:    resultState
            }
        }
        .animation(MobileTheme.heroSpring, value: phase)
        .sheet(isPresented: $showManualAdd) {
            ManualAddSheet()
                .environmentObject(store)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet().environmentObject(store)
        }
        .task { await drainPending() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { Task { await drainPending() } }
        }
        .onAppear(perform: consumeMicDeepLink)
        .onChange(of: store.autoStartMic) { _, _ in consumeMicDeepLink() }
    }

    // MARK: - Empty state (spec §4.2)

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Capture").edScreenTitle()
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(MobileTheme.ink)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)

            // The page IS the input (spec §6, Direction A) — no box, no chrome.
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .focused($editorFocused)
                    .font(.system(size: 22, weight: .regular, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
                    .tint(MobileTheme.accent)          // caret = brand accent, not a fill
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 22)
                    .padding(.top, 10)

                if text.isEmpty {
                    Text("What’s on your mind?")
                        .font(.system(size: 22, weight: .regular, design: .rounded))
                        .foregroundStyle(MobileTheme.faint)
                        .padding(.horizontal, 27)
                        .padding(.top, 18)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 18) {
                if let note {
                    Text(note).edCapsLabel()
                } else if !pending.items.isEmpty {
                    Text("Saved offline · \(pending.items.count) waiting").edCapsLabel()
                }

                if trimmedText.isEmpty {
                    micButton
                } else {
                    Button { sortItOut(text) } label: {
                        Text("Sort it out")
                            .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(MobileTheme.ink)
                            .frame(maxWidth: .infinity)
                            .edOutlineControl()
                    }
                    .buttonStyle(.plain)
                }

                Button { showManualAdd = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                        Text("Add a task manually")
                    }
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.88)
                    .textCase(.uppercase)
                    .foregroundStyle(MobileTheme.ink)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.bottom, 10)
            .animation(MobileTheme.spring, value: trimmedText.isEmpty)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { editorFocused = false }
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
            }
        }
    }

    /// The prominent voice entry — outlined, never a fill (mic 64 pt, thumb reach).
    private var micButton: some View {
        Button(action: startListening) {
            Image(systemName: "mic")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(MobileTheme.ink)
                .frame(width: 64, height: 64)
                .overlay(Circle().strokeBorder(MobileTheme.ink, lineWidth: MobileTheme.rule))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Thinking state (spec §6: the hero moment — breathing orb, words dissolve)

    private var thinkingState: some View {
        VStack(spacing: 44) {
            Spacer()
            HeroOrb()
            Text(thinkingText)
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .foregroundStyle(MobileTheme.muted)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 44)
                .blur(radius: dissolve ? 6 : 0)
                .opacity(dissolve ? 0.15 : 1)
                .offset(y: dissolve ? -28 : 0)
                .animation(.easeIn(duration: 1.6), value: dissolve)
            Text("Sorting it out…").edCapsLabel()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { dissolve = true }
    }

    // MARK: - Listening state (on-device speech)

    @ViewBuilder
    private var listeningState: some View {
        switch speech.state {
        case .denied:      permissionExplainer
        case .unavailable: unavailableNote
        default:           liveListening
        }
    }

    private var liveListening: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 9) {
                LiveDot()                       // the ONLY accent in this state
                Text("Listening").edCapsLabel()
            }

            Text(speech.transcript.isEmpty ? "We’ll organise it for you" : speech.transcript)
                .font(.system(size: 22, weight: .regular, design: .rounded))
                .foregroundStyle(speech.transcript.isEmpty ? MobileTheme.faint : MobileTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            LevelBars(level: speech.level)

            Spacer()

            Button(action: stopListening) {
                Text("Stop")
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
                    .frame(maxWidth: .infinity)
                    .edOutlineControl()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var permissionExplainer: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Microphone off").edScreenTitle()
            Text("Atlas needs microphone and speech access to take dictation. You can turn them on in Settings.")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(MobileTheme.muted)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Text("Open Settings")
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(MobileTheme.ink)
                    .frame(maxWidth: .infinity)
                    .edOutlineControl()
            }
            .buttonStyle(.plain)

            Button { speech.stop(); phase = .empty } label: {
                Text("Back").edCapsLabel()
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var unavailableNote: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Voice unavailable").edScreenTitle()
            Text("Speech recognition isn’t available right now. You can type your dump instead.")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(MobileTheme.muted)
            Button { speech.stop(); phase = .empty } label: {
                Text("Back").edCapsLabel()
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Result state (shared card for voice + typed)

    private var resultState: some View {
        CaptureResultCard(
            drafts: $drafts,
            spaces: store.snapshot.spaces,
            onCommit: commitAll,
            onUndo: { drafts = []; phase = .empty }
        )
    }

    // MARK: - Voice control

    private func startListening() {
        note = nil
        phase = .listening
        // Route an auto-finalized transcript (recognizer hit isFinal / errored while
        // the user was still on the Listening screen) through the same AI flow.
        speech.onFinish = { spoken in
            let trimmed = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                phase = .empty
            } else {
                sortItOut(trimmed)
            }
        }
        speech.start()
    }

    /// Stop the mic and route the transcript through the same AI flow as typing.
    private func stopListening() {
        let spoken = speech.transcript
        speech.stop()
        if spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            phase = .empty
        } else {
            sortItOut(spoken)
        }
    }

    /// Begin listening immediately for an `atlas://capture?mic=1` deep link.
    private func consumeMicDeepLink() {
        guard store.autoStartMic else { return }
        store.autoStartMic = false
        startListening()
    }

    // MARK: - AI flow

    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Send a typed (or, in Task 4, spoken) dump through the AI. On a connectivity
    /// failure the raw text is queued for later; other failures return to empty.
    func sortItOut(_ input: String) {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        editorFocused = false
        note = nil
        thinkingText = raw
        dissolve = false
        phase = .thinking
        Task {
            do {
                let ctx = AtlasAI.context(from: store.contextSpaces)
                let results = try await store.ai.parse(raw, spaces: ctx)
                text = ""
                if results.isEmpty {
                    phase = .empty
                    note = "Nothing to add"
                } else {
                    drafts = results.map(DraftItem.init)
                    phase = .result
                }
            } catch let error as URLError where error.isConnectivity {
                pending.enqueue(raw)
                text = ""
                phase = .empty
                note = "Saved — will sort when you’re back online"
            } catch {
                phase = .empty
                note = "Couldn’t sort that. Try again."
            }
        }
    }

    private func commitAll() {
        MobileTheme.Haptic.success()
        note = commitSummary(drafts)
        for draft in drafts { commit(draft) }
        drafts = []
        phase = .empty
    }

    /// "Added 3 · 2 School, 1 Personal" — the calm confirmation shown back on
    /// the empty screen after a commit. Spaces resolved the same way commit() does.
    private func commitSummary(_ drafts: [DraftItem]) -> String {
        let bySpace = Dictionary(grouping: drafts) {
            resolveSpace($0.spaceName)?.name ?? $0.spaceName
        }
        let parts = bySpace
            .sorted { $0.value.count > $1.value.count }
            .map { "\($0.value.count) \($0.key)" }
            .joined(separator: ", ")
        return "Added \(drafts.count) · \(parts)"
    }

    /// Map one draft into a real domain object and persist it through the store.
    /// Space is resolved against the user's real spaces (fallback: the Settings
    /// default space, else the first space). Note-kind captures become tasks whose
    /// body carries the note text.
    private func commit(_ draft: DraftItem) {
        let space = resolveSpace(draft.spaceName)
        let spaceName = space?.name ?? draft.spaceName
        let color = space?.color ?? MobileTheme.accent

        if draft.kind == "event" {
            let start = draft.start ?? draft.due ?? Date()
            let end = start.addingTimeInterval(TimeInterval((draft.durationMin ?? 60) * 60))
            let event = CalendarEvent(
                title: draft.title, subtitle: "", start: start, end: end,
                color: color, spaceName: spaceName, notes: draft.notes, source: .atlas)
            Task { await store.addEvent(event) }
        } else {
            let notes = draft.kind == "note" ? (draft.notes ?? draft.title) : (draft.notes ?? "")
            let task = TaskItem(
                title: draft.title,
                dueLabel: TaskItem.dueLabel(for: draft.due),
                scheduledAt: draft.start,
                dueDate: draft.due,
                durationMin: draft.durationMin,
                spaceColor: color,
                spaceName: spaceName,
                projectName: draft.projectName ?? "",
                notes: notes)
            Task { await store.addTask(task) }
        }
    }

    private func resolveSpace(_ name: String) -> Space? {
        let spaces = store.snapshot.spaces
        if let match = spaces.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return match
        }
        if !defaultSpaceName.isEmpty,
           let fallback = spaces.first(where: { $0.name.caseInsensitiveCompare(defaultSpaceName) == .orderedSame }) {
            return fallback
        }
        return spaces.first
    }

    // MARK: - Offline drain

    /// Parse and commit any queued offline dumps. Stops at the first failure so the
    /// rest stay queued (still offline / server down). The `isDraining` guard
    /// serializes the two triggers (`.task` + scenePhase); each item is removed from
    /// the queue BEFORE parsing (restored on failure) so a crash mid-parse can't
    /// double-commit it later.
    private func drainPending() async {
        guard !isDraining, store.session != nil, !pending.items.isEmpty else { return }
        isDraining = true
        defer { isDraining = false }
        let ctx = AtlasAI.context(from: store.contextSpaces)
        for item in pending.items {
            pending.remove(item.id)
            do {
                let results = try await store.ai.parse(item.text, spaces: ctx)
                for r in results { commit(DraftItem(r)) }
            } catch {
                pending.enqueue(item.text)
                break
            }
        }
    }
}

/// The capture hero (spec §6): a breathing clay orb with expanding ripples — the
/// app's ONE expressive animation moment. Accent = live/brand, allowed here.
private struct HeroOrb: View {
    @State private var breathe = false
    @State private var ripple = false

    var body: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                Circle()
                    .stroke(MobileTheme.accent.opacity(0.35), lineWidth: 1.5)
                    .frame(width: 72, height: 72)
                    .scaleEffect(ripple ? 2.6 : 1)
                    .opacity(ripple ? 0 : 0.8)
                    .animation(
                        .easeOut(duration: 1.8)
                            .repeatForever(autoreverses: false)
                            .delay(Double(i) * 0.9),
                        value: ripple)
            }
            Circle()
                .fill(MobileTheme.accent)
                .frame(width: 72, height: 72)
                .scaleEffect(breathe ? 1.12 : 0.88)
                .shadow(color: MobileTheme.accent.opacity(0.45), radius: breathe ? 34 : 14)
                .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: breathe)
        }
        .frame(height: 100)
        .onAppear { breathe = true; ripple = true }
    }
}

/// The tiny live "recording" dot — the ONLY accent allowed in the listening state.
private struct LiveDot: View {
    @State private var on = false
    var body: some View {
        Circle()
            .fill(MobileTheme.accent)
            .frame(width: 8, height: 8)
            .opacity(on ? 1 : 0.35)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

/// Simple animated waveform bars driven by the mic input level. Monochrome ink —
/// accent is reserved for the live dot.
private struct LevelBars: View {
    let level: CGFloat
    private let weights: [CGFloat] = [0.4, 0.7, 1.0, 0.85, 1.0, 0.6, 0.45]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(weights.indices, id: \.self) { i in
                Capsule()
                    .fill(MobileTheme.ink.opacity(0.55))
                    .frame(width: 4, height: 6 + level * 34 * weights[i])
            }
        }
        .frame(height: 40, alignment: .center)
        .animation(.easeOut(duration: 0.12), value: level)
    }
}

private extension URLError {
    /// True for the "no usable network" family — the signal to hold a dump offline.
    var isConnectivity: Bool {
        switch code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut,
             .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
             .dataNotAllowed, .internationalRoamingOff:
            return true
        default:
            return false
        }
    }
}
