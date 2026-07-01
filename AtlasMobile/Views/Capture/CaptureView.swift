import SwiftUI
import AtlasCore

/// The Capture hero. A small state machine drives the screen: empty → thinking →
/// result (typed or, in Task 4, spoken). Offline dumps are held in
/// `PendingCaptureQueue` and drained when Capture next appears / the app
/// foregrounds with a connection.
struct CaptureView: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.scenePhase) private var scenePhase

    /// Shared with Settings (Task 7) — the capture routing fallback space.
    @AppStorage("defaultSpaceName") private var defaultSpaceName = ""

    enum Phase: Equatable { case empty, listening, thinking, result }

    @State private var phase: Phase = .empty
    @State private var text = ""
    @State private var drafts: [DraftItem] = []
    @State private var showManualAdd = false
    @State private var note: String?
    @FocusState private var editorFocused: Bool

    @StateObject private var pending = PendingCaptureQueue()

    var body: some View {
        ZStack {
            MobileTheme.bg.ignoresSafeArea()
            switch phase {
            case .empty, .listening: emptyState   // .listening built in Task 4
            case .thinking:          thinkingState
            case .result:            resultState
            }
        }
        .sheet(isPresented: $showManualAdd) {
            ManualAddSheet()
                .environmentObject(store)
                .presentationDetents([.medium, .large])
        }
        .task { await drainPending() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { Task { await drainPending() } }
        }
    }

    // MARK: - Empty state (spec §4.2)

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("Capture").edScreenTitle()

            dumpBox

            if !trimmedText.isEmpty {
                Button { sortItOut(text) } label: {
                    Text("Sort it out")
                        .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(MobileTheme.ink)
                        .frame(maxWidth: .infinity)
                        .edOutlineControl()
                }
                .buttonStyle(.plain)
            }

            if let note {
                Text(note).edCapsLabel()
            } else if !pending.items.isEmpty {
                Text("Saved offline · \(pending.items.count) waiting").edCapsLabel()
            }

            VStack(spacing: 22) {
                orDivider
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

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
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

    /// Big outlined dump box (radius 24) with a placeholder + a refined mic glyph.
    private var dumpBox: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .focused($editorFocused)
                .font(.system(size: 18, weight: .regular, design: .rounded))
                .foregroundStyle(MobileTheme.ink)
                .tint(MobileTheme.accent)          // caret = brand accent, not a fill
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

            if text.isEmpty {
                Text("What’s on your mind?")
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .foregroundStyle(MobileTheme.faint)
                    .padding(.horizontal, 19)
                    .padding(.vertical, 20)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 200)
        .overlay(alignment: .bottomTrailing) { micGlyph.padding(14) }
        .overlay(
            RoundedRectangle(cornerRadius: MobileTheme.radiusCard, style: .continuous)
                .strokeBorder(MobileTheme.ink, lineWidth: MobileTheme.rule)
        )
        .contentShape(RoundedRectangle(cornerRadius: MobileTheme.radiusCard, style: .continuous))
    }

    /// Refined mic glyph — outlined, never a fill. Faint (disabled-looking) until
    /// Task 4 wires on-device speech.
    private var micGlyph: some View {
        Image(systemName: "mic")
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(MobileTheme.faint)
            .frame(width: 44, height: 44)
            .overlay(Circle().strokeBorder(MobileTheme.hairline, lineWidth: MobileTheme.rule))
    }

    private var orDivider: some View {
        HStack(spacing: 14) {
            Rectangle().fill(MobileTheme.hairline).frame(height: 1)
            Text("or").edCapsLabel().fixedSize()
            Rectangle().fill(MobileTheme.hairline).frame(height: 1)
        }
    }

    // MARK: - Thinking state (calm pulsing core, no spinner)

    private var thinkingState: some View {
        VStack(spacing: 22) {
            PulsingCore()
            Text("Sorting it out…").edCapsLabel()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    // MARK: - AI flow

    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Send a typed (or, in Task 4, spoken) dump through the AI. On a connectivity
    /// failure the raw text is queued for later; other failures return to empty.
    func sortItOut(_ input: String) {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        editorFocused = false
        note = nil
        phase = .thinking
        Task {
            do {
                let ctx = AtlasAI.context(from: store.snapshot.spaces)
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
        for draft in drafts { commit(draft) }
        drafts = []
        phase = .empty
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
    /// rest stay queued (still offline / server down).
    private func drainPending() async {
        guard store.session != nil, !pending.items.isEmpty else { return }
        let ctx = AtlasAI.context(from: store.snapshot.spaces)
        for item in pending.items {
            do {
                let results = try await store.ai.parse(item.text, spaces: ctx)
                for r in results { commit(DraftItem(r)) }
                pending.remove(item.id)
            } catch {
                break
            }
        }
    }
}

/// A calm pulsing core for the thinking state — scale + opacity breathe, no spinner.
private struct PulsingCore: View {
    @State private var on = false
    var body: some View {
        Circle()
            .fill(MobileTheme.accent)          // accent = live/brand, allowed here
            .frame(width: 18, height: 18)
            .scaleEffect(on ? 1.35 : 0.85)
            .opacity(on ? 1 : 0.45)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
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
