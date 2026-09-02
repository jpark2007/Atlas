import SwiftUI
import AtlasCore
import TipKit

/// The Capture hero. A small state machine drives the screen: empty → listening /
/// thinking → result (typed or spoken — one shared flow). Offline and server-down
/// dumps are held in `PendingCaptureQueue` (AtlasCore) and drained when Capture next
/// appears / the app foregrounds with a connection. The in-progress buffer is
/// mirrored to `CaptureDraftStore` on every keystroke so an app kill can't eat it —
/// Phase 4 §1, "if I typed it, Atlas saved it."
struct CaptureView: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    /// Shared with Settings (Task 7) — the capture routing fallback space.
    @AppStorage("defaultSpaceName") private var defaultSpaceName = ""

    enum Phase: Equatable { case empty, listening, thinking, result }

    @State private var phase: Phase = .empty
    @State private var text = ""
    /// Items this capture ALREADY committed — the result sheet corrects them in
    /// place (Phase 4 §3), it does not gate them.
    @State private var committed: [CommittedItem] = []
    /// The words behind `committed`, handed back to the editor on "Undo everything".
    @State private var lastRawText = ""
    @State private var showManualAdd = false
    @State private var note: String?
    @State private var isDraining = false
    @State private var thinkingText = ""
    @State private var dissolve = false
    @State private var showSettings = false
    @State private var showClearConfirm = false
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
                .edSheetDetents([.medium, .large], preferringLarge: true)
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet().environmentObject(store)
        }
        .confirmationDialog("Clear this capture?",
                            isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { clearDraft() }
        }
        .task { await drainPending() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { Task { await drainPending() } }
            // Backgrounded / interrupted while the mic is live: end it rather than
            // dictate behind the user's back. Only when really listening, so the
            // first-run permission dialogs can't cancel their own request.
            else if speech.isListening { stopListening() }
        }
        // Leaving the tab ends dictation — SwiftUI keeps this view alive, so without
        // this the orange recording indicator burns over an unrelated screen.
        .onDisappear(perform: stopDictationOnLeave)
        .onAppear {
            // "If I typed it, Atlas saved it" — an unsent draft survives an app kill.
            if phase == .empty, text.isEmpty { text = CaptureDraftStore.load() }
            consumeMicDeepLink()
        }
        .onChange(of: store.autoStartMic) { _, _ in consumeMicDeepLink() }
    }

    /// Writes the draft through on every KEYSTROKE only. Programmatic writes to
    /// `text` (the clear after a successful parse) bypass this setter, so an app
    /// kill mid-submit still leaves the typed text on disk for the next launch.
    private var draftBinding: Binding<String> {
        Binding(
            get: { text },
            set: { newValue in
                // Refuse past the cap rather than truncating — the words stay whole and
                // the field simply stops, with one line saying why. Same ceiling the Mac
                // field and the capture function enforce (it 413s past it), so nobody
                // types into a guaranteed failure.
                guard newValue.count <= Self.maxLength else {
                    withAnimation { note = Self.atLimitMessage }
                    return
                }
                if note == Self.atLimitMessage { note = nil }
                text = newValue
                CaptureDraftStore.save(newValue)
            }
        )
    }

    /// The most text one capture can hold, matching the Mac and the server.
    static let maxLength = 20_000
    static let atLimitMessage = "That's as much as one capture can hold"

    /// The two "held for later" outcomes. Nothing was lost — but missing this notice
    /// reads as a capture that vanished, so it gets the app's banner weight (13/medium
    /// ink in a bordered capsule, as in `RootTabView`) instead of a caps caption.
    static let queuedOfflineMessage = "Saved \u{2014} will sort when you\u{2019}re back online"
    static let queuedServerMessage = "Saved \u{2014} will sort when servers are back"

    private static func isQueuedMessage(_ note: String) -> Bool {
        note == queuedOfflineMessage || note == queuedServerMessage
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
                TextEditor(text: draftBinding)
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
            // Keyboard-exit: floats bottom-trailing above the controls column while typing.
            .overlay(alignment: .bottomTrailing) {
                if editorFocused {
                    Button {
                        editorFocused = false
                        MobileTheme.Haptic.selection()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(MobileTheme.ink)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(MobileTheme.bg))
                            .overlay(Circle().strokeBorder(MobileTheme.ink, lineWidth: MobileTheme.rule))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 22)
                    .padding(.bottom, 6)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(MobileTheme.spring, value: editorFocused)

            VStack(spacing: 18) {
                if let note {
                    if Self.isQueuedMessage(note) {
                        Text(note)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(MobileTheme.ink)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 18)
                            .background(Capsule().fill(MobileTheme.bg))
                            .overlay(Capsule().strokeBorder(MobileTheme.hairline, lineWidth: 1))
                    } else {
                        Text(note).edCapsLabel()
                    }
                } else if !pending.items.isEmpty {
                    Text("Saved offline · \(pending.items.count) waiting").edCapsLabel()
                }

                if trimmedText.isEmpty {
                    micButton
                } else {
                    Button { sortItOut(text) } label: {
                        Text("Capture")
                            .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(MobileTheme.ink)
                            .frame(maxWidth: .infinity)
                            .edOutlineControl()
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 22) {
                    Button { showManualAdd = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                            Text("Add manually")
                        }
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(0.88)
                        .textCase(.uppercase)
                        .foregroundStyle(MobileTheme.ink)
                    }
                    .buttonStyle(.plain)

                    // Only offered when there is a draft to throw away.
                    if !trimmedText.isEmpty {
                        Button { showClearConfirm = true } label: {
                            Text("Clear").edCapsLabel()
                        }
                        .buttonStyle(.plain)
                    }
                }
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
        case .preparing:   preparingState
        default:           liveListening
        }
    }

    /// Before the mic is actually live — permissions are async, and on a fresh
    /// install two system dialogs sit on top of this. Quiet: no live dot, no
    /// waveform, nothing claiming to be hearing anything yet.
    private var preparingState: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("Getting ready").edCapsLabel()

            Text("One moment…")
                .font(.system(size: 22, weight: .regular, design: .rounded))
                .foregroundStyle(MobileTheme.faint)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            Button { speech.stop(); phase = .empty } label: {
                Text("Cancel")
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
            Text("Speech recognition isn’t available right now. You can type it instead.")
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
            items: $committed,
            spaces: store.contextSpaces,
            onDone: { committed = []; phase = .empty },
            // Undo everything = "not what I meant" → reverse what was committed
            // and hand the original words back to the editor.
            onUndoAll: undoAll
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

    /// End dictation when Capture goes away. The words are ROUTED through the same
    /// flow as the Stop button — leaving the tab must never silently lose them.
    private func stopDictationOnLeave() {
        guard phase == .listening else { return }
        if speech.isListening {
            stopListening()
        } else if speech.state == .preparing {
            // Permission dialogs were still up — cancel before the mic ever opens.
            speech.stop()
            phase = .empty
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
                let response = try await store.ai.parse(
                    raw,
                    spaces: AtlasAI.context(from: store.contextSpaces),
                    deadlines: AtlasAI.deadlineContext(from: store.snapshot.tasks),
                    recent: AtlasAI.recentContext(recentCaptures))
                if response.results.isEmpty {
                    // Nothing actionable — hand the words back rather than eat them.
                    phase = .empty
                    note = "Nothing to add"
                } else {
                    // Commit immediately (Phase 4 §3): no review screen, no "did it
                    // save?". The words are safely in the app now, so the persisted
                    // draft is cleared — Undo hands them back from `lastRawText`.
                    committed = response.results.map { commit(DraftItem($0)) }
                    CaptureDraftStore.clear()
                    rememberCapture(raw)
                    MobileTheme.Haptic.success()
                    text = ""
                    lastRawText = raw
                    // Rare: the server's defensive item bound trimmed an enormous
                    // paste (normal long pastes fan out and are not capped).
                    note = response.truncated
                        ? "That was a lot — some items may not have been added. Try splitting it up"
                        : nil
                    phase = .result
                }
            } catch let error as URLError where error.isConnectivity {
                pending.enqueue(raw)
                text = ""
                CaptureDraftStore.clear()
                phase = .empty
                note = Self.queuedOfflineMessage
            } catch AtlasAIError.tooLong {
                // Server rejected the size (413) — a retry would 413 forever, so
                // this stays an in-place error with the text kept in the field.
                phase = .empty
                note = "Sorry — that message is too long to sort"
            } catch AtlasAIError.serverUnavailable, AtlasAIError.rateLimited {
                // Server down / busy (5xx / 429) — transient, so hold the dump and
                // drain it later instead of making the user retry by hand.
                pending.enqueue(raw)
                text = ""
                CaptureDraftStore.clear()
                phase = .empty
                note = Self.queuedServerMessage
            } catch {
                phase = .empty
                note = "Couldn’t sort that. Try again."
            }
        }
    }

    /// Reverse everything this capture committed and hand the words back.
    private func undoAll() {
        for item in committed {
            if let prior = item.prior, item.kind == .task {
                if var task = store.snapshot.tasks.first(where: { $0.id == item.id }) {
                    task.dueDate = prior.due
                    task.dueLabel = TaskItem.dueLabel(for: prior.due)
                    task.notes = prior.notes
                    Task { await store.updateTask(task) }
                }
            } else {
                switch item.kind {
                case .task:  Task { await store.deleteTask(id: item.id) }
                case .event: Task { await store.deleteEvent(id: item.id) }
                }
            }
        }
        committed = []
        text = lastRawText
        CaptureDraftStore.save(lastRawText)
        note = nil
        phase = .empty
    }

    /// Throw away the draft in the compose field. A live mic is stopped first —
    /// `SpeechCapture.start()` carries an unrouted transcript into the next session,
    /// so leaving it listening would re-publish the words we just cleared. `stop()`
    /// clears them, and the transcript here is deliberately not routed anywhere.
    private func clearDraft() {
        if speech.isListening { speech.stop() }
        text = ""
        CaptureDraftStore.clear()
        note = nil
    }

    // MARK: - Recent capture referents

    /// The last few raw captures, newest first, so "the essay" in the NEXT dump
    /// can be resolved. Device-local (the Mac keeps its own capture history).
    private static let recentKey = "capture.recentTexts"

    private var recentCaptures: [String] {
        UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? []
    }

    private func rememberCapture(_ raw: String) {
        var list = recentCaptures
        list.insert(String(raw.prefix(AtlasAI.recentContextChars)), at: 0)
        UserDefaults.standard.set(Array(list.prefix(AtlasAI.recentContextLimit)),
                                  forKey: Self.recentKey)
    }

    /// Map one parsed item into a real domain object and persist it through the
    /// store, returning the committed identity the result sheet corrects. Space is
    /// resolved against the user's real spaces (fallback: the Settings default
    /// space, else the first space). Note-kind captures become tasks whose body
    /// carries the note text. An "update" item that names a task the user already
    /// has modifies THAT task instead of creating a duplicate.
    @discardableResult
    private func commit(_ draft: DraftItem) -> CommittedItem {
        let space = resolveSpace(draft.spaceName)
        let spaceName = space?.name ?? draft.spaceName
        let color = space?.color ?? MobileTheme.accent

        if draft.kind == "update", let updated = commitUpdate(draft) { return updated }

        if draft.kind == "event" {
            let rawStart = draft.start ?? draft.due ?? Date()
            let start: Date
            let end: Date
            if draft.isAllDay {
                // All-day: one calendar day, anchored at UTC midnight of that date with an
                // exclusive end — the canonical encoding every source and consumer agrees on
                // (`AllDayDate`). A local midnight here would read as the previous day.
                start = AllDayDate.anchor(forDayOf: rawStart, in: .current)
                end = start.addingTimeInterval(86_400)
            } else {
                start = rawStart
                if let stated = draft.end, stated > rawStart {
                    end = stated
                } else {
                    end = rawStart.addingTimeInterval(TimeInterval((draft.durationMin ?? 60) * 60))
                }
            }
            var event = CalendarEvent(
                title: draft.title, subtitle: "", start: start, end: end,
                color: color, spaceName: spaceName, notes: draft.notes,
                isAllDay: draft.isAllDay,
                projectID: store.projectID(spaceName: spaceName, projectName: draft.projectName ?? ""),
                source: .atlas)
            // `space_id` is the authoritative column — the Mac resolves the space (and
            // its Google account) from it, so writing only the name leaves the two
            // disagreeing and the event filed under the wrong space server-side.
            event.spaceID = space?.id

            // Repeating ("gym every Tuesday") -> one real event per session, sharing a
            // series id. Mirrors the Mac's `AppState.applySeries` so the same sentence
            // produces the same rows on either device.
            if let rule = draft.recurrence,
               case let starts = rule.occurrences(startingAt: start),
               starts.count > 1 {
                let seriesID = UUID()
                let rruleText = rule.rruleText
                let duration = end.timeIntervalSince(start)
                let instances = starts.map { occurrence -> CalendarEvent in
                    var instance = event
                    instance.id = UUID()
                    instance.start = occurrence
                    instance.end = occurrence.addingTimeInterval(duration)
                    instance.seriesID = seriesID
                    instance.recurrenceRule = rruleText
                    return instance
                }
                event = instances[0]   // the chip stands for the first session
                Task { await store.addEvents(instances) }
            } else {
                Task { await store.addEvent(event) }
            }
            donateCapture()
            return CommittedItem(id: event.id, kind: .event, title: event.title,
                                 spaceName: spaceName, projectName: draft.projectName ?? "",
                                 date: event.start, lowConfidence: draft.lowConfidence,
                                 prior: nil)
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
                projectID: store.projectID(spaceName: spaceName, projectName: draft.projectName ?? ""),
                projectName: draft.projectName ?? "",
                notes: notes)
            Task { await store.addTask(task) }
            donateCapture()
            return CommittedItem(id: task.id, kind: .task, title: task.title,
                                 spaceName: spaceName, projectName: task.projectName,
                                 date: task.dueDate, lowConfidence: draft.lowConfidence,
                                 wasNote: draft.kind == "note", prior: nil)
        }
    }

    /// Attach the capture to an EXISTING task: a stated deadline moves the due
    /// date, stated detail is appended to the notes. Returns nil when the model's
    /// `targetId` is missing, malformed or unknown, so the caller falls back to a
    /// normal create — a hallucinated id can never make a capture disappear.
    private func commitUpdate(_ draft: DraftItem) -> CommittedItem? {
        let known = Set(store.snapshot.tasks.map(\.id))
        guard case .update(let id) = CaptureAction.decide(
                CaptureResult(kind: "update", title: draft.title, spaceName: draft.spaceName,
                              targetId: draft.targetId),
                knownIDs: known),
              var task = store.snapshot.tasks.first(where: { $0.id == id }) else { return nil }

        let prior = CommittedItem.PriorState(due: task.dueDate, notes: task.notes)
        if let due = draft.due {
            task.dueDate = due
            task.dueLabel = TaskItem.dueLabel(for: due)
        }
        let extra = (draft.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty, !task.notes.contains(extra) {
            task.notes = task.notes.isEmpty ? extra : task.notes + "\n" + extra
        }
        Task { await store.updateTask(task) }
        donateCapture()
        return CommittedItem(id: task.id, kind: .task, title: task.title,
                             spaceName: task.spaceName, projectName: task.projectName,
                             date: task.dueDate, lowConfidence: draft.lowConfidence,
                             prior: prior)
    }

    /// Feeds the onboarding checklist (Task 7); no capture tip on iOS.
    private func donateCapture() {
        Task { await AtlasTipEvents.captured.donate() }
        UserDefaults.standard.set(true, forKey: "checklist.captured")
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
                let response = try await store.ai.parse(
                    item.text,
                    spaces: ctx,
                    deadlines: AtlasAI.deadlineContext(from: store.snapshot.tasks),
                    recent: AtlasAI.recentContext(recentCaptures))
                for r in response.results { commit(DraftItem(r)) }
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

